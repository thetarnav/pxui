package pixui

//-------//
// BUTTON //
//-------//

// A clickable button with text. `surface` is the 9-slice style; defaults
// to the context's `default_button` if nil. Returns its rect and whether
// it was clicked this frame.
button :: proc (
	text:    string,
	flags:   Flags = {.Clickable, .Draw_Background, .Draw_Border},
	surface: Maybe(Panel_Surface) = nil,
	id:      Maybe(u64) = nil,
) -> (rect: Rect, clicked: bool) {
	ctx := the_context
	use_surface := surface
	if use_surface == nil { use_surface = ctx.default_button }
	r := widget_begin(flags, id=id, surface=use_surface)
	w := r.widget

	// Draw the button's label, centered horizontally, vertically centered
	// against the button height (assuming the font's line height ≈ button
	// height for v0).
	if ctx.default_font != nil {
		fh := f32(ctx.default_font.line_height)
		px_pos := [2]f32{r.rect.x + 4, r.rect.y + (r.rect.size.y - fh) * 0.5}
		draw_text(text, px_pos, {240, 220, 180, 255})
	}

	// Click detection: pressed-and-released inside the button.
	if w.active && ctx.mouse_released {
		clicked = true
	}
	widget_end(r)
	return r.rect, clicked
}
