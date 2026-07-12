// Pixui example — a small kitchen-sink UI rendered with karl2d.

package example

import "core:slice"
import k2 "shared:karl2d"
import px "../"

UI_W, UI_H :: 320, 200
PIXEL_SCALE :: 4

Vec2 :: [2]f32
Rect :: px.Rectf

main :: proc () {

	k2.init(UI_W * PIXEL_SCALE, UI_H * PIXEL_SCALE, "Pixui Example",
		options = {window_mode = .Windowed_Resizable})

	camera := k2.Camera{zoom = PIXEL_SCALE}
	k2.set_camera(camera)

	px.init()

	for k2.update() {
		defer k2.reset_frame_allocator()
		defer free_all(context.temp_allocator)

		k2.clear({30, 30, 40, 255})
		px.frame_begin()

		px.ctx.mouse          = px.Vec2i(k2.screen_to_world(k2.get_mouse_position(), camera))
		px.ctx.mouse_pressed  = k2.mouse_button_went_down(.Left)
		px.ctx.mouse_released = k2.mouse_button_went_up(.Left)
		px.ctx.mouse_held     = k2.mouse_button_is_held(.Left)

		ui()
		px.frame_end()

		render_ui()
		k2.present()
	}

	px.shutdown()
	k2.shutdown()
}

render_ui :: proc () {

	@static
	tex_map: map[^px.Atlas]k2.Texture

	for cmd in px.get_draw_commands(context.temp_allocator) {
		// Scale up the dest rect—ui uses texture pixel size
		src := Rect{Vec2(cmd.src.pos), Vec2(cmd.src.size)}
		dst := Rect{Vec2(cmd.dst.pos), Vec2(cmd.dst.size)}

		// Draw color fill
		if cmd.atlas == nil {
			k2.draw_rect(k2_rect(dst), cmd.tint)
			continue
		}

		// Convert px.Atlas to k2.Texture
		tex, in_map := tex_map[cmd.atlas]
		if !in_map {
			tex = k2.load_texture_from_bytes_raw(slice.reinterpret([]u8, cmd.atlas.pixels),
			                                     **cmd.atlas.size, .RGBA_8_Norm)
			tex_map[cmd.atlas] = tex
		}

		// Draw texture
		k2.draw_texture_fit(tex, k2_rect(src), k2_rect(dst), tint=cmd.tint)
	}

	// ws := k2.get_screen_size() / PIXEL_SCALE
	// k2.draw_rect_outline({0, 0, **ws}, 2, k2.RED)
	//
	// k2.draw_rect_outline(k2_rect_px(px.element_screen_rect(px.ctx.element_root)), 2, k2.GREEN)
}

ui :: proc () {

	// root size
	ws := px.Vec2i(k2.get_screen_size() / PIXEL_SCALE)
	px.size_px(ws)

	@(deferred_none=px.element_pop)
	counter :: proc (id: u64 = 0) -> ^int {
		Counter :: struct {count: int}
		state, _, _ := px.element_push(Counter)
		hovered := px.is_hovered()
		px.textf("Count: %v", state.count, color=k2.BLACK if hovered else {230, 200, 160, 255})
		if px.is_clicked() {
			state.count += 1
		}
		return &state.count
	}

	px.panel()
	px.margin(4)
	px.padding(10)
	px.width_fill()
	px.nine_slice()

	px.v_stack()
	px.width_fill()
	px.background_color(k2.WHITE)

	{
		px.h_stack()
		px.margin(4)

		{
			px.panel()
			px.nine_slice()
			px.margin_right(4)

			px.h_stack()
			px.padding(3)

			{
				counter()
				px.padding(2, 1)
				px.margin_right(1)
			}

			{
				counter()
				px.padding(3, 2)
			}
		}

		{
			px.panel()
			px.nine_slice()

			count := counter()
			px.padding(6, 2, 6, 5)
			count^ += 1
		}
	}

	{
		px.rect_cut(.H)
		px.width(1.0)
		px.background_color(k2.LIGHT_BROWN)
		px.padding(4)
		px.margin(4)

		{
			counter()
			px.padding(3, 0, 3, 3)
		}

		{
			px.panel()
			px.background_color(k2.LIGHT_YELLOW)
			px.margin_right(3)
			px.size_fill()
		}

		{
			px.panel()
			px.background_color(k2.LIGHT_PURPLE)
			px.margin_right(3)
			px.width(20)
			px.height_fill()
		}

		{
			px.panel()
			px.background_color(k2.LIGHT_BLUE)
			px.size_fill()
		}
	}

	{
		px.flex_h()
		px.width_fill()
		px.background_color(k2.LIGHT_BROWN)
		px.padding(2)
		px.margin(4)

		for i in 0..<10 {
			px.panel()
			px.background_color(k2.LIGHT_RED)
			px.margin(2)
			px.width((i % 5) * 10 + 16)
			px.height(14)
		}
	}

	{
		cols := 4
		if      ws.x < 250 do cols = 3
		else if ws.x > 400 do cols = 5
		px.masonry(cols)
		px.width_fill()
		px.background_color(k2.LIGHT_BROWN)
		px.padding(2)
		px.margin(4)
		px.margin_right(16)

		for i in 0..<8 {
			px.rect_cut()
			px.width_fill()
			px.margin(2)
			px.padding(1)
			px.background_color(k2.LIGHT_YELLOW)

			for j in 0..<2 {
				px.panel()
				px.background_color(k2.LIGHT_RED)
				px.width_fill()
				px.height((i % 5) * 8 + 10 + j * 16)
				px.margin(1)
			}
		}
	}

	px.draw({
		variant = px.Draw_Color{k2.LIGHT_RED},
		origin  = {1.0, 1.0},
		pos     = {-10, -20},
		size    = {14, 24},
	})
}

k2_rect :: proc (r: Rect) -> k2.Rect {
	return k2.Rect{**r.pos, **r.size}
}
k2_rect_px :: proc (r: px.Rect) -> k2.Rect {
	return k2.Rect{**Vec2(r.pos), **Vec2(r.size)}
}

