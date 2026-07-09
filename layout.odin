package pxui


vec2i_to_size :: proc (v: Vec2i) -> Size_Vec {return {v.x, v.y}}
vec2f_to_size :: proc (v: Vec2f) -> Size_Vec {return {v.x, v.y}}
to_size :: proc {vec2f_to_size, vec2i_to_size}
size_vec :: to_size

size_get :: proc (h: Element_Handle = {}) -> Size_Vec {
	h := ctx.element_curr if h == {} else h
	return element_get_assert(h).size
}

size_to_absolute :: proc (size: Size, el_size: int) -> (abs: int) {
	switch s in size {
	case int: abs = s
	case f32: abs = int(s * f32(el_size))
	}
	return abs
}
size_vec_to_absolute :: proc (size: Size_Vec, el_size: Vec2i) -> (abs: Vec2i) {
	return {size_to_absolute(size.x, el_size.x), size_to_absolute(size.y, el_size.y)}
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


element_move_x :: proc (el: ^Element, x: int) {
	element_move_by(el, {x - el.calc_rect.pos.x, 0})
}
element_move_y :: proc (el: ^Element, y: int) {
	element_move_by(el, {0, y - el.calc_rect.pos.y})
}
element_move :: proc (el: ^Element, #no_broadcast pos: Vec2i) {
	element_move_by(el, pos - el.calc_rect.pos)
}
element_move_axis :: proc (el: ^Element, $AXIS: enum {X, Y}, v: int) {
	when AXIS == .X do element_move_x(el, v)
	else            do element_move_y(el, v)
}
element_move_by :: proc (el: ^Element, by: Vec2i) {

	el.calc_rect.pos += by
	_move_sibling(el.child_first, by)

	_move_sibling :: proc (h: Element_Handle, by: Vec2i) -> (ok: bool) {
		el := element_get(h) or_return
		el.calc_rect.pos += by
		_move_sibling(el.child_first, by)
		_move_sibling(el.next, by)
		return true
	}
}

@private
_stack_layout_post :: proc (el: ^Element, $AXIS: enum {X, Y}) {

	prev, has_children := element_get(el.child_first)
	if !has_children do return

	child_id := prev.next
	for child in element_get(child_id) {
		defer child_id, prev = child.next, child

		// Position each child below previous
		element_move_axis(child, AXIS, prev.calc_rect.pos[AXIS] +
		                               prev.calc_rect.size[AXIS] +
		                               rb(prev.margin)[AXIS] +
		                               lt(child.margin)[AXIS])
		// Increase element rect
		el.calc_rect.size[AXIS] = max(el.calc_rect.size[AXIS],
		                              child.calc_rect.pos[AXIS] +
		                              child.calc_rect.size[AXIS] +
		                              rb(child.margin)[AXIS] +
		                              rb(el.padding)[AXIS] +
		                              -el.calc_rect.pos[AXIS])
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
