package pixui

//-------//
// SCROLL VIEW //
//-------//

// A scroll view — sets a scissor around its rect and lets the caller place
// content of `content_size` inside. Returns `active` for `if scroll_view(...)
// { ... }`. Mouse wheel adjusts the vertical scroll offset.
scroll_view :: proc (
	content_size: [2]f32,
	id:           Maybe(u64) = nil,
) -> bool {
	flags: Flags = {.Clip, .Scroll_Y}
	r := widget_begin(flags, id=id, size=content_size)
	if !r.active do return false

	w := r.widget
	// Apply scroll offset to the widget's rect, so children are drawn
	// shifted up. Clamp to keep some content visible.
	w.scroll_off.y = clamp(
		w.scroll_off.y - ctx.mouse_wheel * 16,
		0, max(0, content_size.y - w.rect.size.y),
	)
	w.rect.pos.y -= w.scroll_off.y
	append(&ctx.parent_stack, w)
	defer pop(&ctx.parent_stack)
	return true
}
