package pxui

import la "core:math/linalg"

// Draw request relative to emiting element
// Stored internally until layout is solved
Draw_Request :: struct {
	using place: Placement,
	el:          Element_Handle,
	var:         union {Draw_Texture, Draw_Nine_Slice, Draw_Color, Draw_Scissor},
}
// Draw command with screen position
// Output for the user renderer
Draw_Command :: struct {
	dst: Rect, // screen
	var: union {Draw_Texture, Draw_Color, Draw_Scissor},
}

Draw_Color :: Color
Draw_Texture :: struct {
	src:   Rect,
	atlas: ^Atlas,
	tint:  Color,
}
Draw_Nine_Slice :: struct {
	using txt: Draw_Texture,
	insets: Insets,
}
Draw_Scissor :: struct {reset: bool}

draw :: proc (req: Draw_Request, h: Element_Handle = {}) {
	req := req
	req.el = h if h != {} else ctx.element_curr
	append(&ctx.draw_reqs, req)
}
draw_color         :: proc (place: Placement, color: Color,        h: Element_Handle = {}) {draw({place=place, var=color},              h)}
draw_tex           :: proc (place: Placement, tex: Draw_Texture,   h: Element_Handle = {}) {draw({place=place, var=tex},                h)}
draw_nine_slice    :: proc (place: Placement, ns: Draw_Nine_Slice, h: Element_Handle = {}) {draw({place=place, var=ns},                 h)}
draw_scissor_begin :: proc (place: Placement,                      h: Element_Handle = {}) {draw({place=place, var=Draw_Scissor{}},     h)}
draw_scissor_end   :: proc (                                       h: Element_Handle = {}) {draw({place={},    var=Draw_Scissor{true}}, h)}

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

	cmds := make([dynamic]Draw_Command, 0, len(ctx.draw_reqs) * 4, allocator)
	defer shrink(&cmds)

	scissors := make([dynamic]Rect, context.temp_allocator)

	for c in ctx.draw_reqs {
		el := element_get_assert(c.el)

		dst: Rect
		dst.size = size_vec_to_pixel(c.size, el.rel_rect.size)
		dst.pos  = el.screen_pos +
		           size_vec_to_pixel(c.origin, el.rel_rect.size) +
		           size_vec_to_pixel(c.pos, el.rel_rect.size)

		switch v in c.var {
		case Draw_Texture:
			draw_tiled(&cmds, v, v.src, dst)

		case Draw_Color:
			append(&cmds, Draw_Command{dst, v})

		case Draw_Scissor:
			if v.reset {
				pop_safe(&scissors)
				if len(scissors) > 0 {
					append(&cmds, Draw_Command{scissors[len(scissors)-1], Draw_Scissor{false}})
				} else {
					append(&cmds, Draw_Command{{}, Draw_Scissor{true}})
				}
			} else {
				append(&scissors, dst)
				append(&cmds, Draw_Command{dst, v})
			}

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
			append(&cmds, Draw_Command{var=Draw_Texture{tint=v.tint, atlas=v.atlas, src={{c0.x, c0.y}, lt}}, dst={{d0.x, d0.y}, lt}})
			append(&cmds, Draw_Command{var=Draw_Texture{tint=v.tint, atlas=v.atlas, src={{c2.x, c0.y}, rb}}, dst={{d2.x, d0.y}, rb}})
			append(&cmds, Draw_Command{var=Draw_Texture{tint=v.tint, atlas=v.atlas, src={{c0.x, c2.y}, lb}}, dst={{d0.x, d2.y}, lb}})
			append(&cmds, Draw_Command{var=Draw_Texture{tint=v.tint, atlas=v.atlas, src={{c2.x, c2.y}, rb}}, dst={{d2.x, d2.y}, rb}})

			// edges
			draw_tiled(&cmds, v, src={{c1.x, c0.y}, {f.x, t}}, dst={{d1.x, d0.y}, {d.x, t}})
			draw_tiled(&cmds, v, src={{c1.x, c2.y}, {f.x, b}}, dst={{d1.x, d2.y}, {d.x, b}})
			draw_tiled(&cmds, v, src={{c0.x, c1.y}, {l, f.y}}, dst={{d0.x, d1.y}, {l, d.y}})
			draw_tiled(&cmds, v, src={{c2.x, c1.y}, {r, f.y}}, dst={{d2.x, d1.y}, {r, d.y}})

			// fill
			draw_tiled(&cmds, v, src={c1, f}, dst={d1, d})
		}

	}

	clear(&ctx.draw_reqs)

	return cmds[:]
}
