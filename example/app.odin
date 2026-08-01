// Pixui example — application code. No rendering backend dependency.
// The application is driven by `init()`, `frame()`, and `shutdown()`.
// Input state (mouse, keyboard, window size) is provided through `frame()` parameters.

package example

import px ".."

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
COLOR_RED           :: RGBA{220, 120, 120, 255}
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
show_cross:      bool = true
inner_color_idx: int  = 0
cross_size_f:    f32  = 20
selected_tab:    int  = 0

// ─── Lifecycle ──────────────────────────────────────────────────────────

init :: proc () -> bool {
	px.init()
	return true
}

frame :: proc (
	input: px.Frame_Input,
	ws:    Vec2i,
) -> bool {
	px.frame_begin()
	px.ctx.frame_input = input

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

	px.panel()
	px.padding(6, 12)
	px.size_fill()
	px.nine_slice()

	px.rect_cut(.V)
	px.size_fill()

	{// Tabs
		px.radio_group(&selected_tab)
		px.height(20)
		px.width_fill()

		px.h_stack(gap=1)
		px.size_fill()
		px.background_color(COLOR_LIGHT_GRAY)
		px.margin_bottom(4)
		px.padding(1)

		for i in 0..<3 {
			px.radio(i)
			px.height_fill()
			px.background_color(COLOR_DARK_GRAY)
			px.padding(4, 0)

			px.panel()
			px.center_y()

			px.textf("Tab {}", i)
		}
	}

	px.panel()
	px.size_fill()

	switch inner_color_idx {
	case 0: px.background_color(COLOR_WHITE)
	case 1: px.background_color(COLOR_LIGHT_GRAY)
	case 2: px.background_color({200, 200, 220, 255})
	}

	// Centered cross (toggled by the checkbox, sized by the slider).
	defer if show_cross {
		px.panel()
		px.flag(.Non_Interactable)
		px.center()
		px.opacity(0.5)

		for ax in px.Axis {
			px.panel()
			px.center()
			px.size_axis(ax, 4)
			px.size_axis(px.perp(ax), int(cross_size_f))
			px.background_color(COLOR_DARK_GREEN)
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

	px.scroll_content()
	px.padding_l(12)

	px.panel(id=u64(selected_tab))
	px.width_fill()

	switch selected_tab {
	case 0: page_one(ws)
	case:   page_two()
	}
}

button :: proc (text: string) -> (clicked: bool) {

	px.panel()
	px.padding(6, 2)
	px.background_color(COLOR_RED if px.is_hovered() else COLOR_LIGHT_RED)
	clicked = px.is_clicked()

	px.panel()
	px.flag(.Non_Interactable)
	px.center()
	px.text(text)

	return
}
