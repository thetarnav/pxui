package pixui

import "base:runtime"
import "core:mem"
import "core:fmt"
import hm "core:container/handle_map"

Vec2  :: [2]f32
Rect  :: struct {using pos: Vec2, size: Vec2}

ctx: struct {
	elements:     hm.Dynamic_Handle_Map(Element, Element_Handle), // TODO: implement own? why a xar is used—the point of handled is not to use pointers
	element_curr: Element_Handle,
	element_root: Element_Handle,
	allocator:    mem.Allocator,
}

init :: proc (allocator := context.allocator) -> (err: mem.Allocator_Error) {
	ctx.allocator = allocator
	root: Element
	hm.dynamic_init(&ctx.elements, allocator)
	ctx.element_root = hm.add(&ctx.elements, root) or_return
	ctx.element_curr = ctx.element_root
	return
}

shutdown :: proc () {
	hm.dynamic_destroy(&ctx.elements)
}

Element :: struct {
	id:          Element_Id,
	handle:      Element_Handle, // self
	parent:      Element_Handle, // can be zero—root
	child_first: Element_Handle, // can be zero—no children
	child_last:  Element_Handle, // can be zero—no children
	next, prev:  Element_Handle, // can be zero—siblings
	data_ptr:    rawptr,         // ptr to user component state
	found:       bool,           // was the element present in this frame?
}

Element_Handle :: struct {idx, gen: u32}
Element_Id     :: distinct u64

@(require_results)
element_get :: proc (handle: Element_Handle) -> (el: ^Element, ok: bool) #optional_ok {
	return hm.get(&ctx.elements, handle)
}
element_get_assert :: proc (handle: Element_Handle, loc := #caller_location) -> ^Element {
	el, ok := hm.get(&ctx.elements, handle)
	fmt.assertf(ok, "Couldn't find element with the handle `%v`.", handle, loc=loc)
	return el
}

@private
_element_push :: proc (T: typeid, T_size, T_align: int, user_id: u64) -> (state: rawptr, handle: Element_Handle, init: bool) {

	type_id := transmute(u64)T
	id := Element_Id(hash_combine(type_id, user_id) if user_id > 0 else type_id)

	parent := element_get_assert(ctx.element_curr)

	child_id := parent.child_first
	for child in element_get(child_id) {
		// TODO: this search could probably be optimized
		if child.id == id && !child.found {
			// found matching child
			handle           = child.handle
			ctx.element_curr = handle
			state            = child.data_ptr
			child.found      = true
			assert(T_size == 0 || state != nil)
			return
		}
		child_id = child.next
	}

	// TODO: use pool/arena for state to keep memory continious
	bytes, mem_err := runtime.mem_alloc(T_size, T_align, allocator=ctx.allocator)
	assert(mem_err == nil)
	state = raw_data(bytes)

	handle, mem_err = hm.add(&ctx.elements, Element{
		parent   = parent.handle,
		id       = id,
		data_ptr = state,
		found    = true,
	})
	// TODO: how to handle errors?
	assert(mem_err == nil)
	ctx.element_curr = handle

	if sibling, ok := element_get(parent.child_last); ok {
		el := element_get_assert(handle)
		sibling.next = handle
		el.prev      = sibling.handle
	} else {
		parent.child_first = handle
	}
	parent.child_last = handle

	init = true

	return
}

element_push :: #force_inline proc ($T: typeid, id: u64 = 0) -> (state: ^T, handle: Element_Handle, init: bool) {
	ptr: rawptr
	ptr, handle, init = _element_push(T, size_of(T), align_of(T), id)
	state = (^T)(ptr)
	return
}

element_pop :: proc () {
	el_curr := element_get_assert(ctx.element_curr)
	assert(el_curr.parent != {})
	ctx.element_curr = el_curr.parent
}

frame_end :: proc () {
	it := hm.iterator_make(&ctx.elements)
	for el, handle in hm.iterate(&it) {
		if el.found || handle == ctx.element_root {
			el.found = false
		} else {
			free(el.data_ptr)
			hm.remove(&ctx.elements, handle)
		}
	}
}
