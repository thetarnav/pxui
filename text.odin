#+private
package pixui

import "base:runtime"
import "./bmfont"

default_font:       bmfont.Font
default_font_atlas: bmfont.Atlas

@init
init_default_font :: proc "contextless" () {
	context = runtime.default_context()
	default_font, default_font_atlas, _ = bmfont.load_json_bytestream(#load("./fonts/monogram.json", string))
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

draw_text :: proc (
	text:  string,
	pos:   [2]f32,
	color: Color = 255,
) {
	ps := ctx.pixel_scale

	Data :: struct {color: Color}
	context.user_ptr = &(Data{color})

	bmfont.draw_text(text, default_font, cb, ps, pos)

	cb: bmfont.Draw_Callback : proc (src, dst: bmfont.Rect) {
		data := cast(^Data)context.user_ptr

		append(&ctx.draw_cmds, DCmd_Sub_Texture{
			src  = Rect(src),
			dst  = Rect(dst),
			tex  = .Font,
			tint = data.color,
		})
	}
}
