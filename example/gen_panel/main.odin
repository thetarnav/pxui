// Panel asset generator — produces a 24x24 9-slice TGA with a 4px border
// inset. The center is a flat fill color, the borders are a contrasting
// color, and the corners are 1px diagonal accents. Output: example/assets/
// panel.tga. The example embeds the file with #load; karl2d's
// load_texture_from_bytes accepts TGA.

package main

import "core:bytes"
import "core:fmt"
import "core:image"
import "core:image/tga"
import "core:os"
import "core:path/filepath"

W :: 24
H :: 24
INSET :: 4

C_BORDER   :: [4]u8{ 90,  60,  30, 255}
C_BORDER_2 :: [4]u8{120,  90,  60, 255}
C_FILL     :: [4]u8{200, 170, 110, 255}
C_ACCENT   :: [4]u8{255, 230, 180, 255}

main :: proc () {
	buf: bytes.Buffer
	bytes.buffer_init_allocator(&buf, 0, W * H * 4, context.allocator)

	for y in 0..<H {
		for x in 0..<W {
			c: [4]u8
			switch {
			case x < INSET && y < INSET:                 c = C_ACCENT
			case x >= W - INSET && y < INSET:            c = C_BORDER_2
			case x < INSET && y >= H - INSET:            c = C_BORDER
			case x >= W - INSET && y >= H - INSET:       c = C_ACCENT
			case x < INSET || x >= W - INSET || y < INSET || y >= H - INSET:
				c = C_BORDER
			case:                                        c = C_FILL
			}
			bytes.buffer_write(&buf, c[:])
		}
	}

	img := image.Image{
		width    = W,
		height   = H,
		channels = 4,
		depth    = 8,
		pixels   = buf,
	}

	here := filepath.dir(#file)
	parts := []string{here, "assets", "panel.tga"}
	out_path, join_err := filepath.join(parts)
	if join_err != nil {
		fmt.eprintfln("join failed: %v", join_err)
		os.exit(1)
	}
	if err := os.make_directory(filepath.dir(out_path)); err != nil && err != .Exist {
		fmt.eprintfln("mkdir failed: %v", err)
		os.exit(1)
	}

	if err := tga.save_to_file(out_path, &img); err != nil {
		fmt.eprintfln("tga save failed: %v", err)
		os.exit(1)
	}
	fmt.printfln("wrote %s (%dx%d, %d bytes RGBA)", out_path, W, H, W * H * 4)
}
