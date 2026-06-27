package pixui

//-------//
// LABEL //
//-------//

// Plain text label. Does not participate in hit-testing unless `Clickable` is
// in flags. Returns the rect the text was drawn into.
label :: proc (text: string, flags: Flags = {}, id: Maybe(u64) = nil) -> Rect {
	r := widget_begin(text, flags + {.Draw_Text}, id=id)
	widget_end(r)
	return r.rect
}
