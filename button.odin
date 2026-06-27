package pixui

//-------//
// BUTTON //
//-------//

// A clickable button. `surface` is the 9-slice style; defaults to the
// context's `default_button` if nil. Returns its rect and whether it was
// clicked this frame.
button :: proc (
	label:   string,
	flags:   Flags = {.Clickable, .Draw_Text, .Draw_Background, .Draw_Border},
	surface: Maybe(Panel_Surface) = nil,
	id:      Maybe(u64) = nil,
) -> (rect: Rect, clicked: bool) {
	ctx := the_context
	use_surface := surface
	if use_surface == nil { use_surface = ctx.default_button }
	r := widget_begin(label, flags, id=id, surface=use_surface)
	w := r.widget

	// Drag-state: track a per-button "active" press.
	if w.active && ctx.mouse_released {
		clicked = true
	}
	widget_end(r)
	return r.rect, clicked
}
