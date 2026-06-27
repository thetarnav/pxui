package pixui

//-------//
// PANEL //
//-------//

// A panel — a 9-slice background with a label. Pushes onto the parent stack
// so children attach to it. Returns `active` for `if panel(...) { ... }`.
@(deferred_out=widget_pop)
panel :: proc (
	label:   string,
	flags:   Flags = {.Draw_Background, .Draw_Border},
	surface: Maybe(Panel_Surface) = nil,
	id:      Maybe(u64) = nil,
) -> bool {
	r := widget_begin(label, flags, id=id, surface=surface)
	if r.active {
		append(&the_context.parent_stack, r.widget)
	}
	return r.active
}
