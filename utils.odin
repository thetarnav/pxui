package pxui

import "base:runtime"
import la "core:math/linalg"

perp :: #force_inline proc "contextless" (a: Axis) -> Axis {return Axis((int(a) + 1) % 2)}
axis_perp :: perp

bounds_check_axis :: proc (a: Axis, loc := #caller_location) {
	runtime.bounds_check_error_loc(loc, int(a), 2)
}
axis_bounds_check :: bounds_check_axis

lt :: #force_inline proc "contextless" (i: Insets) -> Vec2i {return {i.l, i.t}}
lb :: #force_inline proc "contextless" (i: Insets) -> Vec2i {return {i.l, i.b}}
rt :: #force_inline proc "contextless" (i: Insets) -> Vec2i {return {i.r, i.t}}
rb :: #force_inline proc "contextless" (i: Insets) -> Vec2i {return {i.r, i.b}}

// Convert a Size to a pixel value along one axis.
// `ref` is the reference size in pixels (parent's content area along that axis).
size_to_pixel :: proc (s: Sizing, ref: int) -> int {
	switch v in s {
	case Content: return 0
	case Fill:    return ref
	case int:     return v
	case f32:     return int(v * f32(ref))
	}
	return 0
}

// Convert a Size_Vec to a Vec2i of pixel values, using `ref` as the reference.
size_vec_to_pixel :: proc (s: Sizing_2D, ref: Vec2i) -> Vec2i {
	return {size_to_pixel(s.x, ref.x), size_to_pixel(s.y, ref.y)}
}

vec2i_to_size :: proc (v: Vec2i) -> Sizing_2D {return {v.x, v.y}}
vec2f_to_size :: proc (v: Vec2f) -> Sizing_2D {return {v.x, v.y}}
to_size       :: proc {vec2f_to_size, vec2i_to_size}
size_vec      :: to_size
vec_to_size   :: to_size

@require_results
rect :: #force_inline proc "contextless" (s, e: Vec2i) -> Rect {
    return {s, la.max(e-s, 0)}
}
rect_end :: #force_inline proc "contextless" (rect: Rect) -> (end: Vec2i) {
	return rect.pos + rect.size
}
@require_results
rect_clamp :: #force_inline proc "contextless" (v, m: Rect) -> Rect {
    return rect(la.max(v.pos, m.pos),
	            la.min(rect_end(v), rect_end(m)))
}
@require_results
rect_clamp_point :: #force_inline proc "contextless" (r: Rect, p: Vec2i) -> Vec2i {
	return la.clamp(p, r, r + r.size)
}
@require_results
rect_outset :: #force_inline proc "contextless" (rect: Rect, by: Vec2i) -> Rect {
    return {rect.pos - by, rect.size + by*2}
}
@require_results
rect_inset :: #force_inline proc "contextless" (rect: Rect, by: Vec2i) -> Rect {
    return {rect.pos + by, rect.size - by*2}
}
@require_results
rect_extend :: #force_inline proc "contextless" (r: Rect, by: Vec2i) -> Rect {
	return rect(la.min(r.pos, by),
	            la.max(rect_end(r), by))
}
@require_results
rect_union :: #force_inline proc "contextless" (a, b: Rect) -> Rect {
	return rect(la.min(a.pos, b.pos),
	            la.max(rect_end(a), rect_end(b)))
}
@require_results
rect_intersetcion :: #force_inline proc "contextless" (a, b: Rect) -> Rect {
	return rect(la.max(a.pos, b.pos),
	            la.min(rect_end(a), rect_end(b)))
}
@require_results
rect_offset :: #force_inline proc "contextless" (r: Rect, v: Vec2i) -> Rect {
    return {r.pos + v, r.size}
}
@require_results
rect_contains :: #force_inline proc "contextless" (r: Rect, p: Vec2i) -> bool {
	return p.x >= r.x && p.x < r.x + r.size.x &&
	       p.y >= r.y && p.y < r.y + r.size.y
}
@require_results
rect_intersects :: #force_inline proc "contextless" (a, b: Rect) -> bool {
	return a.x < b.x + b.size.x &&
	       a.x + a.size.x > b.x &&
	       a.y < b.y + b.size.y &&
	       a.y + a.size.y > b.y
}
