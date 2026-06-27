ODIN := odin

.PHONY: all gen run check test test-verbose clean

all: gen run

# Generate the procedurally-made 9-slice panel asset.
gen:
	$(ODIN) run example/gen_panel

# Build and run the kitchen-sink example.
run: gen
	$(ODIN) run example -file \
		-- \
		-define:ODIN_VET=1

# Check the library alone.
check:
	$(ODIN) check .

# Run the unit test suite. `odin test` builds with memory tracking enabled,
# which catches leaks across frame cycles and surface bad frees.
test:
	$(ODIN) test .

# Run the test suite with verbose per-test output and debug symbols.
test-verbose:
	$(ODIN) test . -debug -define:ODIN_TEST_VERBOSE=true

# Run a single test by name:  make test-one TEST_NAME=pixui.test_rect_cut_pixels
test-one:
	$(ODIN) test . -define:ODIN_TEST_NAMES=$(TEST_NAME)

clean:
	rm -f example/assets/panel.tga pixui_example
