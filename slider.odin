package pixui

//-------//
// SLIDER //
//-------//

// A horizontal slider with a text label. `min..max` is the value range.
// The value persists in the widget's `Value` (as f32). Returns the rect,
// the current value, and whether it changed this frame.
slider :: proc (
	text:    string,
	min_v, max_v: f32,
	flags: Flags = {.Clickable, .Draw_Background, .Draw_Border},
	id:    Maybe(u64) = nil,
) -> (rect: Rect, value: f32, changed: bool) {
	
	r := widget_begin(flags, id=id)
	w := r.widget

	if v, ok := w.value.(f32); ok { value = v }
	else { value = min_v; w.value = value }

	// Draw the label, then the track, then the thumb.
	draw_text(text, r.rect.pos, {240, 220, 180, 255})
	track_y := r.rect.y + r.rect.size.y - 4
	track := Rect{{r.rect.x, track_y}, {r.rect.size.x, 4}}
	draw_rect(track, {60, 50, 40, 255})
	t := (value - min_v) / max(0.0001, max_v - min_v)
	thumb := Rect{{r.rect.x + t * (r.rect.size.x - 4), track_y - 2}, {4, 8}}
	draw_rect(thumb, {240, 220, 180, 255})

	// Drag: if pressed inside, jump to mouse x.
	if w.active {
		new_t := clamp((ctx.mouse.x - r.rect.x) / max(1, r.rect.size.x), 0, 1)
		new_v := min_v + new_t * (max_v - min_v)
		if new_v != value {
			value = new_v
			changed = true
			w.value = value
		}
	}

	widget_end(r)
	return r.rect, value, changed
}
