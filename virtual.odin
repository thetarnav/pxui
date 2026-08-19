package pxui

Virtual_Stack :: struct {
	length, height, scroll, overscan: int,
	children: proc (int, int, rawptr), data: rawptr,
	axis: Axis, gap: int,
}
virtual_stack :: proc (
	length, height, scroll: int,
	children: proc (first, last: int, data: rawptr), data: rawptr = nil,
	overscan: int = 0, axis: Axis = .V, gap: int = 0,
	#any_int id: u64 = 0, loc := #caller_location,
) {
	s := element_push(Virtual_Stack, id, loc)
	s^ = {length, height, scroll, overscan, children, data, axis, gap}
	defer element_pop()

	size_axis_fill(perp(axis), loc=loc)
	size_axis_px(axis, (height + gap) * length - gap, loc=loc)

	subtree(proc () {
		el := element_curr()
		using s := element_state(Virtual_Stack, loc=el.loc)
		bounds_check_axis(axis, loc=el.loc)

		row := height + gap
		if row <= 0 do return

		viewport := element_inner_bounds_axis(element_parent(loc=el.loc), axis, loc=el.loc)

		first := max(scroll/row - overscan, 0)
		last  := min(scroll/row + int_ceil(viewport, row) + overscan, length)

		{panel(loc=el.loc)
			pos(axis, first * row, loc=el.loc)
			children(first, last, data)
		}
	}, loc=loc)
}
