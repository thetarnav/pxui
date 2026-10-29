package tests

import "core:testing"

import px ".."

// root 100x80
// +-- Stack (content 20x14)
//     +-- first  (20x5)
//     +-- second (15x7, two pixels below first)
@(test)
test_stack_component :: proc (t: ^testing.T) {
	scope_layout_test({100, 80})

	{px.v_stack(gap=2)
		{test_node("first", 1)
			px.size_px({20, 5})
		}
		{test_node("second", 2)
			px.size_px({15, 7})
		}
	}

	frame_end_expect_layout_tree(t, ```
	root pos=(0,0) box=(100,80) bounds=(100,80)
	  Stack pos=(0,0) box=(20,14) bounds=(20,14)
	    first pos=(0,0) box=(20,5) bounds=(20,5)
	    second pos=(0,7) box=(15,7) bounds=(15,7)
	```)
}

// root 30x60
// +-- Flex (horizontal, wraps the third item to a second row)
//     +-- first  (12x5) + second (14x7)
//     +-- third  (10x4)
@(test)
test_flex_component :: proc (t: ^testing.T) {
	scope_layout_test({30, 60})

	{px.flex_h(gap={2, 3})
		px.padding(1)
		px.size_hv(px.FILL, px.CONTENT)
		{test_node("first", 1)
			px.size_px({10, 5})
		}
		{test_node("second", 2)
			px.size_px({14, 7})
		}
		{test_node("third", 3)
			px.size_px({10, 4})
		}
	}

	frame_end_expect_layout_tree(t, ```
	root pos=(0,0) box=(30,60) bounds=(30,60)
	  Flex pos=(0,0) box=(30,12) bounds=(30,12)
	    first pos=(1,1) box=(10,5) bounds=(10,5)
	    second pos=(13,1) box=(14,7) bounds=(14,7)
	    third pos=(1,11) box=(10,4) bounds=(10,4)
	```)
}

// root 50x30
// +-- Rect_Cut (fixed 10px child, remaining width split between two Fill children)
//     +-- fixed (10x30)
//     +-- fill-a (18x30)
//     +-- fill-b (18x30)
@(test)
test_rect_cut_component :: proc (t: ^testing.T) {
	scope_layout_test({50, 30})

	{px.rect_cut(.H, gap=2)
		px.size_fill()
		{test_node("fixed", 1)
			px.size_px({10, 30})
		}
		{test_node("fill-a", 2)
			px.size_fill()
		}
		{test_node("fill-b", 3)
			px.size_fill()
		}
	}

	frame_end_expect_layout_tree(t, ```
	root pos=(0,0) box=(50,30) bounds=(50,30)
	  Rect_Cut pos=(0,0) box=(50,30) bounds=(50,30)
	    fixed pos=(0,0) box=(10,30) bounds=(10,30)
	    fill-a pos=(12,0) box=(18,30) bounds=(18,30)
	    fill-b pos=(32,0) box=(18,30) bounds=(18,30)
	```)
}

// root 50x60
// +-- Masonry (two 24px columns, 2px horizontal and vertical gaps)
//     +-- first  (col 1, y=0, h=10)
//     +-- second (col 2, y=0, h=15)
//     +-- third  (col 1, y=12, h=7)
//     +-- fourth (col 2, y=17, h=11)
@(test)
test_masonry_component :: proc (t: ^testing.T) {
	scope_layout_test({50, 60})

	{px.masonry(2, axis=.V, gap={2, 2})
		px.size_hv(px.FILL, px.CONTENT)
		{test_node("first", 1)
			px.size_h_px(10)
		}
		{test_node("second", 2)
			px.size_h_px(15)
		}
		{test_node("third", 3)
			px.size_h_px(7)
		}
		{test_node("fourth", 4)
			px.size_h_px(11)
		}
	}

	frame_end_expect_layout_tree(t, ```
	root pos=(0,0) box=(50,60) bounds=(50,60)
	  Masonry pos=(0,0) box=(50,28) bounds=(50,28)
	    first pos=(0,0) box=(24,10) bounds=(24,10)
	    second pos=(26,0) box=(24,15) bounds=(24,15)
	    third pos=(0,12) box=(24,7) bounds=(24,7)
	    fourth pos=(26,17) box=(24,11) bounds=(24,11)
	```)
}

// root 80x40
// +-- Scroll_Area_Container (viewport 80x40)
//     +-- content (80x80, starts at scroll offset 0)
@(test)
test_scroll_area_component :: proc (t: ^testing.T) {
	scope_layout_test({80, 40})

	{px.scroll_area(.V)
		{test_node("content", 1)
			px.size_hv(px.FILL, 80)
		}
	}

	frame_end_expect_layout_tree(t, ```
	root pos=(0,0) box=(80,40) bounds=(80,40)
	  Scroll_Area_Container pos=(0,0) box=(80,40) bounds=(80,40)
	    content pos=(0,0) box=(80,80) bounds=(80,80)
	```)
}

// root 80x40
// +-- Scroll_Area_Container (80x40)
// |   +-- content (80x80)
// +-- overlay Scroll_Area_Scrollbar (4x40)
//     +-- Scroll_Area_Scrollbar_Thumb (4x20)
@(test)
test_scrollbar_component :: proc (t: ^testing.T) {
	scope_layout_test({80, 40})

	{px.scroll_area(.V)
		{test_node("content", 1)
			px.size_hv(px.FILL, 80)
		}
		{px.scrollbar(4, 8)
			{px.scrollbar_thumb()}
		}
	}

	frame_end_expect_layout_tree(t, ```
	root pos=(0,0) box=(80,40) bounds=(80,40)
	  Scroll_Area_Container pos=(0,0) box=(80,40) bounds=(80,40)
	    content pos=(0,0) box=(80,80) bounds=(80,80)
	    Scroll_Area_Scrollbar pos=(0,0) box=(4,40) bounds=(4,40)
	      Scroll_Area_Scrollbar_Thumb pos=(0,0) box=(4,20) bounds=(4,20)
	```)
}

// root 32x16
// +-- thumb-host (32x16)
//     +-- Scroll_Area_Scrollbar_Thumb (fills its parent)
@(test)
test_scrollbar_thumb_component :: proc (t: ^testing.T) {
	scope_layout_test({32, 16})

	{test_node("thumb-host", 1)
		px.size_px({32, 16})

		px.scrollbar_thumb()
	}

	frame_end_expect_layout_tree(t, ```
	root pos=(0,0) box=(32,16) bounds=(32,16)
	  thumb-host pos=(0,0) box=(32,16) bounds=(32,16)
	    Scroll_Area_Scrollbar_Thumb pos=(0,0) box=(32,16) bounds=(32,16)
	```)
}
