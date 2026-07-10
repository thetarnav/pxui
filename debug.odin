package pxui

import "core:os"
import "core:strings"

debug_tree_display :: proc (allocator := context.allocator) -> string {

	root := element_get_assert(ctx.element_root)
	screen := root.screen_pos + root.rel_rect.size

	pixels := make([]u8, screen.x * screen.y, allocator=context.temp_allocator)
	display(ctx.element_root, pixels, screen.x)

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

		el := element_get(h) or_return
		pos := el.screen_pos
		size := el.rel_rect.size

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
debug_tree_print :: proc () {
	str := debug_tree_display(context.temp_allocator)
	os.write_string(os.stdout, str)
}
