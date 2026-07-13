package pxui

import "core:io"
import "core:strings"
import "base:runtime"
import "core:mem"
import "core:fmt"
import la "core:math/linalg"
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

	using prev_frame: struct {
		mouse_in:     bool,
	},

	using frame: struct {
		_found:       bool,             // was the element present in this frame?
		flags:        Element_Flags,

		margin:       Insets,
		padding:      Insets,
		pos, size:    Size_Vec,

		layout:       [Layout_Direction]Layout_Callback,

		rel_rect:     Rect,           // pos and size in pixels starting at parent pos (calculated in frame_end, available in layout callbacks)
		screen_pos:   Vec2i,          // pos on screen/world (calculated in frame_end after layout solve, available for draw commands)

		draw:         Draw_Handle,
	},
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

	it := hm.iterator_make(&ctx.elements)
	for el, _ in hm.iterate(&it) {
		el.frame = {}
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

	solve_siblings :: proc (h: Element_Handle) -> bool {
		el     := element_get(h) or_return
		parent := element_get_assert(el.parent)

		// default_top_down(el, parent)
		call_layout(el, .Top_Down)

		solve_siblings(el.child_first)

		call_layout(el, .Bottom_Up)
		default_bottom_up(el, parent)

		solve_siblings(el.next)

		return true
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


size              :: proc (v: Size_Vec)         {element_curr().size = v}
size_px           :: proc (v: Vec2i)            {element_curr().size = {v.x, v.y}}
size_percent      :: proc (v: Vec2f)            {element_curr().size = {v.x, v.y}}
size_fill         :: proc ()                    {element_curr().size = Fill{}}
size_w            :: proc (w: Size)             {element_curr().size.x = w}
size_w_px         :: proc (w: int)              {element_curr().size.x = w}
size_w_percent    :: proc (w: f32)              {element_curr().size.x = w}
size_w_fill       :: proc ()                    {element_curr().size.x = Fill{}}
size_h            :: proc (h: Size)             {element_curr().size.y = h}
size_h_px         :: proc (h: int)              {element_curr().size.y = h}
size_h_percent    :: proc (h: f32)              {element_curr().size.y = h}
size_h_fill       :: proc ()                    {element_curr().size.y = Fill{}}
size_axis         :: proc (axis: Axis, v: Size) {element_curr().size[axis] = v}
size_axis_px      :: proc (axis: Axis, v: int)  {element_curr().size[axis] = v}
size_axis_percent :: proc (axis: Axis, v: f32)  {element_curr().size[axis] = v}
size_axis_fill    :: proc (axis: Axis)          {element_curr().size[axis] = Fill{}}
size_x            :: size_w
size_x_px         :: size_w_px
size_x_percent    :: size_w_percent
size_x_fill       :: size_w_fill
size_y            :: size_h
size_y_px         :: size_h_px
size_y_percent    :: size_h_percent
size_y_fill       :: size_h_fill
width             :: size_w
width_px          :: size_w_px
width_percent     :: size_w_percent
width_fill        :: size_w_fill
height            :: size_h
height_px         :: size_h_px
height_percent    :: size_h_percent
height_fill       :: size_h_fill

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


layout_top_down  :: proc (cb: Layout_Callback) {element_curr().layout[.Top_Down]  = cb}
layout_bottom_up :: proc (cb: Layout_Callback) {element_curr().layout[.Bottom_Up] = cb}


element_set_pos :: proc {element_set_pos_vec, element_set_pos_axis}
element_set_pos_vec :: proc (h: Element_Handle, v: Vec2i, loc := #caller_location) {
	element_get_assert(h, loc).rel_rect.pos = v
}
element_set_pos_axis :: proc (h: Element_Handle, axis: Axis, v: int, loc := #caller_location) {
	element_get_assert(h, loc).rel_rect.pos[axis] = v
}
element_set_left :: proc (h: Element_Handle, v: int, loc := #caller_location) {
	element_get_assert(h, loc).rel_rect.pos.x = v
}
element_set_top :: proc (h: Element_Handle, v: int, loc := #caller_location) {
	element_get_assert(h, loc).rel_rect.pos.y = v
}

element_set_size :: proc {element_set_size_vec, element_set_size_axis}
element_set_size_vec :: proc (h: Element_Handle, v: Vec2i, loc := #caller_location) {
	element_get_assert(h, loc).rel_rect.size = v
}
element_set_size_axis :: proc (h: Element_Handle, axis: Axis, v: int, loc := #caller_location) {
	element_get_assert(h, loc).rel_rect.size[axis] = v
}
element_set_width :: proc (h: Element_Handle, v: int, loc := #caller_location) {
	element_get_assert(h, loc).rel_rect.size.x = v
}
element_set_height :: proc (h: Element_Handle, v: int, loc := #caller_location) {
	element_get_assert(h, loc).rel_rect.size.y = v
}

element_expand_size :: proc {element_expand_size_vec, element_expand_size_axis}
element_expand_size_vec :: proc (h: Element_Handle, v: Vec2i, loc := #caller_location) {
	element_get_assert(h, loc).rel_rect.size = la.max(v, element_get_assert(h, loc).rel_rect.size)
}
element_expand_size_axis :: proc (h: Element_Handle, axis: Axis, v: int, loc := #caller_location) {
	element_get_assert(h, loc).rel_rect.size[axis] = max(v, element_get_assert(h, loc).rel_rect.size[axis])
}
element_expand_width :: proc (h: Element_Handle, v: int, loc := #caller_location) {
	element_get_assert(h, loc).rel_rect.size.x = max(v, element_get_assert(h, loc).rel_rect.size.x)
}
element_expand_height :: proc (h: Element_Handle, v: int, loc := #caller_location) {
	element_get_assert(h, loc).rel_rect.size.y = max(v, element_get_assert(h, loc).rel_rect.size.y)
}
