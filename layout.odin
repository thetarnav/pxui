package pxui

import "core:math"
import "core:slice"

size              :: proc (v: Size_Vec)         {element_curr().size = v}
size_px           :: proc (v: Vec2i)            {element_curr().size = {v.x, v.y}}
size_percent      :: proc (v: Vec2f)            {element_curr().size = {v.x, v.y}}
size_fill         :: proc ()                    {element_curr().size = Fill{}}
size_w            :: proc (w: Size)             {element_curr().size.x = w}
size_w_px         :: proc (w: int)              {element_curr().size.x = w}
size_w_percent    :: proc (w: f32)              {element_curr().size.x = w}
size_w_fill       :: proc ()                    {element_curr().size.x = Fill{}}
size_h            :: proc (h: Size)             {element_curr().size.y = h}
size_h_px         :: proc (h: int)              {element_curr().size.y = h}
size_h_percent    :: proc (h: f32)              {element_curr().size.y = h}
size_h_fill       :: proc ()                    {element_curr().size.y = Fill{}}
size_axis         :: proc (axis: Axis, v: Size) {element_curr().size[axis] = v}
size_axis_px      :: proc (axis: Axis, v: int)  {element_curr().size[axis] = v}
size_axis_percent :: proc (axis: Axis, v: f32)  {element_curr().size[axis] = v}
size_axis_fill    :: proc (axis: Axis)          {element_curr().size[axis] = Fill{}}
size_x            :: size_w
size_x_px         :: size_w_px
size_x_percent    :: size_w_percent
size_x_fill       :: size_w_fill
size_y            :: size_h
size_y_px         :: size_h_px
size_y_percent    :: size_h_percent
size_y_fill       :: size_h_fill
width             :: size_w
width_px          :: size_w_px
width_percent     :: size_w_percent
width_fill        :: size_w_fill
height            :: size_h
height_px         :: size_h_px
height_percent    :: size_h_percent
height_fill       :: size_h_fill

margin_set        :: proc (v: Insets)       {element_curr().margin = v}
margin_directions :: proc (l, t, r, b: int) {margin(Insets{l, t, r, b})}
margin_axis       :: proc (h, v: int)       {margin(h, v, h, v)}
margin_vec        :: proc (v: Vec2i)        {margin(v.x, v.y, v.x, v.y)}
margin_all        :: proc (v: int)          {margin(v, v, v, v)}
margin_t          :: proc (v: int)          {element_curr().margin.t = v}
margin_b          :: proc (v: int)          {element_curr().margin.b = v}
margin_l          :: proc (v: int)          {element_curr().margin.l = v}
margin_r          :: proc (v: int)          {element_curr().margin.r = v}
margin            :: proc {margin_set, margin_directions, margin_axis, margin_vec, margin_all}
margin_dirs       :: margin_directions
margin_bottom     :: margin_b
margin_bot        :: margin_b
margin_left       :: margin_l
margin_right      :: margin_r
margin_top        :: margin_t

padding_set        :: proc (v: Insets)       {element_curr().padding = v}
padding_directions :: proc (l, t, r, b: int) {padding(Insets{l, t, r, b})}
padding_axis       :: proc (h, v: int)       {padding(h, v, h, v)}
padding_vec        :: proc (v: Vec2i)        {padding(v.x, v.y, v.x, v.y)}
padding_all        :: proc (v: int)          {padding(v, v, v, v)}
padding_t          :: proc (v: int)          {element_curr().padding.t = v}
padding_b          :: proc (v: int)          {element_curr().padding.b = v}
padding_l          :: proc (v: int)          {element_curr().padding.l = v}
padding_r          :: proc (v: int)          {element_curr().padding.r = v}
padding            :: proc {padding_set, padding_directions, padding_axis, padding_vec, padding_all}
padding_dirs       :: padding_directions
padding_bottom     :: padding_b
padding_bot        :: padding_b
padding_left       :: padding_l
padding_right      :: padding_r
padding_top        :: padding_t


layout_top_down  :: proc (cb: Layout_Callback) {element_curr().layout[.Top_Down]  = cb}
layout_bottom_up :: proc (cb: Layout_Callback) {element_curr().layout[.Bottom_Up] = cb}


@private
_stack_update_layout :: proc (el: ^Element, $AX: Axis) {

	prev, has_children := element_get(el.child_first)
	if !has_children do return

	child_id := prev.next
	for child in element_get(child_id) {
		defer child_id, prev = child.next, child

		// Position each child below previous
		child.rel_rect.pos[AX] = prev.rel_rect.pos[AX] +
		                         element_size_and_margin_rb(prev)[AX] +
		                         lt(child.margin)[AX]
	}

	// Increase element rect
	el.rel_rect.size[AX] = max(el.rel_rect.size[AX],
	                           prev.rel_rect.pos[AX] +
	                           element_size_and_margin_rb(prev)[AX] +
	                           rb(el.padding)[AX])
}

V_Stack :: struct {}
v_stack_layout_post :: proc (el: ^Element) {
	_stack_update_layout(el, .Y)
}
v_stack_begin :: proc (id: u64 = 0, loc := #caller_location) {
	element_push(V_Stack, id, loc)
	layout_bottom_up(v_stack_layout_post)
}
v_stack_end :: proc (id: u64 = 0, loc := #caller_location) {
	assert(element_hash(typeid_of(V_Stack), id) == element_curr().hash, loc=loc)
	element_pop()
}
@(deferred_in=v_stack_end)
v_stack :: proc (id: u64 = 0, loc := #caller_location) -> bool {
	v_stack_begin(id, loc)
	return true
}

H_Stack :: struct {}
h_stack_update_layout :: proc (el: ^Element) {
	_stack_update_layout(el, .X)
}
h_stack_begin :: proc (id: u64 = 0, loc := #caller_location) {
	element_push(H_Stack, id, loc)
	layout_bottom_up(h_stack_update_layout)
}
h_stack_end :: proc (id: u64 = 0, loc := #caller_location) {
	assert(element_hash(typeid_of(H_Stack), id) == element_curr().hash, loc=loc)
	element_pop()
}
@(deferred_in=h_stack_end)
h_stack :: proc (id: u64 = 0, loc := #caller_location) -> bool {
	h_stack_begin(id, loc)
	return true
}


@private
_flex_update_layout :: proc (el: ^Element, $AX: Axis) {

	prev, has_children := element_get(el.child_first)
	if !has_children do return

	PERP :: (int(AX) + 1) % 2

	max_size := el.rel_rect.size[AX] +
	            -rb(el.padding)[AX]

	cursor: Vec2i
	cursor[PERP] = lt(el.padding)[PERP]
	cursor[AX] = prev.rel_rect.pos[AX] + element_size_and_margin_rb(prev)[AX]

	row_size: int

	child_id := prev.next
	for child in element_get(child_id) {
		defer child_id, prev = child.next, child

		cursor[AX] += lt(child.margin)[AX]
		if cursor[AX] + element_size_and_margin_rb(child)[AX] > max_size {
			cursor[AX] = lt(el.padding)[AX] + lt(child.margin)[AX]
			cursor[PERP] += row_size
			row_size = 0
		}

		child.rel_rect.pos = cursor
		child.rel_rect.pos[PERP] += lt(child.margin)[PERP]

		cursor[AX] += element_size_and_margin_rb(child)[AX]
		row_size = max(row_size, element_size_and_margin(child)[PERP])
	}

	// Increase element rect
	el.rel_rect.size[PERP] = max(el.rel_rect.size[PERP],
	                             prev.rel_rect.pos[PERP] +
	                             prev.rel_rect.size[PERP] +
	                             rb(prev.margin)[PERP] +
	                             rb(el.padding)[PERP])
}

Flex :: struct {axis: Axis}
flex_update_layout :: proc (el: ^Element) {
	s := element_state(Flex, el.handle)
	if s.axis == .H do _flex_update_layout(el, .H)
	else            do _flex_update_layout(el, .V)
}
flex_begin :: proc (axis: Axis = .H, id: u64 = 0, loc := #caller_location) {
	s, _, _ := element_push(Flex, id, loc)
	s.axis = axis
	layout_bottom_up(flex_update_layout)
}
flex_end :: proc () {
	assert(typeid_of(Flex) == element_curr().type)
	element_pop()
}
@(deferred_none=flex_end)
flex :: proc (axis: Axis = .H, id: u64 = 0, loc := #caller_location) -> bool {
	flex_begin(axis, id, loc)
	return true
}
@(deferred_none=flex_end)
flex_h :: proc (id: u64 = 0, loc := #caller_location) -> bool {
	flex_begin(.H, id, loc)
	return true
}
@(deferred_none=flex_end)
flex_v :: proc (id: u64 = 0, loc := #caller_location) -> bool {
	flex_begin(.V, id, loc)
	return true
}


rect_cut_update_layout :: proc (el: ^Element) {

	s  := element_state(Rect_Cut, el.handle)
	ax := s.axis

	// Find out how much space is taken by non-fill elements
	// and how many elements need to share the remaining space
	space_taken := rb(el.padding)[ax] +
	               lt(el.padding)[ax]
	fills: int

	child_id := el.child_first
	for child in element_get(child_id) {
		defer child_id = child.next

		if _, is_fill := child.size[ax].(Fill); is_fill {
			fills += 1
		} else {
			space_taken += child.rel_rect.size[ax]
		}
		space_taken += rb(child.margin)[ax] +
		               lt(child.margin)[ax]
	}

	prev: ^Element
	child_id = el.child_first
	for child in element_get(child_id) {
		defer child_id, prev = child.next, child

		// All fill-children divide the remaining space equally
		if _, is_fill := child.size[ax].(Fill); is_fill {
			space := (el.rel_rect.size[ax] - space_taken)/fills
			space_taken += space
			fills -= 1
			child.rel_rect.size[ax] = space
		}

		if prev != nil {
			// Position each child below previous
			child.rel_rect.pos[ax] = prev.rel_rect.pos[ax] +
			                         prev.rel_rect.size[ax] +
			                         rb(prev.margin)[ax] +
			                         lt(child.margin)[ax]
		}
	}
}

Rect_Cut :: struct {axis: Axis}
rect_cut_begin :: proc (axis: Axis = .H, id: u64 = 0, loc := #caller_location) {
	s, _, _ := element_push(Rect_Cut, id, loc)
	s.axis = axis
	layout_top_down(rect_cut_update_layout)
}
rect_cut_end :: proc (axis: Axis = .H, id: u64 = 0, loc := #caller_location) {
	assert(element_hash(typeid_of(Rect_Cut), id) == element_curr().hash, loc=loc)
	element_pop()
}
@(deferred_in=rect_cut_end)
rect_cut :: proc (axis: Axis = .H, id: u64 = 0, loc := #caller_location) -> bool {
	rect_cut_begin(axis, id, loc)
	return true
}


@private
_masonry_update_layout :: proc (el: ^Element, c: int, $AX: Axis) {

	_, has_children := element_get(el.child_first)
	if !has_children do return

	PERP :: (int(AX) + 1) % 2

	cols := make([]int, c, context.temp_allocator)

	space_w := el.rel_rect.size[PERP] -
	           lt(el.padding)[PERP] -
	           rb(el.padding)[PERP]
	col_w := space_w / c // TODO: what to do about the flored pixel fraction (it grows space after)

	child_id := el.child_first
	for child in element_get(child_id) {
		defer child_id = child.next

		min_idx := slice.min_index(cols) or_break

		child.rel_rect.pos[PERP] = min_idx * col_w
		child.rel_rect.pos[AX]   = cols[min_idx]
		child.rel_rect.pos += lt(child.margin) + rb(el.padding)

		child.rel_rect.size[PERP] = col_w - lt(child.margin)[PERP] - rb(child.margin)[PERP]

		cols[min_idx] += element_size_and_margin(child)[AX]
	}

	el.rel_rect.size[AX] = max(el.rel_rect.size[AX],
	                           slice.max(cols) +
	                           lt(el.padding)[AX] +
	                           rb(el.padding)[AX])
}
masonry_update_layout :: proc (el: ^Element) {
	s := element_state(Masonry, el.handle)
	if s.axis == .H do _masonry_update_layout(el, s.cols, .H)
	else            do _masonry_update_layout(el, s.cols, .V)
}

Masonry :: struct {axis: Axis, cols: int}
masonry_begin :: proc (cols: int, axis: Axis = .V, id: u64 = 0, loc := #caller_location) {
	s, _, _ := element_push(Masonry, id, loc)
	s.axis = axis
	s.cols = cols
	layout_top_down(masonry_update_layout)
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


Scroll_Area_Container       :: struct {axis: Axis, scroll: f32}
Scroll_Area_Content         :: struct {}
Scroll_Area_Scrollbar       :: struct {}
Scroll_Area_Scrollbar_Thumb :: struct {}
scroll_container_begin :: proc (axis: Axis = .V, id: u64 = 0, loc := #caller_location) {

	state, _, _ := element_push(Scroll_Area_Container, id, loc)
	state.axis = axis

	size_fill()

	layout_bottom_up(proc (outer: ^Element) {
		state := element_state(Scroll_Area_Container,)
		ax := state.axis

		content := element_get_assert(outer.child_first)

		oh := outer.rel_rect.size[ax]
		ih := content.rel_rect.size[ax]

		if is_mouse_in() {
			state.scroll += ctx.wheel_delta[ax]
			state.scroll = clamp(state.scroll, -f32(ih-oh), 0)
		}

		content.rel_rect.pos[ax] += int(state.scroll)
	})
}
scroll_container_end :: proc (axis: Axis = .V, id: u64 = 0, loc := #caller_location) {
	assert(element_hash(typeid_of(Scroll_Area_Container), id) == element_curr().hash, loc=loc)
	element_pop()
}
@(deferred_in=scroll_container_end)
scroll_container :: proc (axis: Axis = .V, id: u64 = 0, loc := #caller_location) -> bool {
	scroll_container_begin(axis, id, loc)
	return true
}

scroll_content_begin :: proc (loc := #caller_location) {
	_, el, _ := element_push(Scroll_Area_Content, loc=loc)
	state := element_state(Scroll_Area_Container, el.parent, loc)
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

scrollbar_begin :: proc (loc := #caller_location) {
	_, el, _ := element_push(Scroll_Area_Scrollbar, loc=loc)
	state := element_state(Scroll_Area_Container, el.parent, loc)

	size_axis_fill(state.axis)
	size_axis(perp(state.axis), 10)
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

	layout_top_down(proc (el: ^Element) {
		scrollbar := element_parent()
		container := element_parent(scrollbar)
		content   := element_get_assert(container.child_first)
		state     := element_state(Scroll_Area_Container, container)

		ax     := state.axis
		scroll := state.scroll

		oh := f32(container.rel_rect.size[ax])
		ih := f32(content.rel_rect.size[ax])
		sh := ih-oh

		if ih > 0 && sh > 0 && oh > 0 {
			el.rel_rect.size[ax] = int(oh * oh/ih)
			el.rel_rect.pos[ax]  = int(math.ceil(oh * (1 - oh/ih) * (-scroll/(ih-oh))))
		} else {
			el.rel_rect.size[ax] = 10
			el.rel_rect.pos[ax]  = 0
		}
	})
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
