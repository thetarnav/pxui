package pixui

// Internal per-frame pipeline. These are called by `end_frame` in order.
// (1) `allocate_root` creates the implicit root widget. (2) `resolve_ids`
// assigns each widget its React-style id from the structural position. (3)
// `autolayout` computes the rect of every widget. (4) `hit_test` walks the
// tree against last frame's rects to mark hot/active. (5) `emit_draw` issues
// draw commands to the backend in z-order.

@(private)
allocate_root :: proc (ctx: ^Context) {
	root := alloc_widget(ctx)
	root.id = 0
	root.flags = {}
	root.semantic_size = {ctx.screen_w / max(ctx.pixel_scale, 0.0001),
	                      ctx.screen_h / max(ctx.pixel_scale, 0.0001)}
	root.rect = {{0, 0}, root.semantic_size}
	append(&ctx.parent_stack, root)
	ctx.by_id[root.id] = root
}

@(private)
resolve_ids :: proc (ctx: ^Context) {
	rec_resolve_ids(ctx, ctx.parent_stack[0])
}

rec_resolve_ids :: proc (ctx: ^Context, parent: ^Widget) {
	idx := 0
	for child := parent.first_child; child != nil; child = child.next {
		base := hash_combine(parent.id, u64(idx))
		child.id = base
		ctx.by_id[child.id] = child
		idx += 1
	}
	for child := parent.first_child; child != nil; child = child.next {
		if child.first_child != nil {
			rec_resolve_ids(ctx, child)
		}
	}
}

@(private)
hit_test :: proc (ctx: ^Context) {
	mouse := ctx.mouse

	for &w in ctx.widget_storage {
		w.hot = false
		w.active = false
	}
	ctx.hovered_id = 0

	root := ctx.parent_stack[0]
	rec_hit_test(ctx, root, mouse)
}

rec_hit_test :: proc (ctx: ^Context, w: ^Widget, mouse: [2]f32) {
	// Children first, so a child steals hover from its parent.
	for child := w.last_child; child != nil; child = child.prev {
		if child.first_child != nil {
			rec_hit_test(ctx, child, mouse)
		}
		if .Clickable in child.flags && rect_contains(child.rect, mouse) {
			child.hot = true
			ctx.hovered_id = child.id
		}
	}
	// If no child was hot, this widget might be hot.
	if ctx.hovered_id == 0 && .Clickable in w.flags {
		if rect_contains(w.rect, mouse) {
			w.hot = true
			ctx.hovered_id = w.id
		}
	}

	// Active state: pressing the mouse grabs the hovered widget.
	if ctx.mouse_pressed && ctx.hovered_id != 0 && ctx.active_id == 0 {
		ctx.active_id = ctx.hovered_id
	}
	if ctx.active_id != 0 {
		if w_, ok := ctx.by_id[ctx.active_id]; ok {
			w_.active = true
		}
	}
	if ctx.mouse_released {
		ctx.active_id = 0
	}
}

@(private)
emit_draw :: proc (ctx: ^Context) {
	bctx := Backend_Draw_Ctx{ctx, 0}
	root := ctx.parent_stack[0]
	rec_emit_draw(&bctx, root)
}

Backend_Draw_Ctx :: struct {
	ctx:    ^Context,
	z_base: int,
}

rec_emit_draw :: proc (b: ^Backend_Draw_Ctx, w: ^Widget) {
	ctx := b.ctx

	scissored := .Clip in w.flags
	if scissored {
		emit(b, b.z_base, DCmd_Scissor{w.rect})
	}

	if w.panel_surface != nil {
		ps_ := w.panel_surface.?
		if ps_.fill_color.a != 0 {
			emit_scaled_rect(b, b.z_base, w.rect, ps_.fill_color)
		}
		if ns, ok := ps_.nine_slice.(Nine_Slice); ok {
			draw_nine_slice(b, ns, w.rect, b.z_base + 1)
		}
		if ps_.border_color.a != 0 {
			emit_scaled_rect_outline(b, b.z_base + 2, w.rect, 1, ps_.border_color)
		}
	}

	// Text is no longer drawn here — widget helpers call `draw_text`
	// directly at widget creation, so text lands in the right z-order slot.

	child_ctx := Backend_Draw_Ctx{ctx, b.z_base + 100}
	for child := w.first_child; child != nil; child = child.next {
		rec_emit_draw(&child_ctx, child)
	}

	if scissored {
		emit(b, b.z_base + 1000, DCmd_Scissor{nil})
	}
}

emit :: proc (b: ^Backend_Draw_Ctx, z: int, cmd: Draw_Cmd) {
	append(&b.ctx.draw_cmds, Draw_Command{z, cmd})
}

emit_scaled_rect :: proc (b: ^Backend_Draw_Ctx, z: int, r: Rect, color: Color) {
	ps := b.ctx.pixel_scale
	scaled := Rect{r.pos * ps, r.size * ps}
	emit(b, z, DCmd_Rect{scaled, color})
}

emit_scaled_rect_outline :: proc (b: ^Backend_Draw_Ctx, z: int, r: Rect, t: f32, color: Color) {
	ps := b.ctx.pixel_scale
	scaled := Rect{r.pos * ps, r.size * ps}
	emit(b, z, DCmd_Rect_Outline{scaled, t * ps, color})
}

draw_nine_slice :: proc (b: ^Backend_Draw_Ctx, ns: Nine_Slice, dst: Rect, z: int) {
	L, T := ns.l, ns.t
	R, B := ns.r, ns.b
	sw, sh := ns.src.size.x, ns.src.size.y
	dw, dh := dst.size.x, dst.size.y

	cx0, cy0 := ns.src.x,         ns.src.y
	cx1, cy1 := ns.src.x + L,     ns.src.y + T
	cx2, cy2 := ns.src.x + sw - R, ns.src.y + sh - B

	dx0, dy0 := dst.x,             dst.y
	dx1, dy1 := dst.x + L,         dst.y + T
	dx2, dy2 := dst.x + dw - R,    dst.y + dh - B

	emit_sub(b, z, ns, {{cx0, cy0}, {L, T}},                 {{dx0, dy0}, {L, T}})
	emit_sub(b, z, ns, {{cx1, cy0}, {cx2 - cx1, T}},         {{dx1, dy0}, {dx2 - dx1, T}})
	emit_sub(b, z, ns, {{cx2, cy0}, {R, T}},                 {{dx2, dy0}, {R, T}})
	emit_sub(b, z, ns, {{cx0, cy1}, {L, cy2 - cy1}},         {{dx0, dy1}, {L, dy2 - dy1}})
	emit_sub(b, z, ns, {{cx1, cy1}, {cx2 - cx1, cy2 - cy1}}, {{dx1, dy1}, {dx2 - dx1, dy2 - dy1}})
	emit_sub(b, z, ns, {{cx2, cy1}, {R, cy2 - cy1}},         {{dx2, dy1}, {R, dy2 - dy1}})
	emit_sub(b, z, ns, {{cx0, cy2}, {L, B}},                 {{dx0, dy2}, {L, B}})
	emit_sub(b, z, ns, {{cx1, cy2}, {cx2 - cx1, B}},         {{dx1, dy2}, {dx2 - dx1, B}})
	emit_sub(b, z, ns, {{cx2, cy2}, {R, B}},                 {{dx2, dy2}, {R, B}})
}

emit_sub :: proc (b: ^Backend_Draw_Ctx, z: int, ns: Nine_Slice, src, dst: Rect) {
	ps := b.ctx.pixel_scale
	emit(b, z, DCmd_Sub_Texture{ns.texture, src, Rect{dst.pos * ps, dst.size * ps}, {255, 255, 255, 255}})
}

// Emit a text draw command. The position is in *UI pixels* — the backend
// dispatcher scales by `ctx.pixel_scale` before handing off to the
// renderer. The font defaults to `ctx.default_font`.
//
// Called by widget helpers (`label`, `button`, `panel`, `slider`,
// `checkbox`) immediately after `widget_begin`, so the text lands in the
// correct z-order relative to the widget's background and children.
draw_text :: proc (
	text:  string,
	pos:   [2]f32,
	color: Color = {255, 255, 255, 255},
	font:  Maybe(^Font) = nil,
) {
	f := font.? if font != nil else the_context.default_font
	if f == nil do return
	ps := the_context.pixel_scale
	append(&the_context.draw_cmds, Draw_Command{
		z = 0,
		cmd = DCmd_Text{
			font  = f.handle,
			text  = text,
			pos   = {pos.x * ps, pos.y * ps},
			color = color,
		},
	})
}
