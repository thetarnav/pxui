package tests

import "core:diff"
import "core:fmt"
import "core:strings"
import "core:testing"

import px ".."

Test_Node :: struct {
	name: string,
}

push_test_node :: proc (name: string, id: u64) -> px.Element_Handle {
	node := px.element_push(Test_Node, id)
	node.name = name
	return px.element_curr().handle
}

begin_layout_test :: proc (root_size: px.Vec2i) {
	px.init(context.allocator)
	px.frame_begin()
	px.size_px(root_size)
}

layout_tree :: proc () -> string {
	sb := strings.builder_make(context.temp_allocator)
	write_node(&sb, px.ctx.element_root, 0, true)
	return strings.to_string(sb)

	write_node :: proc (sb: ^strings.Builder, handle: px.Element_Handle, depth: int, is_root: bool) {
		el, ok := px.element_get(handle)
		if !ok do return

		for _ in 0..<depth {
			strings.write_string(sb, "  ")
		}

		name := "root"
		if !is_root {
			name = px.element_state(Test_Node, handle).name
		}
		pos := px.element_screen_pos(handle)
		box := px.element_box_size(handle)
		bounds := px.element_bounds(handle)
		strings.write_string(sb, fmt.tprintf(
			"%s pos=(%d,%d) box=(%d,%d) bounds=(%d,%d)\n",
			name,
			pos.x, pos.y,
			box.x, box.y,
			bounds.x, bounds.y,
		))

		child_id := el.child_first
		for child in px.element_get(child_id) {
			write_node(sb, child.handle, depth+1, false)
			child_id = child.next
		}
	}
}

expect_layout_tree :: proc (t: ^testing.T, expected: string) {
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

layout_two_children_x :: proc () {
	parent := px.element_curr()
	first := px.element_get_assert(parent.child_first)
	second := px.element_get_assert(first.next)

	px.element_set_pos(second.handle, .X, px.element_bounds(first.handle, .X))
	px.element_set_inner_bounds(parent.handle, .X,
		px.element_bounds(first.handle, .X) + px.element_bounds(second.handle, .X),
	)
}

layout_two_children_y :: proc () {
	parent := px.element_curr()
	first := px.element_get_assert(parent.child_first)
	second := px.element_get_assert(first.next)

	px.element_set_pos(second.handle, .Y, px.element_bounds(first.handle, .Y))
	px.element_set_inner_bounds(parent.handle, .Y,
		px.element_bounds(first.handle, .Y) + px.element_bounds(second.handle, .Y),
	)
}

add_subtree_child :: proc () {
	_ = push_test_node("generated", 1)
	px.size_hv(px.FILL, 0.5)
	px.pos_set({6, 4})
	px.element_pop()
}

@(test)
test_fixed_size_and_relative_placement :: proc (t: ^testing.T) {
	begin_layout_test({100, 80})
	defer px.shutdown()

	px.padding_set(px.Insets{l=2, t=3, r=2, b=3})
	_ = push_test_node("anchor", 1)
	px.size_px({25, 10})
	px.margin_set(px.Insets{l=3, t=4, r=5, b=6})
	px.pos_set({0.5, 0.25})
	px.origin_set({0.5, 0.5})
	px.element_pop()

	px.frame_end()
	expect_layout_tree(t, "root pos=(0,0) box=(100,80) bounds=(100,80)\n"+
		"  anchor pos=(41,20) box=(25,10) bounds=(33,20)\n")
}

@(test)
test_content_size_and_raw_layout_callbacks :: proc (t: ^testing.T) {
	begin_layout_test({100, 80})
	defer px.shutdown()

	_ = push_test_node("content", 1)
	px.layout_axis(.X, layout_two_children_x)
	px.layout_axis(.Y, layout_two_children_y)

	_ = push_test_node("first", 2)
	px.size_px({12, 7})
	px.element_pop()

	_ = push_test_node("second", 3)
	px.size_px({20, 9})
	px.element_pop()
	px.element_pop()

	px.frame_end()
	expect_layout_tree(t, "root pos=(0,0) box=(100,80) bounds=(100,80)\n"+
		"  content pos=(0,0) box=(32,16) bounds=(32,16)\n"+
		"    first pos=(0,0) box=(12,7) bounds=(12,7)\n"+
		"    second pos=(12,7) box=(20,9) bounds=(20,9)\n")
}

@(test)
test_subtree_callback_builds_layout_child :: proc (t: ^testing.T) {
	begin_layout_test({100, 80})
	defer px.shutdown()

	_ = push_test_node("container", 1)
	px.size_px({30, 20})
	px.pos_set({4, 5})
	px.subtree(add_subtree_child)
	px.element_pop()

	px.frame_end()
	expect_layout_tree(t, "root pos=(0,0) box=(100,80) bounds=(100,80)\n"+
		"  container pos=(4,5) box=(30,20) bounds=(30,20)\n"+
		"    generated pos=(10,9) box=(30,10) bounds=(30,10)\n")
}
