package pixui

import "base:runtime"
import "core:mem"
import "core:fmt"
import hm "core:container/handle_map"


Vec    :: [2]int
Rect   :: struct {using pos: Vec, size: Vec}
Insets :: struct {l, t, r, b: int}

ctx: struct {
	elements:     hm.Dynamic_Handle_Map(Element, Element_Handle), // TODO: implement own? why a xar is used—the point of handled is not to use pointers
	element_curr: Element_Handle,
	element_root: Element_Handle,
	allocator:    mem.Allocator,
}

Element :: struct {
	hash:        u64,            // type + user id
	data_ptr:    rawptr,         // ptr to user component state

	handle:      Element_Handle, // self
	parent:      Element_Handle, // can be zero—root
	child_first: Element_Handle, // can be zero—no children
	child_last:  Element_Handle, // can be zero—no children
	next, prev:  Element_Handle, // can be zero—siblings

	_found:      bool,           // was the element present in this frame?

	margin:      Insets,
	padding:     Insets,
	rect:        Rect,           // world rect, calculated from children, margin, padding etc.
}

Element_Handle :: struct {idx, gen: u32} // index to `ctx.elements`


init :: proc (allocator := context.allocator) -> (err: mem.Allocator_Error) {

	ctx.allocator = allocator

	hm.dynamic_init(&ctx.elements, allocator)

	ctx.element_root, err = hm.add(&ctx.elements, Element{})
	ctx.element_curr = ctx.element_root

	root := element_get_assert(ctx.element_root)
	root.handle = ctx.element_root

	return
}

shutdown :: proc () {
	hm.dynamic_destroy(&ctx.elements)
}

@(require_results)
element_get :: proc (handle: Element_Handle) -> (el: ^Element, ok: bool) #optional_ok {
	return hm.get(&ctx.elements, handle)
}
element_get_assert :: proc (handle: Element_Handle, loc := #caller_location) -> ^Element {
	el, ok := hm.get(&ctx.elements, handle)
	fmt.assertf(ok, "Couldn't find element with the handle `%v`.", handle, loc=loc)
	return el
}

@(require_results)
element_hash :: proc (T: typeid, user_id: u64) -> u64 {
	type_id := transmute(u64)T
	return hash_combine(type_id, user_id) if user_id > 0 else type_id
}

@private
_element_push :: proc (T: typeid, T_size, T_align: int, user_id: u64) ->
                      (state: rawptr, el: ^Element, init: bool)
{
	hash   := element_hash(T, user_id)
	parent := element_get_assert(ctx.element_curr)

	search: {
		// Search for matching child from previous frame

		child_id := parent.child_first
		for child in element_get(child_id) {
			// TODO: this search could probably be optimized
			if child.hash == hash && !child._found {
				// Found matching child
				el = child
				break search
			}
			child_id = child.next
		}

		// Not found—alloc and append a new element

		// TODO: use pool/arena for state to keep memory continious
		bytes, alloc_err := runtime.mem_alloc(T_size, T_align, allocator=ctx.allocator)
		assert(alloc_err == nil)

		handle, add_err := hm.add(&ctx.elements, Element{
			parent   = parent.handle,
			hash     = hash,
			data_ptr = raw_data(bytes),
		})
		// TODO: how to handle errors?
		assert(add_err == nil)
		el = element_get_assert(handle)

		if sibling, has_siblings := element_get(parent.child_last); has_siblings {
			sibling.next = handle
			el.prev = sibling.handle
		} else {
			parent.child_first = handle
		}
		parent.child_last = handle

		init = true
	}

	ctx.element_curr = el.handle
	el._found        = true
	state            = el.data_ptr
	assert(T_size == 0 || state != nil)

	// Update element rect
	el.rect.size.x = el.padding.l + el.padding.r
	el.rect.size.y = el.padding.t + el.padding.b
	el.rect.pos  = parent.rect.pos
	el.rect.pos += {parent.padding.l, parent.padding.t}
	el.rect.pos += {el.margin.l, el.margin.t}

	return
}

element_push :: #force_inline proc ($T: typeid, id: u64 = 0) ->
                                   (state: ^T, element: ^Element, init: bool) {
	ptr: rawptr
	ptr, element, init = _element_push(T, size_of(T), align_of(T), id)
	return (^T)(ptr), element, init
}

element_pop :: proc () {
	// switch current element to parent
	el     := element_get_assert(ctx.element_curr)
	parent := element_get_assert(el.parent)
	ctx.element_curr = el.parent

	// Update parent rect by own size
	parent.rect.size.x = max(parent.rect.size.x,
	                         el.rect.size.x + el.margin.l + el.margin.r + parent.padding.l + parent.padding.r)
	parent.rect.size.y = max(parent.rect.size.y,
	                         el.rect.size.y + el.margin.t + el.margin.b + parent.padding.t + parent.padding.b)
}

element_curr :: proc () -> ^Element {
	return element_get_assert(ctx.element_curr)
}

frame_end :: proc () {

	assert(ctx.element_curr == ctx.element_root)

	it := hm.iterator_make(&ctx.elements)
	for el, handle in hm.iterate(&it) {
		if el._found || handle == ctx.element_root {
			el._found = false
		} else {
			free(el.data_ptr)
			hm.remove(&ctx.elements, handle)
		}
	}

	debug_tree_print()
}

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
			child.rect.pos.y = prev.rect.pos.y + prev.rect.size.y + prev.margin.b + child.margin.t
			// Increase element rect
			el.rect.size.y = max(el.rect.size.y,
			                     child.rect.pos.y + child.rect.size.y + child.margin.b + el.padding.b - el.rect.pos.y)

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
			child.rect.pos.x = prev.rect.pos.x + prev.rect.size.x + prev.margin.r + child.margin.l
			// Increase element rect
			el.rect.size.x = max(el.rect.size.x,
			                     child.rect.pos.x + child.rect.size.x + child.margin.r + el.padding.r - el.rect.pos.x)

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
