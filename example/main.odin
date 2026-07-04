// Pixui example — a small kitchen-sink UI rendered with karl2d.

package example

import "core:fmt"
import k2 "shared:karl2d"
import px "../"

UI_W, UI_H :: 320, 200
PIXEL_SCALE :: 4

Vec2 :: [2]f32
Rect :: px.Rect

main :: proc () {

	k2.init(UI_W * PIXEL_SCALE, UI_H * PIXEL_SCALE, "Pixui Example",
		options = {window_mode = .Windowed_Resizable})

	px.init()

	for k2.update() {
		defer k2.reset_frame_allocator()
		defer free_all(context.temp_allocator)

		k2.clear({30, 30, 40, 255})

		mouse := k2.get_mouse_position() / PIXEL_SCALE

		draw_ui()

		px.frame_end()
		k2.present()
	}

	px.shutdown()
	k2.shutdown()
}

draw_ui :: proc () {

	{
		px.element_push(struct {})
		defer px.element_pop()

		{
			state, el_id, init := px.element_push(struct {count: int})
			defer px.element_pop()

			state.count += 1
			fmt.println("Count A", state.count, el_id, init)
		}

		{
			state, el_id, init := px.element_push(struct {count: int})
			defer px.element_pop()

			state.count -= 1
			fmt.println("Count B", state.count, el_id, init)
		}
	}

	{
		state, el_id, init := px.element_push(struct {count: int})
		defer px.element_pop()

		state.count += 1
		fmt.println("Count C", state.count, el_id, init)
	}
}

k2_rect :: proc (r: Rect) -> k2.Rect {
	return k2.Rect{**r.pos, **r.size}
}

