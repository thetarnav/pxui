package pixui

//-------//
// SCROLL VIEW //
//-------//

// A scroll view — sets a scissor around its rect and lets the caller place
// content of `content_size` inside. Returns `content_offset` for the caller
// to apply to children. Mouse wheel adjusts the offset.
@(deferred_out=widget_pop)
scroll_view :: proc (
	label:        string,
	content_size: [2]f32,
	id:           Maybe(u64) = nil,
) -> bool {
	flags: Flags = {.Clip, .Scroll_Y}
	r := widget_begin(label, flags, id=id, size=content_size)
	if !r.active { return false }
	ctx := the_context
	// Apply scroll offset to the widget's rect, so children are drawn
	// shifted up. Use last frame's content_offset for input (one-frame-
	// deferred). For v0, just use the current value (clamped).
	w := r.widget
	w.scroll_off.y = clamp(w.scroll_off.y - get_mouse_wheel() * 16, 0, max(0, content_size.y - w.rect.size.y))
	w.rect.y -= w.scroll_off.y
	append(&ctx.parent_stack, w)
	return true
}

@(private)
get_mouse_wheel :: proc () -> f32 {
	// The backend does not expose a mouse wheel delta; the example fills
	// `the_context.mouse_wheel` from k2 in begin_frame. For now, no-op.
	return the_context.mouse_wheel
}
