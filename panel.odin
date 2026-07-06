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
		atlas = &panel_atlas,
		tint  = 255,
		src   = {0, Vec2f(panel_atlas.size)},
		dst   = Rectf{0, 1},
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
