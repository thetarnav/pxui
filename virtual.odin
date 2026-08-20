package pxui

Virtual_Stack :: struct {
	length, height, scroll, overscan: int,
	child: proc (int, rawptr), data: rawptr,
	axis: Axis, gap, padding: int,
}
virtual_stack :: proc (
	length, height, scroll: int,
	child: proc (idx: int, data: rawptr), data: rawptr = nil,
	overscan: int = 0, axis: Axis = .V,
	gap: int = 0, padding: int = 0,
	#any_int id: u64 = 0, loc := #caller_location,
) {
	s := element_push(Virtual_Stack, id, loc)
	s^ = {length, height, scroll, overscan, child, data, axis, gap, padding}
	defer element_pop()

	size_axis_fill(perp(axis), loc=loc)
	size_axis_px(axis, (height + gap) * length - gap + padding * 2, loc=loc)
	padding_axis(axis, padding, loc=loc) // TODO: should allow all insets? What about other props?

	subtree(proc () {
		el := element_curr()
		using s := element_state(Virtual_Stack, loc=el.loc)
		bounds_check_axis(axis, loc=el.loc)

		row := height + gap
		viewport := element_inner_bounds_axis(element_parent(loc=el.loc), axis, loc=el.loc)

		if row <= 0 || viewport <= 0 do return

		first := max(scroll/row - overscan, 0)
		last  := min(scroll/row + int_ceil(viewport, row) + overscan, length)

		if first >= last do return

		{stack(axis=axis, gap=gap, loc=el.loc)
			pos(axis, first * row, loc=el.loc)

			for idx in first..<last {
				{panel(id=idx, loc=el.loc)
					size_h(height, loc=el.loc)
					child(idx, data)
				}
			}
		}
	}, loc=loc)
}
