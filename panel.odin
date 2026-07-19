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
	effect(proc () {
		box := element_box_size()
		if box.x <= 0 || box.y <= 0 do return

		atlas := &panel_atlas
		insets := Insets{l=4, t=4, r=4, b=4}

		l, t, r, b := insets.l, insets.t, insets.r, insets.b
		aw, ah := atlas.size.x, atlas.size.y

		draw_slice :: proc (atlas: ^Atlas, dst, src: Rect) {
			draw_tex(to_placement(dst), {src, atlas, WHITE})
		}

		// Corners
		draw_slice(atlas, {{0, 0},                 {l, t}},         {{0, 0},                  {l, t}})
		draw_slice(atlas, {{box.x - r, 0},         {r, t}},         {{aw - r, 0},             {r, t}})
		draw_slice(atlas, {{0, box.y - b},         {l, b}},         {{0, ah - b},             {l, b}})
		draw_slice(atlas, {{box.x - r, box.y - b}, {r, b}},         {{aw - r, ah - b},        {r, b}})
		// Edges
		draw_slice(atlas, {{l, 0},         {box.x - l - r, t}},     {{l, 0},         {aw - l - r, t}})
		draw_slice(atlas, {{l, box.y - b}, {box.x - l - r, b}},     {{l, ah - b},    {aw - l - r, b}})
		draw_slice(atlas, {{0, t},         {l, box.y - t - b}},     {{0, t},         {l, ah - t - b}})
		draw_slice(atlas, {{box.x - r, t}, {r, box.y - t - b}},     {{aw - r, t},    {r, ah - t - b}})
		// Center
		draw_slice(atlas, {{l, t}, {box.x - l - r, box.y - t - b}}, {{l, t}, {aw - l - r, ah - t - b}})
	})
}
background_color :: proc (color: Color) {
	draw_color({size=FILL}, color)
}
