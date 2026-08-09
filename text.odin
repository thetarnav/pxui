package pxui

import "core:strings"
import "base:runtime"
import "core:fmt"
import "./bmfont"

Font :: bmfont.Font

default_font:       Font
default_font_atlas: bmfont.Atlas

@init
init_default_font :: proc "contextless" () {
	context = runtime.default_context()
	default_font, default_font_atlas, _ = bmfont.load_json_bytestream(#load("./assets/monogram.json", string))
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

text :: proc (str: string, color: Color = 255, loc := #caller_location) {
	element_push(Text, loc=loc)
	defer element_pop()

	flag(.Non_Interactable)

	bounds := draw_text(str, color)
	size_px(bounds)
}
textf :: proc (str: string, args: ..any, color: Color = 255, loc := #caller_location) {
	text(fmt.tprintf(str, ..args), color, loc)
}

Paragraph :: struct {str: string, color: Color}
paragraph :: proc (str: string, color: Color = 255, loc := #caller_location) {

	s := element_push(Paragraph, loc=loc)
	defer element_pop()

	width_fill()
	flag(.Non_Interactable)

	if str != s.str {
		del_err := delete(s.str) // TODO: components need their own temp allocator (to handle memoized element layout callbacks)
		assert(del_err == nil)
		s.str, _ = strings.clone(str)
	}
	s.color = color

	cleanup(proc () {
		using s := element_state(Paragraph)
		del_err := delete(s.str)
		assert(del_err == nil)
	})

	layout(.Y, _paragraph_layout, deps={.X})
}

measure_text :: proc (font: Font, text: string) -> Vec2i {
	return Vec2i(bmfont.measure_text(font, text))
}
line_height :: proc() -> int {
	return measure_text(default_font, "M").y
}
space_width :: proc() -> int {
	return measure_text(default_font, " ").x
}

@private
_paragraph_layout :: proc () {
	el := element_curr()
	using s := element_state(Paragraph)

	mw := element_inner_bounds(el, Axis.X)
	if mw <= 0 do return

	lh := line_height()

	cursor:     int
	line_start: int
	word_end:   int
	word_start: int
	in_space:   bool = true
	in_newline: bool = true

	for ch, i in str {
		switch ch {
		case ' ', '\n':
			if !in_space {
				if measure_text(default_font, str[line_start:i]).x > mw {
					draw_text(str[line_start:word_end], color, origin={0, cursor})
					cursor += lh
					line_start = word_start
				}

				word_end = i
				in_space = true
			}

			if ch == '\n' {
				if !in_newline {
					in_newline = true
					draw_text(str[line_start:word_end], color, origin={0, cursor})
				}
				cursor += lh
			}
		case:
			if in_newline {
				in_newline = false
				line_start = i
			}
			if in_space {
				word_start = i
				in_space   = false
			}
		}
	}

	rest := word_end if in_space else len(str)
	if line_start < rest {
		draw_text(str[line_start:rest], color, origin={0, cursor} )
		cursor += lh
	}

	element_set_height(el, cursor)
}

draw_text :: proc (str: string, color: Color, origin: Vec2i = {0, 0}, cursor: ^Vec2i = nil) -> Vec2i {

	Data :: struct {color: Color}
	data := Data{color}
	context.user_ptr = &data

	cursorf := Vec2f(cursor^) if cursor != nil else {}
	bounds := bmfont.draw_text(str, default_font, cb, origin=Vec2f(origin), cursor=&cursorf)
	if cursor != nil do cursor^ = Vec2i(cursorf)

	return Vec2i(bounds.size)

	cb :: proc (srcf, dstf: bmfont.Rect) {
		using data := cast(^Data)context.user_ptr

		src, dst := rect(Rectf(srcf)), rect(Rectf(dstf))

		draw_tex(to_placement(dst), {
			src   = src,
			tint  = color,
			atlas = (^Atlas)(&default_font_atlas),
		})
	}
}
