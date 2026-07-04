package pixui

import "core:strings"
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
	id:          u64,            // type + user id
	data_ptr:    rawptr,         // ptr to user component state

	handle:      Element_Handle, // self
	parent:      Element_Handle, // can be zero—root
	child_first: Element_Handle, // can be zero—no children
	child_last:  Element_Handle, // can be zero—no children
	next, prev:  Element_Handle, // can be zero—siblings

	_found:      bool,           // was the element present in this frame?

	margin:      Insets,
	padding:     Insets,

	_rect:       Rect,
}

Element_Handle :: struct {idx, gen: u32}

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

@private
_element_push :: proc (T: typeid, T_size, T_align: int, user_id: u64) -> (state: rawptr, element: ^Element, init: bool) {

	type_id := transmute(u64)T
	id := hash_combine(type_id, user_id) if user_id > 0 else type_id

	parent := element_get_assert(ctx.element_curr)

	child_id := parent.child_first
	for child in element_get(child_id) {
		// TODO: this search could probably be optimized
		if child.id == id && !child._found {
			// found matching child
			element          = child
			ctx.element_curr = element.handle
			state            = element.data_ptr
			child._found     = true
			assert(T_size == 0 || state != nil)
			return
		}
		child_id = child.next
	}

	// TODO: use pool/arena for state to keep memory continious
	bytes, alloc_err := runtime.mem_alloc(T_size, T_align, allocator=ctx.allocator)
	assert(alloc_err == nil)
	state = raw_data(bytes)

	handle, add_err := hm.add(&ctx.elements, Element{
		parent   = parent.handle,
		id       = id,
		data_ptr = state,
		_found   = true,
	})
	// TODO: how to handle errors?
	assert(add_err == nil)
	ctx.element_curr = handle

	element = element_get_assert(handle)

	if sibling, ok := element_get(parent.child_last); ok {
		sibling.next = handle
		element.prev = sibling.handle
	} else {
		parent.child_first = handle
	}
	parent.child_last = handle

	init = true

	return
}

element_push :: #force_inline proc ($T: typeid, id: u64 = 0) -> (state: ^T, element: ^Element, init: bool) {
	ptr: rawptr
	ptr, element, init = _element_push(T, size_of(T), align_of(T), id)
	state = (^T)(ptr)
	return
}

element_pop :: proc () {
	el_curr := element_get_assert(ctx.element_curr)
	assert(el_curr.parent != {})
	ctx.element_curr = el_curr.parent
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

	screen: Rect
	measure(ctx.element_root, &screen, {}, 0)

	screen_w := screen.size.x + screen.pos.x
	screen_h := screen.size.y + screen.pos.y

	pixels := make([]u8, screen_w * screen_h, allocator=context.temp_allocator)
	display(ctx.element_root, pixels, screen_w)

	sb: strings.Builder
	for p, i in pixels {
		x := i % screen_w
		if x == 0 {
			strings.write_rune(&sb, '\n')
		}
		if p != 0 {
			strings.write_rune(&sb, '0' + rune(p))
		} else {
			strings.write_rune(&sb, ' ')
		}
	}
	fmt.print(strings.to_string(sb))

	measure :: proc (h: Element_Handle, parent_rect: ^Rect, parent_padding: Insets, child_off: int) -> (ok: bool) {

		el := element_get(h) or_return

		rect := &el._rect
		rect^ = {}

		rect.pos  += parent_rect.pos
		rect.pos  += {parent_padding.l, parent_padding.t}
		rect.pos  += {0, child_off}
		rect.pos  += {el.margin.l, el.margin.t}
		rect.size += {el.padding.l + el.padding.r, el.padding.t + el.padding.b}

		measure(el.child_first, rect, el.padding, 0)

		parent_rect.size += rect.size
		parent_rect.size.y += el.margin.t + el.margin.b
		parent_rect.size.x = max(parent_rect.size.x, rect.size.x + el.margin.l + el.margin.r + parent_padding.l + parent_padding.r)

		measure(el.next, parent_rect, parent_padding, rect.size.y + el.margin.b + el.margin.t)

		return true
	}

	display :: proc (h: Element_Handle, pixels: []u8, screen_w: int) -> (ok: bool) {

		el := element_get(h) or_return
		rect := el._rect

		for xi in 0..<rect.size.x {
			pos := rect.pos + {xi, 0}
			pixels[pos.x + pos.y * screen_w] = u8(el.handle.idx)
			pos.y += rect.size.y - 1
			pixels[pos.x + pos.y * screen_w] = u8(el.handle.idx)
		}
		for yi in 0..<rect.size.y {
			pos := rect.pos + {0, yi}
			pixels[pos.x + pos.y * screen_w] = u8(el.handle.idx)
			pos.x += rect.size.x - 1
			pixels[pos.x + pos.y * screen_w] = u8(el.handle.idx)
		}

		display(el.child_first, pixels, screen_w)

		display(el.next, pixels, screen_w)

		return true
	}
}

margin_set :: proc (v: Insets) {
	element_curr().margin = v
}
margin_directions :: proc (l, t, r, b: int) {margin(Insets{l, t, r, b})}
margin_axis       :: proc (v, h: int)       {margin(h, v, h, v)}
margin_vec        :: proc (v: [2]int)       {margin(v.x, v.y, v.x, v.y)}
margin_all        :: proc (v: int)          {margin(v, v, v, v)}
margin :: proc {margin_set, margin_directions, margin_axis, margin_vec, margin_all}

padding_set :: proc (v: Insets) {
	element_curr().padding = v
}
padding_directions :: proc (l, t, r, b: int) {padding(Insets{l, t, r, b})}
padding_axis       :: proc (v, h: int)       {padding(h, v, h, v)}
padding_vec        :: proc (v: [2]int)       {padding(v.x, v.y, v.x, v.y)}
padding_all        :: proc (v: int)          {padding(v, v, v, v)}
padding :: proc {padding_set, padding_directions, padding_axis, padding_vec, padding_all}
