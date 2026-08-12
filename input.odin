// Basic input components. Each component is a single element that the user styles by
// placing child elements (panels, text, etc.) inside it.
//
// State handling follows two patterns:
//   1. User-managed: pass a pointer (e.g. ^bool) and the component writes directly to it.
//   2. Internal: don't pass a pointer; the component keeps its own state. Query it via
//      the *_value / *_is_checked / *_selected helper or via the typed element state.

package pxui

import "core:math"

// ─── Checkbox ────────────────────────────────────────────────────────────
// A toggleable boolean. State is either user-managed (pass ^bool) or internal.

Checkbox :: struct {
	ptr:     ^bool,
	checked: bool,
}

checkbox_begin :: proc (state: ^bool = nil, id: u64 = 0, loc := #caller_location) {
	s := element_push(Checkbox, id, loc)
	s.ptr = state if state != nil else &s.checked

	if is_click_in() {
		s.ptr^ = !s.ptr^
	}
}
checkbox_end :: proc (state: ^bool = nil, id: u64 = 0, loc := #caller_location) {
	assert(element_hash(typeid_of(Checkbox), id) == element_curr().hash, loc=loc)
	element_pop()
}
@(deferred_in=checkbox_end)
checkbox :: proc (state: ^bool = nil, id: u64 = 0, loc := #caller_location) -> bool {
	checkbox_begin(state, id, loc)
	return true
}

checkbox_is_checked :: proc (h: Element_Handle = {}, loc := #caller_location) -> bool {
	s := element_state(Checkbox, h, loc)
	return s.ptr^ if s.ptr != nil else s.checked
}

// ─── Radio Group ─────────────────────────────────────────────────────────
// A group of mutually exclusive options. Create the group, then add radio() children
// inside it. State is either user-managed (pass ^int) or internal.

Radio_Group :: struct {
	ptr:   ^int,
	index: int,
}

Radio :: struct {
	index: int,
}

radio_group_begin :: proc (value: ^int = nil, id: u64 = 0, loc := #caller_location) {
	s := element_push(Radio_Group, id, loc)
	s.ptr = value if value != nil else &s.index
}
radio_group_end :: proc (state: ^int = nil, id: u64 = 0, loc := #caller_location) {
	assert(element_hash(typeid_of(Radio_Group), id) == element_curr().hash, loc=loc)
	element_pop()
}
@(deferred_in=radio_group_end)
radio_group :: proc (state: ^int = nil, id: u64 = 0, loc := #caller_location) -> bool {
	radio_group_begin(state, id, loc)
	return true
}

radio_group_selected :: proc () -> int {
	s := element_state(Radio_Group)
	if s.ptr != nil do return s.ptr^
	return s.index
}

radio_begin :: proc (index: int, id: u64 = 0, loc := #caller_location) {
	element_push(Radio, id, loc)

	r := element_state(Radio, loc=loc)
	r.index = index

	rg := element_lookup_state(Radio_Group, loc=loc)

	if is_click_in() {
		rg.ptr^ = index
	}
}
radio_end :: proc (index: int, id: u64 = 0, loc := #caller_location) {
	assert(element_hash(typeid_of(Radio), id) == element_curr().hash, loc=loc)
	element_pop()
}
@(deferred_in=radio_end)
radio :: proc (index: int, id: u64 = 0, loc := #caller_location) -> bool {
	radio_begin(index, id, loc)
	return true
}

radio_is_selected :: proc (h: Element_Handle = {}, loc := #caller_location) -> bool {
	rg := element_lookup_state(Radio_Group, h, loc=loc)
	r  := element_state(Radio, h, loc=loc)
	return rg.ptr^ == r.index
}

// ─── Slider ──────────────────────────────────────────────────────────────
// A draggable value in [min, max]. Built from composable parts (like the scrollbar):
//   - slider()        — the container (required). Sets up layout + effect.
//   - slider_thumb()  — the draggable thumb (required, must be a child of the slider).
//   - slider_button() — optional +/- buttons (must be children of the slider).
//   - slider_bar()    — optional bars between thumb and buttons (must be children).
//
// The thumb's position and size along the axis are computed by the slider's layout_axis
// callback. The effect handles dragging—from the thumb or from anywhere on the track.

Slider :: struct {
	ptr:      ^f32,
	value:    f32,
	min, max: f32,
	axis:     Axis,
	dragging: bool,
	offset:   f32,
}

Slider_Thumb  :: struct {}
Slider_Button :: struct {dir: int} // -1 = decrement, +1 = increment
Slider_Bar    :: struct {}

// Compute thumb position and size on the slider's axis.
// ih is the total value range (max - min), oh is the available track length.
slider_get_thumb_pos_and_size :: proc (value, min, max: f32, track_len: int) -> (pos, size: int) {
	if max == min || track_len <= 0 {
		return 0, track_len
	}
	pos  = int(f32(track_len) * (value - min) / (max - min))
	size = track_len // thumb fills whole track; user can override with their own layout
	return
}

slider_begin :: proc (
	value: ^f32 = nil, min: f32 = 0, max: f32 = 1, axis: Axis = .X,
	#any_int id: u64 = 0, loc := #caller_location,
) {
	s := element_push(Slider, id, loc)
	s.min  = min
	s.max  = max
	s.axis = axis
	s.ptr  = value if value != nil else &s.value

	layout_axis(s.axis, proc () {

		slider  := element_curr()
		using s := element_state(Slider, loc=slider.loc)

		thumb, bar_left, bar_right: ^Element
		it: Element_Handle
		for child in each_element_child(slider, &it) {
			if _, is_thumb := element_state_safe(Slider_Thumb, child, loc=slider.loc); is_thumb {
				assert(thumb == nil, "Slider cannot have multiple Thumb children", loc=slider.loc)
				thumb = child
				continue
			}
			if _, is_bar := element_state_safe(Slider_Bar, child, loc=slider.loc); is_bar {
				if bar_left == nil {
					bar_left = child
				} else {
					assert(bar_right == nil, "Slider cannot have more than two bar children", loc=slider.loc)
					bar_right = child
				}
			}
		}

		assert(thumb != nil, "Slider requires one Thumb children", loc=slider.loc)

		thumb_w  := element_bounds(thumb, axis, loc=slider.loc)
		slider_w := element_inner_bounds(slider, axis, loc=slider.loc)
		thumb_p  := int(math.remap_clamped(s.ptr^, min, max, 0, f32(slider_w-thumb_w)))

		element_set_pos(thumb, axis, thumb_p, loc=slider.loc)

		if bar_left != nil {
			element_set_bounds(bar_left, axis, thumb_p, loc=slider.loc)
		}

		if bar_right != nil {
			element_set_pos(bar_right, axis, thumb_p + thumb_w, loc=slider.loc)
			element_set_bounds(bar_right, axis, slider_w - thumb_p - thumb_w, loc=slider.loc)
		}
	}, loc=loc)

	effect(proc () {
		slider   := element_curr()
		using s  := element_state(Slider, loc=slider.loc)
		thumb, _ := element_find_child_assert(Slider_Thumb, loc=slider.loc)
		thumb_w  := element_bounds(thumb, axis, loc=slider.loc)
		avail_w  := element_inner_bounds(slider, axis, loc=slider.loc)-thumb_w
		thumb_p  := int(math.remap_clamped(s.ptr^, min, max, 0, f32(avail_w)))
		sl_pos   := element_screen_pos(slider, axis, loc=slider.loc)
		mouse    := ctx.mouse[axis]

		// Start dragging if pressed on the thumb or anywhere on the track
		if is_press_in(thumb) {
			dragging = true
			offset   = f32(mouse - sl_pos - thumb_p) - f32(thumb_w)/2
		} else if is_press_in(slider) {
			dragging = true
			offset   = 0
		}

		if is_released() {
			dragging = false
			offset   = 0
		}

		if dragging {
			p := f32(mouse - sl_pos) - f32(thumb_w)/2 - offset
			ptr^ = math.remap_clamped(p, 0, f32(avail_w), min, max)
		}
	}, loc=loc)
}
slider_end :: proc (value: ^f32 = nil, min: f32 = 0, max: f32 = 1, axis: Axis = .X, #any_int id: u64 = 0, loc := #caller_location) {
	_ = value; _ = min; _ = max; _ = axis
	assert(element_hash(typeid_of(Slider), id) == element_curr().hash, loc=loc)
	element_pop()
}
@(deferred_in=slider_end)
slider :: proc (value: ^f32 = nil, min: f32 = 0, max: f32 = 1, axis: Axis = .X, #any_int id: u64 = 0, loc := #caller_location) -> bool {
	slider_begin(value, min, max, axis, id, loc)
	return true
}

slider_value :: proc () -> f32 {
	s := element_state(Slider)
	if s.ptr != nil do return s.ptr^
	return s.value
}

// Required: slider thumb (must be child of the slider).
slider_thumb_begin :: proc (loc := #caller_location) {
	element_push(Slider_Thumb, loc=loc)
	size_fill()
	position_absolute()
}
slider_thumb_end :: proc (loc := #caller_location) {
	assert(typeid_of(Slider_Thumb) == element_curr(loc).type, loc=loc)
	element_pop()
}
@(deferred_in=slider_thumb_end)
slider_thumb :: proc (loc := #caller_location) -> bool {
	slider_thumb_begin(loc)
	return true
}

// Optional: decrement/increment buttons (must be children of the slider).
slider_button_begin :: proc (dir: int, id: u64 = 0, loc := #caller_location) {
	s := element_push(Slider_Button, id, loc)
	s.dir = dir
}
slider_button_end :: proc (dir: int, id: u64 = 0, loc := #caller_location) {
	_ = dir
	assert(element_hash(typeid_of(Slider_Button), id) == element_curr().hash, loc=loc)
	element_pop()
}
@(deferred_in=slider_button_end)
slider_button :: proc (dir: int, id: u64 = 0, loc := #caller_location) -> bool {
	slider_button_begin(dir, id, loc)
	return true
}

slider_button_clicked :: proc () -> bool {
	if !is_clicked() do return false
	s  := element_state(Slider_Button)
	sl := element_state(Slider, element_parent().handle)
	step := (sl.max - sl.min) * 0.05
	// dir is relative to the slider's axis. -1 = decrement, +1 = increment.
	sl.ptr^ = clamp(sl.ptr^ + step * f32(s.dir), sl.min, sl.max)
	return true
}

// Optional: bar between thumb and buttons (must be children of the slider).
slider_bar_begin :: proc (loc := #caller_location) {
	element_push(Slider_Bar, loc=loc)
	size_fill()
	position_absolute()
}
slider_bar_end :: proc (loc := #caller_location) {
	assert(element_hash(typeid_of(Slider_Bar)) == element_curr(loc).hash, loc=loc)
	element_pop()
}
@(deferred_in=slider_bar_end)
slider_bar :: proc (loc := #caller_location) -> bool {
	slider_bar_begin(loc)
	return true
}
