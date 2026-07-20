// Karl2d frontend for the Pixui example. Same experience as the original
// example/main.odin — renders to a karl2d window.

package main

import "core:slice"
import k2 "shared:karl2d"
import px "../.."
import app ".."

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

	if px.init() != nil do return

	for k2.update() {
		defer k2.reset_frame_allocator()
		defer free_all(context.temp_allocator)

		k2.clear({30, 30, 40, 255})

		ws := app.Vec2i(k2.get_screen_size() / PIXEL_SCALE)
		mouse := app.Vec2i(k2.screen_to_world(k2.get_mouse_position(), camera))

		continue_frame := app.frame(
			mouse          = mouse,
			mouse_pressed  = k2.mouse_button_went_down(.Left),
			mouse_released = k2.mouse_button_went_up(.Left),
			mouse_held     = k2.mouse_button_is_held(.Left),
			wheel_delta    = {0, f32(k2.get_mouse_wheel_delta() * 10)},
			ws             = ws,
		)
		if !continue_frame do break

		render_ui()
		k2.present()
	}

	app.shutdown()
	k2.shutdown()
}

render_ui :: proc () {

	@static
	tex_map: map[^px.Atlas]k2.Texture

	for cmd in px.get_draw_commands(context.temp_allocator) {
		dst := k2_rect_px(cmd.dst)

		switch v in cmd.var {
		case px.Draw_Color:
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

			tex, in_map := tex_map[v.atlas]
			if !in_map {
				tex = k2.load_texture_from_bytes_raw(slice.reinterpret([]u8, v.atlas.pixels),
				                                     **v.atlas.size, .RGBA_8_Norm)
				tex_map[v.atlas] = tex
			}

			k2.draw_texture_fit(tex, k2_rect(src), dst, tint=v.tint)
		}
	}

	k2.set_scissor_rect(nil)
}

k2_rect :: proc (r: Rect) -> k2.Rect {
	return k2.Rect{**r.pos, **r.size}
}
k2_rect_px :: proc (r: px.Rect) -> k2.Rect {
	return k2.Rect{**Vec2(r.pos), **Vec2(r.size)}
}
