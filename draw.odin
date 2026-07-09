package pxui

import la "core:math/linalg"

Draw_Commands :: [dynamic]Draw_Plain

Draw_Plain :: struct {
	pos:     Size,
	size:    Size,
	origin:  Size,
	element: Element_Handle,
	variant: Draw_Variant,
}

Draw_Variant :: union {Draw_Texture, Draw_Nine_Slice, Draw_Color}

Draw_Color :: struct {
	color: Color,
}
Draw_Texture :: struct {
	src:   Rect,
	atlas: ^Atlas,
	tint:  Color,
}
Draw_Nine_Slice :: struct {
	using txt: Draw_Texture,
	insets: Insets,
}

Size :: union {
	Vec2i, // absolute
	Vec2f, // relative
}

Draw_Handle :: distinct int

draw :: proc (tex: Draw_Plain) -> Draw_Handle {
	tex := tex
	tex.element = ctx.element_curr
	append(&ctx.draw_commands, tex)
	return Draw_Handle(len(ctx.draw_commands)-1)
}

draw_get :: proc (h: Draw_Handle) -> (^Draw_Plain) {
	return &ctx.draw_commands[h]
}

Draw_Command :: struct {
	using _: Draw_Texture,
	dst: Rect,
}

@(private)
draw_tiled :: proc (cmds: ^[dynamic]Draw_Command, v: Draw_Texture, src, dst: Rect) {
	f, d := src.size, dst.size
	for y := 0; y < d.y; y += f.y {
	for x := 0; x < d.x; x += f.x {
		clip := la.min(f, d - {x, y})
		append(cmds, Draw_Command{tint=v.tint, atlas=v.atlas,
		                          src={src.pos,          clip},
		                          dst={dst.pos + {x, y}, clip}})
	}}
}

get_draw_commands :: proc (allocator := context.allocator) -> []Draw_Command {

	cmds := make([dynamic]Draw_Command, 0, len(ctx.draw_commands) * 4, allocator)
	defer shrink(&cmds)

	for c in ctx.draw_commands {
		el := element_get_assert(c.element)

		size_to_absolute :: proc (size: Size, el_size: Vec2i) -> (abs: Vec2i) {
			switch s in size {
			case Vec2i: abs = s
			case Vec2f: abs = Vec2i(s * Vec2f(el_size))
			}
			return abs
		}

		dst: Rect
		dst.size = size_to_absolute(c.size, el.calc_rect.size)
		dst.pos  = el.calc_rect.pos +
		           size_to_absolute(c.origin, el.calc_rect.size) +
		           size_to_absolute(c.pos, el.calc_rect.size)

		switch v in c.variant {
		case Draw_Texture:
			draw_tiled(&cmds, v, v.src, dst)

		case Draw_Color:
			append(&cmds, Draw_Command{tint=v.color, dst=dst})

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
			append(&cmds, Draw_Command{tint=v.tint, atlas=v.atlas, src={{c0.x, c0.y}, lt}, dst={{d0.x, d0.y}, lt}})
			append(&cmds, Draw_Command{tint=v.tint, atlas=v.atlas, src={{c2.x, c0.y}, rb}, dst={{d2.x, d0.y}, rb}})
			append(&cmds, Draw_Command{tint=v.tint, atlas=v.atlas, src={{c0.x, c2.y}, lb}, dst={{d0.x, d2.y}, lb}})
			append(&cmds, Draw_Command{tint=v.tint, atlas=v.atlas, src={{c2.x, c2.y}, rb}, dst={{d2.x, d2.y}, rb}})

			// edges
			draw_tiled(&cmds, v, src={{c1.x, c0.y}, {f.x, t}}, dst={{d1.x, d0.y}, {d.x, t}})
			draw_tiled(&cmds, v, src={{c1.x, c2.y}, {f.x, b}}, dst={{d1.x, d2.y}, {d.x, b}})
			draw_tiled(&cmds, v, src={{c0.x, c1.y}, {l, f.y}}, dst={{d0.x, d1.y}, {l, d.y}})
			draw_tiled(&cmds, v, src={{c2.x, c1.y}, {r, f.y}}, dst={{d2.x, d1.y}, {r, d.y}})

			// fill
			draw_tiled(&cmds, v, src={c1, f}, dst={d1, d})
		}

	}

	clear(&ctx.draw_commands)

	return cmds[:]
}
