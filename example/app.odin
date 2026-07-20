// Pixui example — application code. No rendering backend dependency.
// The application is driven by `init()`, `frame()`, and `shutdown()`.
// Input state (mouse, keyboard, window size) is provided through `frame()` parameters.

package example

import px "../"

UI_W, UI_H :: 320, 200
PIXEL_SCALE :: 4

Vec2  :: [2]f32
Vec2i :: [2]int
Rect  :: px.Rectf
RGBA  :: px.RGBA
Color :: px.Color

// Color palette (independent of any rendering backend).
// Kept pale to match the original karl2d aesthetic.
COLOR_TEXT          :: RGBA{210, 180, 160, 255}
COLOR_WHITE         :: RGBA{255, 255, 255, 255}
COLOR_BLACK         :: RGBA{0, 0, 0, 255}
COLOR_BROWN         :: RGBA{139, 90, 43, 255}
COLOR_LIGHT_GREEN   :: RGBA{180, 220, 180, 255}
COLOR_LIGHT_GRAY    :: RGBA{200, 200, 200, 255}
COLOR_LIGHT_BROWN   :: RGBA{210, 190, 160, 255}
COLOR_LIGHT_YELLOW  :: RGBA{240, 230, 180, 255}
COLOR_LIGHT_PURPLE  :: RGBA{210, 200, 230, 255}
COLOR_LIGHT_BLUE    :: RGBA{170, 190, 220, 255}
COLOR_LIGHT_RED     :: RGBA{230, 140, 140, 255}
COLOR_DARK_GREEN    :: RGBA{34, 120, 60, 255}
COLOR_DARK_GRAY     :: RGBA{60, 60, 70, 255}

// ─── Input component state ───────────────────────────────────────────────
// These are driven by the input components in the demo.
show_cross       : bool = true
inner_pad        : int  = 0
inner_color_idx  : int  = 0
cross_size_f     : f32  = 20

// ─── Lifecycle ──────────────────────────────────────────────────────────

init :: proc () -> bool {
	px.init()
	return true
}

frame :: proc (
	mouse: Vec2i,
	mouse_pressed, mouse_released, mouse_held: bool,
	wheel_delta: Vec2,
	ws: Vec2i,
) -> bool {
	px.frame_begin()
	px.ctx.mouse          = mouse
	px.ctx.mouse_pressed  = mouse_pressed
	px.ctx.mouse_released = mouse_released
	px.ctx.mouse_held     = mouse_held
	px.ctx.wheel_delta    = wheel_delta

	ui(ws)
	px.frame_end()
	return true
}

shutdown :: proc () {
	px.shutdown()
}

// ─── UI definition ─────────────────────────────────────────────────────

ui :: proc (ws: Vec2i) {

	// root size
	px.size_px(ws)

	@(deferred_none=px.element_pop)
	counter :: proc (color := COLOR_TEXT, id: u64 = 0, loc := #caller_location) -> ^int {
		Counter :: struct {count: int}
		state, _ := px.element_push(Counter, id, loc=loc)
		hovered := px.is_hovered()
		px.textf("Count: %v", state.count, color=COLOR_BLACK if hovered else color)
		if px.is_clicked() {
			state.count += 1
		}
		return &state.count
	}

	px.panel()
	px.padding(6, 12)
	px.size_fill()
	px.nine_slice()

	// Inner panel: padding controlled by the slider, color by the radio.
	px.panel()
	px.size_fill()
	px.padding(inner_pad)
	{
		// Visualize the padding change.
		px.panel()
		px.size_fill()
		switch inner_color_idx {
		case 0: px.background_color(COLOR_WHITE)
		case 1: px.background_color(COLOR_LIGHT_GRAY)
		case 2: px.background_color({200, 200, 220, 255})
		}

		// Centered cross (toggled by the checkbox, sized by the slider).
		if show_cross do for ax in px.Axis {
			px.panel()
			px.origin_left(0.5)
			px.origin_top(0.5)
			px.left(0.5)
			px.top(0.5)
			px.size_axis(ax, 4)
			px.size_axis(px.perp(ax), int(cross_size_f))
			px.background_color(COLOR_LIGHT_GREEN)
		}
	}

	px.scroll_area()

	defer {
		px.scrollbar()
		px.background_color({180, 140, 100, 255})

		px.scrollbar_thumb()
		grabbed := px.scrollbar_is_dragging()

		px.panel()
		px.size_fill()
		px.margin(2)
		// TODO: grabbed state (even when mouse is outside)
		if px.is_hovered() || grabbed {
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
			px.background_color(COLOR_DARK_GRAY)
			px.padding(4)
			px.margin(4)

			{
				counter()
				px.padding(2)
				px.margin_right(2)
			}

			{
				px.panel()
				px.background_color(COLOR_LIGHT_YELLOW)
				px.margin_right(3)
				px.size_fill()
			}

			{
				px.panel()
				px.background_color(COLOR_LIGHT_PURPLE)
				px.margin_right(3)
				px.width(20)
				px.height_fill()
			}

			{
				px.panel()
				px.background_color(COLOR_LIGHT_BLUE)
				px.size_fill()
			}
		}

		{
			px.flex_h()
			px.width_fill()
			px.background_color(COLOR_DARK_GRAY)
			px.padding(2)
			px.margin(4)

			for i in 0..<10 {
				px.panel()
				px.background_color(COLOR_LIGHT_RED)
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
			px.background_color(COLOR_LIGHT_BROWN)

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
				px.background_color({100, 100, 100, 255})

				for _ in 0..<2 {
					px.panel()
					px.width_fill()
					px.height(30)
					px.margin(2)
					px.background_color(COLOR_LIGHT_YELLOW)
				}
			}

			for i in 0..<8 {
				px.rect_cut()
				px.width_fill()
				px.margin(2)
				px.padding(1)
				px.background_color(COLOR_LIGHT_YELLOW)

				for j in 0..<2 {
					px.panel()
					px.background_color(COLOR_LIGHT_RED)
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
Can be used with any rendering backend—see example/ for use with karl2d.`, COLOR_BROWN)
		}

		{
			px.panel()
			px.margin(2)
			px.padding(8, 2)
			px.background_color(COLOR_BROWN)
			px.text("END OF PAGE")
		}

		// ─── Input components demo ──────────────────────────────────────
		// These controls drive layout data in the demo above.
		{
			px.panel()
			px.margin(2)
			px.padding(8, 4)
			px.width_fill()
			px.background_color({50, 50, 60, 255})

			px.v_stack()
			px.width_fill()

			// Checkbox: toggles the centered cross in the top panel.
			{
				px.checkbox(&show_cross)

				px.h_stack()

				{
					px.panel()
					px.size_px({12, 12})
					px.margin_right(4)
					px.background_color(COLOR_WHITE if show_cross else COLOR_DARK_GRAY)
				}

				px.panel()
				px.top(0.5)
				px.origin_top(0.5)

				px.textf("Show cross", color=COLOR_TEXT)
			}

			// Radio: selects the inner panel's background color.
			{
				px.radio_group(&inner_color_idx)

				px.h_stack()

				px.text("BG = ", color=COLOR_TEXT)

				for i in 0..=2 {
					px.radio(i)
					px.padding_right(4)
					name: string
					switch i {
					case 0: name = "white"
					case 1: name = "gray"
					case 2: name = "blue"
					}
					px.text(name, color=COLOR_WHITE if inner_color_idx == i else COLOR_TEXT)
				}
			}

			 // Slider: controls the inner panel's padding.
			{
			 	px.slider(&cross_size_f, 4, 100)
			 	px.width_fill()
			 	px.height(20)
			 	px.background_color(COLOR_WHITE)

			 	px.slider_thumb()
			 	px.height_fill()
				px.width(20)
			 	px.background_color(COLOR_LIGHT_RED)
			}

			 // Vertical slider demo: show that the slider works on either axis.
			{
			 	px.slider(&cross_size_f, min=4, max=60, axis=.V)
				px.width(20)
			 	px.height(80)
			 	px.background_color(COLOR_WHITE)

			 	px.slider_thumb()
				px.width_fill()
				px.height(20)
			 	px.background_color(COLOR_LIGHT_BLUE)
			}
		}
	}
}
