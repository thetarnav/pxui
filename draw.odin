package pxui

Draw_Commands :: [dynamic]Draw_Plain

Draw_Plain :: struct {
	pos:     Position,
	size:    Position,
	from:    Position_From,
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

Position :: union {
	Vec,   // absolute
	Vec2f, // relative
}
Position_From :: enum u8 {TL, TR, BL, BR}

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

get_draw_commands :: proc (allocator := context.allocator) -> []Draw_Command {

	cmds := make([dynamic]Draw_Command, 0, len(ctx.draw_commands) * 4, allocator)
	defer shrink(&cmds)

	for c in ctx.draw_commands {
		el := element_get_assert(c.element)

		dst: Rectf

		switch size in c.size {
		case Vec:   dst.size = Vec2f(size)
		case Vec2f: dst.size = size * Vec2f(el.size)
		}

		origin: Vec2f
		mod: Vec2f
		switch c.from {
		case .TL: origin = {0, 0}; mod = { 1,  1}
		case .TR: origin = {1, 0}; mod = {-1,  1}
		case .BL: origin = {0, 1}; mod = { 1, -1}
		case .BR: origin = {1, 1}; mod = {-1, -1}
		}
		dst.pos = Vec2f(el.pos) + origin * Vec2f(el.size)

		switch pos in c.pos {
		case Vec:   dst.pos += Vec2f(pos) * mod
		case Vec2f: dst.pos += (pos * Vec2f(el.size)) * mod
		}

		switch v in c.variant {
		case Draw_Texture:
			append(&cmds, Draw_Command{v, dst})

		case Draw_Color:
			// TODO: implement

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

			// corners
			append(&cmds, Draw_Command{tint=v.tint, atlas=v.atlas, src={{c0.x, c0.y}, {l, t}}, dst={{d0.x, d0.y}, {l, t}}})
			append(&cmds, Draw_Command{tint=v.tint, atlas=v.atlas, src={{c2.x, c0.y}, {r, t}}, dst={{d2.x, d0.y}, {r, t}}})
			append(&cmds, Draw_Command{tint=v.tint, atlas=v.atlas, src={{c0.x, c2.y}, {l, b}}, dst={{d0.x, d2.y}, {l, b}}})
			append(&cmds, Draw_Command{tint=v.tint, atlas=v.atlas, src={{c2.x, c2.y}, {r, b}}, dst={{d2.x, d2.y}, {r, b}}})

			// repeat edges
			fw, fh := c2.x - c1.x, c2.y - c1.y
			dw, dh := d2.x - d1.x, d2.y - d1.y
			for x := f32(0); x < dw; x += fw {
				w_clip := min(fw, dw - x)
				// top
				append(&cmds, Draw_Command{tint=v.tint, atlas=v.atlas,
				                           src={{c1.x,     c0.y}, {w_clip, t}},
				                           dst={{d1.x + x, d0.y}, {w_clip, t}}})
				// bottom
				append(&cmds, Draw_Command{tint=v.tint, atlas=v.atlas,
				                           src={{c1.x,     c2.y}, {w_clip, b}},
				                           dst={{d1.x + x, d2.y}, {w_clip, b}}})
			}
			for y := f32(0); y < dh; y += fh {
				h_clip := min(fh, dh - y)
				// top
				append(&cmds, Draw_Command{tint=v.tint, atlas=v.atlas,
				                           src={{c0.x, c1.y    }, {l, h_clip}},
				                           dst={{d0.x, d1.y + y}, {l, h_clip}}})
				// bottom
				append(&cmds, Draw_Command{tint=v.tint, atlas=v.atlas,
				                           src={{c2.x, c1.y    }, {b, h_clip}},
				                           dst={{d2.x, d1.y + y}, {b, h_clip}}})
			}

			// repeat fill
			for y := f32(0); y < dh; y += fh {
			for x := f32(0); x < dw; x += fw {
				fh_clip := min(fh, dh - y)
				fw_clip := min(fw, dw - x)
				append(&cmds, Draw_Command{tint=v.tint, atlas=v.atlas,
				                           src={{c1.x,     c1.y    }, {fw_clip, fh_clip}},
				                           dst={{d1.x + x, d1.y + y}, {fw_clip, fh_clip}}})
			}}
		}

	}

	clear(&ctx.draw_commands)

	return cmds[:]
}
