// Karl2d frontend for the Pixui example. Same experience as the original
// example/main.odin — renders to a karl2d window.

package main

import "core:slice"
import "core:fmt"
import "core:time"
import "core:log"
import "core:mem"
import k2 "shared:karl2d"
import px "../.."
import app ".."

_ :: mem

UI_W, UI_H :: 320, 200
PIXEL_SCALE :: 3

MAX_FPS :: 60.0
MIN_FPS :: 12.0

MAX_DT :: 1000.0 / MAX_FPS
MIN_DT :: 1000.0 / MIN_FPS

Vec2  :: px.Vec2f
Vec2i :: px.Vec2i
Rect  :: px.Rectf
RGBA  :: px.RGBA
Color :: px.Color

time_now :: proc () -> f32 {
    @static start: time.Time
    if start == {} {
        start = time.now()
    }
    return f32(time.duration_milliseconds(time.since(start)))
}

main :: proc () {

	/* Logger */
	context.logger = log.create_console_logger(
		lowest = .Debug when ODIN_DEBUG else .Warning,
	)

	/* Memory Tracking */
	when ODIN_DEBUG {
		default_allocator := context.allocator
		tracking_allocator: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking_allocator, default_allocator)
		context.allocator = mem.tracking_allocator(&tracking_allocator)

		defer {
			for _, value in tracking_allocator.allocation_map {
				log.warnf("Leaked %v bytes", value.size, location=value.location)
				// log.warnf("%v Leaked %v bytes\n", value.location, value.size)
			}
		}
	}

	_ = k2.init(UI_W * PIXEL_SCALE, UI_H * PIXEL_SCALE, "Pixui Example", options = {
		window_mode = .Windowed_Resizable,
	})

	px.init()

	for step() {}

	app.shutdown()
	k2.shutdown()
}

step :: proc () -> bool {

    @static time_last: f32
    @static time_miss: f32

    time_now   := time_now()
    dt         := time_now - time_last
    elapsed    := dt + time_miss
    capped_dt  := min(dt, MAX_DT*2)

    if elapsed < MAX_DT {
        return true
    }

    time_last = time_now
    time_miss = max(0, elapsed - MAX_DT) // Carry over extra time

	px.trace("step()")

	k2.reset_frame_allocator()
	free_all(context.temp_allocator)

	run_frame: {

		{
			px.trace("k2.update()")
			k2.update() or_return
		}

		// frame(capped_dt) or_return
		_ = capped_dt

		ws := Vec2i(k2.get_screen_size() / PIXEL_SCALE)
		mouse := Vec2i(k2.get_mouse_position() / PIXEL_SCALE)

		app.frame(
			ws    = ws,
			input = {
				mouse          = mouse,
				mouse_pressed  = k2.mouse_button_went_down(.Left),
				mouse_released = k2.mouse_button_went_up(.Left),
				mouse_held     = k2.mouse_button_is_held(.Left),
				wheel_delta    = {k2.get_mouse_wheel_delta_horizontal(), k2.get_mouse_wheel_delta()} * 10,
				time           = int(k2.get_time() * 1000),
			},
		) or_return
	}

	render: {
		k2.clear({30, 30, 40, 255})

		render_ui()

		{
			fps := 1000.0/dt
			str := fmt.tprint(int(fps))
			k2.draw_text(str, 6.5, 10, k2.BLACK)
			k2.draw_text(str, 6,   10, k2.LIGHT_GREEN)
		}

		{
			px.trace("k2.present()")
			k2.present()
		}
	}

    return true
}

render_ui :: proc () {

	px.trace("render_ui")

	ws := px.Vec2i(k2.get_screen_size())

	@static
	tex_map: map[^px.Texture]k2.Texture

	Layer :: struct #all_or_none {tex: int, opacity: f32, offset: Vec2}
	layers := make([dynamic]Layer, context.temp_allocator)

	@static
	render_textures: [dynamic]k2.Render_Texture
	@static
	render_textures_size: Vec2i

	// Clear render textures on window resize
	if render_textures_size != ws {
		for tex in render_textures {
			k2.destroy_render_texture(tex)
		}
		clear(&render_textures)
		render_textures_size = ws
	}

	for cmd in px.get_draw_commands(context.temp_allocator) {

		dst := k2.rect_from_pos_size(Vec2(cmd.dst.pos  * PIXEL_SCALE),
		                             Vec2(cmd.dst.size * PIXEL_SCALE))

		switch v in cmd.var {
		case px.Draw_Color:
			k2.draw_rect(dst, v)

		case px.Draw_Scissor:
			k2.set_scissor_rect(dst if !v.reset else nil)

		case px.Draw_Texture:
			src := Rect{Vec2(v.src.pos), Vec2(v.src.size)}

			tex, in_map := tex_map[v.tex]
			if !in_map {
				tex = k2.load_texture_from_bytes_raw(slice.reinterpret([]u8, v.tex.pixels),
				                                     **v.tex.size, .RGBA_8_Norm)
				tex_map[v.tex] = tex
			}

			k2.draw_texture_fit(tex, k2_rect(src), dst, tint=v.tint)

		case px.Draw_Layer:
			if v.opacity < 1 {
				// Reuse existing texture if available, otherwise create new
				tex: k2.Render_Texture
				if len(layers) < len(render_textures) {
					tex = render_textures[len(layers)]
				} else {
					tex = k2.create_render_texture(**ws)
					append(&render_textures, tex)
				}
				append(&layers, Layer{len(layers), v.opacity, Vec2(cmd.dst.pos)})

				k2.set_render_texture(tex)
				k2.clear(0) // Clear before use
			}
			else {
				layer := pop(&layers)
				k2.set_render_texture(render_textures[layers[len(layers)-1].tex] if len(layers) > 0 else nil)
				k2.draw_texture(render_textures[layer.tex].texture, 0, tint={255, 255, 255, u8(layer.opacity*255)})
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
