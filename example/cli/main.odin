// CLI/readline frontend for the Pixui example. Provides a REPL for
// debugging without a graphics backend. Reads commands from stdin and
// prints results to stdout.
//
// Commands:
//   run [N]           run N frames (default 1)
//   mouse X Y         set the mouse position
//   press             simulate a mouse press on the next frame
//   release           simulate a mouse release on the next frame
//   hold              toggle mouse-held flag
//   wheel DX DY       simulate a wheel delta
//   resize W H        set the window size
//   tree              dump the element tree
//   find NAME         find elements whose type name contains NAME
//   state             print input-component state
//   help              show this help
//   quit / exit       exit

package main

import "core:fmt"
import "core:io"
import "core:os"
import "core:strconv"
import "core:strings"
import app ".."
import px "../../"

UI_W, UI_H :: 320, 200

// Simulated input state.
State :: struct {
	ws:              app.Vec2i,
	mouse:           app.Vec2i,
	pressed:         bool,
	released:        bool,
	held:            bool,
	wheel:           app.Vec2,
	pending_press:   bool,
	pending_release: bool,
}

main :: proc () {
	state := State{
		ws    = {UI_W, UI_H},
		mouse = {0, 0},
	}

	// app.init returns bool. If false, initialization failed.
	if !app.init() {
		fmt.eprintln("Failed to initialize app")
		os.exit(1)
	}
	defer app.shutdown()

	fmt.println("Pixui CLI — type 'help' for commands, 'quit' to exit.")
	fmt.println()

	for {
		fmt.print("pxui> ")
		line, ok := read_line()
		if !ok do break

		run_command(&state, strings.trim_space(line))
	}
}

run_command :: proc (state: ^State, line: string) {
	if line == "" do return

	parts := strings.split(line, " ")
	cmd := parts[0]
	args := parts[1:]

	switch cmd {
	case "help", "?":
		print_help()
	case "quit", "exit", "q":
		os.exit(0)
	case "run":
		n_str := "1"
		if len(args) > 0 do n_str = args[0]
		n := strconv.parse_int(n_str) or_else 1
		run_frames(state, n)
	case "mouse":
		if len(args) < 2 {
			fmt.println("usage: mouse X Y")
			return
		}
		state.mouse.x = strconv.parse_int(args[0]) or_else 0
		state.mouse.y = strconv.parse_int(args[1]) or_else 0
	case "press":
		state.pending_press = true
		fmt.println("(next frame: mouse pressed)")
	case "release":
		state.pending_release = true
		fmt.println("(next frame: mouse released)")
	case "hold":
		state.held = !state.held
		if state.held do fmt.println("mouse held: on")
		else do fmt.println("mouse held: off")
	case "wheel":
		if len(args) < 2 {
			fmt.println("usage: wheel DX DY")
			return
		}
		state.wheel.x = f32(strconv.parse_int(args[0]) or_else 0)
		state.wheel.y = f32(strconv.parse_int(args[1]) or_else 0)
	case "resize":
		if len(args) < 2 {
			fmt.println("usage: resize W H")
			return
		}
		state.ws.x = strconv.parse_int(args[0]) or_else UI_W
		state.ws.y = strconv.parse_int(args[1]) or_else UI_H
	case "tree":
		fmt.print(dump_tree())
	case "find":
		if len(args) < 1 {
			fmt.println("usage: find NAME")
			return
		}
		name := strings.join(args, " ")
		matches := find(name)
		if len(matches) == 0 {
			fmt.println("no matches")
		} else {
			for m in matches do fmt.println(m)
		}
	case "state":
		print_state()
	case:
		fmt.printf("unknown command: %s (type 'help')\n", cmd)
	}
}

run_frames :: proc (state: ^State, n: int) {
	for _ in 0..<n {
		pressed  := state.pressed || state.pending_press
		released := state.released || state.pending_release
		held     := state.held || state.pending_press

		app.frame(
			mouse          = state.mouse,
			mouse_pressed  = pressed,
			mouse_released = released,
			mouse_held     = held,
			wheel_delta    = state.wheel,
			ws             = state.ws,
		)

		// Consume one-shot events.
		state.pressed         = state.held && !state.pending_release
		state.released        = false
		state.pending_press   = false
		state.pending_release = false
		state.wheel           = {0, 0}
	}
}

print_state :: proc () {
	fmt.println("Input state:")
	fmt.printf("  show_cross      = %v\n", app.show_cross)
	fmt.printf("  inner_pad       = %v\n", app.inner_pad)
	fmt.printf("  inner_color_idx = %v\n", app.inner_color_idx)
	fmt.printf("  cross_size_f    = %v\n", app.cross_size_f)
}

print_help :: proc () {
	fmt.println("Commands:")
	fmt.println("  run [N]           run N frames (default 1)")
	fmt.println("  mouse X Y         set the mouse position")
	fmt.println("  press             simulate mouse press on next frame")
	fmt.println("  release           simulate mouse release on next frame")
	fmt.println("  hold              toggle mouse-held flag")
	fmt.println("  wheel DX DY       set the wheel delta (consumed each frame)")
	fmt.println("  resize W H        set the window size")
	fmt.println("  tree              dump the element tree")
	fmt.println("  find NAME         find elements whose type name contains NAME")
	fmt.println("  state             print input-component state")
	fmt.println("  help              show this help")
	fmt.println("  quit / exit       exit")
}

// Read a line from stdin (up to and including '\n').
// Returns the line (without the trailing newline) and whether the read succeeded.
read_line :: proc () -> (string, bool) {
	buf: [4096]byte
	line_len := 0
	for line_len < len(buf) {
		n, err := os.read(os.stdin, buf[line_len:line_len+1])
		if err != 0 || n == 0 {
			if line_len == 0 do return "", false
			break
		}
		if buf[line_len] == '\n' do break
		line_len += 1
	}
	// Strip trailing newline(s).
	end := line_len
	for end > 0 && (buf[end-1] == '\n' || buf[end-1] == '\r') {
		end -= 1
	}
	return strings.clone(string(buf[:end]), context.temp_allocator), true
}

dump_tree :: proc () -> string {
	sb := strings.builder_make(context.temp_allocator)
	w := strings.to_writer(&sb)
	px.debug_tree_display_write(w, px.element_root())
	return strings.to_string(sb)
}

find :: proc (name: string) -> []string {
	tree := dump_tree()
	matches := make([dynamic]string, context.temp_allocator)
	lower_name := strings.to_lower(name)
	for line in strings.split_lines(tree) {
		if strings.contains(strings.to_lower(line), lower_name) {
			append(&matches, strings.clone(line, context.temp_allocator))
		}
	}
	return matches[:]
}
