package pxui

import "core:math"
import "core:slice"


@private
_stack_update_layout :: proc (el: ^Element, $AX: Axis, gap: int = 0) {

	prev, has_children := element_get(el.child_first)
	if !has_children do return

	cursor := element_bounds(prev, AX) + gap

	child_id := prev.next
	for child in element_get(child_id) {
		defer child_id, prev = child.next, child

		// Each child's bounds follow the previous child's bounds, with a gap
		element_set_pos(child, AX, cursor)
		cursor += element_bounds(child, AX) + gap
	}

	// Total size includes the last child's bounds (without the trailing gap).
	element_set_inner_bounds(el, AX, cursor - gap)
}

V_Stack :: struct {gap: int}
v_stack_update_layout :: proc () {
	el := element_curr()
	s := element_state(V_Stack, el)
	_stack_update_layout(el, .Y, s.gap)
}
v_stack_begin :: proc (gap: int = 0, id: u64 = 0, loc := #caller_location) {
	s, _ := element_push(V_Stack, id, loc)
	s.gap = gap
	layout(.V, v_stack_update_layout)
}
v_stack_end :: proc (gap: int = 0, id: u64 = 0, loc := #caller_location) {
	assert(element_hash(typeid_of(V_Stack), id) == element_curr().hash, loc=loc)
	element_pop()
}
@(deferred_in=v_stack_end)
v_stack :: proc (gap: int = 0, id: u64 = 0, loc := #caller_location) -> bool {
	v_stack_begin(gap, id, loc)
	return true
}

H_Stack :: struct {gap: int}
h_stack_update_layout :: proc () {
	el := element_curr()
	s  := element_state(H_Stack, el)
	_stack_update_layout(el, .X, s.gap)
}
h_stack_begin :: proc (gap: int = 0, id: u64 = 0, loc := #caller_location) {
	s, _ := element_push(H_Stack, id, loc)
	s.gap = gap
	layout(.H, h_stack_update_layout)
}
h_stack_end :: proc (gap: int = 0, id: u64 = 0, loc := #caller_location) {
	assert(element_hash(typeid_of(H_Stack), id) == element_curr().hash, loc=loc)
	element_pop()
}
@(deferred_in=h_stack_end)
h_stack :: proc (gap: int = 0, id: u64 = 0, loc := #caller_location) -> bool {
	h_stack_begin(gap, id, loc)
	return true
}


@private
_flex_update_layout :: proc (el: ^Element, $AXIS: Axis, gap: Vec2i = 0) {

	prev, has_children := element_get(el.child_first)
	if !has_children do return

	PERP :: Axis((int(AXIS) + 1) % 2)

	// Max size on the axis = inner bounds (area available to children).
	max_size := element_inner_bounds(el, AXIS)

	// Position first child at the start of the reference plane.
	element_set_pos(prev, {AXIS = 0, PERP = 0})
	cursor: Vec2i
	cursor[PERP] = 0
	cursor[AXIS] = element_bounds(prev, AXIS)

	row_size: int

	child_id := prev.next
	for child in element_get(child_id) {
		defer child_id, prev = child.next, child

		// Wrap to a new row if the next child doesn't fit.
		// Leave room for the gap between this child and
		// the next on the same row.
		if cursor[AXIS] > 0 &&
		   cursor[AXIS] + element_bounds(child, AXIS) + gap[AXIS] > max_size
		{
			cursor[AXIS] = 0
			cursor[PERP] += row_size + gap[PERP]
			row_size = 0
		}

		element_set_pos(child, {AXIS = cursor[AXIS], PERP = cursor[PERP]})

		cursor[AXIS] += element_bounds(child, AXIS) + gap[AXIS]
		row_size = max(row_size, element_bounds(child, PERP))
	}

	element_set_inner_bounds(el, PERP, cursor[PERP] + element_bounds(prev, PERP))
}

Flex :: struct {axis: Axis, gap: Vec2i}
flex_update_layout :: proc () {
	el := element_curr()
	s  := element_state(Flex, el)
	if s.axis == .H do _flex_update_layout(el, .H, s.gap)
	else            do _flex_update_layout(el, .V, s.gap)
}
flex_begin :: proc (axis: Axis = .H, gap: Vec2i = 0, id: u64 = 0, loc := #caller_location) {
	s, _ := element_push(Flex, id, loc)
	s.axis = axis
	s.gap  = gap
	layout(axis, flex_update_layout)
}
flex_end :: proc () {
	assert(typeid_of(Flex) == element_curr().type)
	element_pop()
}
@(deferred_none=flex_end)
flex :: proc (axis: Axis = .H, gap: Vec2i = 0, id: u64 = 0, loc := #caller_location) -> bool {
	flex_begin(axis, gap, id, loc)
	return true
}
@(deferred_none=flex_end)
flex_h :: proc (gap: Vec2i = 0, id: u64 = 0, loc := #caller_location) -> bool {
	flex_begin(.H, gap, id, loc)
	return true
}
@(deferred_none=flex_end)
flex_v :: proc (gap: Vec2i = 0, id: u64 = 0, loc := #caller_location) -> bool {
	flex_begin(.V, gap, id, loc)
	return true
}


rect_cut_update_layout :: proc () {

	el  := element_curr()
	s   := element_state(Rect_Cut, el)
	ax  := s.axis
	gap := s.gap

	// space_taken = total outer bounds of non-Fill children.
	space_taken: int
	fills: int

	child_id := el.child_first
	for child in element_get(child_id) {
		defer child_id = child.next

		if _, is_fill := child.size[ax].(Fill); is_fill {
			fills += 1
		} else {
			space_taken += element_bounds(child, ax)
		}

		space_taken += gap
	}

	space_taken = max(space_taken - gap, 0) // Remove last el gap

	prev: ^Element
	child_id = el.child_first
	for child in element_get(child_id) {
		defer child_id, prev = child.next, child

		// All fill-children divide the remaining space equally.
		if _, is_fill := child.size[ax].(Fill); is_fill {
			space := (element_inner_bounds(el, ax) - space_taken) / fills
			space_taken += space
			fills -= 1
			element_set_bounds(child, ax, space)
		}

		pos := 0
		if prev != nil {
			pos += element_pos(prev, ax)
			pos += element_bounds(prev, ax)
			pos += gap
		}
		element_set_pos(child, ax, pos)
	}
}

Rect_Cut :: struct {axis: Axis, gap: int}
rect_cut_begin :: proc (axis: Axis = .H, gap: int = 0, id: u64 = 0, loc := #caller_location) {
	s, _ := element_push(Rect_Cut, id, loc)
	s.axis = axis
	s.gap  = gap
	layout_axis(axis, rect_cut_update_layout)
}
rect_cut_end :: proc (axis: Axis = .H, gap: int = 0, id: u64 = 0, loc := #caller_location) {
	assert(element_hash(typeid_of(Rect_Cut), id) == element_curr().hash, loc=loc)
	element_pop()
}
@(deferred_in=rect_cut_end)
rect_cut :: proc (axis: Axis = .H, gap: int = 0, id: u64 = 0, loc := #caller_location) -> bool {
	rect_cut_begin(axis, gap, id, loc)
	return true
}


@private
_masonry_layout_axis :: proc (el: ^Element, c: int, $AXIS: Axis) {

	_, has_children := element_get(el.child_first)
	if !has_children do return

	c := c if c > 0 else 1

	PERP :: Axis((int(AXIS) + 1) % 2)

	cols := make([]int, c, context.temp_allocator)

	col_w := element_inner_bounds(el, PERP) / c // TODO: what to do about the flored pixel fraction (it grows space after)

	child_id := el.child_first
	for child in element_get(child_id) {
		defer child_id = child.next

		min_idx := slice.min_index(cols) or_break

		element_set_pos(child, {AXIS=cols[min_idx], PERP=min_idx * col_w})

		cols[min_idx] += element_bounds(child, AXIS)
	}

	element_set_inner_bounds(el, AXIS, slice.max(cols))
}
@private
_masonry_layout_perp :: proc (el: ^Element, c: int, $AXIS: Axis) {

	_, has_children := element_get(el.child_first)
	if !has_children do return

	c := c if c > 0 else 1

	PERP :: Axis((int(AXIS) + 1) % 2)

	col_w := element_inner_bounds(el, PERP) / c

	child_id := el.child_first
	for child in element_get(child_id) {
		defer child_id = child.next

		element_set_bounds(child, PERP, col_w)
	}
}

Masonry :: struct {axis: Axis, cols: int}
masonry_begin :: proc (cols: int, axis: Axis = .V, id: u64 = 0, loc := #caller_location) {
	bounds_check_axis(axis, loc)

	s, _ := element_push(Masonry, id, loc)
	s.axis = axis
	s.cols = cols

	layout(axis, proc () {
		el := element_curr()
		s  := element_state(Masonry, el)
		if s.axis == .H do _masonry_layout_axis(el, s.cols, .H)
		else            do _masonry_layout_axis(el, s.cols, .V)
	}, deps={perp(axis)})

	layout(perp(axis), proc () {
		el := element_curr()
		s  := element_state(Masonry, el)
		if s.axis == .H do _masonry_layout_perp(el, s.cols, .H)
		else            do _masonry_layout_perp(el, s.cols, .V)
	})
}
masonry_end :: proc (cols: int, axis: Axis = .V, id: u64 = 0, loc := #caller_location) {
	assert(element_hash(typeid_of(Masonry), id) == element_curr().hash, loc=loc)
	element_pop()
}
@(deferred_in=masonry_end)
masonry :: proc (cols: int, axis: Axis = .V, id: u64 = 0, loc := #caller_location) -> bool {
	masonry_begin(cols, axis, id, loc)
	return true
}


Scroll_Area_Container :: struct {axis: Axis, scroll: f32}
Scroll_Area_Content   :: struct {}
scroll_area_begin :: proc (axis: Axis = .V, id: u64 = 0, loc := #caller_location) {

	s, _ := element_push(Scroll_Area_Container, id, loc)
	s.axis = axis

	size_fill()
	clip_outside()
	flag(.Capture_Wheel)

	s.scroll += wheel_delta_axis(axis)

	layout_axis(axis, proc () {
		area := element_curr()
		s    := element_state(Scroll_Area_Container,)
		ax   := s.axis

		content := element_get_assert(area.child_first)

		oh := element_inner_bounds(area, ax)
		ih := element_bounds(content, ax)

		s.scroll = clamp(s.scroll, -f32(ih-oh), 0)

		element_set_pos(content, ax, int(s.scroll))
	}, deps={axis, perp(axis)})
}
scroll_area_end :: proc (axis: Axis = .V, id: u64 = 0, loc := #caller_location) {
	assert(element_hash(typeid_of(Scroll_Area_Container), id) == element_curr().hash, loc=loc)
	element_pop()
}
@(deferred_in=scroll_area_end)
scroll_area :: proc (axis: Axis = .V, id: u64 = 0, loc := #caller_location) -> bool {
	scroll_area_begin(axis, id, loc)
	return true
}

scroll_content_begin :: proc (loc := #caller_location) {
	element_push(Scroll_Area_Content, loc=loc)
	container := element_parent()
	state := element_state(Scroll_Area_Container, container, loc)
	size_axis_fill(perp(state.axis))
}
scroll_content_end :: proc (loc := #caller_location) {
	assert(typeid_of(Scroll_Area_Content) == element_curr().type, loc=loc)
	element_pop()
}
@(deferred_in=scroll_content_end)
scroll_content :: proc (loc := #caller_location) -> bool {
	scroll_content_begin(loc)
	return true
}

Scroll_Area_Scrollbar       :: struct {dragging: bool, offset: int}
Scroll_Area_Scrollbar_Thumb :: struct {}
scrollbar_begin :: proc (loc := #caller_location) {
	element_push(Scroll_Area_Scrollbar, loc=loc)
	container := element_state(Scroll_Area_Container, element_parent(), loc)

	size_axis_fill(container.axis)
	size_axis(perp(container.axis), 10)

	get_thumb_pos_and_size :: proc (oh, ih: int, scroll: f32) -> (pos, size: int) {
		if ih <= oh {
			size = oh
		} else if ih > 0 && oh > 0 {
			pos  = int(math.ceil(f32(oh) * (1 - f32(oh)/f32(ih)) * (-scroll / (f32(ih)-f32(oh)))))
			size = int(f32(oh) * f32(oh)/f32(ih))
		} else {
			size = 10
		}
		return
	}

	layout_axis(container.axis, proc () {
		scrollbar := element_curr()
		container := element_parent()
		content   := element_get_assert(container.child_first)
		thumb     := element_get_assert(scrollbar.child_first)
		state     := element_state(Scroll_Area_Container, container)
		_          = element_state(Scroll_Area_Scrollbar_Thumb, thumb)

		ax     := state.axis
		scroll := state.scroll

		oh := element_inner_bounds(container, ax)
		ih := element_bounds(content, ax)

		thumb_pos, thumb_size := get_thumb_pos_and_size(oh, ih, scroll)

		element_set_pos(thumb, ax, thumb_pos)
		element_set_bounds(thumb, ax, thumb_size)
	})

	effect(proc () {
		scrollbar := element_curr()
		container := element_parent()
		content   := element_get_assert(container.child_first)
		thumb     := element_get_assert(scrollbar.child_first)
		state     := element_state(Scroll_Area_Container, container)
		_          = element_state(Scroll_Area_Scrollbar_Thumb, thumb)
		using scrollbar_state := element_state(Scroll_Area_Scrollbar, scrollbar)

		ax     := state.axis
		scroll := &state.scroll

		oh := element_inner_bounds(container, ax)
		ih := element_bounds(content, ax)

		scrollbar_pos := element_screen_pos(scrollbar)
		thumb_pos, thumb_size := get_thumb_pos_and_size(oh, ih, scroll^)

		if is_press_in(thumb) {
			dragging = true
			offset   = ctx.mouse[ax] - scrollbar_pos[ax] - thumb_pos - thumb_size/2
		} else if is_press_in(scrollbar) {
			dragging = true
		}

		if is_released() {
			dragging = false
			offset   = 0
		}

		if dragging {
			h := f32(oh-thumb_size)
			p := f32(ctx.mouse[ax]) - f32(scrollbar_pos[ax]) - f32(oh)/2 - f32(offset)
			scroll^ = -math.remap_clamped(p, -h/2, h/2, 0, f32(ih-oh))
		}
	})
}
scrollbar_end :: proc (loc := #caller_location) {
	assert(typeid_of(Scroll_Area_Scrollbar) == element_curr().type, loc=loc)
	element_pop()
}
@(deferred_in=scrollbar_end)
scrollbar :: proc (loc := #caller_location) -> bool {
	scrollbar_begin(loc)
	return true
}

scrollbar_thumb_begin :: proc (loc := #caller_location) {
	element_push(Scroll_Area_Scrollbar_Thumb, loc=loc)
	size_fill()
}
scrollbar_thumb_end :: proc (loc := #caller_location) {
	assert(typeid_of(Scroll_Area_Scrollbar_Thumb) == element_curr().type, loc=loc)
	element_pop()
}
@(deferred_in=scrollbar_thumb_end)
scrollbar_thumb :: proc (loc := #caller_location) -> bool {
	scrollbar_thumb_begin(loc)
	return true
}

scrollbar_is_dragging :: proc () -> bool {
	el        := element_curr()
	scrollbar := element_parent() if el.type == Scroll_Area_Scrollbar_Thumb else el
	s         := element_state(Scroll_Area_Scrollbar, scrollbar)
	return s.dragging
}
