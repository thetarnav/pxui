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

@private
_paragraph_layout :: proc () {
	el := element_curr()
	using s := element_state(Paragraph)

	mw := element_inner_bounds(el, Axis.X)
	if mw <= 0 do return

	lh := bmfont.line_height(default_font)
	sw := bmfont.space_width(default_font)

	offset_top: int
	line_start: int
	line_width: int
	word_start: int
	word_end:   int
	state: enum {Word, Space, Newline}

	for ch, i in str {
		switch ch {
		case ' ', '\n':
			if state == .Word {

				word_width := bmfont.measure_text(default_font, str[word_start:i]).x
				line_width += word_width
				if line_width > mw {
					draw_text(str[line_start:word_end], color, origin={0, offset_top})
					offset_top += lh
					line_start = word_start
					line_width = word_width
				}

				word_end = i
				state = .Space
			}

			switch ch {
			case '\n':
				if state < .Newline {
					state = .Newline
					draw_text(str[line_start:word_end], color, origin={0, offset_top})
				}
				offset_top += lh
			case ' ':
				line_width += sw
			}
		case:
			#partial switch state {
			case .Newline:
				line_start = i
				word_start = i
				line_width = 0
			case .Space:
				word_start = i
			}
			state = .Word
		}
	}

	if state == .Word {
		line_width += bmfont.measure_text(default_font, str[word_start:len(str)]).x
		if line_width > mw {
			draw_text(str[line_start:word_end], color, origin={0, offset_top})
			offset_top += lh
			line_start = word_start
		}
		word_end = len(str)
	}
	if line_start < word_end {
		draw_text(str[line_start:word_end], color, origin={0, offset_top} )
		offset_top += lh
	}

	element_set_height(el, offset_top)
}

draw_text :: proc (str: string, color: Color, origin: Vec2i = {0, 0}, cursor: ^Vec2i = nil) -> Vec2i {

	Data :: struct {color: Color}
	data := Data{color}
	context.user_ptr = &data

	bounds := bmfont.draw_text(str, default_font, cb, origin=origin, cursor=cursor)

	return Vec2i(bounds.size)

	cb :: proc (src, dst: bmfont.Rect) {
		using data := cast(^Data)context.user_ptr

		draw_tex(to_placement(Rect(dst)), {
			src   = Rect(src),
			tint  = color,
			tex   = (^Texture)(&default_font_atlas),
		})
	}
}
