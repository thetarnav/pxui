package pixui

import "core:mem"
RGBA :: [4]u8

Atlas :: struct {
	pixels: []RGBA,
	size:   [2]int,
}

Texture_Handle :: enum {
	Font,
	Panel,
}

// One per draw command type. The union below uses these as variants.
DCmd_Rect         :: struct {r: Rect, color: Color}
DCmd_Rect_Outline :: struct {r: Rect, thickness: f32, color: Color}
DCmd_Sub_Texture  :: struct {tex: Texture_Handle, src, dst: Rect, tint: Color}
DCmd_Scissor      :: struct {rect: Maybe(Rect)}

// A draw command emitted by the end-of-frame autolayout + draw pass. We sort
// by `z` and walk the list in `end_frame`, calling the backend proc.
Draw_Cmd :: union {
	DCmd_Rect,
	DCmd_Rect_Outline,
	DCmd_Sub_Texture,
	DCmd_Scissor,
}

// A widget's per-frame input/result bag. Built by `end_frame` and consumed by
// the caller's `if button(...) { ... }` style checks.
Interaction :: struct {
	widget:        ^Widget,
	hovering:      bool,
	pressed:       bool,
	released:      bool,
	clicked:       bool,
	right_clicked: bool,
	dragging:      bool,
	drag_delta:    [2]f32,
	mouse:         [2]f32,
	value_changed: bool,
}

// The per-frame library state. There is one of these per UI surface (usually
// one per window). Allocated by the user, freed with `destroy_context`.
Context :: struct {
	pixel_scale: f32, // multiplies all draw dst rects at emit time
	screen_w:    f32, // screen width in *screen* pixels
	screen_h:    f32, // screen height in *screen* pixels
	frame_index: u64, // incremented every begin_frame

	allocator: mem.Allocator, // for cross-frame persistent storage

	// All widgets live in this arena. Reclaimed only when the context dies.
	widget_storage: [dynamic]Widget,
	by_id:          map[u64]^Widget, // id -> widget slot from this frame

	// Parent stack — the top is where new children are attached.
	parent_stack: [dynamic]^Widget,

	// The widget currently being interacted with.
	hovered_id: u64,
	active_id:  u64,

	// Emitted by end_frame, drawn in order.
	draw_cmds: [dynamic]Draw_Cmd,

	// Per-frame input.
	mouse: Vec2,
	mouse_pressed: bool,
	mouse_released: bool,
	mouse_held:    bool,
	mouse_wheel:   f32,

	default_panel:  Panel_Surface,
	default_button: Panel_Surface,
}

ctx: Context

// Initialise a context. The context must outlive all its widgets.
init_context :: proc (allocator: mem.Allocator) -> ^Context {
	ctx = {}
	ctx.allocator      = allocator
	ctx.by_id          = make(map[u64]^Widget, allocator)
	ctx.widget_storage = make([dynamic]Widget, 0, 1024, allocator)
	ctx.parent_stack   = make([dynamic]^Widget, 0, 32, allocator)
	ctx.draw_cmds      = make([dynamic]Draw_Cmd, 0, 1024, allocator)
	return &ctx
}

// Release all resources held by a context. Call after the last frame.
destroy_context :: proc () {
	delete(ctx.by_id)
	delete(ctx.widget_storage)
	delete(ctx.parent_stack)
	delete(ctx.draw_cmds)
}

// Begin a new frame. The mouse position is used for hit-testing in
// `end_frame`. Call before any widget code.
begin_frame :: proc (mouse: Vec2, pixel_scale: f32) {

	ctx.frame_index += 1
	ctx.pixel_scale = pixel_scale
	ctx.mouse = mouse

	// Wipe the per-frame storage. The widget arena grows monotonically; old
	// slots are reused by `alloc_widget`. This is fine because widgets are
	// value types and `^Widget` references into the arena stay valid.
	clear(&ctx.widget_storage)
	clear(&ctx.by_id)
	clear(&ctx.parent_stack)
	clear(&ctx.draw_cmds)

	// Create the implicit root widget. The first user widget attaches here.
	allocate_root()
}

end_frame :: proc () {
	resolve_ids()
	hit_test()
	emit_draw()
}

get_atlas :: proc (handle: Texture_Handle) -> Atlas {
	switch handle {
	case .Font:  return get_font_atlas()
	case .Panel: return get_panel_atlas()
	case: unreachable()
	}
}
