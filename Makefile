.PHONY: run debug run-karl2d build-debug-karl2d \
        run-cli \
        check test test-verbose \
        clean


# Default target
all: run


# Build and run the kitchen-sink example with the karl2d frontend.
run: atlas run-karl2d

debug: atlas build-debug-karl2d

run-karl2d:
	odin run example/karl2d

build-debug-karl2d:
	odin build example/karl2d -debug


# Build and run the CLI/readline frontend for debugging.
run-cli:
	odin run example/cli


atlas: assets/atlas.png assets/atlas.odin

assets/atlas.png assets/atlas.odin: assets/ui.aseprite
	odin run atlas-builder \
		-define:TEXTURES_DIR="assets" \
		-define:PACKAGE_NAME="assets" \
		-define:ATLAS_PNG_OUTPUT_PATH="assets/atlas.png" \
		-define:ATLAS_ODIN_OUTPUT_PATH="assets/atlas.odin" \
		-define:PALETTE_SRC_FILE="assets/ui.aseprite"


# Check the library alone.
check:
	odin check . -vet

# Run the unit test suite. `odin test` builds with memory tracking enabled,
# which catches leaks across frame cycles and surface bad frees.
test:
	odin test . \
		-out:build/test \
		-define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true \
		-define:ODIN_TEST_THREADS=1

# Run the test suite with verbose per-test output and debug symbols.
test-verbose:
	odin test . \
		-out:build/test \
		-debug \
		-define:ODIN_TEST_VERBOSE=true \
		-define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true \
		-define:ODIN_TEST_THREADS=1

# Run a single test by name:  make test-one TEST_NAME=pxui.test_rect_cut_pixels
test-one:
	odin test . \
		 -out:build/test \
		 -define:ODIN_TEST_NAMES=$(TEST_NAME) \
		 -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true \
		 -define:ODIN_TEST_THREADS=1

clean:
	rm -f pxui_example pxui_cli pxui_karl2d
