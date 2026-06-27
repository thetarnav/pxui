package pixui

//-------//
// WIDGET //
//-------//

// The return value of `widget_begin`. Includes the widget pointer, its
// computed rect, and whether the widget was created successfully.
Widget_Result :: struct {
	widget: ^Widget,
	rect:   Rect,
	active: bool,
}

// Allocate a widget, attach it to the top of the parent stack, and return
// its result. Manual use; most callers should use the per-widget helpers
// (panel, button, …) which add the deferred end call.
widget_begin :: proc (
	label:    string,
	flags:    Flags = {},
	id:       Maybe(u64) = nil,
	size:     Maybe([2]f32) = nil,
	surface:  Maybe(Panel_Surface) = nil,
) -> Widget_Result {
	ctx := the_context
	w := alloc_widget(ctx)
	w.flags = flags
	w.label = label
	w.last_touched = ctx.frame_index
	if surface != nil { w.panel_surface = surface.? }
	if size != nil { w.semantic_size = size.? }

	parent := ctx.parent_stack[len(ctx.parent_stack) - 1]
	w.parent = parent
	if parent.last_child == nil {
		parent.first_child = w
	} else {
		parent.last_child.next = w
		w.prev = parent.last_child
	}
	parent.last_child = w

	return Widget_Result{w, w.rect, true}
}

// Tear down a widget. Stores its state for next frame's id lookup.
widget_end :: proc (r: Widget_Result) {
	if !r.active { return }
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
	label: string,
	flags: Flags = {},
	id:    Maybe(u64) = nil,
	size:  Maybe([2]f32) = nil,
) -> bool {
	r := widget_begin(label, flags, id, size)
	if r.active {
		ctx := the_context
		append(&ctx.parent_stack, r.widget)
	}
	return r.active
}

widget_pop :: proc (active: bool) {
	if !active { return }
	ctx := the_context
	pop(&ctx.parent_stack)
}
