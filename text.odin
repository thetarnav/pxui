package pxui

import "core:strings"
import "base:runtime"
import "core:fmt"
import "./bmfont"

Font         :: bmfont.Font
measure_text :: bmfont.measure_text

default_font:       Font
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

line_height :: proc() -> f32 {
	return measure_text(default_font, "M").y
}
space_width :: proc() -> f32 {
	return measure_text(default_font, " ").x
}

Paragraph :: struct {str: string, color: Color}
paragraph :: proc (str: string, color: Color = 255, loc := #caller_location) {

	s, _ := element_push(Paragraph, loc=loc)
	defer element_pop()

	width_fill()
	flag(.Non_Interactable)

	s.str, _ = strings.clone(str, context.temp_allocator, loc)
	s.color  = color

	layout(.Y, _paragraph_layout, deps={.X})
}

@private
_paragraph_layout :: proc () {
	el := element_curr()
	using s := element_state(Paragraph)

	mw := element_width()
	sw := space_width()
	lh := line_height()
	lw: f32

	current := make([dynamic]u8, context.temp_allocator)

	cursor:    Vec2f // top-left of the next line to draw
	extra_gap: f32   // extra vertical space inserted between lines

	i, n := 0, len(str)
	for i < n {

		// Read one word (non-space, non-newline).
		word_start := i
		for i < n && str[i] != ' ' && str[i] != '\n' {
			i += 1
		}
		word := str[word_start:i]

		// Hard newline: flush the line with the current word, then start fresh.
		if i < n && str[i] == '\n' {
			append(&current, ' ')
			append(&current, word)
			if len(current) > 0 {
				draw_text(string(current[:]), color, cursor)
				cursor.y += lh + extra_gap
				clear(&current)
			}
			lw = 0
			i += 1
			continue
		}

		// Skip spaces (they belong to the inter-word gap, not the next word).
		for i < n && str[i] == ' ' {
			i += 1
		}

		if len(current) == 0 {
			// First word on a line — always fits (single oversized word goes on
			// its own line; the wrap step below catches the next one).
			append(&current, word)
			lw = measure_text(default_font, word).x
		} else if lw + sw + measure_text(default_font, word).x > f32(mw) {
			// Adding this word would overflow the line: emit what we have, start
			// a new line with the word.
			draw_text(string(current[:]), color, cursor)
			cursor.y += lh + extra_gap
			clear(&current)
			append(&current, word)
			lw = measure_text(default_font, word).x
		} else {
			// Fits on the current line.
			append(&current, ' ')
			append(&current, word)
			lw += sw + measure_text(default_font, word).x
		}
	}

	if len(current) > 0 {
		draw_text(string(current[:]), color, cursor)
		cursor.y += lh + extra_gap
	}

	element_set_height(el, int(cursor.y))
}

draw_text :: proc (str: string, color: Color, origin: Vec2f = {0, 0}, cursor: ^Vec2f = nil) -> Vec2i {

	Data :: struct {color: Color}
	data := Data{color}
	context.user_ptr = &data

	bounds := bmfont.draw_text(str, default_font, cb, origin=origin, cursor=cursor)
	return Vec2i(bounds.size)

	cb :: proc (src, dst: bmfont.Rect) {
		using data := cast(^Data)context.user_ptr

		pos  := Vec2i(dst.pos)
		size := Vec2i(dst.size)

		draw_tex({pos=size_vec(pos), size=size_vec(size)}, {
			src   = {Vec2i(src.pos), Vec2i(src.size)},
			tint  = color,
			atlas = (^Atlas)(&default_font_atlas),
		})
	}
}
