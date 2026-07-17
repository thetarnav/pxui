// Pixui example — a small kitchen-sink UI rendered with karl2d.

package example

import "core:slice"
import k2 "shared:karl2d"
import px "../"

UI_W, UI_H :: 320, 200
PIXEL_SCALE :: 4

Vec2  :: [2]f32
Rect  :: px.Rectf
RGBA  :: px.RGBA
Color :: px.Color

camera: k2.Camera

main :: proc () {

	k2.init(UI_W * PIXEL_SCALE, UI_H * PIXEL_SCALE, "Pixui Example",
		options = {window_mode = .Windowed_Resizable})

	camera = {zoom = PIXEL_SCALE}
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
		px.ctx.wheel_delta    = {0, k2.get_mouse_wheel_delta() * 10} // no x delta in k2 :(

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
		dst := k2_rect_px(cmd.dst)

		switch v in cmd.var {
		case px.Draw_Color:
			// Draw color fill
			k2.draw_rect(dst, v)

		case px.Draw_Scissor:
			if v.reset {
				k2.set_scissor_rect(nil)
			} else {
				k2.set_scissor_rect(k2.rect_from_pos_size(
						k2.world_to_screen({dst.x, dst.y}, camera),
						k2.world_to_screen({dst.w, dst.h}, camera),
				))
			}

		case px.Draw_Texture:
			src := Rect{Vec2(v.src.pos), Vec2(v.src.size)}

			// Convert px.Atlas to k2.Texture
			tex, in_map := tex_map[v.atlas]
			if !in_map {
				tex = k2.load_texture_from_bytes_raw(slice.reinterpret([]u8, v.atlas.pixels),
				                                     **v.atlas.size, .RGBA_8_Norm)
				tex_map[v.atlas] = tex
			}

			// Draw texture
			k2.draw_texture_fit(tex, k2_rect(src), dst, tint=v.tint)
		}
	}

	k2.set_scissor_rect(nil)
}

COLOR_TEXT :: RGBA{230, 200, 160, 255}

ui :: proc () {

	// root size
	ws := px.Vec2i(k2.get_screen_size() / PIXEL_SCALE)
	px.size_px(ws)

	@(deferred_none=px.element_pop)
	counter :: proc (id: u64 = 0, loc := #caller_location) -> ^int {
		Counter :: struct {count: int}
		state, _ := px.element_push(Counter, id, loc=loc)
		hovered := px.is_hovered()
		px.textf("Count: %v", state.count, color=k2.BLACK if hovered else COLOR_TEXT)
		if px.is_clicked() {
			state.count += 1
		}
		return &state.count
	}

	px.panel()
	px.padding(6, 12)
	px.width_fill()
	px.height_fill()
	px.nine_slice()

	px.scroll_area()

	defer {
		px.scrollbar()
		px.background_color({180, 140, 100, 255})

		px.scrollbar_thumb()

		px.panel()
		px.size_fill()
		px.margin(2)
		// TODO: grabbed state (even when mouse is outside)
		if px.is_hovered() {
			px.background_color({250, 220, 180, 255})
		} else {
			px.background_color({230, 200, 160, 255})
		}
	}

	{
		px.scroll_content()
		px.padding_l(12)

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
					px.padding(3, 1)
					px.margin_right(1)
				}

				{
					counter()
					px.padding(4, 2)
				}
			}

			{
				px.panel()
				px.nine_slice()

				count := counter()
				px.padding(6, 4)
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
				px.padding(2)
				px.margin_right(2)
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
			px.scroll_area()
			px.width_fill()
			px.height(120)
			px.margin(4)
			px.margin_right(16)
			px.background_color(k2.LIGHT_BROWN)

			defer {
				px.scrollbar()
				px.background_color({180, 140, 100, 255})

				px.scrollbar_thumb()

				px.panel()
				px.size_fill()
				px.margin(2)
				if px.is_hovered() {
					px.background_color({250, 220, 180, 255})
				} else {
					px.background_color({230, 200, 160, 255})
				}
			}

			px.scroll_content()

			cols := 4
			if      ws.x < 250 do cols = 3
			else if ws.x > 400 do cols = 5
			px.masonry(cols)
			px.width_fill()
			px.padding(2)

			{
				px.v_stack()
				px.width_fill()
				px.margin(2)
				px.background_color(k2.LIGHT_GRAY)

				for _ in 0..<2 {
					px.panel()
					px.width_fill()
					px.height(30)
					px.margin(2)
					px.background_color(k2.LIGHT_YELLOW)
				}
			}

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
					px.height((i % 5) * 10 + 16 + j * 16)
					px.margin(1)
				}
			}
		}

		{
			px.panel()
			px.padding(12, 8)
			px.width_fill()

			px.paragraph(`PXUI is a pixel-art focused and aseprite-inspired Odin UI library.
Currently offering an immediate-mode API, layout, text and texture primitives
as well as React-like layout/effect "hooks"—used to implement all builtin components.
Can be used with any rendering backend—see example/ for use with karl2d.`, k2.BROWN)
		}

		{
			px.panel()
			px.margin(2)
			px.padding(8, 2)
			px.background_color(k2.BROWN)
			px.text("END OF PAGE")
		}
	}

	px.draw_color({
		origin = {1.0, 1.0},
		pos    = {-10, -20},
		size   = {14, 24},
	}, k2.LIGHT_RED)
}

k2_rect :: proc (r: Rect) -> k2.Rect {
	return k2.Rect{**r.pos, **r.size}
}
k2_rect_px :: proc (r: px.Rect) -> k2.Rect {
	return k2.Rect{**Vec2(r.pos), **Vec2(r.size)}
}

