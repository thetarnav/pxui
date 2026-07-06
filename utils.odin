package pxui

import la "core:math/linalg"

@require_results
rect :: #force_inline proc "contextless" (s, e: Vec) -> Rect {
    return {s, e-s}
}
rect_end :: #force_inline proc "contextless" (rect: Rect) -> (end: Vec) {
	return rect.pos + rect.size
}
@require_results
rect_clamp :: #force_inline proc "contextless" (v, m: Rect) -> Rect {
    return rect(la.max(v.pos, m.pos),
	            la.min(rect_end(v), rect_end(m)))
}
@require_results
rect_clamp_point :: #force_inline proc "contextless" (r: Rect, p: Vec) -> Vec {
	return la.clamp(p, r, r + r.size)
}
@require_results
rect_outset :: #force_inline proc "contextless" (rect: Rect, by: Vec) -> Rect {
    return {rect.pos - by, rect.size + by*2}
}
@require_results
rect_inset :: #force_inline proc "contextless" (rect: Rect, by: Vec) -> Rect {
    return {rect.pos + by, rect.size - by*2}
}
@require_results
rect_extend :: #force_inline proc "contextless" (r: Rect, by: Vec) -> Rect {
	return rect(la.min(r.pos, by),
	            la.min(rect_end(r), by))
}
@require_results
rect_union :: #force_inline proc "contextless" (a, b: Rect) -> Rect {
	return rect(la.min(a.pos, b.pos),
	            la.min(rect_end(a), rect_end(b)))
}
