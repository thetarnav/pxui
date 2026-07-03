package pixui

// A 9-slice source. The insets are in source pixels.
Nine_Slice :: struct {
	src:        Rect,   // full source rect
	l, t, r, b: f32,   // insets in source pixels
}

// A panel/button/widget surface. For v0 this is a texture 9-slice plus an
// optional solid fill and border. Procedural styles will plug in here in
// v0.1 via a vtable.
Panel_Surface :: struct {
	nine_slice:   Maybe(Nine_Slice),
	fill_color:   Color,    // drawn under the 9-slice (alpha 0 = skip)
	border_color: Color,    // 1px outline (alpha 0 = skip)
	label_offset: [2]f32,   // offset applied to label text inside the rect
}
