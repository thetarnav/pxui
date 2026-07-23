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

root_camera := k2.Camera{zoom = PIXEL_SCALE}
camera: k2.Camera

main :: proc () {

	_ = k2.init(UI_W * PIXEL_SCALE, UI_H * PIXEL_SCALE, "Pixui Example",
	            options = {window_mode = .Windowed_Resizable})

	camera = root_camera
	k2.set_camera(camera)

	if px.init() != nil do return

	for k2.update() {
		defer k2.reset_frame_allocator()
		defer free_all(context.temp_allocator)

		k2.clear({30, 30, 40, 255})

		ws := app.Vec2i(k2.get_screen_size() / PIXEL_SCALE)
		mouse := app.Vec2i(k2.screen_to_world(k2.get_mouse_position(), camera))

		continue_frame := app.frame(
			ws    = ws,
			input = {
				mouse          = mouse,
				mouse_pressed  = k2.mouse_button_went_down(.Left),
				mouse_released = k2.mouse_button_went_up(.Left),
				mouse_held     = k2.mouse_button_is_held(.Left),
				wheel_delta    = {0, f32(k2.get_mouse_wheel_delta() * 10)},
				time           = int(k2.get_time() * 1000),
			},
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

	Layer :: struct #all_or_none {tex: k2.Render_Texture, opacity: f32, offset: Vec2}
	render_textures := make([dynamic]Layer, context.temp_allocator)

	ws := px.Vec2i(k2.get_screen_size())

	scissor: Maybe(k2.Rect)
	// Apply scissor rect with the current camera
	update_scissor :: proc (scissor: Maybe(k2.Rect)) {
		if s, has_scrissor := scissor.?; has_scrissor {
			k2.set_scissor_rect(k2.rect_from_pos_size(
				k2.world_to_screen({s.x, s.y}, camera),
				k2.world_to_screen({s.w, s.h}, camera),
			))
		} else {
			k2.set_scissor_rect(nil)
		}
	}

	for cmd in px.get_draw_commands(context.temp_allocator) {
		dst := k2_rect_px(cmd.dst)

		switch v in cmd.var {
		case px.Draw_Color:
			k2.draw_rect(dst, v)

		case px.Draw_Scissor:
			scissor = dst if !v.reset else nil
			update_scissor(scissor)

		case px.Draw_Texture:
			src := Rect{Vec2(v.src.pos), Vec2(v.src.size)}

			tex, in_map := tex_map[v.atlas]
			if !in_map {
				tex = k2.load_texture_from_bytes_raw(slice.reinterpret([]u8, v.atlas.pixels),
				                                     **v.atlas.size, .RGBA_8_Norm)
				tex_map[v.atlas] = tex
			}

			k2.draw_texture_fit(tex, k2_rect(src), dst, tint=v.tint)

		case px.Draw_Layer:
			if v.opacity < 1 {
				tex := k2.create_render_texture(**ws)
				append(&render_textures, Layer{tex, v.opacity, Vec2(cmd.dst.pos)})
				k2.set_render_texture(tex)
				camera = {zoom=1}
				k2.set_camera(camera)
				update_scissor(scissor)
			} else {
				layer := pop(&render_textures)
				if len(render_textures) > 0 {
					k2.set_render_texture(render_textures[len(render_textures)-1].tex)
					camera = {zoom=1}
					k2.set_camera(camera)
				} else {
					k2.set_render_texture(nil)
					camera = root_camera
					k2.set_camera(root_camera)
				}
				update_scissor(scissor)
				k2.draw_texture(layer.tex.texture, 0, tint={255, 255, 255, u8(layer.opacity*255)})
			}
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
