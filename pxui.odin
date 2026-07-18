package pxui

import "core:os"
import "core:io"
import "core:strings"
import "base:runtime"
import "core:mem"
import "core:fmt"
import "core:container/topological_sort"
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
Sizing :: union #no_nil {
	Content, // derive from content - default
	Fill,    // fill available space
	int,     // absolute - pixels
	f32,     // relative - percent
}
Sizing_2D :: [2]Sizing

@rodata FILL    := Fill{}
@rodata CONTENT := Content{}

Placement :: struct {
	pos, size, origin: Sizing_2D,
}

Axis :: enum {H=0, V=1,
              X=0, Y=1}

Axis_Set :: bit_set[Axis]

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

	draw_reqs:         [dynamic]Draw_Request,

	using frame_input: Frame_Input,

	element_hover:     Element_Handle,
	element_wheel:     Element_Handle,
}
ctx: Context

Element_Flag  :: enum u8 {Non_Interactable, Capture_Wheel}
Element_Flags :: bit_set[Element_Flag]

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
		using place:  Placement,

		layout:       [2]struct {cb: proc (), deps: Axis_Set},
		effect:       proc (),

		ref_pos:      Vec2i,           // pos of the element's bounds (including margin) on the parent's ref plane (pixels, default 0,0)
		ref_size:     Vec2i,           // bounds of the element (outer size, including margin) — the "space" this element occupies in the parent (pixels)
		screen_pos:   Vec2i,           // pos of the element's box (excluding margin) on screen/world (calculated in frame_end after layout solve, available for draw commands)
		size_set:     [2]bool,

		draw_first:   Draw_Request_Handle,
		draw_last:    Draw_Request_Handle,
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
	fmt.assertf(ok, "", handle, loc=loc)
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

element_parent :: proc (h: Element_Handle = {}, loc := #caller_location) -> ^Element {
	return element_get_assert(element_get_or_curr(h, loc).parent, loc)
}

@private
_element_push :: proc (type: typeid, type_size, type_align: int, user_id: u64, loc := #caller_location) ->
                      (state: rawptr, init: bool)
{
	hash   := element_hash(type, user_id)
	parent := element_curr()
	el: ^Element

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
                                   (state: ^T, init: bool) {
	ptr: rawptr
	ptr, init = _element_push(T, size_of(T), align_of(T), id, loc)
	return (^T)(ptr), init
}

element_pop :: proc () {
	// switch current element to parent
	parent := element_parent()
	ctx.element_curr = parent.handle
}

element_curr :: proc () -> ^Element {
	return element_get_assert(ctx.element_curr)
}
element_root :: proc () -> ^Element {
	return element_get_assert(ctx.element_root)
}

frame_begin :: proc () {
	assert(ctx.element_curr == ctx.element_root)

	it := hm.iterator_make(&ctx.elements)
	for el, _ in hm.iterate(&it) {
		el.frame = {}
	}

	clear(&ctx.draw_reqs)
}

frame_end :: proc () {
	assert(ctx.element_curr == ctx.element_root)

	it := hm.iterator_make(&ctx.elements)

	for el, handle in hm.iterate(&it) {
		if !el._found && handle != ctx.element_root {
			free(el.data_ptr)
			hm.remove(&ctx.elements, handle)
		}
	}

	topological_solve()

	update_screen_rect_and_mouse()

	for el, _ in hm.iterate(&it) {
		_call_effect(el)
	}
}

topological_solve :: proc () {

	context.allocator = context.temp_allocator

	root := element_root()

	// Root has no parent; its ref_size comes from the user-set size only.
	// Percentages on the root resolve against 0 (i.e. zero).
	root.ref_pos  = 0
	root.ref_size = size_vec_to_pixel(root.size, 0)
	root.size_set = true

	it := hm.iterator_make(&ctx.elements)

	Key :: struct {el: ^Element, axis: Axis}
	sorter: topological_sort.Sorter(Key)

	for el, _ in hm.iterate(&it) {
		for axis in Axis {
			topological_sort.add_key(&sorter, Key{el, axis})

			#partial switch s in el.size[axis] {
			case Fill, f32:
				parent := element_get_assert(el.parent)
				topological_sort.add_dependency(&sorter, Key{el, axis}, Key{parent, axis})
			case Content:
				child_id := el.child_first
				for child in element_get(child_id) {
					defer child_id = child.next

					#partial switch _ in child.size[axis] {
					case Fill, f32: continue // skip cyclic deps
					}

					topological_sort.add_dependency(&sorter, Key{el, axis}, Key{child, axis})
				}
			}

			// Custom layouts can depend on other axis
			if el.layout[axis].cb != nil {
				if perp(axis) in el.layout[axis].deps {
					topological_sort.add_dependency(&sorter, Key{el, axis}, Key{el, perp(axis)})
				}
				if axis in el.layout[axis].deps && el.size[axis] != CONTENT {
					child_id := el.child_first
					for child in element_get(child_id) {
						defer child_id = child.next

						#partial switch _ in child.size[axis] {
						case Fill, f32: continue // skip cyclic deps
						}

						topological_sort.add_dependency(&sorter, Key{el, axis}, Key{child, axis})
					}
				}
			}
		}
	}

	sorted, cycled := topological_sort.sort(&sorter)

	if len(cycled) > 0 {
		w := io.to_writer(os.to_writer(os.stdout))
		fmt.wprintln(w, "Cycled:")
		for key in cycled {
			fmt.wprint(w, "\t")
			element_display_writer(w, key.el)
			fmt.wprintln(w, ":", key.axis == .X ? "X" : "Y")
		}
	}

	for key in sorted {
		el, axis := key.el, key.axis

		if !el.size_set[axis] {
			switch v in el.size[axis] {
			case Fill, f32:
				element_set_size(el, axis, size_to_pixel(v, element_inner_bounds(el.parent, axis)))
			case Content:
				child_id := el.child_first
				for child in element_get(child_id) {
					defer child_id = child.next

					switch _ in child.size[axis] {
					case Fill, f32:
						// skip cyclic deps
					case Content, int:
						element_expand_inner_bounds(el, axis, element_bounds(child, axis))
					}
				}
			case int:
				element_set_size(el, axis, v + lt(el.margin)[axis] + rb(el.margin)[axis])
			}
		}

		_call_layout(el, axis)

		el.size_set[axis] = true
	}

	return
}

@private
_call_layout :: proc (el: ^Element, axis: Axis) {
	layout := el.layout[axis]
	if layout.cb == nil do return
	prev_el := ctx.element_curr
	ctx.element_curr = el.handle
	layout.cb()
	ctx.element_curr = prev_el
}
@private
_call_effect :: proc (el: ^Element) {
	cb := el.effect
	if cb == nil do return
	prev_el := ctx.element_curr
	ctx.element_curr = el.handle
	cb()
	ctx.element_curr = prev_el
}

update_screen_rect_and_mouse :: proc () {

	root := element_root()

	// Iterate in reverse order as
	// later children are rendered on top of previous
	_visit(root.child_last, check_mouse=true)

	_visit :: proc (h: Element_Handle, check_mouse: bool) -> bool {

		el     := element_get(h) or_return
		parent := element_get_assert(el.parent)

		el.screen_pos = parent.screen_pos +
		                lt(parent.padding) +
		                el.ref_pos +
		                lt(el.margin)

		el.mouse_in = check_mouse && .Non_Interactable not_in el.flags &&
		              rect_contains(element_screen_rect(el), ctx.mouse)

		if el.mouse_in {
			ctx.element_hover = el
		}

		if el.mouse_in && .Capture_Wheel in el.flags {
			ctx.element_wheel = el
		}

		_visit(el.child_last, check_mouse=el.mouse_in)

		_visit(el.prev, check_mouse=check_mouse && !el.mouse_in)

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
is_pressed :: proc (h: Element_Handle = {}) -> bool {
	return is_hovered(h) && ctx.mouse_pressed
}
is_click_in :: proc (h: Element_Handle = {}) -> bool {
	return is_mouse_in(h) && ctx.mouse_pressed
}
is_press_in :: proc (h: Element_Handle = {}) -> bool {
	return is_mouse_in(h) && ctx.mouse_pressed
}
is_released :: proc () -> bool {
	return ctx.mouse_released
}
is_wheel_in :: proc (h: Element_Handle = {}) -> bool {
	return element_get_or_curr(h).handle == ctx.element_wheel
}

wheel_delta :: proc (h: Element_Handle = {}) -> Vec2f {
	return ctx.wheel_delta if is_wheel_in(h) else {}
}
wheel_delta_axis :: proc (axis: Axis, h: Element_Handle = {}) -> f32 {
	return wheel_delta(h)[axis]
}
wheel_delta_x :: proc (h: Element_Handle = {}) -> f32 {
	return wheel_delta(h).x
}
wheel_delta_y :: proc (h: Element_Handle = {}) -> f32 {
	return wheel_delta(h).y
}


flag :: proc (f: Element_Flag, h: Element_Handle = {}) {
	el := element_get_or_curr(h)
	el.flags += {f}
}
flags :: proc (f: Element_Flags, h: Element_Handle = {}) {
	el := element_get_or_curr(h)
	el.flags += f
}

size              :: proc (v: Sizing_2D)          {element_curr().size = v}
size_px           :: proc (v: Vec2i)              {element_curr().size = {v.x, v.y}}
size_percent      :: proc (v: Vec2f)              {element_curr().size = {v.x, v.y}}
size_fill         :: proc ()                      {element_curr().size = FILL}
size_w            :: proc (w: Sizing)             {element_curr().size.x = w}
size_w_px         :: proc (w: int)                {element_curr().size.x = w}
size_w_percent    :: proc (w: f32)                {element_curr().size.x = w}
size_w_fill       :: proc ()                      {element_curr().size.x = FILL}
size_h            :: proc (h: Sizing)             {element_curr().size.y = h}
size_h_px         :: proc (h: int)                {element_curr().size.y = h}
size_h_percent    :: proc (h: f32)                {element_curr().size.y = h}
size_h_fill       :: proc ()                      {element_curr().size.y = FILL}
size_axis         :: proc (axis: Axis, v: Sizing) {element_curr().size[axis] = v}
size_axis_px      :: proc (axis: Axis, v: int)    {element_curr().size[axis] = v}
size_axis_percent :: proc (axis: Axis, v: f32)    {element_curr().size[axis] = v}
size_axis_fill    :: proc (axis: Axis)            {element_curr().size[axis] = FILL}
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
margin_h          :: proc (h: int)          {margin_l(h); margin_r(h)}
margin_v          :: proc (v: int)          {margin_t(v); margin_b(v)}
margin            :: proc {margin_set, margin_directions, margin_axis, margin_vec, margin_all}
margin_dirs       :: margin_directions
margin_bottom     :: margin_b
margin_bot        :: margin_b
margin_left       :: margin_l
margin_right      :: margin_r
margin_top        :: margin_t
margin_x          :: margin_h
margin_y          :: margin_v

padding_set        :: proc (v: Insets)       {element_curr().padding = v}
padding_directions :: proc (l, t, r, b: int) {padding(Insets{l, t, r, b})}
padding_axis       :: proc (h, v: int)       {padding(h, v, h, v)}
padding_vec        :: proc (v: Vec2i)        {padding(v.x, v.y, v.x, v.y)}
padding_all        :: proc (v: int)          {padding(v, v, v, v)}
padding_t          :: proc (v: int)          {element_curr().padding.t = v}
padding_b          :: proc (v: int)          {element_curr().padding.b = v}
padding_l          :: proc (v: int)          {element_curr().padding.l = v}
padding_r          :: proc (v: int)          {element_curr().padding.r = v}
padding_h          :: proc (h: int)          {padding_l(h); padding_r(h)}
padding_v          :: proc (v: int)          {padding_t(v); padding_b(v)}
padding            :: proc {padding_set, padding_directions, padding_axis, padding_vec, padding_all}
padding_dirs       :: padding_directions
padding_bottom     :: padding_b
padding_bot        :: padding_b
padding_left       :: padding_l
padding_right      :: padding_r
padding_top        :: padding_t
padding_x          :: padding_h
padding_y          :: padding_v


layout_axis :: proc (axis: Axis, cb: proc (), deps: Axis_Set = {}, h: Element_Handle = {}) {
	deps := deps if deps != {} else {axis}
	element_get_or_curr(h).layout[axis] = {cb, deps}
}
layout :: proc {layout_axis}

effect :: proc (cb: proc (), h: Element_Handle = {}) {element_get_or_curr(h).effect = cb}


element_set_pos :: proc {element_set_pos_vec, element_set_pos_axis}
element_set_pos_vec :: proc (h: Element_Handle, v: Vec2i, loc := #caller_location) {
	element_get_assert(h, loc).ref_pos = v
}
element_set_pos_axis :: proc (h: Element_Handle, axis: Axis, v: int, loc := #caller_location) {
	element_get_assert(h, loc).ref_pos[axis] = v
}
element_set_left :: proc (h: Element_Handle, v: int, loc := #caller_location) {
	element_get_assert(h, loc).ref_pos.x = v
}
element_set_top :: proc (h: Element_Handle, v: int, loc := #caller_location) {
	element_get_assert(h, loc).ref_pos.y = v
}

element_set_size :: proc {element_set_size_vec, element_set_size_axis}
element_set_size_vec :: proc (h: Element_Handle, v: Vec2i, loc := #caller_location) {
	el := element_get_assert(h, loc)
	el.ref_size = v
	el.size_set = true
}
element_set_size_axis :: proc (h: Element_Handle, axis: Axis, v: int, loc := #caller_location) {
	el := element_get_assert(h, loc)
	el.ref_size[axis] = v
	el.size_set[axis] = true
}
element_set_width :: proc (h: Element_Handle, v: int, loc := #caller_location) {
	el := element_get_assert(h, loc)
	el.ref_size.x = v
	el.size_set.x = true
}
element_set_height :: proc (h: Element_Handle, v: int, loc := #caller_location) {
	el := element_get_assert(h, loc)
	el.ref_size.y = v
	el.size_set.y = true
}

element_pos :: proc {element_pos_vec, element_pos_axis}
element_pos_vec :: proc (h: Element_Handle = {}, loc := #caller_location) -> Vec2i {
	el := element_get_or_curr(h, loc)
	return el.ref_pos
}
element_pos_axis :: proc (h: Element_Handle = {}, axis: Axis, loc := #caller_location) -> int {
	el := element_get_or_curr(h, loc)
	return el.ref_pos[axis]
}

element_screen_pos :: proc (h: Element_Handle = {}, loc := #caller_location) -> Vec2i {
	el := element_get_or_curr(h, loc)
	return el.screen_pos
}
element_screen_rect :: proc (h: Element_Handle = {}, loc := #caller_location) -> Rect {
	el := element_get_or_curr(h, loc)
	return {el.screen_pos, element_box_size(h, loc)}
}

// element_box_size returns the element's box size (excluding margin). This is what gets drawn.
element_box_size :: proc (h: Element_Handle = {}, loc := #caller_location) -> Vec2i {
	el := element_get_or_curr(h, loc)
	return el.ref_size - lt(el.margin) - rb(el.margin)
}

// element_bounds returns the element's outer bounds (including margin). This is the space the
// element occupies in its parent. Equivalent to element_size.
element_bounds :: proc {element_bounds_vec, element_bounds_axis}
element_bounds_vec :: proc (h: Element_Handle = {}, loc := #caller_location) -> Vec2i {
	el := element_get_or_curr(h, loc)
	return el.ref_size
}
element_bounds_axis :: proc (h: Element_Handle = {}, axis: Axis, loc := #caller_location) -> int {
	el := element_get_or_curr(h, loc)
	return el.ref_size[axis]
}

// element_inner_bounds returns the size of the reference plane (inner area) available to children.
// This is the outer bounds minus margin and padding.
element_inner_bounds :: proc {element_inner_bounds_vec, element_inner_bounds_axis}
element_inner_bounds_vec :: proc (h: Element_Handle = {}, loc := #caller_location) -> Vec2i {
	el := element_get_or_curr(h, loc)
	return el.ref_size -
	       lt(el.margin) -
	       rb(el.margin) -
	       lt(el.padding) -
	       rb(el.padding)
}
element_inner_bounds_axis :: proc (h: Element_Handle = {}, axis: Axis, loc := #caller_location) -> int {
	return element_inner_bounds(h, loc)[axis]
}

// element_set_inner_bounds sets the element's inner bounds (area for children). The outer bounds
// are auto-computed as inner + margin + padding.
element_set_inner_bounds :: proc {element_set_inner_bounds_vec, element_set_inner_bounds_axis}
element_set_inner_bounds_vec :: proc (h: Element_Handle, v: Vec2i, loc := #caller_location) {
	element_set_inner_bounds_axis(h, .X, v.x, loc)
	element_set_inner_bounds_axis(h, .Y, v.y, loc)
}
element_set_inner_bounds_axis :: proc (h: Element_Handle, axis: Axis, v: int, loc := #caller_location) {
	el := element_get_assert(h, loc)
	el.ref_size[axis] = v +
	                    lt(el.margin)[axis] +
	                    rb(el.margin)[axis] +
	                    lt(el.padding)[axis] +
	                    rb(el.padding)[axis]
	el.size_set[axis] = true
}

// element_expand_inner_bounds expands the element's inner bounds to at least the given value.
element_expand_inner_bounds :: proc {element_expand_inner_bounds_vec, element_expand_inner_bounds_axis}
element_expand_inner_bounds_vec :: proc (h: Element_Handle, v: Vec2i, loc := #caller_location) {
	element_expand_inner_bounds_axis(h, .X, v.x, loc)
	element_expand_inner_bounds_axis(h, .Y, v.y, loc)
}
element_expand_inner_bounds_axis :: proc (h: Element_Handle, axis: Axis, v: int, loc := #caller_location) {
	el := element_get_assert(h, loc)
	el.ref_size[axis] = max(el.ref_size[axis],
	                        v +
	                        lt(el.margin)[axis] +
	                        rb(el.margin)[axis] +
	                        lt(el.padding)[axis] +
	                        rb(el.padding)[axis])
	el.size_set[axis] = true
}
