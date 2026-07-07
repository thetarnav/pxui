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
			sw, sh := v.src.size.x, v.src.size.y
			dw, dh := dst.size.x, dst.size.y

			cx0, cy0 := v.src.x,          v.src.y
			cx1, cy1 := v.src.x + l,      v.src.y + t
			cx2, cy2 := v.src.x + sw - r, v.src.y + sh - b

			dx0, dy0 := dst.x,            dst.y
			dx1, dy1 := dst.x + l,        dst.y + t
			dx2, dy2 := dst.x + dw - r,   dst.y + dh - b

			append(&cmds, Draw_Command{tint=v.tint, atlas=v.atlas, src={{cx0, cy0}, {l, t}},                 dst={{dx0, dy0}, {l, t}}})
			append(&cmds, Draw_Command{tint=v.tint, atlas=v.atlas, src={{cx1, cy0}, {cx2 - cx1, t}},         dst={{dx1, dy0}, {dx2 - dx1, t}}})
			append(&cmds, Draw_Command{tint=v.tint, atlas=v.atlas, src={{cx2, cy0}, {r, t}},                 dst={{dx2, dy0}, {r, t}}})
			append(&cmds, Draw_Command{tint=v.tint, atlas=v.atlas, src={{cx0, cy1}, {l, cy2 - cy1}},         dst={{dx0, dy1}, {l, dy2 - dy1}}})
			append(&cmds, Draw_Command{tint=v.tint, atlas=v.atlas, src={{cx1, cy1}, {cx2 - cx1, cy2 - cy1}}, dst={{dx1, dy1}, {dx2 - dx1, dy2 - dy1}}})
			append(&cmds, Draw_Command{tint=v.tint, atlas=v.atlas, src={{cx2, cy1}, {r, cy2 - cy1}},         dst={{dx2, dy1}, {r, dy2 - dy1}}})
			append(&cmds, Draw_Command{tint=v.tint, atlas=v.atlas, src={{cx0, cy2}, {l, b}},                 dst={{dx0, dy2}, {l, b}}})
			append(&cmds, Draw_Command{tint=v.tint, atlas=v.atlas, src={{cx1, cy2}, {cx2 - cx1, b}},         dst={{dx1, dy2}, {dx2 - dx1, b}}})
			append(&cmds, Draw_Command{tint=v.tint, atlas=v.atlas, src={{cx2, cy2}, {r, b}},                 dst={{dx2, dy2}, {r, b}}})
		}

	}

	clear(&ctx.draw_commands)

	return cmds[:]
}
