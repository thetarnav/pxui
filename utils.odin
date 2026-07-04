package pixui

import la "core:math/linalg"

@require_results
rect :: #force_inline proc "contextless" (s, e: Vec) -> Rect {
    return {s, e-s}
}
@require_results
rect_clamp :: proc "contextless" (v, m: Rect) -> Rect {
    return rect(la.max(v.pos, m.pos), la.min(v.pos+v.size, m.pos+m.size))
}
@require_results
rect_clamp_point :: proc "contextless" (r: Rect, p: Vec) -> Vec {
	return la.clamp(p, r, r + r.size)
}
@require_results
rect_outset :: proc "contextless" (rect: Rect, by: Vec) -> Rect {
    return {rect.pos - by, rect.size + by*2}
}
@require_results
rect_inset :: proc "contextless" (rect: Rect, by: Vec) -> Rect {
    return {rect.pos + by, rect.size - by*2}
}
