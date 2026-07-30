package example

import px ".."

page_two :: proc () {

	px.v_stack()
	px.width_fill()

	s, init := px.element_push(struct {on: bool})
	px.element_pop()

	px.text("Hello", color=COLOR_BLACK)

	{
		px.panel()
		px.padding(6, 2)
		px.background_color(COLOR_RED if px.is_hovered() else COLOR_LIGHT_RED)
		if px.is_clicked() {
			s.on = !s.on
		}

		px.panel()
		px.flag(.Non_Interactable)
		px.origin({0.5, 0.5})
		px.pos({0.5, 0.5})
		px.text("Animate!")
	}

	if px.memo(int(init) * 10 + int(s.on)) {

		px.v_stack()
		px.margin_top(2)
		px.padding(2)
		px.background_color(COLOR_DARK_GRAY)
		px.width_fill()

		for i in 0..<2 {
			px.panel()
			px.background_color(COLOR_LIGHT_GREEN if i == 0 else COLOR_LIGHT_PURPLE)
			px.clip_outside()
			px.height(20)
			px.margin(2)
			if init {
				px.width(200)
			} else if s.on {
				px.animate(.width, px.FILL)
			} else {
				px.animate(.width, 20)
			}

			px.panel()
			px.flag(.Non_Interactable)
			px.origin({0.5, 0.5})
			px.pos({0.5, 0.5})
			px.opacity(0.8)
			px.text("Woooo...")
		}
	}
}
