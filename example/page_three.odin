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

		defer {px.scrollbar()
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
			length=1_000_000, height=16, gap=4, scroll=-int(scroll), overscan=1,
			children=proc (first, last: int, data: rawptr) {

			{px.v_stack(gap=4)
				for idx in first..<last {
					{px.panel(idx)
						px.padding_h(6)
						px.height(16)
						px.background_color(COLOR_RED)

						{px.panel()
							px.center()
							px.textf("Item %i.", idx+1)
						}
					}
				}
			}
		})
	}
}
