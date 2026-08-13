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
		b = rect.h - nine_slice.y - nine_slice.h,
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
	if tex == nil do return

	l, t, r, b := **insets
	s          := src.? or_else {0, tex.size}
	sw, sh     := **s.size

	if sh == 0 || sh == 0 do return

	if insets != {} {
		// Corners
		draw_tex({size={l, t}, pos={  0,   0}, origin={  0,   0}}, {{s.pos + {   0,    0}, {l, t}}, tex, tint})
		draw_tex({size={r, t}, pos={1.0,   0}, origin={1.0,   0}}, {{s.pos + {sw-r,    0}, {r, t}}, tex, tint})
		draw_tex({size={l, b}, pos={  0, 1.0}, origin={  0, 1.0}}, {{s.pos + {   0, sh-b}, {l, b}}, tex, tint})
		draw_tex({size={r, b}, pos={1.0, 1.0}, origin={1.0, 1.0}}, {{s.pos + {sw-r, sh-b}, {r, b}}, tex, tint})

		// Edges
		draw_tex({margin={l,0,r,0}, size={1.0, t}, pos={0,   0}, origin={0,   0}}, {{s.pos + {l,    0}, {sw-l-r, t}}, tex, tint})
		draw_tex({margin={l,0,r,0}, size={1.0, b}, pos={0, 1.0}, origin={0, 1.0}}, {{s.pos + {l, sh-b}, {sw-l-r, b}}, tex, tint})
		draw_tex({margin={0,t,0,b}, size={l, 1.0}, pos={0,   0}, origin={0,   0}}, {{s.pos + {0,    t}, {l, sh-t-b}}, tex, tint})
		draw_tex({margin={0,t,0,b}, size={r, 1.0}, pos={1.0, 0}, origin={1.0, 0}}, {{s.pos + {sw-r, t}, {r, sh-t-b}}, tex, tint})
	}

	// Center
	draw_tex({margin=insets, size=FILL}, {{s.pos + {l, t}, {sw - l - r, sh - t - b}}, tex, tint})
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
