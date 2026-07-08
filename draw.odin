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
	src:   Rectf,
	atlas: ^Atlas,
	tint:  Color,
}
Draw_Nine_Slice :: struct {
	using txt: Draw_Texture,
	insets: Insets,
}

Size :: union {
	Vec,   // absolute
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
	dst: Rectf,
}

@(private)
draw_tiled :: proc (cmds: ^[dynamic]Draw_Command, v: Draw_Texture, src, dst: Rectf) {
	f, d := src.size, dst.size
	for y: f32; y < d.y; y += f.y {
	for x: f32; x < d.x; x += f.x {
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

		size_to_absolute :: proc (size: Size, el_size: Vec) -> (abs: Vec2f) {
			switch s in size {
			case Vec:   abs = Vec2f(s)
			case Vec2f: abs = s * Vec2f(el_size)
			}
			return abs
		}

		dst: Rectf
		dst.size = size_to_absolute(c.size, el.size)
		dst.pos  = Vec2f(el.pos) +
		           size_to_absolute(c.origin, el.size) +
		           size_to_absolute(c.pos, el.size)

		switch v in c.variant {
		case Draw_Texture:
			draw_tiled(&cmds, v, v.src, dst)

		case Draw_Color:
			append(&cmds, Draw_Command{tint=v.color, dst=dst})

		case Draw_Nine_Slice:
			l, t := f32(v.insets.l), f32(v.insets.t)
			r, b := f32(v.insets.r), f32(v.insets.b)
			s  := v.src.size
			ds := dst.size

			c0 := v.src.pos
			c1 := v.src.pos + {l, t}
			c2 := v.src.pos + s - {r, b}

			d0 := dst.pos
			d1 := dst.pos + {l, t}
			d2 := dst.pos + ds - {r, b}

			f := c2 - c1
			d := d2 - d1

			// corners
			append(&cmds, Draw_Command{tint=v.tint, atlas=v.atlas, src={{c0.x, c0.y}, {l, t}}, dst={{d0.x, d0.y}, {l, t}}})
			append(&cmds, Draw_Command{tint=v.tint, atlas=v.atlas, src={{c2.x, c0.y}, {r, t}}, dst={{d2.x, d0.y}, {r, t}}})
			append(&cmds, Draw_Command{tint=v.tint, atlas=v.atlas, src={{c0.x, c2.y}, {l, b}}, dst={{d0.x, d2.y}, {l, b}}})
			append(&cmds, Draw_Command{tint=v.tint, atlas=v.atlas, src={{c2.x, c2.y}, {r, b}}, dst={{d2.x, d2.y}, {r, b}}})

			// edges
			draw_tiled(&cmds, v, src={{c1.x, c0.y}, {f.x, t}}, dst={{d1.x, d0.y}, {d.x, t}})
			draw_tiled(&cmds, v, src={{c1.x, c2.y}, {f.x, b}}, dst={{d1.x, d2.y}, {d.x, b}})
			draw_tiled(&cmds, v, src={{c0.x, c1.y}, {l, f.y}}, dst={{d0.x, d1.y}, {l, d.y}})
			draw_tiled(&cmds, v, src={{c2.x, c1.y}, {r, f.y}}, dst={{d2.x, d1.y}, {r, d.y}})

			// fill
			draw_tiled(&cmds, v, src={{c1.x, c1.y}, f}, dst={{d1.x, d1.y}, d})
		}

	}

	clear(&ctx.draw_commands)

	return cmds[:]
}
