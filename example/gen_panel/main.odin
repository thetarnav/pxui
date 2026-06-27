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
import la "core:math/linalg"

W :: 24
H :: 24
INSET :: 4

Color :: [4]u8

color_lerp :: proc "contextless" (a, b: Color, t: f32) -> Color {
	return {
		u8(clamp(la.lerp(f32(a.r), f32(b.r), t), 0.0, 255.0)),
		u8(clamp(la.lerp(f32(a.g), f32(b.g), t), 0.0, 255.0)),
		u8(clamp(la.lerp(f32(a.b), f32(b.b), t), 0.0, 255.0)),
		u8(clamp(la.lerp(f32(a.a), f32(b.a), t), 0.0, 255.0)),
	}
}

WHITE  :: Color{255, 255, 255, 255}
BLACK  :: Color{  0,   0,   0, 255}
RED    :: Color{255,   0,   0, 255}
GREEN  :: Color{  0, 255,   0, 255}
BLUE   :: Color{  0,   0, 255, 255}
PURPLE :: Color{255,   0, 255, 255}

main :: proc () {
	buf: bytes.Buffer
	bytes.buffer_init_allocator(&buf, 0, W * H * 4, context.allocator)

	for y in 0..<H {
		for x in 0..<W {
            xp := f32(x) / W
            yp := f32(y) / H
            c: Color
			switch {
			case x < INSET && y < INSET:           c = RED    // LT corner
			case x >= W - INSET && y < INSET:      c = PURPLE // RT corner
			case x < INSET && y >= H - INSET:      c = BLUE   // LB corner
			case x >= W - INSET && y >= H - INSET: c = GREEN  // RB corner
			case x < INSET:                        c = color_lerp(RED,    BLUE,   yp) // L border
			case x >= W - INSET:                   c = color_lerp(PURPLE, GREEN,  yp) // R border
			case y < INSET:                        c = color_lerp(RED,    PURPLE, xp) // T border
			case y >= H - INSET:                   c = color_lerp(BLUE,   GREEN,  xp) // B border
            case:                                  c = color_lerp(BLACK,  WHITE, yp/2 + xp/2) // fill
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
