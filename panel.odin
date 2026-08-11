package pxui

import "base:runtime"
import "core:slice"
import "core:image/png"
import "./assets"

panel_atlas: Atlas
nine_slice_rect: Rect
nine_slice_insets: Insets

@(private, init)
init_panel_texture :: proc "contextless" () {
	context = runtime.default_context()
	img, _ := png.load_from_bytes(#load(assets.TEXTURE_ATLAS_FILENAME), allocator=context.temp_allocator)
	panel_atlas = {
		pixels = slice.clone(slice.reinterpret([]RGBA, img.pixels.buf[:])),
		size   = {img.width, img.height}
	}
	tex := assets.atlas_textures[.Border_Rounded]
	nine_slice_rect = {Vec2i{tex.rect.x, tex.rect.y}, Vec2i{tex.rect.w, tex.rect.h}}
	nine_slice_insets = {
		l = tex.nine_slice.x,
		t = tex.nine_slice.y,
		r = tex.rect.w - tex.nine_slice.x - tex.nine_slice.w,
		b = tex.rect.h - tex.nine_slice.y - tex.nine_slice.y,
	}
}

Panel :: struct {}
panel_begin :: proc (#any_int id: u64 = 0, loc := #caller_location) {
	element_push(Panel, id, loc)
}
panel_end :: proc (#any_int id: u64 = 0, loc := #caller_location) {
	assert(element_hash(typeid_of(Panel), id) == element_curr().hash, loc=loc)
	element_pop()
}
@(deferred_in=panel_end)
panel :: proc (#any_int id: u64 = 0, loc := #caller_location) -> bool {
	panel_begin(id, loc)
	return true
}


nine_slice :: proc (
	atlas:  ^Atlas,
	src:    Rect,
	insets: Insets,
	#any_int id: u64 = 0,
	loc := #caller_location,
) {

	Nine_Slice :: struct {
		atlas:  ^Atlas,
		src:    Rect,
		insets: Insets,
	}
	s := element_push(Nine_Slice, id, loc)
	s^ = {atlas, src, insets}
	defer element_pop()

	size_fill()
	position_absolute()

	effect(proc () {
		using s := element_state(Nine_Slice)

		box        := element_box_size()
		l, t, r, b := **insets
		sw, sh     := **src.size
		origin     := src.pos

		if box.x <= 0 || box.y <= 0 || sw == 0 || sh == 0 do return

		draw_slice :: proc (atlas: ^Atlas, origin: Vec2i, dst, src: Rect) {
			draw_tex(to_placement(dst), {{origin + src.pos, src.size}, atlas, WHITE})
		}

		// Corners
		draw_slice(atlas, origin, {{0, 0},                 {l, t}},         {{0, 0},                  {l, t}})
		draw_slice(atlas, origin, {{box.x - r, 0},         {r, t}},         {{sw - r, 0},             {r, t}})
		draw_slice(atlas, origin, {{0, box.y - b},         {l, b}},         {{0, sh - b},             {l, b}})
		draw_slice(atlas, origin, {{box.x - r, box.y - b}, {r, b}},         {{sw - r, sh - b},        {r, b}})
		// Edges
		draw_slice(atlas, origin, {{l, 0},         {box.x - l - r, t}},     {{l, 0},         {sw - l - r, t}})
		draw_slice(atlas, origin, {{l, box.y - b}, {box.x - l - r, b}},     {{l, sh - b},    {sw - l - r, b}})
		draw_slice(atlas, origin, {{0, t},         {l, box.y - t - b}},     {{0, t},         {l, sh - t - b}})
		draw_slice(atlas, origin, {{box.x - r, t}, {r, box.y - t - b}},     {{sw - r, t},    {r, sh - t - b}})
		// Center
		draw_slice(atlas, origin, {{l, t}, {box.x - l - r, box.y - t - b}}, {{l, t}, {sw - l - r, sh - t - b}})
	})
}
background_color :: proc (color: Color) {
	draw_color({size=FILL}, color)
}

clip_outside :: proc (h: Element_Handle = {}) {
	draw_scissor({size=FILL}, h)
}
