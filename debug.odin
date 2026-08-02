package pxui

import "core:io"
import "core:os"
import "core:strings"
import "core:fmt"

debug_tree_display_layout :: proc (allocator := context.allocator) -> string {

	root := element_root()
	screen := element_screen_rect(root)

	pixels := make([]u8, screen.x * screen.y, allocator=context.temp_allocator)
	display(root, pixels, screen.x)

	sb := strings.builder_make(allocator)
	for p, i in pixels {
		x := i % screen.x
		if x == 0 && i != 0 {
			strings.write_rune(&sb, '\n')
		}
		if p != 0 {
			strings.write_rune(&sb, '0' + rune(p))
		} else {
			strings.write_rune(&sb, ' ')
		}
	}
	strings.write_rune(&sb, '\n')
	return strings.to_string(sb)

	display :: proc (h: Element_Handle, pixels: []u8, screen_w: int) -> (ok: bool) {

		el   := element_get(h) or_return
		pos  := element_screen_pos(el)
		size := element_box_size(el)

		for xi in 0..<size.x {
			p := pos + {xi, 0}
			i := p.x + p.y * screen_w
			if i < len(pixels) - 1 {
				pixels[i] = u8(el.handle.idx)
			}
			p.y += size.y - 1
			i = p.x + p.y * screen_w
			if i < len(pixels) - 1 {
				pixels[p.x + p.y * screen_w] = u8(el.handle.idx)
			}
		}
		for yi in 0..<size.y {
			p := pos + {0, yi}
			i := p.x + p.y * screen_w
			if i < len(pixels) - 1 {
				pixels[p.x + p.y * screen_w] = u8(el.handle.idx)
			}
			p.x += size.x - 1
			i = p.x + p.y * screen_w
			if i < len(pixels) - 1 {
				pixels[p.x + p.y * screen_w] = u8(el.handle.idx)
			}
		}

		display(el.child_first, pixels, screen_w)
		display(el.next, pixels, screen_w)

		return true
	}
}
debug_tree_layout_print :: proc () {
	str := debug_tree_display_layout(context.temp_allocator)
	os.write_string(os.stdout, str)
}

Debug_Tree_Display_Proc :: proc (w: io.Writer, el: ^Element)
debug_tree_display_write :: proc (w: io.Writer, root: Element_Handle, info: Debug_Tree_Display_Proc = nil) {

	visit(w, info, root, 0)
	visit :: proc (w: io.Writer, info: Debug_Tree_Display_Proc, h: Element_Handle, depth: int) -> bool {
		el := element_get(h) or_return

		for _ in 0..<depth {
			io.write_string(w, "| ")
		}
		element_display_writer(w, el)

		if info != nil {
			io.write_rune(w, ' ')
			info(w, el)
		}

		io.write_rune(w, '\n')

		visit(w, info, el.child_first, depth+1)
		visit(w, info, el.next, depth)

		return true
	}
}

debug_tree_display_print :: proc (root: Element_Handle, info: Debug_Tree_Display_Proc = nil) {
	w := io.to_writer(os.to_writer(os.stdout))
	debug_tree_display_write(w, root, info)
}

// TODO: all strings should allocate or none—otherwise you cannot free
sizing_to_string :: proc (s: Sizing, allocator := context.allocator) -> string {
	switch v in s {
	case Content: return "Content"
	case Fill:    return "Fill"
	case int:     return fmt.aprintf("%d", v, allocator=allocator)
	case f32:     return fmt.aprintf("%g", v, allocator=allocator)
	}
	return "?"
}

debug_tree_dump :: proc (path: string, root: Element_Handle, info: Debug_Tree_Display_Proc = nil) {
	f, err := os.open(path, {.Write, .Create, .Trunc})
	if err != nil do return
	defer os.close(f)
	w := io.to_writer(os.to_writer(f))
	debug_tree_display_write(w, root, info)
}
