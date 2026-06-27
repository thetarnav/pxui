package pixui

//-------//
// TYPES //
//-------//

Vec2  :: [2]f32
Color :: [4]u8
Rect  :: struct {using pos: Vec2, size: Vec2}

rect_offset :: proc (r: Rect, v: Vec2) -> Rect {
    return {r.pos + v, r.size}
}
rect_translate :: proc (r: ^Rect, v: Vec2) {
    r.x += v.x
    r.y += v.y
}
rect_contains :: proc (r: Rect, p: Vec2) -> bool {
	return p.x >= r.x && p.x < r.x + r.size.x &&
	       p.y >= r.y && p.y < r.y + r.size.y
}
rect_intersects :: proc (a, b: Rect) -> bool {
	return a.x < b.x + b.size.x &&
	       a.x + a.size.x > b.x &&
	       a.y < b.y + b.size.y &&
	       a.y + a.size.y > b.y
}

//-------//
// FLAGS //
//-------//

// A widget's capabilities and visual elements.
Flag :: enum u32 {
	Clickable,       // takes part in hit-testing and click handling
	Draggable,       // can be drag-moved when the mouse is held inside
	Toggleable,      // holds a persistent bool (checkbox)
	Draw_Text,       // draws its label as text inside its rect
	Draw_Background, // draws a 9-slice or fill before children
	Draw_Border,     // draws a 1px outline around its rect
	Clip,            // sets a scissor to its rect before drawing children
	Scroll_X,        // supports horizontal scrolling
	Scroll_Y,        // supports vertical scrolling
}

Flags :: distinct bit_set[Flag; u32]

// A widget's persistent scalar state. The nil state of the union is used by
// widgets that have no scalar value (labels, panels, scroll views). Use a
// type switch to read.
Value :: union {f32, int, bool, string}

//-------//
// WIDGET //
//-------//

// A single node in the immediate-mode tree. The tree is rebuilt every frame;
// cross-frame state is found via the `id` -> `^Widget` hash table.
Widget :: struct {
	id: u64,

	// Tree links — rewritten every frame.
	parent:      ^Widget,
	first_child: ^Widget,
	last_child:  ^Widget,
	prev:        ^Widget,
	next:        ^Widget,

	// Hash-table links — for cross-frame lookup.
	hash_next: ^Widget,
	hash_prev: ^Widget,

	// Set to the current frame index every time the widget is touched. Lets
	// `end_frame` prune widgets that were not rebuilt this frame.
	last_touched: u64,

	flags: Flags,
	label: string, // display string

	// Optional fixed size. Zero means "computed by layout".
	semantic_size: Vec2,

	// Computed every frame during `end_frame`'s autolayout pass.
	rect: Rect,

	// Persistent scalar state.
	value: Value,

	// Instant interaction flags (no easing for v0).
	hot:    bool,
	active: bool,

	// Scroll offset applied to descendants. Used by `scroll_view`.
	scroll_off: Vec2,

	// Optional 9-slice / fill parameters for the draw dispatch.
	panel_surface: Maybe(Panel_Surface),
}

// Allocate a widget slot from the context's arena. The slot is owned by the
// context and lives until the context is destroyed.
alloc_widget :: proc (ctx: ^Context) -> ^Widget {
	w: Widget
	append(&ctx.widget_storage, w)
	return &ctx.widget_storage[len(ctx.widget_storage) - 1]
}
