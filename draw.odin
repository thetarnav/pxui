package pxui

import "core:slice"
import la "core:math/linalg"

// Draw request relative to emiting element
// Stored internally until layout is solved
Draw_Request :: struct {
	using place: Placement,
	next:        Draw_Request_Handle,
	var:         union {Draw_Texture, Draw_Nine_Slice, Draw_Color, Draw_Scissor},
}
// Draw command with screen position
// Output for the user renderer
Draw_Command :: struct {
	dst: Rect, // screen
	var: union {Draw_Texture, Draw_Color, Draw_Scissor},
}

Draw_Request_Handle :: distinct int

Draw_Color :: Color
Draw_Texture :: struct {
	src:   Rect,
	atlas: ^Atlas,
	tint:  Color,
}
Draw_Nine_Slice :: struct {
	using txt: Draw_Texture,
	insets:    Insets,
}
Draw_Scissor :: struct {reset: bool}

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

draw_color      :: proc (place: Placement, color: Color,        h: Element_Handle = {}) {draw({place=place, var=color},          h)}
draw_tex        :: proc (place: Placement, tex: Draw_Texture,   h: Element_Handle = {}) {draw({place=place, var=tex},            h)}
draw_nine_slice :: proc (place: Placement, ns: Draw_Nine_Slice, h: Element_Handle = {}) {draw({place=place, var=ns},             h)}
draw_scissor    :: proc (place: Placement,                      h: Element_Handle = {}) {draw({place=place, var=Draw_Scissor{}}, h)}

@(private)
draw_tiled :: proc (cmds: ^[dynamic]Draw_Command, tex: Draw_Texture, src, dst: Rect) {
	f, d := src.size, dst.size
	for y := 0; y < d.y; y += f.y {
	for x := 0; x < d.x; x += f.x {
		clip := la.min(f, d - {x, y})
		tex := tex
		tex.src = {src.pos, clip}
		append(cmds, Draw_Command{{dst.pos + {x, y}, clip}, tex})
	}}
}

get_draw_commands :: proc (allocator := context.allocator) -> []Draw_Command {

	// TODO: shrink the init cap after nine-slice is removed from core-or make it a slice
	cmds := make([dynamic]Draw_Command, 0, len(ctx.draw_reqs) * 4, allocator)
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

		req_id := el.draw_first
		for req in draw_get(req_id) {
			defer req_id = req.next

			dst: Rect
			dst.size = size_vec_to_pixel(req.size, el.rel_rect.size)
			dst.pos  = el.screen_pos +
			           size_vec_to_pixel(req.origin, el.rel_rect.size) +
			           size_vec_to_pixel(req.pos, el.rel_rect.size)

			switch v in req.var {
			case Draw_Texture:
				draw_tiled(cmds, v, v.src, dst)

			case Draw_Color:
				append(cmds, Draw_Command{dst, v})

			case Draw_Scissor:
				append(scissors, Scrissor{dst, el})
				append(cmds, Draw_Command{dst, v})

			case Draw_Nine_Slice:
				l, t := v.insets.l, v.insets.t
				r, b := v.insets.r, v.insets.b
				lt, lb, rb := Vec2i{l, t}, Vec2i{l, b}, Vec2i{r, b}
				s  := v.src.size
				ds := dst.size

				c0 := v.src.pos
				c1 := v.src.pos + lt
				c2 := v.src.pos + s - rb

				d0 := dst.pos
				d1 := dst.pos + lt
				d2 := dst.pos + ds - rb

				f := c2 - c1
				d := d2 - d1

				// corners
				append(cmds, Draw_Command{var=Draw_Texture{tint=v.tint, atlas=v.atlas, src={{c0.x, c0.y}, lt}}, dst={{d0.x, d0.y}, lt}})
				append(cmds, Draw_Command{var=Draw_Texture{tint=v.tint, atlas=v.atlas, src={{c2.x, c0.y}, rb}}, dst={{d2.x, d0.y}, rb}})
				append(cmds, Draw_Command{var=Draw_Texture{tint=v.tint, atlas=v.atlas, src={{c0.x, c2.y}, lb}}, dst={{d0.x, d2.y}, lb}})
				append(cmds, Draw_Command{var=Draw_Texture{tint=v.tint, atlas=v.atlas, src={{c2.x, c2.y}, rb}}, dst={{d2.x, d2.y}, rb}})

				// edges
				draw_tiled(cmds, v, src={{c1.x, c0.y}, {f.x, t}}, dst={{d1.x, d0.y}, {d.x, t}})
				draw_tiled(cmds, v, src={{c1.x, c2.y}, {f.x, b}}, dst={{d1.x, d2.y}, {d.x, b}})
				draw_tiled(cmds, v, src={{c0.x, c1.y}, {l, f.y}}, dst={{d0.x, d1.y}, {l, d.y}})
				draw_tiled(cmds, v, src={{c2.x, c1.y}, {r, f.y}}, dst={{d2.x, d1.y}, {r, d.y}})

				// fill
				draw_tiled(cmds, v, src={c1, f}, dst={d1, d})
			}
		}
	}

	visit_element_after :: proc (el: ^Element) {
		using data := (^Data)(context.user_ptr)^

		if len(scissors) > 0 && slice.last(scissors[:]).el == el {
			pop_safe(scissors)
			if len(scissors) > 0 {
				append(cmds, Draw_Command{slice.last(scissors[:]).rect, Draw_Scissor{false}})
			} else {
				append(cmds, Draw_Command{{}, Draw_Scissor{true}})
			}
		}
	}

	return cmds[:]
}
