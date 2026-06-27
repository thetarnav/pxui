package pixui

// Plain text label. Does not create a widget — just emits a text draw
// command at the current parent rect's top-left. The caller is expected to
// position the parent (e.g. with `rect_cut`) before calling.
label :: proc (
	text: string,
	pos:  [2]f32 = {0, 0},
	color: Color = {240, 220, 180, 255},
) {
	draw_text(text, pos, color)
}
