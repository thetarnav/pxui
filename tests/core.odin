package tests

import "core:testing"

import px ".."

// root 100x80
// +-- anchor (25x10 box, margins expand its outer bounds to 33x20)
@(test)
test_fixed_size_and_relative_placement :: proc (t: ^testing.T) {
	scope_layout_test({100, 80})

	px.padding_set(px.Insets{l=2, t=3, r=2, b=3})
	{
		test_node("anchor", 1)
		px.size_px({25, 10})
		px.margin_set(px.Insets{l=3, t=4, r=5, b=6})
		px.pos_set({0.5, 0.25})
		px.origin_set({0.5, 0.5})
	}

	frame_end_expect_layout_tree(t, ```
	root (0,0) (100,80)
	  anchor (41,20) (25,10)
	```)
}

// root 100x80
// +-- content (32x16, measured by the two raw layout callbacks)
//     +-- first  (12x7)
//     +-- second (20x9, placed after first on both axes)
@(test)
test_content_size_and_raw_layout_callbacks :: proc (t: ^testing.T) {
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

	scope_layout_test({100, 80})

	{
		test_node("content", 1)
		px.layout_axis(.X, layout_two_children_x)
		px.layout_axis(.Y, layout_two_children_y)

		{
			test_node("first", 2)
			px.size_px({12, 7})
		}
		{
			test_node("second", 3)
			px.size_px({20, 9})
		}
	}

	frame_end_expect_layout_tree(t, ```
	root (0,0) (100,80)
	  content (0,0) (32,16)
	    first (0,0) (12,7)
	    second (12,7) (20,9)
	```)
}

// root 100x80
// +-- container (30x20, positioned at 4,5)
//     +-- generated (Fill x 50% of parent height, positioned at 6,4)
@(test)
test_subtree_callback_builds_layout_child :: proc (t: ^testing.T) {
	add_subtree_child :: proc () {
		test_node("generated", 1)
		px.size_hv(px.FILL, 0.5)
		px.pos_set({6, 4})
	}

	scope_layout_test({100, 80})

	{
		test_node("container", 1)
		px.size_px({30, 20})
		px.pos_set({4, 5})
		px.subtree(add_subtree_child)
	}

	frame_end_expect_layout_tree(t, ```
	root (0,0) (100,80)
	  container (4,5) (30,20)
	    generated (10,9) (30,10)
	```)
}

// root 80x60
// +-- column (content width 26, Fill height 60)
//     +-- intrinsic (26x12)
//     +-- match-column-width (Fill x, 15px high, placed below intrinsic)
@(test)
test_content_width_parent_fill_height :: proc (t: ^testing.T) {
	layout_children_vertically :: proc () {
		parent := px.element_curr()
		first := px.element_get_assert(parent.child_first)
		second := px.element_get_assert(first.next)
		px.element_set_pos(second.handle, .Y, px.element_bounds(first.handle, .Y))
	}

	scope_layout_test({80, 60})

	{
		test_node("column", 1)
		px.size_hv(px.CONTENT, px.FILL)
		px.layout_axis(.Y, layout_children_vertically)

		{
			test_node("intrinsic", 2)
			px.size_px({26, 12})
		}
		{
			test_node("match-column-width", 3)
			px.size_hv(px.FILL, 15)
		}
	}

	frame_end_expect_layout_tree(t, ```
	root (0,0) (80,60)
	  column (0,0) (26,60)
	    intrinsic (0,0) (26,12)
	    match-column-width (0,12) (26,15)
	```)
}

// root 60x60
// +-- list (size of content)
// |   +-- children (height 10, min_width of content and width of parent)
// |       +-- content (height of parent, varying fixed width)
//
// children and list should be same size—matching the largest content el
@test
test_children_fill_and_grow_parent :: proc (t: ^testing.T) {
	scope_layout_test({60, 60})

	{test_node("list")

		{test_node("child a")
			px.height(10)
			px.min_width(px.CONTENT)
			px.width_fill()

			{test_node("content")
				px.height_fill()
				px.width(10)
			}
		}
		{test_node("child b")
			px.height(10)
			px.min_width(px.CONTENT)
			px.width_fill()

			{test_node("content")
				px.height_fill()
				px.width(20)
			}
		}
		{test_node("child c")
			px.height(10)
			px.min_width(px.CONTENT)
			px.width_fill()

			{test_node("content")
				px.height_fill()
				px.width(15)
			}
		}
	}

	frame_end_expect_layout_tree(t, ```
	root (0,0) (60,60)
	  list (0,0) (20,10)
	    child a (0,0) (20,10)
	      content (0,0) (10,10)
	    child b (0,0) (20,10)
	      content (0,0) (20,10)
	    child c (0,0) (20,10)
	      content (0,0) (15,10)
	```)
}

// root 100x100
// +-- min-list (content width 50, clamped up to min 60)
// |   +-- intrinsic (50x10)
// |   +-- fill-width (60x10)
// +-- max-list (content width 100, clamped down to max 80)
//     +-- intrinsic (100x10)
//     +-- fill-width (80x10)
@(test)
test_content_width_min_max_and_fill_children :: proc (t: ^testing.T) {
	layout_vertical_children :: proc () {
		list   := px.element_curr()
		first  := px.element_get_assert(list.child_first)
		second := px.element_get_assert(first.next)
		px.element_set_pos(second.handle, .Y, px.element_bounds(first.handle, .Y))
	}

	layout_two_lists :: proc () {
		root   := px.element_curr()
		first  := px.element_get_assert(root.child_first)
		second := px.element_get_assert(first.next)
		px.element_set_pos(second.handle, .Y, px.element_bounds(first.handle, .Y))
	}

	scope_layout_test({100, 100})

	px.layout_axis(.Y, layout_two_lists)
	{
		test_node("min-list", 1)
		px.size_hv(px.CONTENT, 40)
		px.min_size_w_px(60)
		px.max_size_w_px(80)
		px.layout_axis(.Y, layout_vertical_children)

		{
			test_node("min-intrinsic", 2)
			px.size_px({50, 10})
		}
		{
			test_node("min-fill", 3)
			px.size_hv(px.FILL, 10)
		}
	}
	{
		test_node("max-list", 4)
		px.size_hv(px.CONTENT, 40)
		px.min_size_w_px(60)
		px.max_size_w_px(80)
		px.layout_axis(.Y, layout_vertical_children)

		{
			test_node("max-intrinsic", 5)
			px.size_px({100, 10})
		}
		{
			test_node("max-fill", 6)
			px.size_hv(px.FILL, 10)
		}
	}

	frame_end_expect_layout_tree(t, ```
	root (0,0) (100,100)
	  min-list (0,0) (60,40)
	    min-intrinsic (0,0) (50,10)
	    min-fill (0,10) (60,10)
	  max-list (0,40) (80,40)
	    max-intrinsic (0,40) (100,10)
	    max-fill (0,50) (80,10)
	```)
}

// root 36x60
// +-- paragraph-like node (Fill width; a cross-axis callback derives 24px height)
@(test)
test_content_height_depends_on_fill_width :: proc (t: ^testing.T) {
	measure_wrapped_height :: proc () {
		el := px.element_curr()
		available_width := px.element_inner_bounds(el.handle, .X)
		height := 12
		if available_width < 40 {
			height *= 2
		}
		px.element_set_height(el.handle, height)
	}

	scope_layout_test({36, 60})

	{
		test_node("paragraph-like", 1)
		px.size_w_fill()
		px.layout_axis(.Y, measure_wrapped_height, deps={.X})
	}

	frame_end_expect_layout_tree(t, ```
	root (0,0) (36,60)
	  paragraph-like (0,0) (36,24)
	```)
}
