package pixui

//-------//
// HANDLE //
//-------//

// Backend-agnostic handles. Backends interpret the integer however they
// like (e.g. karl2d wraps it in a `Texture` struct).
Texture_Handle :: distinct u64
Font_Handle    :: distinct u64

//-------//
// LOADER //
//-------//

// The only callback pixui needs during UI building: turn a PNG byte slice
// (e.g. a BMFont atlas) into a backend-specific texture handle. The example
// wraps karl2d's `load_texture_from_bytes` here.
//
// All *rendering* goes through the `Draw_Command` list (see state.odin) —
// the user's example dispatches those to its own renderer. The Loader is
// only for asset upload (currently fonts; panel/button textures are
// uploaded by the example and passed in as `px.Texture_Handle`).
Loader :: struct {
	load_texture_png: proc (png_bytes: []u8) -> Texture_Handle,
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
