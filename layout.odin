package pxui


vec2i_to_size :: proc (v: Vec2i) -> Size_Vec {return {v.x, v.y}}
vec2f_to_size :: proc (v: Vec2f) -> Size_Vec {return {v.x, v.y}}
to_size :: proc {vec2f_to_size, vec2i_to_size}
size_vec :: to_size

size_get :: proc (h: Element_Handle = {}) -> Size_Vec {
	h := ctx.element_curr if h == {} else h
	return element_get_assert(h).size
}

size           :: proc (v: Size_Vec) {element_curr().size = v}
size_px        :: proc (v: Vec2i)    {element_curr().size = {v.x, v.y}}
size_percent   :: proc (v: Vec2f)    {element_curr().size = {v.x, v.y}}
size_w         :: proc (w: Size)     {element_curr().size.x = w}
size_w_px      :: proc (w: int)      {element_curr().size.x = w}
size_w_percent :: proc (w: f32)      {element_curr().size.x = w}
size_h         :: proc (h: Size)     {element_curr().size.y = h}
size_h_px      :: proc (h: int)      {element_curr().size.y = h}
size_h_percent :: proc (h: f32)      {element_curr().size.y = h}
size_x         :: size_w
size_x_px      :: size_w_px
size_x_percent :: size_w_percent
size_y         :: size_h
size_y_px      :: size_h_px
size_y_percent :: size_h_percent
width          :: size_w
width_px       :: size_w_px
width_percent  :: size_w_percent
height         :: size_h
height_px      :: size_h_px
height_percent :: size_h_percent

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


layout_pre  :: proc (cb: Layout_Callback) {element_curr().layout[.Pre]  = cb}
layout_post :: proc (cb: Layout_Callback) {element_curr().layout[.Post] = cb}


@private
_stack_layout_post :: proc (el: ^Element, $AXIS: Axis) {

	prev, has_children := element_get(el.child_first)
	if !has_children do return

	child_id := prev.next
	for child in element_get(child_id) {
		defer child_id, prev = child.next, child

		// Position each child below previous
		child.rel_rect.pos[AXIS] = prev.rel_rect.pos[AXIS] +
		                           prev.rel_rect.size[AXIS] +
		                           rb(prev.margin)[AXIS] +
		                           lt(child.margin)[AXIS]
		// Increase element rect
		el.rel_rect.size[AXIS] = max(el.rel_rect.size[AXIS],
		                             child.rel_rect.pos[AXIS] +
		                             child.rel_rect.size[AXIS] +
		                             rb(child.margin)[AXIS] +
		                             rb(el.padding)[AXIS])
	}
}

V_Stack :: struct {}
v_stack_layout_post :: proc (el: ^Element) {
	_stack_layout_post(el, .Y)
}
v_stack_begin :: proc (id: u64 = 0) {
	element_push(V_Stack, id)
	layout_post(v_stack_layout_post)
}
v_stack_end :: proc (id: u64 = 0) {
	assert(element_hash(typeid_of(V_Stack), id) == element_curr().hash)
	element_pop()
}
@(deferred_in=v_stack_end)
v_stack :: proc (id: u64 = 0) -> bool {
	v_stack_begin(id)
	return true
}

H_Stack :: struct {}
h_stack_layout_post :: proc (el: ^Element) {
	_stack_layout_post(el, .X)
}
h_stack_begin :: proc (id: u64 = 0) {
	element_push(H_Stack, id)
	layout_post(h_stack_layout_post)
}
h_stack_end :: proc (id: u64 = 0) {
	assert(element_hash(typeid_of(H_Stack), id) == element_curr().hash)
	element_pop()
}
@(deferred_in=h_stack_end)
h_stack :: proc (id: u64 = 0) -> bool {
	h_stack_begin(id)
	return true
}


rect_cut_layout_post :: proc (el: ^Element) {
	s := element_state(Rect_Cut, el.handle)

	space_taken := rb(el.padding)[s.axis] +
	               lt(el.padding)[s.axis]
	fills: int

	child_id := el.child_first
	for child in element_get(child_id) {
		defer child_id = child.next

		if _, is_fill := child.size[s.axis].(Fill); is_fill {
			fills += 1
		} else {
			space_taken += child.rel_rect.size[s.axis]
		}
		space_taken += rb(child.margin)[s.axis] +
		               lt(child.margin)[s.axis]
	}

	prev: ^Element
	child_id = el.child_first
	for child in element_get(child_id) {
		defer child_id, prev = child.next, child

		// All fill-children divide the remaining space equally
		if _, is_fill := child.size[s.axis].(Fill); is_fill {
			space := (el.rel_rect.size[s.axis] - space_taken)/fills
			space_taken += space
			fills -= 1
			child.rel_rect.size[s.axis] = space
		}

		if prev != nil {
			// Position each child below previous
			child.rel_rect.pos[s.axis] = prev.rel_rect.pos[s.axis] +
			                             prev.rel_rect.size[s.axis] +
			                             rb(prev.margin)[s.axis] +
			                             lt(child.margin)[s.axis]
		}
	}
}

Rect_Cut :: struct {axis: Axis}
rect_cut_begin :: proc (axis: Axis, id: u64 = 0) {
	s, _, _ := element_push(Rect_Cut, id)
	s.axis = axis
	layout_post(rect_cut_layout_post)
}
rect_cut_end :: proc (axis: Axis, id: u64 = 0) {
	assert(element_hash(typeid_of(Rect_Cut), id) == element_curr().hash)
	element_pop()
}
@(deferred_in=rect_cut_end)
rect_cut :: proc (axis: Axis, id: u64 = 0) -> bool {
	rect_cut_begin(axis, id)
	return true
}
