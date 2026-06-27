ODIN := odin

.PHONY: all gen run clean

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

clean:
	rm -f example/assets/panel.tga pixui_example
