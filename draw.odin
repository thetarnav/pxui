package pxui

import "core:slice"
import la "core:math/linalg"

// Draw request relative to emiting element
// Stored internally until layout is solved
Draw_Request :: struct {
	using place: Placement,
	next:        Draw_Request_Handle,
	var:         Draw_Variant,
}
// Draw command with screen position
// Output for the user renderer
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

Draw_Request_Handle :: distinct int

Draw_Color   :: Color
Draw_Texture :: struct {
	src:   Rect,
	atlas: ^Atlas,
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
draw_get :: proc (h: Draw_Request_Handle) -> (req: ^Draw_Request, ok: bool) {
	idx := int(h)-1
	if idx < 0 || idx >= len(ctx.draw_reqs) do return
	return &ctx.draw_reqs[idx], true
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

	cmds := make([dynamic]Draw_Command, 0, len(ctx.draw_reqs) * 2, allocator)
	defer shrink(&cmds)

	Scrissor :: struct {rect: Rect, el: ^Element}
	scissors := make([dynamic]Scrissor, context.temp_allocator)

	Data :: struct #all_or_none {cmds: ^[dynamic]Draw_Command, scissors: ^[dynamic]Scrissor}
	context.user_ptr = &(Data{&cmds, &scissors})

	root := element_root()
	visit_siblings(root.child_first)

	clear(&ctx.draw_reqs)

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

		if el.transparency > 0 {
			dst := element_screen_rect(el)
			append(cmds, Draw_Command{dst, Draw_Layer{opacity = 1-el.transparency}})
		}

		req_id := el.draw_first
		for req in draw_get(req_id) {
			defer req_id = req.next

			dst: Rect
			dst.size = size_vec_to_pixel(req.size, box_size)
			dst.pos  = el.screen_pos +
			           -size_vec_to_pixel(req.origin, dst.size) +
			           size_vec_to_pixel(req.pos, box_size)

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
		if el.transparency > 0 {
			dst := element_screen_rect(el)
			append(cmds, Draw_Command{dst, Draw_Layer{opacity=1}})
		}
	}

	return cmds[:]
}
