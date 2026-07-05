// Pixui example — a small kitchen-sink UI rendered with karl2d.

package example

import "core:fmt"
import k2 "shared:karl2d"
import px "../"

UI_W, UI_H :: 320, 200
PIXEL_SCALE :: 4

Vec2 :: [2]f32
Rect   :: struct {using pos: Vec2, size: Vec2}

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

	@(deferred_none=px.element_pop)
	counter :: proc (id: u64 = 0) -> ^int {
		Counter :: struct {count: int}
		state, _, _ := px.element_push(Counter)
		return &state.count
	}

	px.v_stack()

	{
		px.h_stack()

		px.margin(2)
		px.padding(3)

		{
			count := counter()
			px.padding(2, 1)
			px.margin_right(1)
			count^ += 1
		}

		{
			count := counter()
			px.padding(3, 2)
			count^ -= 1
		}
	}

	{
		count := counter()
		px.margin(4, 0, 4, 5)
		px.padding(6, 2)
		count^ += 1
	}
}

k2_rect :: proc (r: Rect) -> k2.Rect {
	return k2.Rect{**r.pos, **r.size}
}

