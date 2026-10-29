package tests

import "base:runtime"

import "core:diff"
import "core:fmt"
import "core:strings"
import "core:testing"

import px ".."

Test_Node :: struct {
	name: string,
}

begin_layout_test :: proc (root_size: px.Vec2i) {
	px.init(context.allocator)
	px.frame_begin()
	px.size_px(root_size)
}
@(deferred_none=px.shutdown)
scope_layout_test :: proc (root_size: px.Vec2i) {
	begin_layout_test(root_size)
}

@(deferred_none=test_node_end)
test_node :: proc (name: string, id: u64) {
	px.element_push(Test_Node, id)
	el := px.element_curr()
	px.element_state(Test_Node, el.handle).name = name
}

test_node_end :: proc () {
	px.element_pop()
}

layout_tree :: proc () -> string {
	sb := strings.builder_make(context.temp_allocator)
	first := true
	write_node(&sb, px.ctx.element_root, 0, true, &first)
	strings.write_rune(&sb, '\n')
	return strings.to_string(sb)

	write_node :: proc (sb: ^strings.Builder, handle: px.Element_Handle, depth: int, is_root: bool, first: ^bool) {
		el, ok := px.element_get(handle)
		if !ok do return

		if !first^ {
			strings.write_rune(sb, '\n')
		}
		first^ = false

		for _ in 0..<depth {
			strings.write_string(sb, "  ")
		}

		if is_root {
			strings.write_string(sb, "root")
		} else if node, has_node := px.element_state_safe(Test_Node, handle); has_node {
			strings.write_string(sb, node.name)
		} else {
			buf: [256]byte
			written: int
			if runtime.write_typeid(&written, buf[:], el.type) {
				strings.write_bytes(sb, buf[:written])
			} else {
				strings.write_string(sb, "<unknown type>")
			}
		}
		pos := px.element_screen_pos(handle)
		box := px.element_box_size(handle)
		bounds := px.element_bounds(handle)
		strings.write_string(sb, fmt.tprintf(
			" pos=(%d,%d) box=(%d,%d) bounds=(%d,%d)",
			pos.x, pos.y,
			box.x, box.y,
			bounds.x, bounds.y,
		))

		child_id := el.child_first
		for child in px.element_get(child_id) {
			write_node(sb, child.handle, depth+1, false, first)
			child_id = child.next
		}
	}
}

expect_layout_tree :: proc (t: ^testing.T, expected: string) {
	expected := strings.concatenate({expected, "\n"}, context.temp_allocator)
	actual := layout_tree()
	if actual == expected do return

	d, err := diff.diff_text(expected, actual, context.allocator, context.temp_allocator)
	if err != nil {
		testing.expectf(t, false, "could not diff layout tree: %v", err)
		return
	}
	defer diff.text_diff_destroy(d, context.allocator)

	report, report_err := diff.unified(d, context.temp_allocator, "expected", "actual")
	if report_err != nil {
		testing.expectf(t, false, "could not format layout diff: %v", report_err)
		return
	}
	testing.expectf(t, false, "layout tree mismatch:\n%s", report)
}

frame_end_expect_layout_tree :: proc (t: ^testing.T, expected: string) {
	px.frame_end()
	expect_layout_tree(t, expected)
}
