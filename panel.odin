package pxui

import "base:runtime"
import "core:slice"
import "core:image/png"
import "./assets"

Atlas_Texture_Kind :: assets.Texture_Name

Atlas_Texture :: struct {
	src:    Rect,
	insets: Insets,
}

atlas_texture:  Texture
atlas_textures: [Atlas_Texture_Kind]Atlas_Texture

_assets_rect_to_rect :: #force_inline proc "contextless" (rect: assets.Rect) -> Rect {
	return {{rect.x, rect.y}, {rect.w, rect.h}}
}
_assets_nine_slice_to_insets :: #force_inline proc "contextless" (rect, nine_slice: assets.Rect) -> Insets {
	return {
		l = nine_slice.x,
		t = nine_slice.y,
		r = rect.w - nine_slice.x - nine_slice.w,
		b = rect.h - nine_slice.y - nine_slice.y,
	}
}

@(private, init)
init_panel_texture :: proc "contextless" () {
	context = runtime.default_context()

	img, _ := png.load_from_bytes(#load(assets.TEXTURE_ATLAS_FILENAME), allocator=context.temp_allocator)

	atlas_texture = {
		pixels = slice.clone(slice.reinterpret([]RGBA, img.pixels.buf[:])),
		size   = {img.width, img.height}
	}

	for &t, kind in atlas_textures {
		tex := &assets.atlas_textures[kind]
		t.src    = _assets_rect_to_rect(tex.rect)
		t.insets = _assets_nine_slice_to_insets(tex.rect, tex.nine_slice)
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
	tex:    ^Texture,
	src:    Maybe(Rect) = nil,
	insets: Insets,
	tint:   Color = WHITE,
	#any_int id: u64 = 0,
	loc := #caller_location,
) {

	Nine_Slice :: struct {
		tex:    ^Texture,
		src:    Rect,
		insets: Insets,
		tint:   Color,
	}
	s := element_push(Nine_Slice, id, loc)
	s^ = {tex, {}, insets, tint}
	s.src = src.? or_else {0, tex.size if tex != nil else {}}
	defer element_pop()

	size_fill()
	position_absolute()

	effect(proc () {
		using s := element_state(Nine_Slice)

		box        := element_box_size()
		l, t, r, b := **insets
		sw, sh     := **src.size

		if box.x <= 0 || box.y <= 0 || sw == 0 || sh == 0 || tex == nil do return

		draw_slice :: proc (dst, src: Rect) {
			s := element_state(Nine_Slice)
			draw_tex(to_placement(dst), {{s.src.pos + src.pos, src.size}, s.tex, s.tint})
		}

		// Corners
		draw_slice({{0, 0},                 {l, t}},         {{0, 0},                  {l, t}})
		draw_slice({{box.x - r, 0},         {r, t}},         {{sw - r, 0},             {r, t}})
		draw_slice({{0, box.y - b},         {l, b}},         {{0, sh - b},             {l, b}})
		draw_slice({{box.x - r, box.y - b}, {r, b}},         {{sw - r, sh - b},        {r, b}})
		// Edges
		draw_slice({{l, 0},         {box.x - l - r, t}},     {{l, 0},         {sw - l - r, t}})
		draw_slice({{l, box.y - b}, {box.x - l - r, b}},     {{l, sh - b},    {sw - l - r, b}})
		draw_slice({{0, t},         {l, box.y - t - b}},     {{0, t},         {l, sh - t - b}})
		draw_slice({{box.x - r, t}, {r, box.y - t - b}},     {{sw - r, t},    {r, sh - t - b}})
		// Center
		draw_slice({{l, t}, {box.x - l - r, box.y - t - b}}, {{l, t}, {sw - l - r, sh - t - b}})
	})
}
background_color :: proc (color: Color, h: Element_Handle = {}) {
	draw_color({size=FILL}, color, h)
}
background_texture :: proc (
	tex:  ^Texture,
	src:  Maybe(Rect) = nil,
	tint: Color       = WHITE,
	h: Element_Handle = {},
) {
	if tex == nil do return
	draw_tex({size=FILL}, {
		src  = src.? or_else {0, tex.size},
		tex  = tex,
		tint = tint,
	}, h)
}

clip_outside :: proc (h: Element_Handle = {}) {
	draw_scissor({size=FILL}, h)
}
