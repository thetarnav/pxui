package pixui

import "base:runtime"
import "core:slice"
import "core:image/tga"

@private
panel_atlas: Atlas

@(private, init)
init_panel_texture :: proc "contextless" () {
	context = runtime.default_context()
	img, _ := tga.load_from_bytes(#load("./panel.tga"), allocator=context.temp_allocator)
	panel_atlas = {
		pixels = slice.clone(slice.reinterpret([]RGBA, img.pixels.buf[:])),
		size   = {img.width, img.height}
	}
}

@private
get_panel_atlas :: proc () -> Atlas {
	return panel_atlas
}

// A panel — a 9-slice background with text. Pushes onto the parent stack
// so children attach to it. Returns `active` for `if panel(...) { ... }`.
panel :: proc (
	text:    string,
	flags:   Flags = {.Draw_Background, .Draw_Border},
	surface: Maybe(Panel_Surface) = nil,
	id:      Maybe(u64) = nil,
) -> bool {
	use_surface := surface
	if use_surface == nil {use_surface = ctx.default_panel}
	r := widget_begin(flags, id=id, surface=use_surface)
	if r.active {
		label(text, r.rect.pos, {240, 220, 180, 255})
		append(&ctx.parent_stack, r.widget)
		defer pop(&ctx.parent_stack) // pop at end of *this* scope
	}
	return r.active
}
