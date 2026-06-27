package pixui

//-------//
// LAYOUT //
//-------//

// Martin Cohen's "rectcut" primitive. Take a parent rect, cut `size` off the
// `side` on the given axis, return the cut piece and shrink the parent in
// place. Compose: rows, columns, sidebars, toolbars, centered items.
//
// `size` is one of:
//   - `Size_Pixels(120)`            : carve off 120 UI px
//   - `Size_Percent_Of_Parent(0.25) : carve off 25% of the parent's length on the axis
//   - `Size_Remaining               : carve off everything left
// `margin` is uniform spacing inserted *between* the cut and the remainder.

Size_Pixels            :: struct {v: f32}
Size_Percent_Of_Parent :: struct {v: f32}
Size_Remaining         :: struct {}

Size :: union {
	Size_Pixels,
	Size_Percent_Of_Parent,
	Size_Remaining,
}

Axis :: enum { X, Y }
Edge :: enum { Min, Max } // .Min = left/top, .Max = right/bottom

rect_cut :: proc (parent: ^Rect, axis: Axis, edge: Edge, size: Size, margin: f32 = 0) -> Rect {
	pixels: f32
	switch s in size {
	case Size_Pixels:            pixels = s.v
	case Size_Percent_Of_Parent: pixels = parent.size[axis] * s.v
	case Size_Remaining:         pixels = parent.size[axis]
	}

	// Clamp so the cut never overshoots the parent.
	pixels = min(pixels, parent.size[axis])

	out: Rect
	if axis == .X {
		if edge == .Min {
			out = {parent.x, parent.y, {pixels, parent.size.y}}
			parent.x += pixels + margin
		} else {
			out = {parent.x + parent.size.x - pixels, parent.y, {pixels, parent.size.y}}
			parent.size.x -= pixels + margin
		}
		parent.size.x -= margin
	} else {
		if edge == .Min {
			out = {parent.x, parent.y, {parent.size.x, pixels}}
			parent.y += pixels + margin
		} else {
			out = {parent.x, parent.y + parent.size.y - pixels, {parent.size.x, pixels}}
			parent.size.y -= pixels + margin
		}
		parent.size.y -= margin
	}
	// If the cut consumed everything, the remainder rect can become empty.
	if parent.size.x < 0 { parent.size.x = 0 }
	if parent.size.y < 0 { parent.size.y = 0 }
	return out
}

// Side-band queries — return a rect on the named side without shrinking the
// input. Useful for drawing 9-slice borders or hover rings around a child.
get_left   :: proc (r: Rect, amt: f32) -> Rect { return {r.x, r.y, {amt, r.size.y}} }
get_right  :: proc (r: Rect, amt: f32) -> Rect { return {r.x + r.size.x - amt, r.y, {amt, r.size.y}} }
get_top    :: proc (r: Rect, amt: f32) -> Rect { return {r.x, r.y, {r.size.x, amt}} }
get_bottom :: proc (r: Rect, amt: f32) -> Rect { return {r.x, r.y + r.size.y - amt, {r.size.x, amt}} }

// Inset/extend a rect uniformly.
contract :: proc (r: Rect, amt: f32) -> Rect { return {r.x + amt, r.y + amt, {max(0, r.size.x - amt*2), max(0, r.size.y - amt*2)}} }
expand   :: proc (r: Rect, amt: f32) -> Rect { return {r.x - amt, r.y - amt, {r.size.x + amt*2, r.size.y + amt*2}} }
