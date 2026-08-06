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

	px.v_stack(gap=6)
	px.width_fill()

	{
		px.v_stack()
		px.width_fill()

		px.text("Hello!", color=COLOR_BROWN)
		px.text("This is a page with ANIMATIONS", color=COLOR_BROWN)
	}

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

		px.panel(1)
		px.width_fill()

		if px.is_init() {
			px.opacity(0)
			px.top(10)
		}
		px.transition_all(300)
		px.animate_exit(.opacity, 0.0)
		px.animate_exit(.top, 10)

		if px.memo(int(s.show) * 100 + int(px.is_init()) * 10 + int(s.on)) {
		// {

			px.v_stack(gap=4)
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

	{
		@static texts := []string{
			"- Welcome weary traveler! To my SHOP\n- How may I assis you?",
			"Use transition(prop, time, ease) to automatically animate changes to element properties.",
			"To implement enter animations use is_init() to set starting props, different from normal ones.",
			"For exit animations use animate_exit(prop, value).\nPXUI will transition to these as the element is removed from the UI.",
		}

		Item :: struct {id: int, text: string}
		State :: struct {
			open:    int,
			items:   [dynamic; 12]Item,
			last_id: int,
			remove:  int,
		}

		s := px.element_push(State, 2)
		defer px.element_pop()

		add_item :: proc (s: ^State) {
			text := texts[s.last_id % len(texts)]
			s.last_id += 1
			append(&s.items, Item{s.last_id, text})
		}

		if px.is_init() {
			for _ in 0..<5 {
				add_item(s)
			}
		}

		defer if s.remove != 0 {
			for item, i in s.items {
				if item.id == s.remove {
					ordered_remove(&s.items, i)
					break
				}
			}
			s.remove = 0
		}

		px.width_fill()
		px.transition(.top)

		px.masonry(cols=2, gap=4)
		px.width_fill()

		for &item in s.items {

			px.panel(item.id)
			px.width_fill()
			px.clip_outside()

			if s.open != item.id {
				px.height(20)
			}

			px.transition(.height)
			px.transition(.left)
			px.transition(.top)

			px.v_stack()
			px.width_fill()
			px.background_color(COLOR_BROWN)

			{
				px.panel()
				px.width_fill()
				px.height(20)
				px.background_color(COLOR_LIGHT_BROWN)

				if px.is_clicked() {
					s.open = item.id if s.open != item.id else 0
				}

				{
					px.panel()
					px.left(1.0)
					px.origin_left(1.0)
					px.height_fill()
					px.width(20)
					px.background_color(COLOR_RED)

					if px.is_hovered() {
						px.background_color(COLOR_DARK_RED)
					}
					if px.is_clicked() {
						s.remove = item.id
					}

					px.panel()
					px.flag(.Non_Interactable)
					px.center()

					px.text("X", color=COLOR_WHITE)
				}

				px.panel()
				px.flag(.Non_Interactable)
				px.center()

				px.textf("Card %i.", item.id, color=COLOR_BROWN)
			}

			{
				px.panel()
				px.width_fill()
				px.padding(4)

				px.paragraph(item.text, color=COLOR_LIGHT_BROWN)
			}
		}

		if len(s.items) < cap(s.items) {
			px.panel(max(int))
			px.width_fill()
			px.height(20)
			px.transition(.left)
			px.transition(.top)

			px.panel()
			px.height(16)
			px.width(0.8)
			px.center()
			px.background_color(COLOR_GREEN)
			if px.is_hovered() {
				px.background_color(COLOR_DARK_GREEN)
			}
			if px.is_clicked() {
				add_item(s)
			}

			px.panel()
			px.flag(.Non_Interactable)
			px.center()

			px.text("Add another", color=COLOR_WHITE)
		}
	}
}
