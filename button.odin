package pixui

import "core:fmt"

// A clickable button with text. `surface` is the 9-slice style; defaults
// to the context's `default_button` if nil. Returns its rect and whether
// it was clicked this frame.
button :: proc (
	text:    string,
	flags:   Flags = {.Clickable, .Draw_Background, .Draw_Border},
	surface: Maybe(Panel_Surface) = nil,
	id:      Maybe(u64) = nil,
) -> (rect: Rect, clicked: bool) {

	r := widget_begin(flags, id=id, surface=surface.? or_else the_context.default_button)
	w := r.widget

	// Draw the button's label, centered horizontally, vertically centered
	// against the button height (assuming the font's line height ≈ button
	// height for v0).
	if the_context.default_font != nil {
		fh := f32(the_context.default_font.line_height)
		px_pos := [2]f32{r.rect.x + 4, r.rect.y + (r.rect.size.y - fh) * 0.5}
		draw_text(text, px_pos, {240, 220, 180, 255})
	}

	// Click detection: standard IMGUI semantics — a click happens when
	// the user releases the mouse while the button is still hovered AND
	// the same widget was the one that captured the press.
	fmt.eprintln("[button] w.id=", w.id, "active_id=", the_context.active_id, "hovered_id=", the_context.hovered_id, "released=", the_context.mouse_released)
	if the_context.active_id == w.id &&
	   the_context.hovered_id == w.id &&
	   the_context.mouse_released {
		clicked = true
	}
	widget_end(r)
	return r.rect, clicked
}
