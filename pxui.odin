package pxui

import "core:io"
import "core:strings"
import "base:runtime"
import "core:mem"
import "core:fmt"
import hm "core:container/handle_map"

@private
Source_Code_Location :: runtime.Source_Code_Location

Vec2i    :: [2]int
Vec2f    :: [2]f32
RGBA     :: [4]u8
Color    :: RGBA
Rect     :: struct {using pos: Vec2i, size: Vec2i}
Rectf    :: struct {using pos: Vec2f, size: Vec2f}
Insets   :: struct {l, t, r, b: int}

Content :: struct {}
Fill    :: struct {}
Size :: union #no_nil {
	Content, // derive from content - default
	Fill,    // fill available space
	int,     // absolute
	f32,     // relative
}
Size_Vec :: [2]Size

Axis :: enum {H=0, V=1,
              X=0, Y=1}

Atlas :: struct {
	pixels: []RGBA,
	size:   Vec2i,
}

// Per frame input
Frame_Input :: struct {
	mouse:          Vec2i,
	mouse_pressed:  bool,
	mouse_released: bool,
	mouse_held:     bool,

	wheel_delta:    Vec2f,
}

Context :: struct {
	allocator:         mem.Allocator,

	// TODO: implement own?  why a xar is  used—the point of handled  is not to use  pointers
	elements:          hm.Dynamic_Handle_Map(Element, Element_Handle),
	element_curr:      Element_Handle,
	element_root:      Element_Handle,

	draw_commands:     Draw_Commands,

	using frame_input: Frame_Input,

	element_hover:     Element_Handle,
}
ctx: Context

Element_Flag  :: enum u8 {Non_Interactable}
Element_Flags :: bit_set[Element_Flag]

Layout_Direction :: enum {Top_Down, Bottom_Up}
Layout_Callback  :: proc (^Element)

Element :: struct {
	type:         typeid,               // data_ptr type
	id:           u64,
	loc:          Source_Code_Location, // element_push call location
	hash:         u64,                  // type + user id
	data_ptr:     rawptr,               // ptr to user component state

	using handle: Element_Handle,       // self
	parent:       Element_Handle,       // can be zero—root
	child_first:  Element_Handle,       // can be zero—no children
	child_last:   Element_Handle,       // can be zero—no children
	next, prev:   Element_Handle,       // can be zero—siblings

	_found:       bool,                 // was the element present in this frame?
	flags:        Element_Flags,
	mouse_in:     bool,

	margin:       Insets,
	padding:      Insets,
	pos, size:    Size_Vec,

	layout:       [Layout_Direction]Layout_Callback,

	rel_rect:     Rect,           // pos and size in pixels starting at parent pos (calculated in frame_end, available in layout callbacks)
	screen_pos:   Vec2i,          // pos on screen/world (calculated in frame_end after layout solve, available for draw commands)

	draw:         Draw_Handle,
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
element_get_or_curr :: proc (h: Element_Handle = {}, loc := #caller_location) -> ^Element {
	h := ctx.element_curr if h == {} else h
	return element_get_assert(h, loc)
}

@(require_results)
element_hash :: proc (T: typeid, user_id: u64 = 0) -> u64 {
	type_id := transmute(u64)T
	return hash_combine(type_id, user_id) if user_id > 0 else type_id
}

element_display_write  :: proc (buf: []byte, i: ^int, h: Element_Handle = {}, loc := #caller_location) -> bool {
	el := element_get_or_curr(h, loc=loc)

	_ = runtime.write_rune(i, buf, '<') or_return

	runtime.write_typeid(i, buf, el.type) or_return

	if el.id != 0 {
		runtime.write_string(i, buf, " id=") or_return
		runtime.write_u64(i, buf, el.id) or_return
	}

	if el.loc != {} {
		runtime.write_string(i, buf, " loc=") or_return
		runtime.write_caller_location(i, buf, el.loc) or_return
	}

	_ = runtime.write_rune(i, buf, '>') or_return

	return true
}
element_display_writer  :: proc (w: io.Writer, h: Element_Handle = {}, n_written: ^int = nil, loc := #caller_location) -> (n: int, err: io.Error) {
	buf: [1024]byte
	i: int
	element_display_write(buf[:], &i, h, loc=loc)
	return io.write_full(w, buf[:i])
}
element_display_builder  :: proc (sb: ^strings.Builder, h: Element_Handle = {}, loc := #caller_location) -> int {
	buf: [1024]byte
	i: int
	element_display_write(buf[:], &i, h, loc=loc)
	return strings.write_bytes(sb, buf[:i], loc=loc)
}
@(require_results)
element_display_string :: proc (h: Element_Handle = {}, allocator := context.allocator, loc := #caller_location) -> (string, bool) #optional_ok {
	sb := strings.builder_make(allocator, loc=loc)
	n := element_display_builder(&sb, h, loc=loc)
	return strings.to_string(sb), n > 0
}
element_display :: proc {element_display_write, element_display_writer, element_display_builder, element_display_string}

element_state :: proc ($T: typeid, h: Element_Handle = {}, loc := #caller_location) -> ^T {
	el := element_get_or_curr(h, loc)
	assert(el.type == typeid_of(T), loc=loc)
	return (^T)(el.data_ptr)
}

element_size :: proc (h: Element_Handle = {}, loc := #caller_location) -> Size_Vec {
	return element_get_or_curr(h, loc).size
}
element_screen_rect :: proc (h: Element_Handle = {}, loc := #caller_location) -> Rect {
	el := element_get_or_curr(h, loc)
	return {el.screen_pos, el.rel_rect.size}
}

element_parent :: proc (h: Element_Handle = {}, loc := #caller_location) -> ^Element {
	return element_get_assert(element_get_or_curr(h, loc).parent, loc)
}

@private
_element_push :: proc (type: typeid, type_size, type_align: int, user_id: u64, loc := #caller_location) ->
                      (state: rawptr, el: ^Element, init: bool)
{
	hash   := element_hash(type, user_id)
	parent := element_curr()

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
		bytes, alloc_err := runtime.mem_alloc(type_size, type_align, allocator=ctx.allocator)
		assert(alloc_err == nil)

		handle, add_err := hm.add(&ctx.elements, Element{
			type     = type,
			hash     = hash,
			id       = user_id,
			loc      = loc,
			parent   = parent.handle,
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
	assert(type_size == 0 || state != nil)

	return
}

element_push :: #force_inline proc ($T: typeid, id: u64 = 0, loc := #caller_location) ->
                                   (state: ^T, element: ^Element, init: bool) {
	ptr: rawptr
	ptr, element, init = _element_push(T, size_of(T), align_of(T), id, loc)
	return (^T)(ptr), element, init
}

element_pop :: proc () {
	// switch current element to parent
	parent := element_parent()
	ctx.element_curr = parent.handle
}

element_curr :: proc () -> ^Element {
	return element_get_assert(ctx.element_curr)
}

frame_begin :: proc () {
	assert(ctx.element_curr == ctx.element_root)

	// TODO: temporary—remove once no stale-prev-frame calc_rect reads remain.
	// calc_rect is recomputed by the solver in frame_end; reading it before
	// that would expose the previous frame's value.
	it := hm.iterator_make(&ctx.elements)
	for el, _ in hm.iterate(&it) {
		el.rel_rect   = {}
		el.screen_pos = {}
	}

	clear(&ctx.draw_commands)
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

	solve_layout()

	update_screen_rect_and_mouse()
}

solve_layout :: proc () {

	root := element_get_assert(ctx.element_root)

	// Root is sized by the user like any other element.
	// Percentages on the root resolve against 0 (i.e. zero) since it has no parent.
	root.rel_rect = {0, size_vec_to_pixel(root.size, 0)}

	update_size(root.child_first)

	update_size :: proc (h: Element_Handle) -> bool {
		el     := element_get(h) or_return
		parent := element_get_assert(el.parent)

		default_top_down(el, parent)
		update_size(el.child_first)

		default_bottom_up(el, parent)
		update_size(el.next)

		return true
	}

	// Pre cb on root: trusted to size/position root.
	call_layout(root, .Top_Down)
	solve_siblings(root.child_first)

	call_layout :: proc (el: ^Element, phase: Layout_Direction) -> bool {
		cb := el.layout[phase]
		if cb == nil do return false
		ctx.element_curr = el.handle
		cb(el)
		ctx.element_curr = ctx.element_root
		return true
	}

	solve_node :: proc (el: ^Element) {
		parent := element_get_assert(el.parent)

		// default_top_down(el, parent)
		call_layout(el, .Top_Down)

		solve_siblings(el.child_first)

		call_layout(el, .Bottom_Up)
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

	pos := size_vec_to_pixel(el.pos,  parent.rel_rect.size)

	el.rel_rect.pos = lt(parent.padding) + lt(el.margin) + pos

	for s, ax in el.size {
		switch v in s {
		case Fill, f32:
			percent := v.(f32) or_else 1.0
			avail_size := parent.rel_rect.size[ax] -
			              lt(parent.padding)[ax] - rb(parent.padding)[ax] -
			              lt(el.padding)[ax] - rb(el.padding)[ax] -
			              lt(el.margin)[ax] - rb(el.margin)[ax]
			el.rel_rect.size[ax] = int(f32(avail_size) * percent) +
			                       lt(el.padding)[ax] + rb(el.padding)[ax]
		case Content:
			// skip - done in bottom-up step
		case int:
			el.rel_rect.size[ax] = v
		}
	}
}

default_bottom_up :: proc (el, parent: ^Element) {
	// Update parent rect by own size
	for s, ax in parent.size {
		_ = s.(Content) or_continue
		parent.rel_rect.size[ax] = max(parent.rel_rect.size[ax],
		                               el.rel_rect.size[ax] +
		                               lt(el.margin)[ax] + rb(el.margin)[ax] +
		                               lt(parent.padding)[ax] + rb(parent.padding)[ax])
	}
}

update_screen_rect_and_mouse :: proc () {

	root := element_get_assert(ctx.element_root)

	_visit(root.child_first, check_mouse=true)

	_visit :: proc (h: Element_Handle, check_mouse: bool) -> (hit: bool) {

		el     := element_get(h) or_return
		parent := element_get_assert(el.parent)

		// Update position on screen
		el.screen_pos = parent.screen_pos + el.rel_rect.pos

		// Check mouse hover
		if check_mouse &&
		   .Non_Interactable not_in el.flags &&
		   rect_contains({el.screen_pos, el.rel_rect.size}, ctx.mouse)
		{
			el.mouse_in = true
			ctx.element_hover = h
		} else {
			el.mouse_in = false
		}

		_visit(el.child_first, check_mouse=el.mouse_in)

		_visit(el.next, check_mouse=check_mouse && !el.mouse_in)

		return true
	}
}

is_hovered :: proc (h: Element_Handle = {}) -> bool {
	return element_get_or_curr(h).handle == ctx.element_hover
}
is_mouse_in :: proc (h: Element_Handle = {}) -> bool {
	return element_get_or_curr(h).mouse_in
}
is_clicked :: proc (h: Element_Handle = {}) -> bool {
	return is_hovered(h) && ctx.mouse_pressed
}
