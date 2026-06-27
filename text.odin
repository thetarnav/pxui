package pixui

//-------//
// TEXT //
//-------//

import "core:encoding/xml"
import "core:fmt"
import "core:strconv"
import "core:mem"

// A single glyph in a BMFont atlas. Coordinates are in source pixels.
Font_Glyph :: struct {
	src_x, src_y, src_w, src_h: u16,
	x_off, y_off, advance: i16,
	page, channel: u8,
}

// A bitmap font parsed from a BMFont XML file + one or more atlas PNGs.
Font :: struct {
	face:        string,
	line_height: i32,
	base:        i32,
	scale_w:     i32,
	scale_h:     i32,
	handle:      Font_Handle, // handle of the first page (single-page v0)
	pages:       []Texture_Handle, // one per <page>
	glyphs:      map[u32]Font_Glyph, // codepoint -> glyph
}

// Default font size when none is specified. Picked to match the typical
// line-height of the included fonts in the `fonts/` directory.
DEFAULT_FONT_SIZE :: f32(10)

load_font_from_bytes :: proc (
	xml_bytes: []u8,
	png_bytes: []u8, // single-page fonts only for v0
	backend:   ^Backend,
	allocator: mem.Allocator,
) -> ^Font {
	doc, err := xml.parse(xml_bytes, xml.Options{flags = {.Ignore_Unsupported}}, allocator=context.temp_allocator)
	if err != nil {
		fmt.eprintfln("pixui: failed to parse font xml: %v", err)
		return nil
	}

	// The parser stores the entire tree in doc.elements[]. Element 0 is the
	// root. We expect element 0 to be the <font> tag.
	if len(doc.elements) == 0 {
		fmt.eprintln("pixui: font xml has no elements")
		return nil
	}

    font_el_id: xml.Element_ID
    if doc.elements[0].ident == "font" {
        font_el_id = 0
    } else if el_id, found :=xml.find_child_by_ident(doc, 0, "font"); found {
        font_el_id = el_id
    } else {
        fmt.eprintln("pixui: font xml has no <font> root")
        return nil
    }

	font := new(Font, allocator)
	font.glyphs = make(map[u32]Font_Glyph, allocator)

	walk_font_xml(doc, font_el_id, font)

	// Single-page fonts only for v0.
	font.pages = make([]Texture_Handle, 1, allocator)
	font.pages[0] = backend_load_texture(backend, png_bytes)
	font.handle = Font_Handle(font.pages[0])
	return font
}

destroy_font :: proc (font: ^Font, allocator: mem.Allocator) {
	if font == nil { return }
	delete(font.glyphs)
	delete(font.pages)
	free(font, allocator)
}

@(private)
walk_font_xml :: proc (
	doc:    ^xml.Document,
	font_id: xml.Element_ID,
	font:   ^Font,
) {
	for v in doc.elements[font_id].value {
		child_id, is_id := v.(xml.Element_ID)
		if !is_id { continue }
		ident := doc.elements[child_id].ident

		switch ident {
		case "info":
			if val, ok := xml.find_attribute_val_by_key(doc, child_id, "face"); ok {
				font.face = val
			}
		case "common":
			if val, ok := xml.find_attribute_val_by_key(doc, child_id, "lineHeight"); ok {
				font.line_height = i32(atoi(val))
			}
			if val, ok := xml.find_attribute_val_by_key(doc, child_id, "base"); ok {
				font.base = i32(atoi(val))
			}
			if val, ok := xml.find_attribute_val_by_key(doc, child_id, "scaleW"); ok {
				font.scale_w = i32(atoi(val))
			}
			if val, ok := xml.find_attribute_val_by_key(doc, child_id, "scaleH"); ok {
				font.scale_h = i32(atoi(val))
			}
		case "chars":
			read_char_elements(doc, child_id, font)
		}
	}
}

@(private)
read_char_elements :: proc (doc: ^xml.Document, chars_id: xml.Element_ID, font: ^Font) {
	for v in doc.elements[chars_id].value {
		child_id := v.(xml.Element_ID) or_continue
		if doc.elements[child_id].ident != "char" do continue

		g: Font_Glyph
		codepoint: u32 = 0

		if val, ok := xml.find_attribute_val_by_key(doc, child_id, "id"); ok {
			codepoint = u32(atoi(val))
		}
		if val, ok := xml.find_attribute_val_by_key(doc, child_id, "x"); ok {
			g.src_x = u16(i32(atoi(val)))
		}
		if val, ok := xml.find_attribute_val_by_key(doc, child_id, "y"); ok {
			g.src_y = u16(i32(atoi(val)))
		}
		if val, ok := xml.find_attribute_val_by_key(doc, child_id, "width"); ok {
			g.src_w = u16(i32(atoi(val)))
		}
		if val, ok := xml.find_attribute_val_by_key(doc, child_id, "height"); ok {
			g.src_h = u16(i32(atoi(val)))
		}
		if val, ok := xml.find_attribute_val_by_key(doc, child_id, "xoffset"); ok {
			g.x_off = i16(i32(atoi(val)))
		}
		if val, ok := xml.find_attribute_val_by_key(doc, child_id, "yoffset"); ok {
			g.y_off = i16(i32(atoi(val)))
		}
		if val, ok := xml.find_attribute_val_by_key(doc, child_id, "xadvance"); ok {
			g.advance = i16(i32(atoi(val)))
		}
		if val, ok := xml.find_attribute_val_by_key(doc, child_id, "page"); ok {
			g.page = u8(i32(atoi(val)))
		}
		if val, ok := xml.find_attribute_val_by_key(doc, child_id, "chnl"); ok {
			g.channel = u8(i32(atoi(val)))
		}

		font.glyphs[codepoint] = g
	}
}

@(private)
atoi :: proc (s: string) -> int {
	v, _ := strconv.parse_int(s, 10)
	return v
}

// Each backend implements texture loading in its own way. The example wires
// this via the `Backend.load_texture_png` proc pointer.
@(private)
backend_load_texture :: proc (backend: ^Backend, png: []u8) -> Texture_Handle {
	return backend.load_texture_png(png)
}
