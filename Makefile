.PHONY: run check test test-verbose clean

# Build and run the kitchen-sink example.
run:
	odin run example

# Check the library alone.
check:
	odin check . -vet

# Run the unit test suite. `odin test` builds with memory tracking enabled,
# which catches leaks across frame cycles and surface bad frees.
test:
	odin test . -out:build/test -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true -define:ODIN_TEST_THREADS=1

# Run the test suite with verbose per-test output and debug symbols.
test-verbose:
	odin test . -out:build/test -debug -define:ODIN_TEST_VERBOSE=true -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true -define:ODIN_TEST_THREADS=1

# Run a single test by name:  make test-one TEST_NAME=pxui.test_rect_cut_pixels
test-one:
	odin test . -out:build/test -define:ODIN_TEST_NAMES=$(TEST_NAME) -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true -define:ODIN_TEST_THREADS=1

clean:
	rm -f example/assets/panel.tga pxui_example
