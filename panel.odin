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
panel_begin :: proc (id: u64 = 0) {
	element_push(Panel, id)
	draw({
		variant = Draw_Nine_Slice{
			atlas  = &panel_atlas,
			tint   = 255,
			src    = {0, panel_atlas.size},
			insets = {l=4, t=4, r=4, b=4},
		},
		size = Vec2f(1),
	})
}
panel_end :: proc (id: u64 = 0) {
	assert(element_hash(typeid_of(Panel), id) == element_curr().hash)
	element_pop()
}
@(deferred_in=panel_end)
panel :: proc (id: u64 = 0) -> bool {
	panel_begin(id)
	return true
}

background_color :: proc (color: Color) {
	draw({
		variant = Draw_Color{color},
		size    = Vec2f(1),
	})
}
