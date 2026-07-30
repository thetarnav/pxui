package pxui

import "core:math"
import "core:math/ease"
import hm "core:container/handle_map"


Animation :: struct {
	using handle: Animation_Handle,
	start_time:   int,
	start_value:  Sizing,
	value:        Sizing,
}
Animation_Handle :: struct {idx, gen: u32}

Animation_Property :: enum {width, height, left, top, opacity}

Transition :: struct {
	time: int,
	ease: ease.Ease,
}

animation_update :: proc (h: Animation_Handle, el: ^Element, prop: Animation_Property) -> (ok: bool) {

	// TODO: custom transitions
	transition := Transition{
		time = 200,
		ease = .Linear,
	}

	a := hm.get(&ctx.animations, h) or_return

	if ctx.time >= transition.time + a.start_time || a.start_value == a.value {
		animation_property_set(a, el, prop, 1.0)
		animation_remove(a, el, prop)
		return false
	}

	t := f32(ctx.time - a.start_time) / f32(transition.time)
	t = ease.ease(transition.ease, t)

	animation_property_set(a, el, prop, t)

	return true
}

animation_remove :: proc (h: Animation_Handle, el: ^Element, prop: Animation_Property, loc := #caller_location) -> bool {
	a := hm.get(&ctx.animations, h) or_return
	hm.remove(&ctx.animations, a)
	el.animations[prop] = {}
	return true
}

animation_property_set :: proc (a: ^Animation, h: Element_Handle, prop: Animation_Property, t: f32) {
	el := element_get(h)

	switch prop {
	case .width, .height, .left, .top:

		axis := prop == .width || prop == .left ? Axis.X : Axis.Y

		s := a.start_value.(int)
		e := size_to_pixel(a.value, element_inner_bounds(element_parent(el), axis))
		v := int(math.lerp(f32(s), f32(e), t))

		#no_bounds_check #partial switch prop {
		case .width, .height: el.size[axis] = v
		case .left,  .top:    el.pos[axis]  = v
		}

	case .opacity:
		s := a.start_value.(f32)
		e := a.value.(f32)
		el.transparency = 1.0 - math.lerp(s, e, t)
	}
}
animation_property_get :: proc (h: Element_Handle, prop: Animation_Property) -> Sizing {
	switch prop {
	case .width:   return element_box_size(h, Axis.X)
	case .height:  return element_box_size(h, Axis.Y)
	case .left:    return element_screen_pos(h).x
	case .top:     return element_screen_pos(h).y
	case .opacity: return 1.0 - element_get(h).prev_frame.transparency
	}
	unreachable()
}

animate :: proc (prop: Animation_Property, value: Sizing, h: Element_Handle = {}, loc := #caller_location) {

	el := element_get_or_curr(h, loc)

	a, has_animation := hm.get(&ctx.animations, el.prev_frame.animations[prop])

	if !has_animation {
		ah := hm.add(&ctx.animations, Animation{})
		a = hm.get(&ctx.animations, ah)
	}

	assert(a != nil, loc=loc)

	if a.value != value {
		a.value       = value
		a.start_value = animation_property_get(el, prop)
		a.start_time  = ctx.time
	}

	el.animations[prop] = a
	animation_update(a, el, prop)
}
