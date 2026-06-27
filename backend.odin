package pixui

//-------//
// HANDLE //
//-------//

// Backend-agnostic handles. Backends interpret the integer however they
// like (e.g. karl2d wraps it in a `Texture` struct).
Texture_Handle :: distinct u64
Font_Handle    :: distinct u64

//-------//
// BACKEND //
//-------//

// A bag of proc pointers that pixui uses for all rendering and state queries.
// Fill it in once at startup. The example wraps karl2d procs.
Backend :: struct {
	draw_rect_filled:  proc (r: Rect, color: Color),
	draw_rect_outline: proc (r: Rect, thickness: f32, color: Color),
	draw_sub_texture:  proc (tex: Texture_Handle, src, dst: Rect, tint: Color),
	draw_text:         proc (font: Font_Handle, text: string, pos: [2]f32, color: Color),
	measure_text:      proc (font: Font_Handle, text: string) -> [2]f32,
	text_height:       proc (font: Font_Handle) -> f32,
	set_scissor:       proc (maybe_rect: Maybe(Rect)),
	screen_size:       proc () -> [2]f32,
	load_texture_png:  proc (png_bytes: []u8) -> Texture_Handle,
}

//-------//
// STYLE //
//-------//

// A 9-slice source. The insets are in source pixels.
Nine_Slice :: struct {
	src:        Rect,   // full source rect
	l, t, r, b: f32,   // insets in source pixels
	texture:    Texture_Handle,
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
