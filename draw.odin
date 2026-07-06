package pxui

Draw_Commands :: [dynamic]Draw_Texture

Draw_Texture :: struct {
	src:     Rectf,
	dst:     Rect,
	tint:    Color,
	atlas:   ^Atlas,
	element: Element_Handle,
}

Draw_Handle :: distinct int

draw :: proc (tex: Draw_Texture) -> Draw_Handle {
	tex := tex
	tex.element = ctx.element_curr
	append(&ctx.draw_commands, tex)
	return Draw_Handle(len(ctx.draw_commands)-1)
}

draw_get :: proc (h: Draw_Handle) -> (^Draw_Texture) {
	return &ctx.draw_commands[h]
}

Draw_Command :: struct {
	src, dst: Rectf,
	tint:     Color,
	atlas:    ^Atlas,
}

get_draw_commands :: proc (allocator := context.allocator) -> []Draw_Command {
	cmds := make([]Draw_Command, len(ctx.draw_commands), allocator)
	for c, i in ctx.draw_commands {
		el := element_get_assert(c.element)
		cmds[i] = {
			src   = c.src,
			atlas = c.atlas,
			tint  = c.tint,
			dst   = {Vec2f(el.pos + c.dst.pos), Vec2f(c.dst.size)},
		}
	}
	clear(&ctx.draw_commands)
	return cmds
}
