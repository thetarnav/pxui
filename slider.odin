package pixui

//-------//
// SLIDER //
//-------//

// A horizontal slider. `min..max` is the value range. The value persists in
// the widget's `Value` (as f32). Returns the rect, the current value, and
// whether it changed this frame.
slider :: proc (
	label: string,
	min_v, max_v: f32,
	flags: Flags = {.Clickable, .Draw_Background, .Draw_Border},
	id:    Maybe(u64) = nil,
) -> (rect: Rect, value: f32, changed: bool) {
	ctx := the_context
	r := widget_begin(label, flags, id=id)
	w := r.widget

	if v, ok := w.value.(f32); ok { value = v }
	else { value = min_v; w.value = value }

	// Drag the slider: if pressed inside, jump to mouse x; if pressed
	// outside, continue dragging from previous position.
	if w.active {
		t := clamp((ctx.mouse.x - w.rect.x) / max(1, w.rect.size.x), 0, 1)
		new_v := min_v + t * (max_v - min_v)
		if new_v != value {
			value = new_v
			changed = true
			w.value = value
		}
	}

	widget_end(r)
	return r.rect, value, changed
}
