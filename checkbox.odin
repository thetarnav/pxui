package pixui

//-------//
// CHECKBOX //
//-------//

// A toggleable checkbox with text. Stores a `bool` value in the widget's
// `Value`. Returns the rect, the current checked state, and whether it
// changed this frame.
checkbox :: proc (
	text:  string,
	flags: Flags = {.Clickable, .Draw_Background, .Draw_Border, .Toggleable},
	id:    Maybe(u64) = nil,
) -> (rect: Rect, checked: bool, changed: bool) {
	ctx := the_context
	r := widget_begin(flags, id=id)
	w := r.widget

	// Read current value (stays in the previous slot's value if not bool).
	if v, ok := w.value.(bool); ok { checked = v } else { checked = false; w.value = false }

	// Draw the box (filled if checked) + the text label to its right.
	box := Rect{{r.rect.x, r.rect.y + (r.rect.size.y - 8) * 0.5}, {8, 8}}
	draw_rect(box, checked ? Color{240, 220, 180, 255} : Color{60, 50, 40, 255})
	draw_rect_outline(box, 1, {180, 150, 110, 255})
	draw_text(text, {r.rect.x + 12, r.rect.y + (r.rect.size.y - 10) * 0.5}, {240, 220, 180, 255})

	// Click toggles.
	if w.active && ctx.mouse_released {
		checked = !checked
		changed = true
		w.value = checked
	}

	widget_end(r)
	return r.rect, checked, changed
}

// Top-level rect helpers (so checkbox can draw its box without depending
// on the backend module). These just append draw commands.
draw_rect        :: proc (r: Rect, color: Color) {
	ps := the_context.pixel_scale
	append(&the_context.draw_cmds, Draw_Command{0, DCmd_Rect{
		Rect{r.pos * ps, r.size * ps}, color,
	}})
}
draw_rect_outline :: proc (r: Rect, thickness: f32, color: Color) {
	ps := the_context.pixel_scale
	append(&the_context.draw_cmds, Draw_Command{0, DCmd_Rect_Outline{
		Rect{r.pos * ps, r.size * ps}, thickness * ps, color,
	}})
}
