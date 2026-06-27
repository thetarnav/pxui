ODIN := odin

.PHONY: gen run check test test-verbose clean

# Generate the procedurally-made 9-slice panel asset.
gen:
	$(ODIN) run example/gen_panel

# Build and run the kitchen-sink example.
run: gen
	$(ODIN) run example

# Check the library alone.
check:
	$(ODIN) check . -vet

# Run the unit test suite. `odin test` builds with memory tracking enabled,
# which catches leaks across frame cycles and surface bad frees.
test:
	$(ODIN) test . -out:build/test -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true -define:ODIN_TEST_THREADS=1

# Run the test suite with verbose per-test output and debug symbols.
test-verbose:
	$(ODIN) test . -out:build/test -debug -define:ODIN_TEST_VERBOSE=true -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true -define:ODIN_TEST_THREADS=1

# Run a single test by name:  make test-one TEST_NAME=pixui.test_rect_cut_pixels
test-one:
	$(ODIN) test . -out:build/test -define:ODIN_TEST_NAMES=$(TEST_NAME) -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true -define:ODIN_TEST_THREADS=1

clean:
	rm -f example/assets/panel.tga pixui_example
