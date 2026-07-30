package pxui

import "core:slice"
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

WHITE :: Color{255, 255, 255, 255}

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

	time:           int,
}

Context :: struct {
	allocator:         mem.Allocator,

	// TODO: implement own?  why a xar is  used—the point of handled  is not to use  pointers
	elements:          hm.Dynamic_Handle_Map(Element, Element_Handle),
	element_curr:      Element_Handle,
	element_root:      Element_Handle,

	draw_reqs_prev:    []Draw_Request, // Used for memoized elements; copied from draw_reqs at the start of a frame
	draw_reqs:         [dynamic]Draw_Request,

	animations:        hm.Dynamic_Handle_Map(Animation, Animation_Handle),

	using frame_input: Frame_Input,

	element_hover:     Element_Handle,
	element_wheel:     Element_Handle,
}
ctx: Context

Element_Flag  :: enum u8 {Non_Interactable, Capture_Wheel}
Element_Flags :: bit_set[Element_Flag]

Element_Frame_Data :: struct {
	_found:       bool,             // was the element present in this frame? TODO: could use frame count
	flags:        Element_Flags,

	margin:       Insets,
	padding:      Insets,
	using place:  Placement,

	layout:       [2]struct {cb: proc (), deps: Axis_Set},
	effect:       proc (),

	animations:   [Animation_Property]Animation_Handle,

	// 0 = fully opaque (default)
	// 1 = fully transparent
	//
	// The element's subtree is rendered to an offscreen surface and composited back with this alpha
	transparency: f32,

	draw_first:   Draw_Request_Handle,
	draw_last:    Draw_Request_Handle,
	draw_frame_end: Draw_Request_Handle, // Last draw request called before layout/effect callbacks

	ref_pos:      Vec2i,           // pos of the element's bounds (including margin) on the parent's ref plane (pixels, default 0,0)
	ref_size:     Vec2i,           // bounds of the element (outer size, including margin) — the "space" this element occupies in the parent (pixels)
	screen_pos:   Vec2i,           // pos of the element's box (excluding margin) on screen/world (calculated in frame_end after layout solve, available for draw commands)
	size_set:     [2]bool,

	mouse_in:     bool,
}

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

	memos:        [dynamic]Memo,
	memo_curr:    Maybe(^Memo),
	memo:         Maybe(^Memo),

	prev_frame:   Element_Frame_Data,
	using frame:  Element_Frame_Data,
}
Element_Handle :: struct {idx, gen: u32} // index to `ctx.elements`

Memo :: struct {
	id:       u64,
	data_id:  u64,
	_found:   bool, // TODO: could use frame count
	el_first: Element_Handle,
	el_last:  Element_Handle,
}

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
element_print :: proc (h: Element_Handle = {}, loc := #caller_location) {
	w := io.to_writer(os.to_writer(os.stdout))
	element_display_writer(w, h, loc=loc)
}

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

element_parent :: proc (h: Element_Handle = {}, loc := #caller_location) -> ^Element {
	return element_get_assert(element_get_or_curr(h, loc).parent, loc)
}

@private
_element_push :: proc (type: typeid, type_size, type_align: int, user_id: u64, loc := #caller_location) ->
                      (state: rawptr, init: bool)
{
	hash   := element_hash(type, user_id)
	parent := element_curr(loc)
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
			memos    = make([dynamic]Memo, allocator=ctx.allocator),
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

element_push :: #force_inline proc ($T: typeid, #any_int id: u64 = 0, loc := #caller_location) ->
                                   (state: ^T, init: bool) {
	ptr: rawptr
	ptr, init = _element_push(T, size_of(T), align_of(T), id, loc)
	return (^T)(ptr), init
}

element_pop :: proc () {

	// Mark end of draw requests called before callbacks (need to be copied for memoized elements)
	el := element_curr()
	el.draw_frame_end = el.draw_last

	// switch current element to parent
	parent := element_parent()
	ctx.element_curr = parent.handle
}

_element_destroy :: proc (el: ^Element) {

	if parent, has_parent := element_get(el.parent); has_parent && parent._found {
		// Unlink from siblings
		if prev, has_prev := element_get(el.prev); has_prev && prev.next == el.handle {
			prev.next = el.next
		}
		if next, has_next := element_get(el.next); has_next && next.prev == el.handle {
			next.prev = el.prev
		}
		// Unlink from parent
		if parent.child_first == el.handle {
			parent.child_first = el.next
		}
		if parent.child_last == el.handle {
			parent.child_last = el.prev
		}
	}

	// Free data
	delete(el.memos)
	free(el.data_ptr)

	// Remove pending animations
	for a in el.animations {
		// TODO: animations should also be removed when they end
		hm.remove(&ctx.animations, a)
	}

	// Free self
	hm.remove(&ctx.elements, el)
}

element_curr :: proc (loc := #caller_location) -> ^Element {
	return element_get_assert(ctx.element_curr, loc)
}
element_root :: proc (loc := #caller_location) -> ^Element {
	return element_get_assert(ctx.element_root, loc)
}


memo_begin :: proc (#any_int data_id: u64, #any_int memo_id: u64 = 0, loc := #caller_location) -> (changed: bool) {

	el := element_curr(loc)
	assert(el.memo_curr == nil, loc=loc)

	memo: ^Memo
	memo_search: {
		for &m in el.memos do if !m._found && m.id == memo_id {
			memo = &m

			changed = memo.data_id != data_id

			if changed {
				// Data changes invalidates stored elements
				// and they need to be collected again
				memo.el_first = {}
				memo.el_last  = {}
			} else {
				// Add memoized children elements to current element

				child_id := memo.el_first
				for child in element_get(child_id) {

					visit(child)
					visit :: proc (h: Element_Handle) -> bool {
						el := element_get(h) or_return

						el._found = true

						// Copy prev frame data TODO: separate prev_frame user data and calculated data
						el.flags        = el.prev_frame.flags
						el.margin       = el.prev_frame.margin
						el.padding      = el.prev_frame.padding
						el.place        = el.prev_frame.place
						el.layout       = el.prev_frame.layout
						el.effect       = el.prev_frame.effect
						el.animations   = el.prev_frame.animations
						el.transparency = el.prev_frame.transparency

						// Copy draw requests from previous frame
						// Ignoring the ones from layout/effect callbacks
						if el.prev_frame.draw_frame_end != {} {
							draw_id := el.prev_frame.draw_first
							for d in draw_get_prev(draw_id) {
								draw(d^, el)
								if draw_id == el.prev_frame.draw_frame_end do break
								draw_id = d.next
							}
							el.draw_frame_end = el.draw_last
						}

						// Update animations
						for a, prop in el.animations {
							animation_update(a, el, prop)
						}

						child_id := el.child_first
						for child in element_get(child_id) {
							visit(child)
							child_id = child.next
						}

						return true
					}

					if child_id == memo.el_last do break
					child_id = child.next
				}
			}

			break memo_search
		}

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


frame_begin :: proc () {
	assert(ctx.element_curr == ctx.element_root)

	it := hm.iterator_make(&ctx.elements)
	for el, _ in hm.iterate(&it) {
		el.prev_frame = el.frame
		el.frame = {}
	}

	// TODO: instead of copying could use two dynamic arrays and frame count % 2
	ctx.draw_reqs_prev = slice.clone(ctx.draw_reqs[:], context.temp_allocator)
	clear(&ctx.draw_reqs)
}

frame_end :: proc () {
	assert(ctx.element_curr == ctx.element_root)

	it := hm.iterator_make(&ctx.elements)

	for el, handle in hm.iterate(&it) {
		if el._found || handle == ctx.element_root do continue
		_element_destroy(el)
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
	root.ref_size = size_vec_to_pixel(root.size, 0)
	root.size_set = true

	it := hm.iterator_make(&ctx.elements)

	Key :: struct {el: ^Element, axis: Axis}
	sorter: topological_sort.Sorter(Key)

	for el, _ in hm.iterate(&it) {
		#unroll for axis in Axis {
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
				element_set_bounds(el, axis, size_to_pixel(v, element_inner_bounds(el.parent, axis)))
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
				element_set_bounds(el, axis, v + lt(el.margin)[axis] + rb(el.margin)[axis])
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
		                lt(el.margin) +
		                -size_vec_to_pixel(el.origin, element_box_size(el)) +
	 	                size_vec_to_pixel(el.pos, element_inner_bounds(parent))

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
	return element_get_or_curr(h).prev_frame.mouse_in
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

transparency :: proc (alpha: f32 = 0, h: Element_Handle = {}, loc := #caller_location) {
	assert(0 <= alpha && alpha <= 1, loc=loc)
	element_get_or_curr(h, loc).transparency = alpha
}
opacity :: proc (alpha: f32 = 1, h: Element_Handle = {}, loc := #caller_location) {
	transparency(1-alpha, h, loc)
}

size_set          :: proc (v: Sizing_2D)          {element_curr().size = v}
size_px           :: proc (v: Vec2i)              {element_curr().size = {v.x, v.y}}
size_percent      :: proc (v: Vec2f)              {element_curr().size = {v.x, v.y}}
size_fill         :: proc ()                      {element_curr().size = FILL}
size_hv           :: proc (h, v: Sizing)          {element_curr().size = {h, v}}
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
size              :: proc {size_set, size_hv}
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

origin_set  :: proc (v: Sizing_2D,          h: Element_Handle = {}) {element_get_or_curr(h).origin = v}
origin_axis :: proc (axis: Axis, v: Sizing, h: Element_Handle = {}) {element_get_or_curr(h).origin[axis] = v}
origin_left :: proc (v: Sizing,             h: Element_Handle = {}) {element_get_or_curr(h).origin.x = v}
origin_top  :: proc (v: Sizing,             h: Element_Handle = {}) {element_get_or_curr(h).origin.y = v}
origin      :: proc {origin_set, origin_axis}

pos_set  :: proc (v: Sizing_2D,          h: Element_Handle = {}) {element_get_or_curr(h).pos = v}
pos_axis :: proc (axis: Axis, v: Sizing, h: Element_Handle = {}) {element_get_or_curr(h).pos[axis] = v}
pos_left :: proc (v: Sizing,             h: Element_Handle = {}) {element_get_or_curr(h).pos.x = v}
pos_top  :: proc (v: Sizing,             h: Element_Handle = {}) {element_get_or_curr(h).pos.y = v}
left     :: pos_left
top      :: pos_top
pos      :: proc {pos_set, pos_axis}

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

element_pos :: proc {element_pos_vec, element_pos_axis}
element_pos_vec :: proc (h: Element_Handle = {}, loc := #caller_location) -> Vec2i {
	el := element_get_or_curr(h, loc)
	return el.ref_pos if el._found else el.prev_frame.ref_pos
}
element_pos_axis :: proc (h: Element_Handle = {}, axis: Axis, loc := #caller_location) -> int {
	return element_pos(h, loc)[axis]
}

element_screen_pos :: proc {element_screen_pos_vec, element_screen_pos_axis}
element_screen_pos_vec :: proc (h: Element_Handle = {}, loc := #caller_location) -> Vec2i {
	el := element_get_or_curr(h, loc)
	return el.screen_pos if el._found else el.prev_frame.screen_pos
}
element_screen_pos_axis :: proc (h: Element_Handle = {}, axis: Axis, loc := #caller_location) -> int {
	return element_screen_pos(h, loc)[axis]
}

element_screen_rect :: proc (h: Element_Handle = {}, loc := #caller_location) -> Rect {
	return {element_screen_pos(h, loc), element_box_size(h, loc)}
}

// element_box_size returns the element's box size (excluding margin). This is what gets drawn.
element_box_size :: proc {element_box_size_vec, element_box_size_axis}
element_box_size_vec :: proc (h: Element_Handle = {}, loc := #caller_location) -> Vec2i {
	return {element_box_size(h, Axis.X, loc), element_box_size(h, Axis.Y, loc)}
}
element_box_size_axis :: proc (h: Element_Handle = {}, axis: Axis, loc := #caller_location) -> int #no_bounds_check {
	axis_bounds_check(axis, loc)
	el := element_get_or_curr(h, loc)
	if el.size_set[axis] { // TODO: margins shouldn't be a part of ref_size
		return el.ref_size[axis] - lt(el.margin)[axis] - rb(el.margin)[axis]
	} else {
		return el.prev_frame.ref_size[axis] - lt(el.prev_frame.margin)[axis] - rb(el.prev_frame.margin)[axis]
	}
}

// element_bounds returns the element's outer bounds (including margin). This is the space the
// element occupies in its parent. Equivalent to element_size.
element_bounds :: proc {element_bounds_vec, element_bounds_axis}
element_bounds_vec :: proc (h: Element_Handle = {}, loc := #caller_location) -> Vec2i {
	el := element_get_or_curr(h, loc)
	return el.ref_size if el._found else el.prev_frame.ref_size
}
element_bounds_axis :: proc (h: Element_Handle = {}, axis: Axis, loc := #caller_location) -> int {
	return element_bounds(h, loc)[axis]
}

// element_inner_bounds returns the size of the reference plane (inner area) available to children.
// This is the outer bounds minus margin and padding.
element_inner_bounds :: proc {element_inner_bounds_vec, element_inner_bounds_axis}
element_inner_bounds_vec :: proc (h: Element_Handle = {}, loc := #caller_location) -> Vec2i {
	return {element_inner_bounds(h, Axis.X, loc), element_inner_bounds(h, Axis.Y, loc)}
}
element_inner_bounds_axis :: proc (h: Element_Handle = {}, axis: Axis, loc := #caller_location) -> int #no_bounds_check {
	axis_bounds_check(axis, loc)
	el := element_get_or_curr(h, loc)
	if el.size_set[axis] {
		return el.ref_size[axis] -
		       lt(el.margin)[axis] -
		       rb(el.margin)[axis] -
		       lt(el.padding)[axis] -
		       rb(el.padding)[axis]
	} else {
		return el.prev_frame.ref_size[axis] -
		       lt(el.prev_frame.margin)[axis] -
		       rb(el.prev_frame.margin)[axis] -
		       lt(el.prev_frame.padding)[axis] -
		       rb(el.prev_frame.padding)[axis]
	}
}

element_set_bounds :: proc {element_set_bounds_vec, element_set_bounds_axis}
element_set_bounds_vec :: proc (h: Element_Handle, v: Vec2i, loc := #caller_location) {
	el := element_get_assert(h, loc)
	el.ref_size = v
	el.size_set = true
}
element_set_bounds_axis :: proc (h: Element_Handle, axis: Axis, v: int, loc := #caller_location) {
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

// element_set_inner_bounds sets the element's inner bounds (area for children). The outer bounds
// are auto-computed as inner + margin + padding.
element_set_inner_bounds :: proc {element_set_inner_bounds_vec, element_set_inner_bounds_axis}
element_set_inner_bounds_vec :: proc (h: Element_Handle, v: Vec2i, loc := #caller_location) {
	element_set_inner_bounds_axis(h, .X, v.x, loc)
	element_set_inner_bounds_axis(h, .Y, v.y, loc)
}
element_set_inner_bounds_axis :: proc (h: Element_Handle, axis: Axis, v: int, loc := #caller_location) {
	el := element_get_assert(h, loc)
	// TODO: handle prev frame data
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
	// TODO: handle prev frame data
	el.ref_size[axis] = max(el.ref_size[axis],
	                        v +
	                        lt(el.margin)[axis] +
	                        rb(el.margin)[axis] +
	                        lt(el.padding)[axis] +
	                        rb(el.padding)[axis])
	el.size_set[axis] = true
}
