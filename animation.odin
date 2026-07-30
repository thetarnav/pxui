package pxui

import "core:math"
import "core:math/ease"
import hm "core:container/handle_map"


Animation :: struct {
	using handle: Animation_Handle,
	prop:         Animate_Property,
	el:           Element_Handle,
	start_t:      int,
	start_v:      int,
	end_v:        Sizing,
	transition:   Transition,
}
Animation_Handle :: struct {idx, gen: u32}

Transition :: struct {
	time: int,
	ease: ease.Ease,
}

Animate_Property :: enum {width, height, left, top}

animation_update :: proc (h: Animation_Handle) -> (ok: bool) {

	a := hm.get(&ctx.animations, h) or_return

	el     := element_get(a.el) or_return
	parent := element_get(el.parent) or_return

	s := a.start_v-1
	e := size_to_pixel(a.end_v, element_inner_bounds(parent, animation_property_axis(a.prop)))

	if ctx.time >= a.transition.time + a.start_t || s == e {
		animation_property_set(el, a.prop, e)
		animation_remove(a)
		return false // remove animation
	}

	t := f32(ctx.time - a.start_t) / f32(a.transition.time)
	t = ease.ease(a.transition.ease, t)

	animation_property_set(el, a.prop, int(math.lerp(f32(s), f32(e), t)))

	return true
}

animation_remove :: proc (h: Animation_Handle, loc := #caller_location) -> bool {
	a := hm.get(&ctx.animations, h) or_return
	hm.remove(&ctx.animations, a)
	if el, has_el := element_get(a.el); has_el {
		el.animations[a.prop] = {}
	}
	return true
}

animation_property_ptr :: proc (h: Element_Handle, prop: Animate_Property) -> ^Sizing {
	switch prop {
	case .width:  return &element_get(h).size[0]
	case .height: return &element_get(h).size[1]
	case .left:   return &element_get(h).pos[0]
	case .top:    return &element_get(h).pos[1]
	}
	unreachable()
}
animation_property_axis :: proc (prop: Animate_Property) -> Axis {
	switch prop {
	case .width:  return .X
	case .height: return .Y
	case .left:   return .X
	case .top:    return .Y
	}
	unreachable()
}
animation_property_set :: proc (h: Element_Handle, prop: Animate_Property, v: Sizing) {
	switch prop {
	case .width:  element_get(h).size.x = v
	case .height: element_get(h).size.y = v
	case .left:   element_get(h).pos.x = v
	case .top:    element_get(h).pos.y = v
	}
}
animation_property_get :: proc (h: Element_Handle, prop: Animate_Property) -> int {
	switch prop {
	case .width:  return element_box_size(h, Axis.X)
	case .height: return element_box_size(h, Axis.Y)
	case .left:   return element_screen_pos(h)[0]
	case .top:    return element_screen_pos(h)[1]
	}
	unreachable()
}

animate :: proc (prop: Animate_Property, size: Sizing, h: Element_Handle = {}, loc := #caller_location) {

	el := element_get_or_curr(h, loc)

	a, has_animation := hm.get(&ctx.animations, el.prev_frame.animations[prop])

	if !has_animation {
		ah := hm.add(&ctx.animations, Animation{
			prop       = prop,
			el         = el,
			transition = { // TODO: custom transition
				time = 200,
				ease = .Linear,
			},
		})

		a, has_animation = hm.get(&ctx.animations, ah)
		assert(has_animation)
	}

	if a.end_v != size {
		a.end_v = size
		a.start_v = animation_property_get(el, a.prop)+1 // TODO: what about negative values?
		a.start_t = ctx.time
	}

	el.animations[prop] = a
	animation_update(a)
}
