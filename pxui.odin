package pxui

import "base:runtime"
import "core:mem"
import "core:fmt"
import hm "core:container/handle_map"


Vec    :: [2]int
Vec2f  :: [2]f32
RGBA   :: [4]u8
Color  :: RGBA
Rect   :: struct {using pos: Vec, size: Vec}
Rectf  :: struct {using pos: Vec2f, size: Vec2f}
Insets :: struct {l, t, r, b: int}

Atlas :: struct {
	pixels: []RGBA,
	size:   [2]int,
}

Context :: struct {
	allocator:    mem.Allocator,

	elements:     hm.Dynamic_Handle_Map(Element, Element_Handle), // TODO: implement own? why a xar is used—the point of handled is not to use pointers
	element_curr: Element_Handle,
	element_root: Element_Handle,

	draw_commands: Draw_Commands,

	// Per frame input
	mouse:          Vec,
	mouse_pressed:  bool,
	mouse_released: bool,
	mouse_held:     bool,

	element_hover:  Element_Handle,
}
ctx: Context

Element_Flag :: enum u8 {Non_Interactable}
Element_Flags :: bit_set[Element_Flag]

Element :: struct {
	hash:        u64,            // type + user id
	data_ptr:    rawptr,         // ptr to user component state

	handle:      Element_Handle, // self
	parent:      Element_Handle, // can be zero—root
	child_first: Element_Handle, // can be zero—no children
	child_last:  Element_Handle, // can be zero—no children
	next, prev:  Element_Handle, // can be zero—siblings

	_found:      bool,           // was the element present in this frame?
	flags:       Element_Flags,
	mouse_in:    bool,

	margin:      Insets,
	padding:     Insets,
	using rect:  Rect,           // world rect, calculated from children, margin, padding etc.

	draw:        Draw_Handle,
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
element_hash :: proc (T: typeid, user_id: u64 = 0) -> u64 {
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
	el.size.x = el.padding.l + el.padding.r
	el.size.y = el.padding.t + el.padding.b
	el.pos  = parent.pos
	el.pos += {parent.padding.l, parent.padding.t}
	el.pos += {el.margin.l, el.margin.t}

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
	parent.size.x = max(parent.size.x,
	                    el.size.x + el.margin.l + el.margin.r + parent.padding.l + parent.padding.r)
	parent.size.y = max(parent.size.y,
	                    el.size.y + el.margin.t + el.margin.b + parent.padding.t + parent.padding.b)
}

element_curr :: proc () -> ^Element {
	return element_get_assert(ctx.element_curr)
}

frame_begin :: proc () {
	assert(ctx.element_curr == ctx.element_root)

	root := element_get_assert(ctx.element_root)
	root.rect = {}

	clear(&ctx.draw_commands)
}

frame_end :: proc () {
	assert(ctx.element_curr == ctx.element_root)

	it := hm.iterator_make(&ctx.elements)
	for el, handle in hm.iterate(&it) {
		el.mouse_in = false
		if el._found || handle == ctx.element_root {
			el._found = false
		} else {
			free(el.data_ptr)
			hm.remove(&ctx.elements, handle)
		}
	}

	mouse_hit_test()

	debug_tree_print()
}

mouse_hit_test :: proc () {

	_check(ctx.element_root)

	_check :: proc (h: Element_Handle) -> (hit: bool) {
		el := element_get(h) or_return

		if .Non_Interactable not_in el.flags && rect_contains(el, ctx.mouse) {
			el.mouse_in = true
			ctx.element_hover = el.handle
			return _check(el.child_first)
		} else {
			return _check(el.next)
		}

		return true
	}
}

is_hovered :: proc (h: Element_Handle = {}) -> bool {
	h := ctx.element_curr if h == {} else h
	return ctx.element_hover == h
}
is_mouse_in :: proc (h: Element_Handle = {}) -> bool {
	h := ctx.element_curr if h == {} else h
	el := element_get(h) or_return
	return el.mouse_in
}
is_clicked :: proc (h: Element_Handle = {}) -> bool {
	return is_hovered(h) && ctx.mouse_pressed
}
