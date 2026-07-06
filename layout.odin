package pixui

V_Stack :: struct {}
v_stack_begin :: proc (id: u64 = 0) {
	element_push(V_Stack, id)
}
v_stack_end :: proc (id: u64 = 0) {
	assert(element_hash(typeid_of(V_Stack), id) == element_curr().hash)

	el := element_curr()

	if prev, has_children := element_get(el.child_first); has_children {
		child_id := prev.next
		for child in element_get(child_id) {

			// Position each child below previous
			child.pos.y = prev.pos.y + prev.size.y + prev.margin.b + child.margin.t
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
	assert(element_hash(typeid_of(H_Stack), id) == element_curr().hash)

	el := element_curr()

	if prev, has_children := element_get(el.child_first); has_children {
		child_id := prev.next
		for child in element_get(child_id) {

			// Position each child after previous
			child.pos.x = prev.pos.x + prev.size.x + prev.margin.r + child.margin.l
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
