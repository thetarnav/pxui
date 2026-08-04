package pxui

import "core:math"
import "core:math/ease"
import hm "core:container/handle_map"


Animation :: struct {
	using handle: Animation_Handle,
	start_time:   int,
	start_value:  Sizing,
	end_value:    Sizing,
}
Animation_Handle :: struct {idx, gen: u32}

Animation_Exit_Req :: struct {
	value:      Sizing,
	transition: Transition,
	sheduled:   bool,
}

Animation_Property :: enum {width, height, left, top, opacity}

Ease :: ease.Ease

Transition :: struct {
	time: int,
	ease: Ease,
}
DEFAULT_TRANSITION :: Transition{200, .Sine_In_Out}

_element_animate_props :: proc (el: ^Element, loc := #caller_location) {
	for prop in ([?]Animation_Property{.opacity}) {
		value: Sizing
		#partial switch prop {
		case .opacity: value = 1.0 - el.transparency
		               el.derived_transparency = el.transparency
		case: unreachable()
		}
		el.anims[prop], _ = animation_update(el.anims[prop], el, prop, value)
	}
}
_element_animate_layout :: proc (el: ^Element, loc := #caller_location) {

}
_element_animate_exit :: proc (el: ^Element) {
	for &ae, prop in el.anims_exit do if ae != {} {

		if ae.sheduled {
			if _, running := hm.get(&ctx.animations, el.anims[prop]); !running {
				ae = {} // End
			}
		} else {
			// Schedule
			animation_remove(el.anims[prop], el, prop)
			ae.sheduled = true

			// Apply exit prop values
			switch prop {
			case .width:   el.size.x = ae.value
			case .height:  el.size.y = ae.value
			case .left:    el.pos.x  = ae.value
			case .top:     el.pos.y  = ae.value
			case .opacity: el.transparency = 1.0 - ae.value.(f32)
			}
			el.transition[prop] = ae.transition
		}
	}
}
_element_has_exit_animations :: proc (el: ^Element) -> bool {
	for ae in el.last_frame.anims_exit {
		if ae != {} do return true
	}
	return false
}

_animate_size :: proc (el: ^Element, axis: Axis) #no_bounds_check {
	prop: Animation_Property = axis == .X ? .width : .height
	el.anims[prop], _ = animation_update(el.anims[prop], el, prop, el.size_ref[axis])
}
_animate_pos :: proc (el: ^Element) #no_bounds_check {
	#unroll for axis in AXIS {
		prop: Animation_Property = axis == .X ? .left : .top
		el.anims[prop], _ = animation_update(el.anims[prop], el, prop, el.pos_rel[axis])
	}
}

// Animations are updated by users calling animate() with same prop
// or automatically for memoized elements
animation_update :: proc (h: Animation_Handle, el: ^Element, prop: Animation_Property, value: Sizing) -> (next_h: Animation_Handle, running: bool) {

	h := h

	transition := el.transition[prop]

	if (h == {} && transition.time == 0) || is_init(el) {
		return {}, false
	}

	start_value: Sizing
	start_time:  int
	a, has_anim := hm.get(&ctx.animations, h)
	if has_anim && a.end_value == value {
		start_value = a.start_value
		start_time  = a.start_time
	} else {
		start_value = animation_value_get_prev(el, prop)
		start_time  = ctx.time
	}

	if start_value == value {
		animation_remove(h, el, prop)
		return {}, false
	}

	if ctx.time >= transition.time + start_time {
		animation_property_set(el, prop, start_value, value, 1.0)
		animation_remove(h, el, prop)
		return {}, false
	}

	if !has_anim {
		h = hm.add(&ctx.animations, Animation{})
		a = hm.get(&ctx.animations, h) or_return
	}

	a.start_value = start_value
	a.start_time  = start_time
	a.end_value   = value

	t := f32(ctx.time - start_time) / f32(transition.time)
	t = ease.ease(transition.ease, t)
	animation_property_set(el, prop, start_value, value, t)

	return h, true
}

animation_remove :: proc (h: Animation_Handle, el: ^Element, prop: Animation_Property, loc := #caller_location) {
	hm.remove(&ctx.animations, h)
}

animation_property_set :: proc (el: ^Element, prop: Animation_Property, start, value: Sizing, t: f32) {
	switch prop {
	case .width, .height, .left, .top:

		s := start.(int)
		e := value.(int)
		v := int(math.lerp(f32(s), f32(e), t))

		#partial switch prop {
		case .left:   el.pos_rel.x  = v
		case .top:    el.pos_rel.y  = v
		case .width:  el.size_ref.x = v
		case .height: el.size_ref.y = v
		}

	case .opacity:
		s := start.(f32)
		e := value.(f32)
		el.derived_transparency = 1.0 - math.lerp(s, e, t)
	}
}

animation_value_get_prev :: proc (el: ^Element, prop: Animation_Property) -> Sizing {
	switch prop {
	case .width:   return el.last_frame.size_ref.x
	case .height:  return el.last_frame.size_ref.y
	case .left:    return el.last_frame.pos_rel.x
	case .top:     return el.last_frame.pos_rel.y
	case .opacity: return 1.0 - el.last_frame.derived_transparency
	}
	unreachable()
}

animate_exit :: proc (prop: Animation_Property, value: Sizing, h: Element_Handle = {}, loc := #caller_location) {
	el := element_get_or_curr(h, loc)
	el.anims_exit[prop] = Animation_Exit_Req{value, {200, .Linear}, false}
}

transition_set :: proc (prop: Animation_Property, transition: Transition = DEFAULT_TRANSITION, h: Element_Handle = {}, loc := #caller_location) {
	el := element_get_or_curr(h, loc)
	el.transition[prop] = transition
}
transition :: proc (prop: Animation_Property,
                    time: int = DEFAULT_TRANSITION.time,
                    ease: Ease = DEFAULT_TRANSITION.ease,
                    h: Element_Handle = {}, loc := #caller_location)
	{transition_set(prop, {time, ease}, h, loc)}

transition_all_set :: proc (transition: Transition = DEFAULT_TRANSITION, h: Element_Handle = {}, loc := #caller_location) {
	el := element_get_or_curr(h, loc)
	#unroll for prop in Animation_Property {
		el.transition[prop] = transition
	}
}
transition_all :: proc (time: int = DEFAULT_TRANSITION.time,
                        ease: Ease = DEFAULT_TRANSITION.ease,
                        h: Element_Handle = {}, loc := #caller_location)
	{transition_all_set({time, ease}, h, loc)}
