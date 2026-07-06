package pxui

import "core:os"
import "core:strings"

debug_tree_display :: proc (allocator := context.allocator) -> string {

	root := element_get_assert(ctx.element_root)
	screen := root.size + root.pos

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

		for xi in 0..<el.size.x {
			pos := el.pos + {xi, 0}
			if el.size.y > 0 {
				pixels[pos.x + pos.y * screen_w] = u8(el.handle.idx)
			}
			pos.y += el.size.y - 1
			if el.size.y > 1 {
				pixels[pos.x + pos.y * screen_w] = u8(el.handle.idx)
			}
		}
		for yi in 0..<el.size.y {
			pos := el.pos + {0, yi}
			if el.size.x > 0 {
				pixels[pos.x + pos.y * screen_w] = u8(el.handle.idx)
			}
			pos.x += el.size.x - 1
			if el.size.x > 1 {
				pixels[pos.x + pos.y * screen_w] = u8(el.handle.idx)
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
