package pxui


size   :: proc (v: Vec) {element_curr().size = v}
size_w :: proc (w: int) {element_curr().size.x = w}
size_h :: proc (h: int) {element_curr().size.y = h}
size_x :: size_w
size_y :: size_h
width  :: size_w
height :: size_h

margin_set        :: proc (v: Insets)       {element_curr().margin = v}
margin_directions :: proc (l, t, r, b: int) {margin(Insets{l, t, r, b})}
margin_axis       :: proc (h, v: int)       {margin(h, v, h, v)}
margin_vec        :: proc (v: Vec)          {margin(v.x, v.y, v.x, v.y)}
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
padding_vec        :: proc (v: Vec)          {padding(v.x, v.y, v.x, v.y)}
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


element_move_x :: proc (el: ^Element, x: int) {
	element_move_by(el, {x - el.rect.pos.x, 0})
}
element_move_y :: proc (el: ^Element, y: int) {
	element_move_by(el, {0, y - el.rect.pos.y})
}
element_move :: proc (el: ^Element, #no_broadcast pos: Vec) {
	element_move_by(el, pos - el.rect.pos)
}
element_move_by :: proc (el: ^Element, by: Vec) {

	el.rect.pos += by
	_move_sibling(el.child_first, by)

	_move_sibling :: proc (h: Element_Handle, by: Vec) -> (ok: bool) {
		el := element_get(h) or_return
		el.rect.pos += by
		_move_sibling(el.child_first, by)
		_move_sibling(el.next, by)
		return true
	}
}


V_Stack :: struct {}
v_stack_begin :: proc (id: u64 = 0) {
	element_push(V_Stack, id)
}
v_stack_end :: proc (id: u64 = 0) {

	el := element_curr()
	assert(element_hash(typeid_of(V_Stack), id) == el.hash)

	if prev, has_children := element_get(el.child_first); has_children {
		child_id := prev.next
		for child in element_get(child_id) {

			// Position each child below previous
			element_move_y(child, prev.pos.y + prev.size.y + prev.margin.b + child.margin.t)
			// Increase element rect
			el.size.y = max(el.size.y,
			                child.pos.y + child.size.y + child.margin.b + el.padding.b - el.pos.y)

			child_id, prev = child.next, child
		}
	}

	element_pop()
}
@(deferred_in=v_stack_end)
v_stack :: proc (id: u64 = 0) -> bool {
	v_stack_begin(id)
	return true
}

H_Stack :: struct {}
h_stack_begin :: proc (id: u64 = 0) {
	element_push(H_Stack, id)
}
h_stack_end :: proc (id: u64 = 0) {

	el := element_curr()
	assert(element_hash(typeid_of(H_Stack), id) == el.hash)

	if prev, has_children := element_get(el.child_first); has_children {
		child_id := prev.next
		for child in element_get(child_id) {

			// Position each child after previous
			element_move_x(child, prev.pos.x + prev.size.x + prev.margin.r + child.margin.l)
			// Increase element rect
			el.size.x = max(el.size.x,
			                child.pos.x + child.size.x + child.margin.r + el.padding.r - el.pos.x)

			child_id, prev = child.next, child
		}
	}

	element_pop()
}
@(deferred_in=h_stack_end)
h_stack :: proc (id: u64 = 0) -> bool {
	h_stack_begin(id)
	return true
}
