package pxui

import "core:slice"
import "core:os"
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

WHITE :: Color{255, 255, 255, 255}

Content :: struct {}
Fill    :: struct {}
Sizing :: union {
	// nil — not set; for size it defaults to Content, for other props it's zero or unused
	Content, // derive from content - default
	Fill,    // fill available space
	int,     // absolute - pixels
	f32,     // relative - percent
}
Sizing_2D :: [2]Sizing

@rodata FILL    := Fill{}
@rodata CONTENT := Content{}

Placement :: struct {
	pos, size, min, max, origin: Sizing_2D,
	margin, padding:             Insets,
	aspect_ratio:                f32, // TODO: x/y
}

Axis :: enum {H=0, V=1,
              X=0, Y=1}
AXIS :: [2]Axis{.X, .Y} // because `for axis in Axis` iterates 4 times :(

Axis_Set :: bit_set[Axis]

Texture :: struct {
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

	time:           int,
}

Context :: struct {
	allocator:         mem.Allocator,

	elements:          hm.Static_Handle_Map(10000, Element, Element_Handle),
	element_curr:      Element_Handle,
	element_root:      Element_Handle,

	draw_reqs_prev:    []Draw_Request, // Used for memoized elements; copied from draw_reqs at the start of a frame
	draw_reqs:         [dynamic]Draw_Request,

	animations:        hm.Static_Handle_Map(1000, Animation, Animation_Handle),

	using frame_input: Frame_Input,

	element_hover:     Element_Handle,
	element_wheel:     Element_Handle,
}
ctx: Context

Element_Flag  :: enum u8 {Non_Interactable, Capture_Wheel, Position_Absolute}
Element_Flags :: bit_set[Element_Flag]

// Element data user sets during frame or callbacks
Element_Frame_Input :: struct {
	_found:       bool,             // was the element present in this frame? TODO: could use frame count

	flags:        Element_Flags,

	using place:  Placement,

	// 0 = fully opaque (default)
	// 1 = fully transparent
	//
	// The element's subtree is rendered to an offscreen surface and composited back with this alpha
	transparency: f32,

	layout:       [2]struct {cb: proc (), deps: Axis_Set},
	effect:       proc (),
	cleanup:      proc (),
	subtree:      proc (),

	anims_exit:   [Animation_Property]Animation_Exit_Req,

	transition:   [Animation_Property]Transition,
}

// Element data derived from inputs, layout, etc.
Element_Frame_Derived :: struct {

	child_first:    Element_Handle,       // can be zero—no children
	child_last:     Element_Handle,       // can be zero—no children
	next, prev:     Element_Handle,       // can be zero—siblings

	draw_first:     Draw_Request_Handle,
	draw_last:      Draw_Request_Handle,
	draw_frame_end: Draw_Request_Handle, // Last draw request called before layout/effect callbacks

	pos_ref:        Vec2i,   // pos of the element's bounds (including margin) on the parent's ref plane (pixels, default 0,0)
	pos_rel:        Vec2i,
	pos_set:        [2]bool,

	size_ref:       Vec2i,   // bounds of the element (outer size, including margin) — the "space" this element occupies in the parent (pixels)
	size_set:       [2]bool,

	solved:         [2]bool,
	prevent_destroy: bool,

	pos_screen:     Maybe(Vec2i),   // pos of the element's box (excluding margin) on screen/world (calculated in frame_end after layout solve, available for draw commands)

	derived_transparency: f32,

	mouse_in:       bool,
}

Element_Frame_Data :: struct {
	using input:   Element_Frame_Input,
	using derived: Element_Frame_Derived,
}

// Internal state for each element node.
// Stored in `ctx.elements`
Element :: struct {
	type:          typeid,               // data_ptr type
	id:            u64,
	loc:           Source_Code_Location, // element_push call location
	hash:          u64,                  // type + user id
	data_ptr:      rawptr,               // ptr to user component state

	using handle:  Element_Handle,       // self
	parent:        Element_Handle,       // can be zero—root

	memos:         [dynamic]Memo,
	memo_curr:     Maybe(^Memo),
	memo:          Maybe(^Memo),

	last_frame:    Element_Frame_Data,
	using frame:   Element_Frame_Data,
	anims:         [Animation_Property]Animation_Handle,
}
Element_Handle :: struct {idx, gen: u32} // index to `ctx.elements`

Memo :: struct {
	id:       u64,
	data_id:  u64,
	_found:   bool, // TODO: could use frame count
	el_first: Element_Handle,
	el_last:  Element_Handle,
}

init :: proc (allocator := context.allocator) {

	ctx.allocator = allocator

	ctx.draw_reqs = make([dynamic]Draw_Request, allocator)

	ctx.element_root = hm.add(&ctx.elements, Element{})
	ctx.element_curr = ctx.element_root

	root := element_get_assert(ctx.element_root)
	root.handle = ctx.element_root

	return
}

shutdown :: proc () {
	delete(ctx.draw_reqs)
	it := hm.iterator_make(&ctx.elements)
	for el, _ in hm.iterate(&it) {
		_element_destroy(el)
	}
}


@private
_element_push :: proc (type: typeid, type_size, type_align: int, user_id: u64, loc := #caller_location) -> (state: rawptr)
{
	hash   := element_hash(type, user_id)
	parent := element_curr(loc)
	el: ^Element

	search: {
		// Search for matching child from previous frame
		// TODO: this search could probably be optimized

		child_id := parent.last_frame.child_first
		for child in element_get(child_id) {
			defer child_id = child.last_frame.next

			if child.hash == hash && !child._found {
				// Found matching child
				el = child
				break search
			}
		}

		// Not found—create a new element

		// TODO: use pool/arena for state to keep memory continious
		bytes, alloc_err := runtime.mem_alloc(type_size, type_align, allocator=ctx.allocator)
		assert(alloc_err == nil)

		handle, add_ok := hm.add(&ctx.elements, Element{
			type     = type,
			hash     = hash,
			id       = user_id,
			loc      = loc,
			memos    = make([dynamic]Memo, allocator=ctx.allocator),
			parent   = parent.handle,
			data_ptr = raw_data(bytes),
		})
		// TODO: how to handle errors?
		assert(add_ok)
		el = element_get_assert(handle)
	}

	_element_attach_after(el, parent.child_last)

	ctx.element_curr = el
	el._found        = true
	state            = el.data_ptr
	assert(type_size == 0 || state != nil)

	// Add to memo if called in one
	el.memo = parent.memo_curr
	if memo, has_memo := el.memo.?; has_memo {
		if _, has_first := element_get(memo.el_first); !has_first {
			memo.el_first = el
		}
		memo.el_last = el
	}

	for &m in el.memos {
		m._found = false
	}

	return
}

element_push :: #force_inline proc ($T: typeid, #any_int id: u64 = 0, loc := #caller_location) -> ^T {
	ptr := _element_push(T, size_of(T), align_of(T), id, loc)
	return (^T)(ptr)
}

element_pop :: proc () {

	el := element_curr()

	// Mark end of draw requests called before callbacks (need to be copied for memoized elements)
	el.draw_frame_end = el.draw_last

	_element_animate_props(el)

	// switch current element to parent
	ctx.element_curr = element_parent()
}

_element_attach_after :: proc (el: ^Element, handle: Element_Handle) {

	parent := element_parent(el)

	if handle == {} {
		// Prepend
		if first, has_first := element_get(parent.child_first); has_first {
			first.prev, el.next = el, first
			if next, has_next := element_get(el.next); has_next {
				next.prev = el
			}
		}
		if parent.child_first == parent.child_last {
			parent.child_last = el
		}
		parent.child_first = el
	}
	else if prev, has_prev := element_get(handle); has_prev && handle != parent.child_last && prev._found {
		// Append after handle
		el.prev, prev.next, el.next = prev, el, prev.next
		if next, has_next := element_get(el.next); has_next {
			next.prev = el
		}
	}
	else if last, has_last := element_get(parent.child_last); has_last {
		// Append last
		el.prev, last.next = last, el
		parent.child_last = el
	}
	else {
		// First child
		parent.child_first = el
		parent.child_last  = el
	}
}

@private
_element_check_destroy :: proc (el: ^Element) {

	if !el._found {

		// Prevent destroy if there are exit animations running
		// - but only if the tree above is still present
		prevent_destroy: bool
		if parent, has_parent := element_get(el.parent); has_parent && parent._found {
			prevent_destroy |= parent.prevent_destroy
			prevent_destroy |= _element_has_exit_animations(el)
		}

		if prevent_destroy {
			el.prevent_destroy = true
			_element_copy_last_frame_data(el)
			_element_attach_after(el, el.last_frame.prev)
			flag(.Non_Interactable, el)
			_element_animate_exit(el)
			_element_animate_props(el)
		} else {
			_element_destroy(el)
		}
	}

	// Visit children up to another subtree
	if el.subtree == nil {
		child_id := el.last_frame.child_first
		for child in element_get(child_id) {
			_element_check_destroy(child)
			child_id = child.last_frame.next
		}
	}
}

@private
_element_destroy :: proc (el: ^Element) {

	if el._found {
		_call_element_callback(el, el.cleanup)
	} else {
		_call_element_callback(el, el.last_frame.cleanup)
	}

	// Free data
	delete(el.memos)
	free(el.data_ptr)

	// Remove any pending animations
	for a in el.anims {
		hm.remove(&ctx.animations, a)
	}

	// Free self
	hm.remove(&ctx.elements, el)
}


memo_begin :: proc (#any_int data_id: u64, #any_int memo_id: u64 = 0, loc := #caller_location) -> (changed: bool) {

	el := element_curr(loc)
	assert(el.memo_curr == nil, loc=loc)

	memo: ^Memo
	memo_search: {
		for &m in el.memos do if !m._found && m.id == memo_id {
			// Found matching memo
			memo = &m

			changed = memo.data_id != data_id

			if changed {
				// Data changes invalidates stored elements
				// and they need to be collected again
				memo.el_first, memo.el_last = {}, {}
			} else {
				// Add memoized children elements to current element

				child_id := memo.el_first
				for child in element_get(child_id) {
					_memo_visit_nested_element(child)
					if child_id == memo.el_last do break
					child_id = child.last_frame.next
				}
			}

			break memo_search
		}

		// Create new memo
		append(&el.memos, Memo{id=memo_id}, loc)
		memo = &el.memos[len(el.memos)-1]

		changed = true
	}

	memo._found  = true
	memo.data_id = data_id

	el.memo_curr = memo

	return
}
memo_end :: proc (#any_int data_id: u64, #any_int memo_id: u64 = 0, loc := #caller_location) {
	el := element_curr(loc)
	assert(el.memo_curr != nil, loc=loc)
	el.memo_curr = nil
}
@(deferred_in=memo_end)
memo :: proc (#any_int data_id: u64, #any_int memo_id: u64 = 0, loc := #caller_location) -> bool {
	return memo_begin(data_id, memo_id, loc)
}

@private
_memo_visit_nested_element :: proc (h: Element_Handle) -> bool {
	el := element_get(h) or_return

	_element_copy_last_frame_data(el)
	_element_attach_after(el, el.last_frame.prev)
	_element_animate_props(el)

	child_id := el.last_frame.child_first
	for child in element_get(child_id) {
		_memo_visit_nested_element(child)
		child_id = child.last_frame.next
	}

	return true
}

_element_copy_last_frame_data :: proc (el: ^Element) {

	// Copy prev frame input data
	el.input = el.last_frame.input

	// Copy draw requests from previous frame
	// Ignoring the ones from layout/effect callbacks
	if el.last_frame.draw_frame_end != {} {
		draw_id := el.last_frame.draw_first
		for d in draw_get_last_frame(draw_id) {
			draw(d^, el)
			if draw_id == el.last_frame.draw_frame_end do break
			draw_id = d.next
		}
		el.draw_frame_end = el.draw_last
	}
}


frame_begin :: proc () {
	trace("Frame Begin")

	assert(ctx.element_curr == ctx.element_root)

	it := hm.iterator_make(&ctx.elements)
	for el, _ in hm.iterate(&it) {
		el.last_frame, el.frame = el.frame, {}
	}

	// TODO: instead of copying could use two dynamic arrays and frame count % 2
	ctx.draw_reqs_prev = slice.clone(ctx.draw_reqs[:], context.temp_allocator)
	clear(&ctx.draw_reqs)

	root := element_root()
	root._found = true
}

frame_end :: proc () {
	trace("Frame End")

	assert(ctx.element_curr == ctx.element_root)

	root := element_root()

	_element_check_destroy(root)

	// Root has no parent; its ref_size comes from the user-set size only.
	// Percentages on the root resolve against 0 (i.e. zero).
	root.size_ref   = size_vec_to_pixel(root.size, 0)
	root.size_set   = true
	root.pos_set    = true
	root.pos_screen = 0

	_solve_layout(root)

	update_screen_rect_and_mouse()

	{
		trace("Call Effects")

		it := hm.iterator_make(&ctx.elements)
		for el, _ in hm.iterate(&it) {
			_call_element_callback(el, el.effect)
		}
	}
}

_solve_layout :: proc (el: ^Element) #no_bounds_check {

	visit(el, Axis.X)
	visit(el, Axis.Y)

	// Visit children
	child_id := el.child_first
	for child in element_get(child_id) {
		_solve_layout(child)
		child_id = child.next
	}

	visit :: proc (el: ^Element, axis: Axis) {

		assert(el._found, "Should be found at this point")

		if el.solved[axis] do return
		el.solved[axis] = true

		is_top_down  := _element_size_is_top_down(el, axis)
		is_bottom_up := _element_size_is_bottom_up(el, axis)

		// Visit parent dep
		if is_top_down {
			visit(element_parent(el), axis)
		}

		// Visit children deps
		if is_bottom_up {
			child_id: Element_Handle
			for child in each_element_layout_child(el, &child_id) {
				if !_element_size_is_top_down(child, axis) {
					visit(child, axis)
				}
			}
		}

		// Visit self—other axis
		if el.layout[axis].cb != nil && perp(axis) in el.layout[axis].deps {
			visit(el, perp(axis))
		}

		if !el.size_set[axis] {
			el.size_set[axis] = true
			el.size_ref[axis] = (el.size[axis].(int) or_else 0) +
			                    lt(el.margin)[axis] +
			                    rb(el.margin)[axis]

			if is_top_down {
				parent := element_parent(el)
				assert(parent.size_set[axis])
				parent_size := .Position_Absolute in el.flags \
				               	? element_box_size(parent, axis) \
				               	: element_inner_bounds(parent, axis)
				_element_set_ref_size(el, axis, parent_size)
			}
			else if is_bottom_up {
				child_id: Element_Handle
				for child in each_element_layout_child(el, &child_id) {
					if _element_size_is_top_down(child, axis) do continue

					assert(child.size_set[axis])
					element_expand_inner_bounds(el, axis, element_bounds(child, axis))
				}
			}
		}

		if is_bottom_up {
			// bottom up layout can change size
			_call_element_callback(el, el.layout[axis].cb)
			_animate_size(el, axis)
		} else {
			_animate_size(el, axis)

			// Handle subtree
			if el.solved == true && el.subtree != nil {

				_call_element_callback(el, el.subtree)

				// Check for removed children now that new subtree structure is known
				child_id := el.last_frame.child_first
				for child in element_get(child_id) {
					defer child_id = child.last_frame.next
					_element_check_destroy(child)
				}
			}

			_call_element_callback(el, el.layout[axis].cb)
		}
	}
}

_element_size_is_top_down :: proc (el: ^Element, axis: Axis) -> bool #no_bounds_check {
	#partial switch _ in el.size[axis] {case Fill, f32: return true}
	#partial switch _ in el.min[axis]  {case Fill, f32: return true}
	#partial switch _ in el.max[axis]  {case Fill, f32: return true}
	return false
}
_element_size_is_bottom_up :: proc (el: ^Element, axis: Axis) -> bool #no_bounds_check {
	#partial switch _ in el.size[axis] {case nil, Content: return true} // el.size nil defaults to Content behavior
	#partial switch _ in el.min[axis]  {case Content: return true}
	#partial switch _ in el.max[axis]  {case Content: return true}
	return el.layout[axis].cb != nil && axis in el.layout[axis].deps // layout callback should know the size of it's children
}

_element_set_ref_size :: proc (el: ^Element, axis: Axis, ref: int) #no_bounds_check {
	el.size_ref[axis] = _placement_calc_ref_size(el, axis, ref, ref)
	el.size_set[axis] = true
}

_call_element_callback :: proc (el: ^Element, cb: proc ()) {
	if cb == nil do return
	prev_el := ctx.element_curr
	ctx.element_curr = el.handle
	cb()
	ctx.element_curr = prev_el
}

update_screen_rect_and_mouse :: proc () {

	trace("Screen/Interation update")

	root := element_root()

	// Iterate in reverse order as
	// later children are rendered on top of previous
	_visit(root.child_last, check_mouse=true)

	_visit :: proc (h: Element_Handle, check_mouse: bool) -> bool {

		el     := element_get(h) or_return
		parent := element_parent(el)

		parent_size := .Position_Absolute in el.flags \
		               	? element_box_size(parent) \
		               	: element_inner_bounds(parent)

		el.pos_rel = el.pos_ref +
		             _placement_calc_rel_pos(el, parent_size, element_box_size(el)) +
		             -lt(el.margin) // ignore margin for now as we are animating pos_rel

		_animate_pos(el)

		pos_screen := parent.pos_screen.? +
		              el.pos_rel +
		              lt(el.margin)

		if .Position_Absolute not_in el.flags {
			pos_screen += lt(parent.padding)
		}

		el.pos_screen = pos_screen

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


@(require_results)
element_curr :: proc (loc := #caller_location) -> ^Element {
	return element_get_assert(ctx.element_curr, loc)
}
@(require_results)
element_root :: proc (loc := #caller_location) -> ^Element {
	return element_get_assert(ctx.element_root, loc)
}

@(require_results)
element_get :: #force_inline proc (handle: Element_Handle) -> (el: ^Element, ok: bool) #optional_ok {
	return hm.get(&ctx.elements, handle)
}
@(require_results)
element_get_assert :: #force_inline proc (handle: Element_Handle, loc := #caller_location) -> ^Element {
	el, ok := hm.get(&ctx.elements, handle)
	fmt.assertf(ok, "", handle, loc=loc)
	return el
}
@(require_results)
element_get_or_curr :: #force_inline proc (h: Element_Handle = {}, loc := #caller_location) -> ^Element {
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
element_print :: proc (h: Element_Handle = {}, loc := #caller_location) {
	w := io.to_writer(os.to_writer(os.stdout))
	element_display_writer(w, h, loc=loc)
}

@(require_results)
element_state_safe :: proc ($T: typeid, h: Element_Handle = {}, loc := #caller_location) -> (^T, bool) {
	el := element_get_or_curr(h, loc)
	if el.type == typeid_of(T) {
		return (^T)(el.data_ptr), true
	}
	return nil, false
}
element_state :: proc ($T: typeid, h: Element_Handle = {}, loc := #caller_location) -> ^T {
	s, ok := element_state_safe(T, h, loc)
	assert(ok, "Element doesn't match desired state type", loc)
	return s
}
element_parent_state :: proc ($T: typeid, h: Element_Handle = {}, loc := #caller_location) -> ^T {
	el := element_get_or_curr(h, loc)
	return element_state(T, element_parent(el, loc), loc)
}
element_lookup_state_safe :: proc ($T: typeid, h: Element_Handle = {}, loc := #caller_location) -> (^T, bool) {
	h := ctx.element_curr if h == {} else h
	for el in element_get(h) {
		defer h = el.parent
		s := element_state_safe(T, el, loc) or_continue
		return s, true
	}
	return nil, false
}
element_lookup_state :: proc ($T: typeid, h: Element_Handle = {}, loc := #caller_location) -> ^T {
	s, ok := element_lookup_state_safe(T, h, loc)
	assert(ok, "No element matching desired state type up the tree", loc)
	return s
}

@(require_results)
element_parent :: proc (h: Element_Handle = {}, loc := #caller_location) -> ^Element {
	return element_get_assert(element_get_or_curr(h, loc).parent, loc)
}

@require_results
each_element_child :: proc (el: ^Element, prev: ^Element_Handle) -> (next: ^Element, ok: bool) {

	if prev == nil do return

	next_id := el.child_first
	if prev_el, has_prev := element_get(prev^); has_prev {
		next_id = prev_el.next
	}

	prev^ = next_id
	return element_get(next_id)
}
@require_results
element_has_children :: proc (el: ^Element) -> bool {
	_ = each_element_child(el, &({})) or_return
	return true
}

@require_results
each_element_layout_child :: proc (el: ^Element, prev: ^Element_Handle) -> (next: ^Element, ok: bool) {

	next, ok = each_element_child(el, prev)

	// Skip elements that shouldn't be touched by layout
	if ok && .Position_Absolute in next.flags {
		next, ok = each_element_layout_child(el, prev)
	}

	return
}
@require_results
element_has_layout_children :: proc (el: ^Element) -> bool {
	_ = each_element_layout_child(el, &({})) or_return
	return true
}

@(require_results)
_find_child_by_typeid :: proc (type: typeid, el: ^Element) -> (^Element, bool) {
	child_id := el.child_first
	for child in element_get(child_id) {
		defer child_id = child.next
		if child.type == type do return child, true
	}
	return {}, false
}
@(require_results)
element_find_child :: proc ($T: typeid, h: Element_Handle = {}, loc := #caller_location) -> (child: ^Element, state: ^T, ok: bool) {
	el := element_get_or_curr(h, loc)
	child = _find_child_by_typeid(T, el) or_return
	state = cast(^T)child.data_ptr
	ok    = true
	return
}
element_find_child_assert :: proc ($T: typeid, h: Element_Handle = {}, loc := #caller_location) -> (child: ^Element, state: ^T) {
	ok: bool
	child, state, ok = element_find_child(T)
	when !ODIN_DISABLE_ASSERT do if !ok {
		fmt.panicf("%s requires a direct child of %w but not found",
		           element_display(h, context.temp_allocator, loc), typeid_of(T), loc=loc)
	}
	return
}


_placement_calc_ref_size :: proc {_placement_calc_ref_size_axis, _placement_calc_ref_size_vec}
_placement_calc_ref_size_vec :: proc (place: Placement, parent, content: Vec2i) -> Vec2i #no_bounds_check {
	return {_placement_calc_ref_size_axis(place, .X, parent.x, content.x),
	        _placement_calc_ref_size_axis(place, .Y, parent.y, content.y)}
}
_placement_calc_ref_size_axis :: proc (place: Placement, axis: Axis, parent, content: int) -> int #no_bounds_check {

	size, minimum, maximum: int

	switch v in place.size[axis] {
	case f32:     size = int(f32(parent) * v)
	case int:     size = v
	case nil:     size = content
	case Content: size = content
	case Fill:    size = parent
	}

	switch v in place.min[axis] {
	case f32:     minimum = int(f32(parent) * v)
	case int:     minimum = v
	case nil:     minimum = size
	case Content: minimum = content
	case Fill:    minimum = parent
	}

	switch v in place.max[axis] {
	case f32:     maximum = int(f32(parent) * v)
	case int:     maximum = v
	case nil:     maximum = size
	case Content: maximum = content
	case Fill:    maximum = parent
	}

	return clamp(size, minimum, maximum)
}

_placement_ref_to_box_size :: proc {_placement_ref_to_box_size_axis, _placement_ref_to_box_size_vec}
_placement_ref_to_box_size_vec :: proc (place: Placement, size: Vec2i) -> Vec2i #no_bounds_check {
	return {_placement_ref_to_box_size_axis(place, .X, size.x),
	        _placement_ref_to_box_size_axis(place, .Y, size.y)}
}
_placement_ref_to_box_size_axis :: proc (place: Placement, axis: Axis, size: int) -> int #no_bounds_check {
	return size - lt(place.margin)[axis] - rb(place.margin)[axis]
}

_placement_calc_rel_pos :: proc (place: Placement, parent, size: Vec2i) -> Vec2i #no_bounds_check {
	return -size_vec_to_pixel(place.origin, size) +
	       size_vec_to_pixel(place.pos, parent) +
	       lt(place.margin)
}

element_set_pos :: proc {element_set_pos_vec, element_set_pos_axis}
element_set_pos_vec :: proc (h: Element_Handle, v: Vec2i, loc := #caller_location) {
	el := element_get_assert(h, loc)
	el.pos_ref = v
	el.pos_set = true
}
element_set_pos_axis :: proc (h: Element_Handle, axis: Axis, v: int, loc := #caller_location) {
	el := element_get_assert(h, loc)
	el.pos_ref[axis] = v
	el.pos_set[axis] = true
}
element_set_left :: proc (h: Element_Handle, v: int, loc := #caller_location) {
	el := element_get_assert(h, loc)
	el.pos_ref.x = v
	el.pos_set.x = true
}
element_set_top :: proc (h: Element_Handle, v: int, loc := #caller_location) {
	el := element_get_assert(h, loc)
	el.pos_ref.y = v
	el.pos_set.y = true
}

element_pos :: proc {element_pos_vec, element_pos_axis}
@(require_results)
element_pos_vec :: proc (h: Element_Handle = {}, loc := #caller_location) -> Vec2i {
	return {element_pos(h, Axis.X, loc), element_pos(h, Axis.Y, loc)}
}
@(require_results)
element_pos_axis :: proc (h: Element_Handle = {}, axis: Axis, loc := #caller_location) -> int {
	el := element_get_or_curr(h, loc)
	return el.pos_ref[axis] if el.pos_set[axis] else el.last_frame.pos_ref[axis]
}

element_screen_pos :: proc {element_screen_pos_vec, element_screen_pos_axis}
@(require_results)
element_screen_pos_vec :: proc (h: Element_Handle = {}, loc := #caller_location) -> Vec2i {
	el := element_get_or_curr(h, loc)
	return el.pos_screen.? or_else el.last_frame.pos_screen.?
}
@(require_results)
element_screen_pos_axis :: proc (h: Element_Handle = {}, axis: Axis, loc := #caller_location) -> int #no_bounds_check {
	return element_screen_pos(h, loc)[axis]
}

@(require_results)
element_screen_rect :: proc (h: Element_Handle = {}, loc := #caller_location) -> Rect {
	return {element_screen_pos(h, loc), element_box_size(h, loc)}
}

// element_box_size returns the element's box size (excluding margin). This is what gets drawn.
element_box_size :: proc {element_box_size_vec, element_box_size_axis}
@(require_results)
element_box_size_vec :: proc (h: Element_Handle = {}, loc := #caller_location) -> Vec2i {
	return {element_box_size(h, Axis.X, loc), element_box_size(h, Axis.Y, loc)}
}
@(require_results)
element_box_size_axis :: proc (h: Element_Handle = {}, axis: Axis, loc := #caller_location) -> int #no_bounds_check {
	axis_bounds_check(axis, loc)
	el := element_get_or_curr(h, loc)
	if el.size_set[axis] {
		return _placement_ref_to_box_size(el, axis, el.size_ref[axis])
	} else {
		return _placement_ref_to_box_size(el.last_frame, axis, el.last_frame.size_ref[axis])
	}
}

// element_bounds returns the element's outer bounds (including margin). This is the space the
// element occupies in its parent. Equivalent to element_size.
element_bounds :: proc {element_bounds_vec, element_bounds_axis}
@(require_results)
element_bounds_vec :: proc (h: Element_Handle = {}, loc := #caller_location) -> Vec2i {
	return {element_bounds(h, Axis.X, loc), element_bounds(h, Axis.Y, loc)}
}
@(require_results)
element_bounds_axis :: proc (h: Element_Handle = {}, axis: Axis, loc := #caller_location) -> int #no_bounds_check {
	axis_bounds_check(axis, loc)
	el := element_get_or_curr(h, loc)
	return el.size_ref[axis] if el.size_set[axis] else el.last_frame.size_ref[axis]
}

// element_inner_bounds returns the size of the reference plane (inner area) available to children.
// This is the outer bounds minus margin and padding.
element_inner_bounds :: proc {element_inner_bounds_vec, element_inner_bounds_axis}
@(require_results)
element_inner_bounds_vec :: proc (h: Element_Handle = {}, loc := #caller_location) -> Vec2i {
	return {element_inner_bounds(h, Axis.X, loc), element_inner_bounds(h, Axis.Y, loc)}
}
@(require_results)
element_inner_bounds_axis :: proc (h: Element_Handle = {}, axis: Axis, loc := #caller_location) -> int #no_bounds_check {
	axis_bounds_check(axis, loc)
	el := element_get_or_curr(h, loc)
	if el.size_set[axis] {
		return _placement_ref_to_box_size(el, axis, el.size_ref[axis]) -
		       lt(el.padding)[axis] -
		       rb(el.padding)[axis]
	} else {
		return _placement_ref_to_box_size(el.last_frame, axis, el.last_frame.size_ref[axis]) -
		       lt(el.last_frame.padding)[axis] -
		       rb(el.last_frame.padding)[axis]
	}
}

element_set_bounds :: proc {element_set_bounds_vec, element_set_bounds_axis}
element_set_bounds_vec :: proc (h: Element_Handle, v: Vec2i, loc := #caller_location) {
	el := element_get_assert(h, loc)
	_element_set_ref_size(el, .X, v.x)
	_element_set_ref_size(el, .Y, v.y)
}
element_set_bounds_axis :: proc (h: Element_Handle, axis: Axis, v: int, loc := #caller_location) {
	axis_bounds_check(axis, loc)
	el := element_get_assert(h, loc)
	_element_set_ref_size(el, axis, v)
}
element_set_width :: proc (h: Element_Handle, v: int, loc := #caller_location) {
	el := element_get_assert(h, loc)
	_element_set_ref_size(el, .X, v)
}
element_set_height :: proc (h: Element_Handle, v: int, loc := #caller_location) {
	el := element_get_assert(h, loc)
	_element_set_ref_size(el, .Y, v)
}

// element_set_inner_bounds sets the element's inner bounds (area for children). The outer bounds
// are auto-computed as inner + margin + padding.
element_set_inner_bounds :: proc {element_set_inner_bounds_vec, element_set_inner_bounds_axis}
element_set_inner_bounds_vec :: proc (h: Element_Handle, v: Vec2i, loc := #caller_location) {
	element_set_inner_bounds_axis(h, .X, v.x, loc)
	element_set_inner_bounds_axis(h, .Y, v.y, loc)
}
element_set_inner_bounds_axis :: proc (h: Element_Handle, axis: Axis, v: int, loc := #caller_location) #no_bounds_check {
	axis_bounds_check(axis, loc)
	el := element_get_assert(h, loc)
	_element_set_ref_size(el, axis, v +
	                                lt(el.margin)[axis] +
	                                rb(el.margin)[axis] +
	                                lt(el.padding)[axis] +
	                                rb(el.padding)[axis])
}

// element_expand_inner_bounds expands the element's inner bounds to at least the given value.
element_expand_inner_bounds :: proc {element_expand_inner_bounds_vec, element_expand_inner_bounds_axis}
element_expand_inner_bounds_vec :: proc (h: Element_Handle, v: Vec2i, loc := #caller_location) {
	element_expand_inner_bounds_axis(h, .X, v.x, loc)
	element_expand_inner_bounds_axis(h, .Y, v.y, loc)
}
element_expand_inner_bounds_axis :: proc (h: Element_Handle, axis: Axis, v: int, loc := #caller_location) {
	axis_bounds_check(axis, loc)
	el := element_get_assert(h, loc)
	_element_set_ref_size(el, axis, max(el.size_ref[axis], v +
	                                    lt(el.margin)[axis] +
	                                    rb(el.margin)[axis] +
	                                    lt(el.padding)[axis] +
	                                    rb(el.padding)[axis]))
}


// Returns `true` on the same frame as the element was first created
@(require_results)
is_init :: proc (h: Element_Handle = {}, loc := #caller_location) -> bool {
	el := element_get_or_curr(h, loc)
	return el.last_frame._found == false
}

@(require_results)
is_hovered :: proc (h: Element_Handle = {}) -> bool {
	return element_get_or_curr(h).handle == ctx.element_hover
}
@(require_results)
is_mouse_in :: proc (h: Element_Handle = {}) -> bool {
	return element_get_or_curr(h).last_frame.mouse_in
}
@(require_results)
is_clicked :: proc (h: Element_Handle = {}) -> bool {
	return is_hovered(h) && ctx.mouse_pressed
}
@(require_results)
is_pressed :: proc (h: Element_Handle = {}) -> bool {
	return is_hovered(h) && ctx.mouse_pressed
}
@(require_results)
is_click_in :: proc (h: Element_Handle = {}) -> bool {
	return is_mouse_in(h) && ctx.mouse_pressed
}
@(require_results)
is_press_in :: proc (h: Element_Handle = {}) -> bool {
	return is_mouse_in(h) && ctx.mouse_pressed
}
@(require_results)
is_released :: proc () -> bool {
	return ctx.mouse_released
}
@(require_results)
is_wheel_in :: proc (h: Element_Handle = {}) -> bool {
	return element_get_or_curr(h).handle == ctx.element_wheel
}

@(require_results)
wheel_delta :: proc (h: Element_Handle = {}) -> Vec2f {
	return ctx.wheel_delta if is_wheel_in(h) else {}
}
@(require_results)
wheel_delta_axis :: proc (axis: Axis, h: Element_Handle = {}) -> f32 {
	return wheel_delta(h)[axis]
}
@(require_results)
wheel_delta_x :: proc (h: Element_Handle = {}) -> f32 {
	return wheel_delta(h).x
}
@(require_results)
wheel_delta_y :: proc (h: Element_Handle = {}) -> f32 {
	return wheel_delta(h).y
}


flag :: proc (f: Element_Flag, h: Element_Handle = {}, loc := #caller_location) {
	el := element_get_or_curr(h, loc)
	el.flags += {f}
}
flags :: proc (f: Element_Flags, h: Element_Handle = {}, loc := #caller_location) {
	el := element_get_or_curr(h, loc)
	el.flags += f
}
captures_wheel    :: proc (h: Element_Handle = {}, loc := #caller_location) {flag(.Capture_Wheel,     h, loc)}
non_interactable  :: proc (h: Element_Handle = {}, loc := #caller_location) {flag(.Non_Interactable,  h, loc)}
position_absolute :: proc (h: Element_Handle = {}, loc := #caller_location) {flag(.Position_Absolute, h, loc)}


transparency :: proc (alpha: f32 = 0, h: Element_Handle = {}, loc := #caller_location) {
	assert(0 <= alpha && alpha <= 1, loc=loc)
	element_get_or_curr(h, loc).transparency = alpha
}
opacity :: proc (alpha: f32 = 1, h: Element_Handle = {}, loc := #caller_location) {
	transparency(1-alpha, h, loc)
}


size_set          :: proc (v: Sizing_2D,          h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).size = v}
size_px           :: proc (v: Vec2i,              h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).size = {v.x, v.y}}
size_percent      :: proc (v: Vec2f,              h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).size = {v.x, v.y}}
size_fill         :: proc (                       h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).size = FILL}
size_hv           :: proc (x, y: Sizing,          h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).size = {x, y}}
size_w            :: proc (x: Sizing,             h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).size.x = x}
size_w_px         :: proc (x: int,                h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).size.x = x}
size_w_percent    :: proc (x: f32,                h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).size.x = x}
size_w_fill       :: proc (                       h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).size.x = FILL}
size_h            :: proc (y: Sizing,             h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).size.y = y}
size_h_px         :: proc (y: int,                h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).size.y = y}
size_h_percent    :: proc (y: f32,                h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).size.y = y}
size_h_fill       :: proc (                       h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).size.y = FILL}
size_axis         :: proc (axis: Axis, v: Sizing, h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).size[axis] = v}
size_axis_px      :: proc (axis: Axis, v: int,    h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).size[axis] = v}
size_axis_percent :: proc (axis: Axis, v: f32,    h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).size[axis] = v}
size_axis_fill    :: proc (axis: Axis,            h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).size[axis] = FILL}
size              :: proc {size_set, size_hv, size_axis}
size_x,         size_y          :: size_w,         size_h
size_x_px,      size_y_px       :: size_w_px,      size_h_px
size_x_percent, size_y_percent  :: size_w_percent, size_h_percent
size_x_fill,    size_y_fill     :: size_w_fill,    size_h_fill
width,          height          :: size_w,         size_h
width_px,       height_px       :: size_w_px,      size_h_px
width_percent,  height_percent  :: size_w_percent, size_h_percent
width_fill,     height_fill     :: size_w_fill,    size_h_fill
w,              h               :: size_w,         size_h
w_fill,         h_fill          :: size_w_fill,    size_h_fill

min_size_set          :: proc (v: Sizing_2D,          h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).min = v}
min_size_px           :: proc (v: Vec2i,              h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).min = {v.x, v.y}}
min_size_percent      :: proc (v: Vec2f,              h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).min = {v.x, v.y}}
min_size_hv           :: proc (x, y: Sizing,          h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).min = {x, y}}
min_size_w            :: proc (x: Sizing,             h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).min.x = x}
min_size_w_px         :: proc (x: int,                h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).min.x = x}
min_size_w_percent    :: proc (x: f32,                h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).min.x = x}
min_size_h            :: proc (y: Sizing,             h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).min.y = y}
min_size_h_px         :: proc (y: int,                h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).min.y = y}
min_size_h_percent    :: proc (y: f32,                h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).min.y = y}
min_size_axis         :: proc (axis: Axis, v: Sizing, h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).min[axis] = v}
min_size_axis_px      :: proc (axis: Axis, v: int,    h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).min[axis] = v}
min_size_axis_percent :: proc (axis: Axis, v: f32,    h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).min[axis] = v}
min_size              :: proc {min_size_set, min_size_hv}
min_size_x,         min_size_y          :: min_size_w,         min_size_h
min_size_x_px,      min_size_y_px       :: min_size_w_px,      min_size_h_px
min_size_x_percent, min_size_y_percent  :: min_size_w_percent, min_size_h_percent
min_width,          min_height          :: min_size_w,         min_size_h
min_width_px,       min_height_px       :: min_size_w_px,      min_size_h_px
min_width_percent,  min_height_percent  :: min_size_w_percent, min_size_h_percent
min_w,              min_h               :: min_size_w,         min_size_h

max_size_set          :: proc (v: Sizing_2D,          h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).max = v}
max_size_px           :: proc (v: Vec2i,              h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).max = {v.x, v.y}}
max_size_percent      :: proc (v: Vec2f,              h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).max = {v.x, v.y}}
max_size_fill         :: proc (                       h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).max = FILL}
max_size_hv           :: proc (x, y: Sizing,          h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).max = {x, y}}
max_size_w            :: proc (x: Sizing,             h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).max.x = x}
max_size_w_px         :: proc (x: int,                h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).max.x = x}
max_size_w_percent    :: proc (x: f32,                h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).max.x = x}
max_size_w_fill       :: proc (                       h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).max.x = FILL}
max_size_h            :: proc (y: Sizing,             h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).max.y = y}
max_size_h_px         :: proc (y: int,                h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).max.y = y}
max_size_h_percent    :: proc (y: f32,                h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).max.y = y}
max_size_h_fill       :: proc (                       h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).max.y = FILL}
max_size_axis         :: proc (axis: Axis, v: Sizing, h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).max[axis] = v}
max_size_axis_px      :: proc (axis: Axis, v: int,    h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).max[axis] = v}
max_size_axis_percent :: proc (axis: Axis, v: f32,    h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).max[axis] = v}
max_size_axis_fill    :: proc (axis: Axis,            h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).max[axis] = FILL}
max_size              :: proc {max_size_set, max_size_hv}
max_size_x,         max_size_y          :: max_size_w,         max_size_h
max_size_x_px,      max_size_y_px       :: max_size_w_px,      max_size_h_px
max_size_x_percent, max_size_y_percent  :: max_size_w_percent, max_size_h_percent
max_size_x_fill,    max_size_y_fill     :: max_size_w_fill,    max_size_h_fill
max_width,          max_height          :: max_size_w,         max_size_h
max_width_px,       max_height_px       :: max_size_w_px,      max_size_h_px
max_width_percent,  max_height_percent  :: max_size_w_percent, max_size_h_percent
max_width_fill,     max_height_fill     :: max_size_w_fill,    max_size_h_fill
max_w,              max_h               :: max_size_w,         max_size_h
max_w_fill,         max_h_fill          :: max_size_w_fill,    max_size_h_fill

origin_set  :: proc (v: Sizing_2D,          h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).origin = v}
origin_axis :: proc (axis: Axis, v: Sizing, h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).origin[axis] = v}
origin_left :: proc (v: Sizing,             h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).origin.x = v}
origin_top  :: proc (v: Sizing,             h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).origin.y = v}
origin      :: proc {origin_set, origin_axis}

pos_set   :: proc (v: Sizing_2D,          h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).pos = v}
pos_axis  :: proc (axis: Axis, v: Sizing, h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).pos[axis] = v}
pos_left  :: proc (v: Sizing,             h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).pos.x = v}
pos_top   :: proc (v: Sizing,             h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).pos.y = v}
pos       :: proc {pos_set, pos_axis}
left, top :: pos_left, pos_top
l,    t   :: pos_left, pos_top

center_both :: proc (h: Element_Handle = {}, loc := #caller_location) {
	origin(Sizing_2D{0.5, 0.5}, h, loc)
	pos(Sizing_2D{0.5, 0.5}, h, loc)
}
center_axis :: proc (axis: Axis, h: Element_Handle = {}, loc := #caller_location) {
	origin(axis, 0.5, h, loc)
	pos(axis, 0.5, h, loc)
}
center_x :: proc (h: Element_Handle = {}, loc := #caller_location) {
	origin_left(0.5, h, loc)
	pos_left(0.5, h, loc)
}
center_y :: proc (h: Element_Handle = {}, loc := #caller_location) {
	origin_top(0.5, h, loc)
	pos_top(0.5, h, loc)
}
center_h :: center_x
center_v :: center_y
center   :: proc {center_both, center_axis}

margin_set         :: proc (v: Insets,          h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).margin = v}
margin_directions  :: proc (l, t, r, b: int,    h: Element_Handle = {}, loc := #caller_location) {margin(Insets{l, t, r, b}, h, loc)}
margin_xy          :: proc (x, y: int,          h: Element_Handle = {}, loc := #caller_location) {margin(x, y, x, y, h, loc)}
margin_axis        :: proc (axis: Axis, v: int, h: Element_Handle = {}, loc := #caller_location) {if axis == .V {margin_v(v)} else {margin_h(v)}}
margin_vec         :: proc (v: Vec2i,           h: Element_Handle = {}, loc := #caller_location) {margin(v.x, v.y, v.x, v.y, h, loc)}
margin_all         :: proc (v: int,             h: Element_Handle = {}, loc := #caller_location) {margin(v, v, v, v, h, loc)}
margin_t           :: proc (v: int,             h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).margin.t = v}
margin_b           :: proc (v: int,             h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).margin.b = v}
margin_l           :: proc (v: int,             h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).margin.l = v}
margin_r           :: proc (v: int,             h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).margin.r = v}
margin_h           :: proc (x: int,             h: Element_Handle = {}, loc := #caller_location) {margin_l(x, h, loc); margin_r(x, h, loc)}
margin_v           :: proc (y: int,             h: Element_Handle = {}, loc := #caller_location) {margin_t(y, h, loc); margin_b(y, h, loc)}
margin             :: proc {margin_set, margin_directions, margin_xy, margin_axis, margin_vec, margin_all}
margin_dirs        :: margin_directions
margin_x, margin_y :: margin_h, margin_v
margin_left, margin_top, margin_right, margin_bot :: margin_l, margin_t, margin_r, margin_b
margin_bottom      :: margin_bot
ml, mt, mr, mb     :: margin_l, margin_t, margin_r, margin_b
m                  :: margin

padding_set          :: proc (v: Insets,          h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).padding = v}
padding_directions   :: proc (l, t, r, b: int,    h: Element_Handle = {}, loc := #caller_location) {padding(Insets{l, t, r, b}, h, loc)}
padding_xy           :: proc (x, y: int,          h: Element_Handle = {}, loc := #caller_location) {padding(x, y, x, y, h, loc)}
padding_axis         :: proc (axis: Axis, v: int, h: Element_Handle = {}, loc := #caller_location) {if axis == .V {padding_v(v)} else {padding_h(v)}}
padding_vec          :: proc (v: Vec2i,           h: Element_Handle = {}, loc := #caller_location) {padding(v.x, v.y, v.x, v.y, h, loc)}
padding_all          :: proc (v: int,             h: Element_Handle = {}, loc := #caller_location) {padding(v, v, v, v, h, loc)}
padding_t            :: proc (v: int,             h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).padding.t = v}
padding_b            :: proc (v: int,             h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).padding.b = v}
padding_l            :: proc (v: int,             h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).padding.l = v}
padding_r            :: proc (v: int,             h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).padding.r = v}
padding_h            :: proc (x: int,             h: Element_Handle = {}, loc := #caller_location) {padding_l(x, h, loc); padding_r(x, h, loc)}
padding_v            :: proc (y: int,             h: Element_Handle = {}, loc := #caller_location) {padding_t(y, h, loc); padding_b(y, h, loc)}
padding              :: proc {padding_set, padding_directions, padding_xy, padding_axis, padding_vec, padding_all}
padding_dirs         :: padding_directions
padding_x, padding_y :: padding_h, padding_v
padding_left, padding_top, padding_right, padding_bot :: padding_l, padding_t, padding_r, padding_b
padding_bottom       :: padding_bot
pl, pt, pr, pb       :: padding_l, padding_t, padding_r, padding_b
p                    :: padding


layout_axis :: proc (axis: Axis, cb: proc (), deps: Axis_Set = {}, h: Element_Handle = {}, loc := #caller_location) {
	deps := deps if deps != {} else {axis}
	element_get_or_curr(h, loc).layout[axis] = {cb, deps}
}
layout :: proc {layout_axis}

effect  :: proc (cb: proc (), h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).effect  = cb}
subtree :: proc (cb: proc (), h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).subtree = cb}
cleanup :: proc (cb: proc (), h: Element_Handle = {}, loc := #caller_location) {element_get_or_curr(h, loc).cleanup = cb}
