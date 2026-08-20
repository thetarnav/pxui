package example

import px ".."

page_three :: proc () {

	// This el is just for state
	px.element_push(struct {})
	defer px.element_pop()
	px.width_fill()

	{px.scroll_area()
		px.width_fill()
		px.margin(6)
		px.height(200)
		px.background_color(COLOR_LIGHT_YELLOW)

		scroll := px.scroll_value()

		defer {px.scrollbar(10, 14)
			px.left(1.0)
			px.origin_left(1.0)
			px.background_color({180, 140, 100, 200})

			{px.scrollbar_thumb()
				grabbed := px.scrollbar_is_dragging()

				{px.panel()
					px.size_fill()
					px.margin(2)
					// TODO: grabbed state (even when mouse is outside)
					if px.is_hovered() || grabbed {
						px.background_color({250, 220, 180, 255})
					} else {
						px.background_color({230, 200, 160, 255})
					}
				}
			}
		}

		px.virtual_stack(
			length=1_000_000, scroll=-int(scroll), height=16, gap=4, padding=6, overscan=1,
			child=proc (idx: int, data: rawptr) {

			s := px.element_push(struct {toggled: bool})
			defer px.element_pop()

			px.height_fill()
			px.padding_h(6)
			px.margin_h(6)

			if s.toggled {
				px.background_color(COLOR_DARK_GREEN if px.is_hovered() else COLOR_GREEN)
			} else {
				px.background_color(COLOR_DARK_RED if px.is_hovered() else COLOR_RED)
			}

			if px.is_clicked() {
				s.toggled = !s.toggled
			}

			{px.panel()
				px.non_interactable()
				px.center()
				px.textf("Item %i.", idx+1)
			}
		})
	}
}
