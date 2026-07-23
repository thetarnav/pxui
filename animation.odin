package pxui

import "core:fmt"
import "core:math"
import "core:math/ease"

Animation :: struct #all_or_none {
	prop:       Animate_Property,
	el:         Element_Handle,
	start_t:    int,
	start_v:    int,
	end_v:      Sizing,
	transition: Transition,
}

Transition :: struct {
	time: int,
	ease: ease.Ease,
}

Animate_Property :: enum {width, height, left, top}

animations_update :: proc () {

	fmt.println("animmations updata")

	#reverse for &a, i in ctx.animations {

		// Get prev-frame start value after animation is created/reset
		if a.start_v == 0 {
			// add 1 to start as 0 means "needs start reset"
			a.start_v = animation_property_get(a.el, a.prop)+1 // TODO: what about negative values?
			a.start_t = ctx.time
		}

		ptr := animation_property_ptr(a.el, a.prop)
		s   := a.start_v-1
		e   := size_to_pixel(a.end_v, element_inner_bounds(element_parent(a.el), animation_property_axis(a.prop)))

		if ctx.time >= a.transition.time + a.start_t || s == e {
			unordered_remove(&ctx.animations, i)
			element_get(a.el).animations[a.prop] = nil
			ptr^ = a.end_v
			continue
		}

		t := f32(ctx.time - a.start_t) / f32(a.transition.time)
		t = ease.ease(a.transition.ease, t)

		fmt.println(t, e, s)

		ptr^ = int(math.lerp(f32(s), f32(e), t))
	}
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
animation_property_set :: proc (h: Element_Handle, prop: Animate_Property, v: int) {
	switch prop {
	case .width:  element_get(h).size.x = v
	case .height: element_get(h).size.y = v
	case .left:   element_get(h).pos.x = v
	case .top:    element_get(h).pos.y = v
	}
	unreachable()
}
animation_property_get :: proc (h: Element_Handle, prop: Animate_Property) -> int {
	switch prop {
	case .width:  return element_box_size(h)[0]
	case .height: return element_box_size(h)[1]
	case .left:   return element_screen_pos(h)[0]
	case .top:    return element_screen_pos(h)[1]
	}
	unreachable()
}

animate :: proc (prop: Animate_Property, size: Sizing, h: Element_Handle = {}, loc := #caller_location) {

	el  := element_get_or_curr(h, loc)

	a := el.animations[prop]
	if a == nil {
		append_nothing(&ctx.animations, loc)
		a = &ctx.animations[len(ctx.animations)-1]
		el.animations[prop] = a

		a.prop       = prop
		a.el         = el
		a.transition = { // TODO: custom transition
			time = 200,
			ease = .Linear,
		}
	} else if a.end_v != size {
		a.start_v = 0 // Reset animation on end value change
	}

	a.end_v = size
}
