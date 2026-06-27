package pixui

//-------//
// CHECKBOX //
//-------//

// A toggleable checkbox. Stores a `bool` value in the widget's `Value`.
// Returns the rect, the current checked state, and whether it changed this
// frame.
checkbox :: proc (
	label: string,
	flags: Flags = {.Clickable, .Draw_Text, .Draw_Background, .Draw_Border, .Toggleable},
	id:    Maybe(u64) = nil,
) -> (rect: Rect, checked: bool, changed: bool) {
	ctx := the_context
	r := widget_begin(label, flags, id=id)
	w := r.widget

	// Read current value (stays in the previous slot's value if not bool).
	if v, ok := w.value.(bool); ok { checked = v } else { checked = false; w.value = false }

	// Click toggles.
	if w.active && ctx.mouse_released {
		checked = !checked
		changed = true
		w.value = checked
	}

	widget_end(r)
	return r.rect, checked, changed
}
