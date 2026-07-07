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

text :: proc (str: string) {
	element_push(Text)
	defer element_pop()

	el := element_curr()
	el.flags += {.Non_Interactable}

	color := RGBA{230, 200, 160, 255}
	Data :: struct {color: Color, el: ^Element}
	context.user_ptr = &(Data{color, el})

	bmfont.draw_text(str, default_font, cb)

	cb :: proc (src, dstf: bmfont.Rect) {
		using data := cast(^Data)context.user_ptr

		// dstf := dstf
		// dstf.pos  /= 2
		// dstf.size /= 2

		dst := Rect{Vec(dstf.pos), Vec(dstf.size)}

		el.rect.size = la.max(rect_end(el.rect), el.rect.pos + rect_end(dst)) - el.rect.pos

		draw({
			pos     = dst.pos,
			size    = dst.size,
			variant = Draw_Texture{
				src   = Rectf(src),
				tint  = color,
				atlas = (^Atlas)(&default_font_atlas),
			},
		})
	}
}

textf :: proc (str: string, args: ..any) {
	text(fmt.tprintf(str, ..args))
}
