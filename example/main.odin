// Pixui example — a small kitchen-sink UI rendered with karl2d.
//
// Demonstrates: panel, button, label, checkbox, slider, scroll_view, 9-slice
// panels, BMFont text, and the rectcut layout primitive.

package example

import "core:fmt"
import "core:mem"
import k2 "../karl2d"
import px "../"

UI_W, UI_H :: 320, 200
PIXEL_SCALE :: 4

ui: px.Context
font: ^px.Font
panel_tex: k2.Texture

init :: proc () {
	k2.init(UI_W * PIXEL_SCALE, UI_H * PIXEL_SCALE, "Pixui Example",
		options = {window_mode = .Windowed_Resizable})

	// The Loader only does asset upload (font atlases). All rendering goes
	// through dispatch_draw_cmds below.
	loader := px.Loader{
		load_texture_png = k2_load_texture_png,
	}
	px.init_context(&ui, context.allocator, loader)

	// Load a font (BMFont XML + PNG pair, embedded at compile time).
	font = px.load_font_from_bytes(
		#load("../fonts/minogram_6x10.xml"),
		#load("../fonts/minogram_6x10.png"),
		&ui.backend, context.allocator,
	)
	ui.default_font = font

	// Load the procedurally-generated panel texture.
	panel_tex = k2.load_texture_from_bytes(#load("assets/panel.tga"))
	k2.set_texture_filter(panel_tex, .Point)

	ui.default_panel = px.Panel_Surface{
		nine_slice = px.Nine_Slice{
			src = {{0, 0}, {24, 24}},
			l=4, t=4, r=4, b=4,
			texture = px.Texture_Handle(transmute(u64)panel_tex.handle),
		},
	}
	ui.default_button = px.Panel_Surface{
		fill_color   = {70, 50, 30, 255},
		border_color = {200, 170, 110, 255},
	}
}

step :: proc () -> bool {
	if !k2.update() { return false }
	defer k2.reset_frame_allocator()
	defer free_all(context.temp_allocator)

	k2.clear({30, 30, 40, 255})

	mouse := k2.get_mouse_position()
	mouse.x /= PIXEL_SCALE
	mouse.y /= PIXEL_SCALE

	ui.mouse          = mouse
	ui.mouse_pressed  = k2.mouse_button_went_down(.Left)
	ui.mouse_released = k2.mouse_button_went_up(.Left)
	ui.mouse_held     = k2.mouse_button_is_held(.Left)
	ui.mouse_wheel    = k2.get_mouse_wheel_delta()
	ui.screen_w       = f32(UI_W)
	ui.screen_h       = f32(UI_H)
	ui.pixel_scale    = PIXEL_SCALE

	px.begin_frame(&ui, mouse, PIXEL_SCALE)
	draw_ui()
	px.end_frame(&ui)

	dispatch_draw_cmds(&ui)

	k2.present()
	return true
}

shutdown :: proc () {
	px.destroy_font(font, context.allocator)
	px.destroy_context(&ui)
	k2.destroy_texture(panel_tex)
	k2.shutdown()
}

main :: proc () {
	init()
	for step() {}
	shutdown()
}

draw_ui :: proc () {
	// Build a centered window using rectcut on the root rect.
	root_rect: px.Rect = {{20, 20}, {280, 160}}

	r := root_rect
	_ = px.rect_cut(&r, .Y, .Min, px.Size_Pixels{20}) // title bar cut
	body := r

	if px.panel("Pixui Kitchen Sink", surface = px.Panel_Surface{
		fill_color   = {40, 30, 22, 255},
		border_color = {120, 90, 60, 255},
	}, id = 1) {
		// Body row: two columns of buttons + a slider stack.
		row := body
		col_a := px.rect_cut(&row, .X, .Min, px.Size_Percent_Of_Parent{0.5}, margin = 4)
		col_b := row

		if px.panel("buttons", surface = px.Panel_Surface{
			fill_color = {30, 22, 16, 200},
		}, id = 2) {
			ca := col_a
			for i in 0..<3 {
				ca_row := ca
				ca_row = px.rect_cut(&ca_row, .Y, .Min, px.Size_Percent_Of_Parent{0.33}, margin = 2)
				if _, ok := px.button(fmt.tprintf("Btn %d", i), id = u64(i + 100)); ok {
					fmt.printfln("clicked %d", i)
				}
			}
		}

		if px.panel("sliders", id = 3) {
			cb := col_b
			_ = px.rect_cut(&cb, .Y, .Min, px.Size_Pixels{12})
			_ = px.rect_cut(&cb, .Y, .Min, px.Size_Pixels{14})
			_ = px.rect_cut(&cb, .Y, .Min, px.Size_Pixels{14})

			px.label("Sliders", cb.pos)
			_, checked, _ := px.checkbox("Enable", id = 5)
			_ = checked
			_, v, ch := px.slider("Volume", 0, 100, id = 6)
			_ = v
			_ = ch
		}
	}

	// Scroll view with a list of labels.
	if px.scroll_view({120, 80 * 4}, id = 8) {
		// Position labels vertically inside the scroll view's rect.
		for i in 0..<10 {
			y := f32(i) * 12
			px.label(fmt.tprintf("Item %d", i), {0, y})
		}
	}
}

//-------//
// DISPATCH //
//-------//

dispatch_draw_cmds :: proc (ctx: ^px.Context) {
	for cmd in ctx.draw_cmds {
		switch c in cmd.cmd {
		case px.DCmd_Rect:
			k2.draw_rect(to_k2_rect(c.r), c.color)
		case px.DCmd_Rect_Outline:
			k2.draw_rect_outline(to_k2_rect(c.r), c.thickness, c.color)
		case px.DCmd_Sub_Texture:
			tex := k2.Texture{handle = transmute(k2.Texture_Handle)u64(c.tex), width = 0, height = 0}
			k2.draw_texture_fit(tex, to_k2_rect(c.src), to_k2_rect(c.dst),
				origin = {}, rotation = 0, tint = c.tint)
		case px.DCmd_Text:
			font_handle := cast(k2.Font)u64(c.font)
			k2.draw_text(c.text, c.pos, 10, c.color, font_handle)
		case px.DCmd_Scissor:
			if r, ok := c.rect.(px.Rect); ok {
				k2.set_scissor_rect(to_k2_rect(r))
			} else {
				k2.set_scissor_rect(nil)
			}
		}
	}
}

to_k2_rect :: proc (r: px.Rect) -> k2.Rect {
	return k2.Rect{**r.pos, **r.size}
}

//-------//
// LOADER //
//-------//

k2_load_texture_png :: proc (png_bytes: []u8) -> px.Texture_Handle {
	t := k2.load_texture_from_bytes(png_bytes)
	k2.set_texture_filter(t, .Point)
	return px.Texture_Handle(transmute(u64)t.handle)
}
