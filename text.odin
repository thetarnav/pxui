package pxui

import "base:runtime"
import "core:fmt"
import la "core:math/linalg"
import "./bmfont"

default_font:       bmfont.Font
default_font_atlas: bmfont.Atlas

@init
init_default_font :: proc "contextless" () {
	context = runtime.default_context()
	default_font, default_font_atlas, _ = bmfont.load_json_bytestream(#load("./fonts/monogram.json", string))
	default_font.spacing = 1
}

@fini
fini_default_font :: proc "contextless" () {
	context = runtime.default_context()
	bmfont.destroy_font(default_font)
	delete(default_font_atlas.pixels)
}

get_font_atlas :: proc () -> Atlas {
	return Atlas(default_font_atlas)
}

Text :: struct {}

text :: proc (str: string, color: Color = 255) {
	element_push(Text)
	defer element_pop()

	flag(.Non_Interactable)

	Data :: struct {
		color:  Color,
		bounds: Vec2i,
	}
	data := Data{color, {}}
	context.user_ptr = &data

	bmfont.draw_text(str, default_font, cb)

	cb :: proc (src, dst: bmfont.Rect) {
		using data := cast(^Data)context.user_ptr

		pos  := Vec2i(dst.pos)
		size := Vec2i(dst.size)

		bounds = la.max(bounds, pos + size)

		draw_tex({pos=size_vec(pos), size=size_vec(size)}, {
			src   = {Vec2i(src.pos), Vec2i(src.size)},
			tint  = color,
			atlas = (^Atlas)(&default_font_atlas),
		})
	}

	size_px(data.bounds)
}

textf :: proc (str: string, args: ..any, color: Color = 255) {
	text(fmt.tprintf(str, ..args), color)
}
