package pxui

import "core:math"
import "core:slice"


@private
_stack_update_layout :: proc (el: ^Element, $AX: Axis, gap: int = 0) {

	child_id: Element_Handle
	prev, has_children := each_element_layout_child(el, &child_id)
	if !has_children do return

	cursor := element_bounds(prev, AX) + gap

	for child in each_element_layout_child(el, &child_id) {
		defer prev = child

		// Each child's bounds follow the previous child's bounds, with a gap
		element_set_pos(child, AX, cursor)
		cursor += element_bounds(child, AX) + gap
	}

	// Total size includes the last child's bounds (without the trailing gap).
	element_set_inner_bounds(el, AX, cursor - gap)
}

Stack :: struct {axis: Axis, gap: int}
stack_update_layout :: proc () {
	el := element_curr()
	s  := element_state(Stack, el)
	if s.axis == .X do _stack_update_layout(el, .X, s.gap)
	else            do _stack_update_layout(el, .Y, s.gap)
}
stack_begin :: proc (axis: Axis = .V, gap: int = 0, #any_int id: u64 = 0, loc := #caller_location) {
	s := element_push(Stack, id, loc)
	s^ = {axis, gap}
	layout(axis, stack_update_layout)
}
stack_end :: proc (axis: Axis = .V, gap: int = 0, #any_int id: u64 = 0, loc := #caller_location) {
	assert(element_hash(typeid_of(Stack), id) == element_curr(loc).hash, loc=loc)
	element_pop()
}
@(deferred_in=stack_end)
stack :: proc (axis: Axis = .V, gap: int = 0, #any_int id: u64 = 0, loc := #caller_location) -> bool {
	stack_begin(axis, gap, id, loc)
	return true
}

v_stack_begin :: proc (gap: int = 0, #any_int id: u64 = 0, loc := #caller_location) {
	stack_begin(.V, gap, id, loc)
}
v_stack_end :: proc (gap: int = 0, #any_int id: u64 = 0, loc := #caller_location) {
	stack_end(.V, gap, id, loc)
}
@(deferred_in=v_stack_end)
v_stack :: proc (gap: int = 0, #any_int id: u64 = 0, loc := #caller_location) -> bool {
	v_stack_begin(gap, id, loc)
	return true
}

h_stack_begin :: proc (gap: int = 0, #any_int id: u64 = 0, loc := #caller_location) {
	stack_begin(.H, gap, id, loc)
}
h_stack_end :: proc (gap: int = 0, #any_int id: u64 = 0, loc := #caller_location) {
	stack_end(.H, gap, id, loc)
}
@(deferred_in=h_stack_end)
h_stack :: proc (gap: int = 0, #any_int id: u64 = 0, loc := #caller_location) -> bool {
	h_stack_begin(gap, id, loc)
	return true
}


@private
_flex_update_layout :: proc (el: ^Element, $AXIS: Axis, gap: Vec2i = 0) {

	child_id: Element_Handle
	prev, has_children := each_element_layout_child(el, &child_id)
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

	for child in each_element_layout_child(el, &child_id) {
		defer prev = child

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
flex_begin :: proc (axis: Axis = .H, gap: Vec2i = 0, #any_int id: u64 = 0, loc := #caller_location) {
	s := element_push(Flex, id, loc)
	s.axis = axis
	s.gap  = gap
	layout(perp(axis), flex_update_layout, deps={axis})
}
flex_end :: proc () {
	assert(typeid_of(Flex) == element_curr().type)
	element_pop()
}
@(deferred_none=flex_end)
flex :: proc (axis: Axis = .H, gap: Vec2i = 0, #any_int id: u64 = 0, loc := #caller_location) -> bool {
	flex_begin(axis, gap, id, loc)
	return true
}
@(deferred_none=flex_end)
flex_h :: proc (gap: Vec2i = 0, #any_int id: u64 = 0, loc := #caller_location) -> bool {
	flex_begin(.H, gap, id, loc)
	return true
}
@(deferred_none=flex_end)
flex_v :: proc (gap: Vec2i = 0, #any_int id: u64 = 0, loc := #caller_location) -> bool {
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

	child_id: Element_Handle
	for child in each_element_layout_child(el, &child_id) {

		if _, is_fill := child.size[ax].(Fill); is_fill {
			fills += 1
		} else {
			space_taken += element_bounds(child, ax)
		}

		space_taken += gap
	}

	space_taken = max(space_taken - gap, 0) // Remove last el gap

	prev: ^Element
	child_id = {}
	for child in each_element_layout_child(el, &child_id) {
		defer prev = child

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
rect_cut_begin :: proc (axis: Axis = .H, gap: int = 0, #any_int id: u64 = 0, loc := #caller_location) {
	s := element_push(Rect_Cut, id, loc)
	s.axis = axis
	s.gap  = gap
	layout_axis(axis, rect_cut_update_layout)
}
rect_cut_end :: proc (axis: Axis = .H, gap: int = 0, #any_int id: u64 = 0, loc := #caller_location) {
	assert(element_hash(typeid_of(Rect_Cut), id) == element_curr().hash, loc=loc)
	element_pop()
}
@(deferred_in=rect_cut_end)
rect_cut :: proc (axis: Axis = .H, gap: int = 0, #any_int id: u64 = 0, loc := #caller_location) -> bool {
	rect_cut_begin(axis, gap, id, loc)
	return true
}


@private
_masonry_layout_axis :: proc (el: ^Element, c: int, gap: Vec2i, $AXIS: Axis) {

	if !element_has_layout_children(el) do return

	c := c if c > 0 else 1

	PERP :: Axis((int(AXIS) + 1) % 2)

	cols := make([]int, c, context.temp_allocator)

	// TODO: what to do about the flored pixel fraction (it grows space after)
	max_w := element_inner_bounds(el, PERP)
	col_w := (max_w - gap[PERP] * (c-1)) / c

	child_id: Element_Handle
	for child in each_element_layout_child(el, &child_id) {

		min_idx := slice.min_index(cols) or_break

		element_set_pos(child, {AXIS=cols[min_idx], PERP=min_idx * (col_w + gap[PERP])})

		cols[min_idx] += element_bounds(child, AXIS) + gap[AXIS]
	}

	element_set_inner_bounds(el, AXIS, slice.max(cols) - gap[AXIS])
}
@private
_masonry_layout_perp :: proc (el: ^Element, c: int, gap: Vec2i, $AXIS: Axis) {

	if !element_has_layout_children(el) do return

	c := c if c > 0 else 1

	PERP :: Axis((int(AXIS) + 1) % 2)

	max_w := element_inner_bounds(el, PERP)
	col_w := (max_w - gap[PERP] * (c-1)) / c

	child_id: Element_Handle
	for child in each_element_layout_child(el, &child_id) {

		element_set_bounds(child, PERP, col_w)
	}
}

Masonry :: struct {axis: Axis, cols: int, gap: Vec2i}
masonry_begin :: proc (cols: int, axis: Axis = .V, gap: Vec2i = 0, #any_int id: u64 = 0, loc := #caller_location) {
	bounds_check_axis(axis, loc)

	s := element_push(Masonry, id, loc)
	s.axis = axis
	s.cols = cols
	s.gap  = gap

	layout(axis, proc () {
		el := element_curr()
		s  := element_state(Masonry, el)
		if s.axis == .H do _masonry_layout_axis(el, s.cols, s.gap, .H)
		else            do _masonry_layout_axis(el, s.cols, s.gap, .V)
	}, deps={perp(axis)})

	layout(perp(axis), proc () {
		el := element_curr()
		s  := element_state(Masonry, el)
		if s.axis == .H do _masonry_layout_perp(el, s.cols, s.gap, .H)
		else            do _masonry_layout_perp(el, s.cols, s.gap, .V)
	})
}
masonry_end :: proc (cols: int, axis: Axis = .V, gap: Vec2i = 0, #any_int id: u64 = 0, loc := #caller_location) {
	assert(element_hash(typeid_of(Masonry), id) == element_curr().hash, loc=loc)
	element_pop()
}
@(deferred_in=masonry_end)
masonry :: proc (cols: int, axis: Axis = .V, gap: Vec2i = 0, #any_int id: u64 = 0, loc := #caller_location) -> bool {
	masonry_begin(cols, axis, gap, id, loc)
	return true
}


Scroll_Area_Container :: struct {axis: Axis, scroll: f32}
Scroll_Area_Content   :: struct {}
scroll_area_begin :: proc (axis: Axis = .V, #any_int id: u64 = 0, loc := #caller_location) {

	s := element_push(Scroll_Area_Container, id, loc)
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
scroll_area_end :: proc (axis: Axis = .V, #any_int id: u64 = 0, loc := #caller_location) {
	assert(element_hash(typeid_of(Scroll_Area_Container), id) == element_curr().hash, loc=loc)
	element_pop()
}
@(deferred_in=scroll_area_end)
scroll_area :: proc (axis: Axis = .V, #any_int id: u64 = 0, loc := #caller_location) -> bool {
	scroll_area_begin(axis, id, loc)
	return true
}

scroll_value :: proc (h: Element_Handle = {}, loc := #caller_location) -> f32 {
	s := element_state(Scroll_Area_Container, h, loc)
	return s.scroll
}

Scroll_Area_Scrollbar       :: struct {dragging: bool, offset, size, min_thumb_size: int}
Scroll_Area_Scrollbar_Thumb :: struct {}
scrollbar_begin :: proc (size, min_thumb_size: int, loc := #caller_location) {

	s := element_push(Scroll_Area_Scrollbar, loc=loc)
	s.size           = size
	s.min_thumb_size = min_thumb_size

	container := element_state(Scroll_Area_Container, element_parent(), loc)

	position_absolute()
	size_axis_fill(container.axis)
	size_axis(perp(container.axis), size)

	get_thumb_pos_and_size :: proc (oh, ih: int, scroll: f32, min_thumb_size: int) -> (pos, size: int) {
		if ih <= oh {
			size = oh
		} else if ih > 0 && oh > 0 {
			pos  = int(math.ceil(f32(oh) * (1 - f32(oh)/f32(ih)) * (-scroll / (f32(ih)-f32(oh)))))
			size = int(f32(oh) * f32(oh)/f32(ih))
		}
		if size < min(min_thumb_size, oh) {
			pos -= (min(min_thumb_size, oh)-size)/2
			size = min(min_thumb_size, oh)
		}
		size = min(size, oh)
		pos  = clamp(0, pos, oh-size)
		return
	}

	layout_axis(container.axis, proc () {
		scrollbar := element_curr()
		container := element_parent()
		content   := element_get_assert(container.child_first)
		thumb     := element_get_assert(scrollbar.child_first)

		using s_scrollbar := element_state(Scroll_Area_Scrollbar, scrollbar)
		using s_container := element_state(Scroll_Area_Container, container)
		_                  = element_state(Scroll_Area_Scrollbar_Thumb, thumb)

		oh := element_inner_bounds(container, axis)
		ih := element_bounds(content, axis)

		thumb_pos, thumb_size := get_thumb_pos_and_size(oh, ih, scroll, min_thumb_size)

		element_set_pos(thumb, axis, thumb_pos)
		element_set_bounds(thumb, axis, thumb_size)
	})

	effect(proc () {
		scrollbar := element_curr()
		container := element_parent()
		content   := element_get_assert(container.child_first)
		thumb     := element_get_assert(scrollbar.child_first)

		using s_scrollbar := element_state(Scroll_Area_Scrollbar, scrollbar)
		using s_container := element_state(Scroll_Area_Container, container)
		_                  = element_state(Scroll_Area_Scrollbar_Thumb, thumb)

		oh := element_inner_bounds(container, axis)
		ih := element_bounds(content, axis)

		scrollbar_pos := element_screen_pos(scrollbar)
		thumb_pos, thumb_size := get_thumb_pos_and_size(oh, ih, scroll, min_thumb_size)

		if is_press_in(thumb) {
			dragging = true
			offset   = ctx.mouse[axis] - scrollbar_pos[axis] - thumb_pos - thumb_size/2
		} else if is_press_in(scrollbar) {
			dragging = true
		}

		if is_released() {
			dragging = false
			offset   = 0
		}

		if dragging {
			h := f32(oh-thumb_size)
			p := f32(ctx.mouse[axis]) - f32(scrollbar_pos[axis]) - f32(oh)/2 - f32(offset)
			scroll = -math.remap_clamped(p, -h/2, h/2, 0, f32(ih-oh))
		}
	})
}
scrollbar_end :: proc (size, min_thumb_size: int, loc := #caller_location) {
	assert(typeid_of(Scroll_Area_Scrollbar) == element_curr().type, loc=loc)
	element_pop()
}
@(deferred_in=scrollbar_end)
scrollbar :: proc (size, min_thumb_size: int, loc := #caller_location) -> bool {
	scrollbar_begin(size, min_thumb_size, loc)
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
