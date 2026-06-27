#+test
#+private package
package pixui

// Tests for the pixui UI library. Run with `odin test .` from the project
// root.
//
// Conventions follow `odin-fsw/test.odin`:
//   - @+test build attribute so `odin test` picks this file up
//   - @+private package keeps the helpers from leaking into the public API
//   - @(test) attribute on each test proc
//   - mem.tracking_allocator to catch leaks across full frame cycles
//
// Note: Odin proc literals do not capture enclosing-scope variables, so the
// tests don't use closures for the UI-building code — each test is just
// a sequence of inline begin_frame/widget/end_frame blocks.

import "core:fmt"
import "core:mem"
import "core:testing"

//-------//
// HELPERS //
//-------//

// A Loader that just returns a fixed handle for every load call. Real
// rendering never happens in the tests (we just inspect draw_cmds), so the
// handle is opaque to pixui.
fake_loader := Loader{
	load_texture_png = proc (_: []u8) -> Texture_Handle {
		return Texture_Handle(0xDEADBEEF)
	},
}

// Build a context wired to the fake loader, owned by the given allocator.
make_ctx :: proc (allocator: mem.Allocator) -> ^Context {
	ctx := new(Context, allocator)
	init_context(ctx, allocator, fake_loader)
	return ctx
}

// Count draw commands of a given variant.
count_cmds :: proc (ctx: ^Context, $T: typeid) -> int {
	n := 0
	for c in ctx.draw_cmds {
		_, ok := c.cmd.(T)
		if ok do n += 1
	}
	return n
}

//-------//
// TESTS //
//-------//

@(test)
test_rect_cut_pixels :: proc (t: ^testing.T) {
	parent: Rect = {{0, 0}, {100, 100}}
	out := rect_cut(&parent, .X, .Min, Size_Pixels{30})
	testing.expect_value(t, out.size.x, 30)
	testing.expect_value(t, out.size.y, 100)
	testing.expect_value(t, parent.size.x, 70)
	testing.expect_value(t, parent.size.y, 100)
}

@(test)
test_rect_cut_remaining :: proc (t: ^testing.T) {
	parent: Rect = {{0, 0}, {100, 50}}
	_ = rect_cut(&parent, .X, .Min, Size_Pixels{30})
	out := rect_cut(&parent, .X, .Min, Size_Remaining{})
	testing.expect_value(t, out.size.x, 70)
	testing.expect_value(t, out.size.y, 50)
}

@(test)
test_rect_cut_max_edge :: proc (t: ^testing.T) {
	parent: Rect = {{0, 0}, {100, 100}}
	out := rect_cut(&parent, .X, .Max, Size_Pixels{40})
	testing.expect_value(t, out.x, 60)
	testing.expect_value(t, out.size.x, 40)
	testing.expect_value(t, parent.size.x, 60)
}

@(test)
test_rect_cut_with_margin :: proc (t: ^testing.T) {
	parent: Rect = {{0, 0}, {100, 100}}
	_ = rect_cut(&parent, .X, .Min, Size_Pixels{20}, margin = 4)
	// Cut: 20 px wide, then 4 px margin, remainder starts at x=24.
	testing.expect_value(t, parent.x, 24)
	testing.expect_value(t, parent.size.x, 72) // 100 - 20 - 4 - 4
}

@(test)
test_rect_cut_clamp :: proc (t: ^testing.T) {
	parent: Rect = {{0, 0}, {50, 50}}
	out := rect_cut(&parent, .X, .Min, Size_Pixels{9999})
	// Should clamp to the parent's size, leaving nothing.
	testing.expect_value(t, out.size.x, 50)
	testing.expect_value(t, parent.size.x, 0)
}

@(test)
test_widget_ids_are_stable :: proc (t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)

	ctx := make_ctx(mem.tracking_allocator(&track))
	defer destroy_context(ctx)
	defer free(ctx, context.allocator)

	// First frame: create three sibling buttons, capture their ids.
	begin_frame(ctx, {0, 0}, 1)
	ids1: [3]u64
	for i in 0..<3 {
		_, _ = button(fmt.tprintf("Btn %d", i), id = u64(i + 100))
	}
	for i in 0..<3 {
		w, ok := ctx.by_id[u64(i + 100)]
		testing.expect(t, ok, fmt.tprintf("first frame: id %d not found", i + 100))
		if ok do ids1[i] = w.id
	}
	end_frame(ctx)

	// Second frame: same calls in the same order. The button helper
	// currently re-derives the id from the structural position, so the
	// ids should be identical across frames.
	begin_frame(ctx, {0, 0}, 1)
	for i in 0..<3 {
		_, _ = button(fmt.tprintf("Btn %d", i), id = u64(i + 100))
	}
	for i in 0..<3 {
		w, ok := ctx.by_id[ids1[i]]
		testing.expect(t, ok, fmt.tprintf("second frame: id %d not found", i + 100))
		if ok do testing.expect_value(t, w.id, ids1[i])
	}
	end_frame(ctx)
}

@(test)
test_panel_produces_fill_and_border :: proc (t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)

	ctx := make_ctx(mem.tracking_allocator(&track))
	defer destroy_context(ctx)
	defer free(ctx, context.allocator)

	ctx.default_panel = Panel_Surface{
		fill_color   = {100, 50, 25, 255},
		border_color = {200, 150, 100, 255},
	}

	begin_frame(ctx, {0, 0}, 1)
	ok := panel("Hello", id = 1)
	testing.expect(t, ok, "panel should be active")
	end_frame(ctx)

	testing.expect_value(t, count_cmds(ctx, DCmd_Rect),         1)
	testing.expect_value(t, count_cmds(ctx, DCmd_Rect_Outline), 1)
	testing.expect_value(t, count_cmds(ctx, DCmd_Text),         0) // no font

	// Verify the fill is the color we set.
	for c in ctx.draw_cmds {
		if r, ok := c.cmd.(DCmd_Rect); ok {
			testing.expect_value(t, r.color.r, 100)
			testing.expect_value(t, r.color.g, 50)
			testing.expect_value(t, r.color.b, 25)
		}
	}
}

@(test)
test_button_emits_click :: proc (t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)

	ctx := make_ctx(mem.tracking_allocator(&track))
	defer destroy_context(ctx)
	defer free(ctx, context.allocator)

	// Frame 1: build the button. No click expected.
	begin_frame(ctx, {10, 10}, 1)
	_, clicked := button("OK", id = 42)
	testing.expect(t, !clicked, "no click on initial frame")
	end_frame(ctx)

	// Frame 2: simulate a release on the same button.
	begin_frame(ctx, {10, 10}, 1)
	ctx.mouse_released = true
	_, clicked = button("OK", id = 42)
	testing.expect(t, clicked, "expected click on release")
	end_frame(ctx)

	// Frame 3: mouse moved away. Should not click again.
	begin_frame(ctx, {500, 500}, 1)
	_, clicked_again := button("OK", id = 42)
	testing.expect(t, !clicked_again, "no click when mouse moved away")
	end_frame(ctx)
}

@(test)
test_scroll_view_sets_scissor :: proc (t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)

	ctx := make_ctx(mem.tracking_allocator(&track))
	defer destroy_context(ctx)
	defer free(ctx, context.allocator)

	begin_frame(ctx, {0, 0}, 1)
	ok := scroll_view({200, 400}, id = 5)
	testing.expect(t, ok, "scroll_view should be active")
	end_frame(ctx)

	// scroll_view with .Clip flag should emit an open + close scissor.
	scissor_count := 0
	for c in ctx.draw_cmds {
		if _, ok := c.cmd.(DCmd_Scissor); ok do scissor_count += 1
	}
	testing.expect_value(t, scissor_count, 2)
}

@(test)
test_checkbox_toggles :: proc (t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)

	ctx := make_ctx(mem.tracking_allocator(&track))
	defer destroy_context(ctx)
	defer free(ctx, context.allocator)

	// Frame 1: fresh checkbox, default false.
	begin_frame(ctx, {0, 0}, 1)
	_, checked, changed := checkbox("Toggle", id = 7)
	testing.expect(t, !checked, "fresh checkbox should be false")
	testing.expect(t, !changed, "fresh checkbox should not be changed")
	end_frame(ctx)

	// Frame 2: simulate a click. We can't easily inject a press/release
	// in a single frame via the public API, so we manually set the
	// active_id and mouse_released flags.
	begin_frame(ctx, {0, 0}, 1)
	w, ok := ctx.by_id[7]
	testing.expect(t, ok, "checkbox should exist in hash after first frame")
	if ok {
		ctx.hovered_id     = w.id
		ctx.active_id      = w.id
		ctx.mouse_released = true
	}
	_, checked, changed = checkbox("Toggle", id = 7)
	testing.expect(t, checked, "checkbox should be true after click")
	testing.expect(t, changed, "checkbox should report changed")
	end_frame(ctx)
}

@(test)
test_no_memory_leak :: proc (t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)

	{
		ctx := make_ctx(mem.tracking_allocator(&track))
		defer destroy_context(ctx)
		defer free(ctx, context.allocator)

		// Run a bunch of frames with a non-trivial UI.
		for frame in 0..<10 {
			mx := f32(frame)
			begin_frame(ctx, {mx, mx}, 1)
			if panel("window", id = 1) {
				r: Rect = {{0, 0}, {100, 100}}
				_ = rect_cut(&r, .Y, .Min, Size_Pixels{20})
				if panel("body", id = 2) {
					_, _ = button("A", id = 10)
					_, _ = button("B", id = 11)
					_, _, _ = checkbox("C", id = 12)
					_, _, _ = slider("D", 0, 100, id = 13)
				}
			}
			end_frame(ctx)
		}
	}

	// After destroy, the tracking allocator should report no live
	// allocations that didn't get freed.
	leaks: int
	for _, entry in track.allocation_map {
		_ = entry
		leaks += 1
	}
	testing.expect_value(t, leaks, 0)
}
