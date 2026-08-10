package pxui

import "core:os"
import "core:io"
import "core:strings"
import "core:fmt"
import "base:runtime"
import "core:time"

Trace :: struct {
	start:           time.Tick,
	min, max, total: time.Duration,
	runs:            int,
}
_traces: map[string]Trace

@init _init_trace :: proc "contextless" () {
	context = runtime.default_context()

	_traces = make(type_of(_traces))
}
@fini _fini_trace :: proc "contextless" () {
	context = runtime.default_context()

	fmt.println("=== TRACE ===")

	_print_table_begin()
	_print_table_add("name", "avg", "min", "max", "runs")
	for name, trace in _traces {
		avg := trace.total / time.Duration(trace.runs)
		_print_table_add(name, avg, trace.min, trace.max, trace.runs)
	}
	_print_table_end()

	fmt.println()
}

_print_table_current: struct {
	widths:  [dynamic]int,
	content: [dynamic][]string,
}

_print_table_begin :: proc (loc := #caller_location) {
	_print_table_current.widths  = make([dynamic]int,      context.temp_allocator, loc=loc)
	_print_table_current.content = make([dynamic][]string, context.temp_allocator, loc=loc)
}
_print_table_add :: proc (items: ..any) {

	resize(&_print_table_current.widths, max(len(_print_table_current.widths), len(items)))

	row := make([dynamic]string, 0, len(items), context.temp_allocator)

	for item, i in items {

		str := fmt.tprint(item)
		append(&row, str)

		length: int
		for _ in str do length += 1

		_print_table_current.widths[i] = max(length, _print_table_current.widths[i])
	}

	append(&_print_table_current.content, row[:])
}
_print_table_end :: proc (loc := #caller_location) {

	cap := len(_print_table_current.content) // \n
	for width in _print_table_current.widths {
		cap += (width + 1) * len(_print_table_current.content) // str + space
	}

	sb := strings.builder_make_len_cap(0, cap, context.temp_allocator, loc)
	w := strings.to_writer(&sb)

	for row in _print_table_current.content {
		for str, i in row {
			io.write_string(w, str)

			length: int
			for _ in str do length += 1

			width := _print_table_current.widths[i]
			if i < len(row)-1 do width += 1

			for _ in 0..<width - length {
				io.write_rune(w, ' ')
			}
		}

		io.write_rune(w, '\n')
	}

	os.write_string(os.stdout, strings.to_string(sb))

	_print_table_current = {}
}
@(deferred_in=_print_table_end)
_print_table :: proc (loc := #caller_location) {
	_print_table_begin(loc)
}

trace_begin :: proc (name: string, loc := #caller_location) {

	trace, in_traces := &_traces[name]
	if !in_traces {
		_traces[name] = {}
		trace, _ = &_traces[name]
	}

	assert(trace.start == {}, loc=loc)

	trace.start = time.tick_now()
}
trace_end :: proc (name: string, loc := #caller_location) {

	trace, in_traces := &_traces[name]

	assert(in_traces && trace.start != {}, loc=loc)

	duration := time.tick_since(trace.start)

	trace.total += duration
	trace.runs  += 1
	trace.max    = max(trace.max, duration)
	trace.min    = min(trace.min, duration) if trace.min != time.Duration(0) else duration
	trace.start  = {}
}
@(deferred_in=trace_end)
trace :: proc (name: string, loc := #caller_location) {
	trace_begin(name, loc)
}
