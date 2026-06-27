package pixui

//-------//
// PANEL //
//-------//

// A panel — a 9-slice background with text. Pushes onto the parent stack
// so children attach to it. Returns `active` for `if panel(...) { ... }`.
@(deferred_out=widget_pop)
panel :: proc (
	text:    string,
	flags:   Flags = {.Draw_Background, .Draw_Border},
	surface: Maybe(Panel_Surface) = nil,
	id:      Maybe(u64) = nil,
) -> bool {
	ctx := the_context
	use_surface := surface
	if use_surface == nil { use_surface = ctx.default_panel }
	r := widget_begin(flags, id=id, surface=use_surface)
	if r.active {
		label(text, r.rect.pos, {240, 220, 180, 255})
		append(&ctx.parent_stack, r.widget)
	}
	return r.active
}
