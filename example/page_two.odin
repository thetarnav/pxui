package example

import px ".."

page_two :: proc () {

	// This el is just for state
	s := px.element_push(struct {on: bool, show: bool})
	defer px.element_pop()
	px.width_fill()

	if px.is_init() {
		s.on   = true
		s.show = true
	}

	px.v_stack()
	px.width_fill()

	px.text("Hello!", color=COLOR_BLACK)
	px.text("This is a page with ANIMATIONS", color=COLOR_BLACK)

	{
		px.h_stack(gap=2)

		if button("Animate!") {
			s.on = !s.on
		}
		if button("Hide" if s.show else "Show") {
			s.show = !s.show
		}
	}

	if s.show {

		px.panel()
		px.width_fill()

		if px.is_init() {
			px.opacity(0)
			px.top(10)
		}
		px.transition_all(300)
		px.animate_exit(.opacity, 0.0)
		px.animate_exit(.top, 10)

		if px.memo(int(s.show) * 100 + int(px.is_init()) * 10 + int(s.on)) {

			px.v_stack(gap=4)
			px.margin_top(2)
			px.padding(4)
			px.background_color(COLOR_DARK_GRAY)
			px.width_fill()

			for i in 0..<2 {
				px.panel()
				px.background_color(COLOR_LIGHT_GREEN if i == 0 else COLOR_LIGHT_PURPLE)
				px.clip_outside()
				px.height(20)

				if px.is_init() {
					px.width(200)
				} else if s.on {
					px.width_fill()
				} else {
					px.width(20)
				}
				px.transition(.width)

				px.panel()
				px.flag(.Non_Interactable)
				px.center()

				if px.is_init() {
					px.opacity(0)
				} else if s.on {
					px.opacity(1)
				} else {
					px.opacity(0)
				}
				px.transition(.opacity, 300, .Linear)


				count := counter(COLOR_BLACK)
				count^ += 1
			}
		}
	}
}
