package pxui

import "core:slice"
import la "core:math/linalg"

// Draw request relative to emiting element.
// Stored internally until layout is solved.
// Can be emitted from frame immediately
//  or from layout/effect callbacks.
Draw_Request :: struct {
	using place: Placement,
	next:        Draw_Request_Handle,
	var:         Draw_Variant,
}
// Index to ctx.draw_reqs
Draw_Request_Handle :: distinct int

// Draw command with screen position.
// Output for the user renderer.
Draw_Command :: struct {
	dst: Rect, // screen
	var: Draw_Variant,
}

Draw_Variant :: union {
	Draw_Texture,
	Draw_Color,
	Draw_Scissor,
	Draw_Layer,
}

Draw_Color   :: Color
Draw_Texture :: struct {
	src:   Rect,
	tex:   ^Texture,
	tint:  Color,
}
Draw_Scissor :: struct {reset: bool}
Draw_Layer   :: struct {opacity: f32}

draw :: proc (req: Draw_Request, h: Element_Handle = {}) {
	el := element_get_or_curr(h)
	append(&ctx.draw_reqs, req)
	req_id := Draw_Request_Handle(len(ctx.draw_reqs)) // 0 is nil req
	// Link new draw request
	if prev, has_prev := draw_get(el.draw_last); has_prev {
		prev.next = req_id
	} else {
		el.draw_first = req_id
	}
	el.draw_last = req_id
}
// Gets draw request from current frame's buffer
draw_get :: proc (h: Draw_Request_Handle) -> (req: ^Draw_Request, ok: bool) #no_bounds_check {
	idx := int(h)-1
	if idx < 0 || idx >= len(ctx.draw_reqs) do return
	return &ctx.draw_reqs[idx], true
}
// Gets draw request from previous frame's buffer
draw_get_last_frame :: proc (h: Draw_Request_Handle) -> (req: ^Draw_Request, ok: bool) #no_bounds_check {
	idx := int(h)-1
	if idx < 0 || idx >= len(ctx.draw_reqs_prev) do return
	return &ctx.draw_reqs_prev[idx], true
}

draw_color   :: proc (place: Placement, color: Color,      h: Element_Handle = {}) {draw({place=place, var=color},          h)}
draw_tex     :: proc (place: Placement, tex: Draw_Texture, h: Element_Handle = {}) {draw({place=place, var=tex},            h)}
draw_scissor :: proc (place: Placement,                    h: Element_Handle = {}) {draw({place=place, var=Draw_Scissor{}}, h)}

@(private)
_draw_tiled :: proc (cmds: ^[dynamic]Draw_Command, tex: Draw_Texture, dst: Rect) {
	f, d := tex.src.size, dst.size
	for y := 0; y < d.y; y += f.y {
	for x := 0; x < d.x; x += f.x {
		clip := la.min(f, d - {x, y})
		tex := tex
		tex.src.size = clip
		append(cmds, Draw_Command{{dst.pos + {x, y}, clip}, tex})
	}}
}

get_draw_commands :: proc (allocator := context.allocator) -> []Draw_Command {

	trace(#procedure)

	cmds := make([dynamic]Draw_Command, 0, len(ctx.draw_reqs) * 2, allocator)
	defer shrink(&cmds)

	Scrissor :: struct {rect: Rect, el: ^Element}
	scissors := make([dynamic]Scrissor, context.temp_allocator)

	Data :: struct #all_or_none {cmds: ^[dynamic]Draw_Command, scissors: ^[dynamic]Scrissor}
	context.user_ptr = &(Data{&cmds, &scissors})

	root := element_root()
	visit_siblings(root.child_first)

	visit_siblings :: proc (h: Element_Handle) {
		h := h
		for el in element_get(h) {
			defer h = el.next
			visit_element_before(el)
			visit_siblings(el.child_first)
			visit_element_after(el)
		}
	}

	visit_element_before :: proc (el: ^Element) {
		using data := (^Data)(context.user_ptr)^

		box_size := element_box_size(el)

		if el.derived_transparency > 0 {
			dst := element_screen_rect(el)
			append(cmds, Draw_Command{dst, Draw_Layer{opacity = 1-el.derived_transparency}})
		}

		req_id := el.draw_first
		for req in draw_get(req_id) {
			defer req_id = req.next

			src := (req.var.(Draw_Texture) or_else {}).src

			dst: Rect
			dst.size = _placement_ref_to_box_size(req, _placement_calc_ref_size(req, box_size, src.size))
			dst.pos  = el.pos_screen.? +
			           _placement_calc_rel_pos(req, box_size, dst.size)

			switch v in req.var {
			case Draw_Texture:
				_draw_tiled(cmds, v, dst)

			case Draw_Color:
				append(cmds, Draw_Command{dst, v})

			case Draw_Scissor:
				rect := rect_intersetcion(dst, slice.last(scissors[:]).rect) if len(scissors) > 0 else dst
				append(scissors, Scrissor{rect, el})
				append(cmds, Draw_Command{rect, v})

			case Draw_Layer:
				// emitted before draw requests
			}
		}
	}

	visit_element_after :: proc (el: ^Element) {
		using data := (^Data)(context.user_ptr)^

		// End scissor
		if len(scissors) > 0 && slice.last(scissors[:]).el == el {
			pop_safe(scissors)
			if len(scissors) > 0 {
				append(cmds, Draw_Command{slice.last(scissors[:]).rect, Draw_Scissor{false}})
			} else {
				append(cmds, Draw_Command{{}, Draw_Scissor{true}})
			}
		}

		// Close layer
		if el.derived_transparency > 0 {
			dst := element_screen_rect(el)
			append(cmds, Draw_Command{dst, Draw_Layer{opacity=1}})
		}
	}

	return cmds[:]
}
