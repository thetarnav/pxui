package example

import px ".."

page_two :: proc () {

	px.v_stack()
	px.width_fill()

	s, _ := px.element_push(struct {on: bool})
	px.element_pop()

	px.text("Hello", color=COLOR_BLACK)

	{
		px.panel()
		px.size({40, 20})
		px.background_color(COLOR_LIGHT_RED)
		if px.is_clicked() {
			s.on = !s.on
		}
	}

	{
		px.panel()
		px.background_color(COLOR_LIGHT_GREEN)
		px.height(20)
		if s.on {
			px.animate(.width, 100)
		} else {
			px.animate(.width, 10)
		}
	}
}
