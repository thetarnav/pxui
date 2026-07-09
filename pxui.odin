package pxui

import "base:runtime"
import "core:mem"
import "core:fmt"
import la "core:math/linalg"
import hm "core:container/handle_map"


Vec2i    :: [2]int
Vec2f    :: [2]f32
RGBA     :: [4]u8
Color    :: RGBA
Rect     :: struct {using pos: Vec2i, size: Vec2i}
Rectf    :: struct {using pos: Vec2f, size: Vec2f}
Insets   :: struct {l, t, r, b: int}

Size :: union {
	int, // absolute
	f32, // relative
}
Size_Vec :: [2]Size

Atlas :: struct {
	pixels: []RGBA,
	size:   Vec2i,
}

Context :: struct {
	allocator:    mem.Allocator,

	elements:     hm.Dynamic_Handle_Map(Element, Element_Handle), // TODO: implement own? why a xar is used—the point of handled is not to use pointers
	element_curr: Element_Handle,
	element_root: Element_Handle,

	draw_commands: Draw_Commands,

	// Per frame input
	mouse:          Vec2i,
	mouse_pressed:  bool,
	mouse_released: bool,
	mouse_held:     bool,

	element_hover:  Element_Handle,
}
ctx: Context

Element_Flag :: enum u8 {Non_Interactable}
Element_Flags :: bit_set[Element_Flag]

Layout_Phase :: enum {Pre, Post}
Layout_Callback :: proc (^Element)

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
	pos, size:   Size_Vec,

	layout:      [Layout_Phase]Layout_Callback,

	calc_rect:   Rect,           // world rect, calculated from children, margin, padding etc.

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
	el := element_get_assert(ctx.element_curr)
	assert(el.parent != {})

	ctx.element_curr = el.parent
}

element_curr :: proc () -> ^Element {
	return element_get_assert(ctx.element_curr)
}

frame_begin :: proc () {
	assert(ctx.element_curr == ctx.element_root)

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

	solve_layout()

	mouse_hit_test()
}

solve_layout :: proc () {
	root := element_get_assert(ctx.element_root)

	// Root is sized by the user like any other element.
	// Percentages on the root resolve against 0 (i.e. zero) since it has no parent.
	root.calc_rect = {0, size_vec_to_absolute(root.size, 0)}

	// Pre cb on root: trusted to size/position root.
	call_layout(root, .Pre)
	solve_siblings(root.child_first)

	call_layout :: proc (el: ^Element, phase: Layout_Phase) -> bool {
		cb := el.layout[phase]
		if cb == nil do return false
		cb(el)
		return true
	}

	solve_node :: proc (el: ^Element) {
		parent := element_get_assert(el.parent)

		// Pre cb owns the whole subtree.
		if call_layout(el, .Pre) do return

		default_top_down(el, parent)
		solve_siblings(el.child_first)

		call_layout(el, .Post)

		default_bottom_up(el, parent)
	}

	solve_siblings :: proc (h: Element_Handle) {
		el, ok := element_get(h)
		if !ok do return
		solve_node(el)
		solve_siblings(el.next)
	}
}


default_top_down :: proc (el, parent: ^Element) {
	pos  := size_vec_to_absolute(el.pos,  parent.calc_rect.size)
	size := size_vec_to_absolute(el.size, parent.calc_rect.size)
	// Update element rect
	el.calc_rect = {
		pos  = parent.calc_rect.pos + lt(parent.padding) + lt(el.margin) + pos,
		size = lt(el.padding) + rb(el.padding) + size,
	}
}

default_bottom_up :: proc (el, parent: ^Element) {
	// Update parent rect by own size
	parent.calc_rect.size = la.max(parent.calc_rect.size,
		el.calc_rect.size +
		lt(el.margin) +
		rb(el.margin) +
		lt(parent.padding) +
		rb(parent.padding)
	)
}

mouse_hit_test :: proc () {

	_check(ctx.element_root)

	_check :: proc (h: Element_Handle) -> (hit: bool) {
		el := element_get(h) or_return

		if .Non_Interactable not_in el.flags && rect_contains(el.calc_rect, ctx.mouse) {
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
