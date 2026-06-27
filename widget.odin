package pixui

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

// A widget's capabilities and visual elements.
Flag :: enum u32 {
	Clickable,       // takes part in hit-testing and click handling
	Draggable,       // can be drag-moved when the mouse is held inside
	Toggleable,      // holds a persistent bool (checkbox)
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

	// If the user passed an explicit `id` to the widget helper, it lives
	// here. `resolve_ids` uses this as the canonical id when set;
	// otherwise the id is derived from the structural position
	// (hash_combine(parent.id, child_index)).
	explicit_id: Maybe(u64),

	flags: Flags,

	// Optional fixed size. Zero means "fill parent".
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

	// Optional 9-slice / fill parameters for the draw dispatch. A zero
	// Panel_Surface (alpha 0 on both fill and border, no nine_slice) is
	// treated as "no surface" and emits no draw commands.
	panel_surface: Panel_Surface,
}

// Allocate a widget slot from the context's arena. The slot is owned by the
// context and lives until the context is destroyed.
alloc_widget :: proc (ctx: ^Context) -> ^Widget {
	w: Widget
	append(&ctx.widget_storage, w)
	return &ctx.widget_storage[len(ctx.widget_storage) - 1]
}

// The return value of `widget_begin`. Includes the widget pointer, its
// computed rect, and whether the widget was created successfully.
Widget_Result :: struct {
	widget: ^Widget,
	rect:   Rect,
	active: bool,
}

// Allocate a widget, attach it to the top of the parent stack, compute its
// rect from the parent's rect + semantic_size, and return its result.
// Manual use; most callers should use the per-widget helpers (panel,
// button, …) which add the deferred end call.
widget_begin :: proc (
	flags:    Flags = {},
	id:       Maybe(u64) = nil,
	size:     Maybe(Vec2) = nil,
	surface:  Maybe(Panel_Surface) = nil,
) -> Widget_Result {
	ctx := the_context
	w := alloc_widget(ctx)
	w.flags = flags
	w.last_touched = ctx.frame_index
	if v, ok := surface.?; ok do w.panel_surface = v
	if v, ok := size.?; ok do w.semantic_size = v
	if id != nil do w.explicit_id = id

	parent := ctx.parent_stack[len(ctx.parent_stack) - 1]
	w.parent = parent
	if parent.last_child == nil {
		parent.first_child = w
	} else {
		parent.last_child.next = w
		w.prev = parent.last_child
	}
	parent.last_child = w

	// v0 layout: child's rect = parent rect (optionally clamped by size).
	if size != nil {
		s := size.?
		w.rect = {parent.rect.pos, {min(s.x, parent.rect.size.x), min(s.y, parent.rect.size.y)}}
	} else {
		w.rect = parent.rect
	}

	// Resolve the id eagerly so callers can look up the widget in by_id
	// before end_frame runs. The explicit id wins; otherwise the
	// structural id is derived from the parent's id and the child's
	// sibling index.
	if eid, ok := w.explicit_id.(u64); ok {
		w.id = eid
	} else {
		w.id = hash_combine(parent.id, u64(sibling_index(parent)))
	}
	ctx.by_id[w.id] = w

	return Widget_Result{w, w.rect, true}
}

// Count how many children the widget already has (so widget_begin can
// index the new child for its structural id).
sibling_index :: proc (w: ^Widget) -> int {
	n := 0
	for c := w.first_child; c != nil; c = c.next { n += 1 }
	return n
}

// Tear down a widget. Stores its state for next frame's id lookup.
widget_end :: proc (r: Widget_Result) {
	if !r.active do return
	ctx := the_context
	w := r.widget
	ctx.by_id[w.id] = w
}

// The sugar proc. Returns `active` for `if widget(...) { ... }` style
// usage. Auto-pushes the new widget onto the parent stack so its children
// attach correctly, and auto-pops at the end of the caller's scope via
// the `@(deferred_out)` attribute.
@(deferred_out=widget_pop)
widget :: proc (
	flags: Flags = {},
	id:    Maybe(u64) = nil,
	size:  Maybe(Vec2) = nil,
) -> bool {
	r := widget_begin(flags, id, size)
	if r.active {
		append(&the_context.parent_stack, r.widget)
	}
	return r.active
}

widget_pop :: proc (active: bool) {
	if active {
        pop(&the_context.parent_stack)
    }
}
