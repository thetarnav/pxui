package pxui

import "base:runtime"
import "core:slice"
import "core:image/tga"

@private
panel_atlas: Atlas

@(private, init)
init_panel_texture :: proc "contextless" () {
	context = runtime.default_context()
	img, _ := tga.load_from_bytes(#load("./panel.tga"), allocator=context.temp_allocator)
	panel_atlas = {
		pixels = slice.clone(slice.reinterpret([]RGBA, img.pixels.buf[:])),
		size   = {img.width, img.height}
	}
}

@private
get_panel_atlas :: proc () -> Atlas {
	return panel_atlas
}

Panel :: struct {}
panel_begin :: proc (id: u64 = 0, loc := #caller_location) {
	element_push(Panel, id, loc)
}
panel_end :: proc (id: u64 = 0, loc := #caller_location) {
	assert(element_hash(typeid_of(Panel), id) == element_curr().hash, loc=loc)
	element_pop()
}
@(deferred_in=panel_end)
panel :: proc (id: u64 = 0, loc := #caller_location) -> bool {
	panel_begin(id, loc)
	return true
}

nine_slice :: proc () {
	draw({
		variant = Draw_Nine_Slice{
			atlas  = &panel_atlas,
			tint   = 255,
			src    = {0, panel_atlas.size},
			insets = {l=4, t=4, r=4, b=4},
		},
		size = {1.0, 1.0},
	})
}
background_color :: proc (color: Color) {
	draw({
		variant = Draw_Color{color},
		size    = {1.0, 1.0},
	})
}
