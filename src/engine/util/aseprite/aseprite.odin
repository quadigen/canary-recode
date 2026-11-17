/*
	aseprite - an Odin port of cute_aseprite.h v1.04 (https://github.com/RandyGaul/cute_headers)

	Parses .ase / .aseprite files. The whole file is parsed at once and a fully populated `Ase`
	is handed back. Every frame also gets its cels blended together into `frame.pixels`.

	Usage:

		ase, err := aseprite.load_from_file("data/player.aseprite")
		if err != .None { ... }
		defer aseprite.destroy(ase)

		for frame in ase.frames {
			// frame.pixels is []Color of length ase.w * ase.h, frame.duration_ms is the delay.
		}

	Differences from the C version:

	- Inflate comes from `core:compress/zlib`; the hand-written inflater is gone.
	- Malformed input returns an `Error` instead of tripping an assert / reading out of bounds.
	  Every read is bounds-checked and confined to its chunk.
	- No fixed-size arrays (CUTE_ASEPRITE_MAX_*), everything is dynamic.
	- Layers refer to their parent and cels refer to their layer by index (pointers into a growing
	  array are not stable).
	- Strings are cloned into the allocator you pass to the loader, and freed by `destroy`.
	- Fixes: cel-extra chunks now attach to the cel that precedes them (the C version wrote to the
	  *next* cel slot), old 0x0004 palette packets accumulate their "skip" count as the spec says,
	  group visibility is checked up the whole parent chain, and fixed-point numbers are real
	  16.16 values.

	Limitations (same as the original): only the "normal" blend mode is composited, sRGB / ICC
	profiles are parsed but ignored when blending, and tilemap cels are skipped.
*/
package aseprite

import "base:runtime"
import "core:compress/deflate"
import "core:log"
import "core:os"
import "core:strings"

Color :: struct {
	r, g, b, a: u8,
}

Fixed :: distinct i32

fixed_to_f32 :: proc "contextless" (f: Fixed) -> f32 {
	return f32(f) / 65536.0
}

UData :: struct {
	has_color: bool,
	color:     Color,
	has_text:  bool,
	text:      string,
}

Layer_Flag :: enum u16 {
	Visible            = 0,
	Editable           = 1,
	Lock_Movement      = 2,
	Background         = 3,
	Prefer_Linked_Cels = 4,
	Collapsed          = 5,
	Reference          = 6,
}
Layer_Flags :: bit_set[Layer_Flag;u16]

Layer_Type :: enum u16 {
	Normal  = 0,
	Group   = 1,
	Tilemap = 2,
}

Layer :: struct {
	flags:   Layer_Flags,
	type:    Layer_Type,
	name:    string,
	parent:  int, // index into Ase.layers, -1 if top level
	opacity: f32,
	udata:   UData,
}

Cel_Extra :: struct {
	precise_bounds_are_set: bool,
	precise_x, precise_y:   Fixed,
	w, h:                   Fixed,
}

Cel :: struct {
	layer:              int, // index into Ase.layers
	pixels:             []u8, // raw pixels in the file's color mode, nil for linked / unsupported cels
	w, h:               int,
	x, y:               int,
	opacity:            f32,
	is_linked:          bool,
	linked_frame_index: int,
	has_extra:          bool,
	extra:              Cel_Extra,
	udata:              UData,
}

Frame :: struct {
	duration_ms: int,
	pixels:      []Color, // blended result, Ase.w * Ase.h
	cels:        [dynamic]Cel,
}

Animation_Direction :: enum u8 {
	Forwards,
	Backwards,
	Ping_Pong,
	Ping_Pong_Reverse,
}

Tag :: struct {
	from_frame:               int,
	to_frame:                 int,
	loop_animation_direction: Animation_Direction,
	repeat:                   int,
	r, g, b:                  u8,
	name:                     string,
	udata:                    UData,
}

Slice :: struct {
	name:                  string,
	frame_number:          int,
	origin_x, origin_y:    int,
	w, h:                  int,
	has_center_as_9_slice: bool,
	center_x, center_y:    int,
	center_w, center_h:    int,
	has_pivot:             bool,
	pivot_x, pivot_y:      int,
	udata:                 UData,
}

Palette_Entry :: struct {
	color:      Color,
	color_name: string,
}

Color_Profile_Type :: enum u16 {
	None,
	SRGB,
	Embedded_ICC,
}

Color_Profile :: struct {
	type:             Color_Profile_Type,
	use_fixed_gamma:  bool,
	gamma:            Fixed,
	icc_profile_data: []u8,
}

Mode :: enum {
	RGBA,
	Grayscale,
	Indexed,
}

Ase :: struct {
	mode:                            Mode,
	w, h:                            int,
	transparent_palette_entry_index: int,
	number_of_colors:                int,
	pixel_w, pixel_h:                int,
	grid_x, grid_y:                  int,
	grid_w, grid_h:                  int,
	has_color_profile:               bool,
	color_profile:                   Color_Profile,
	palette:                         [dynamic]Palette_Entry,
	layers:                          [dynamic]Layer,
	frames:                          []Frame,
	tags:                            [dynamic]Tag,
	slices:                          [dynamic]Slice,
	allocator:                       Allocator,
}

Allocator :: runtime.Allocator

Error :: enum {
	None,
	File_Read_Failed,
	Truncated, // input ended early, or a chunk read past its own end
	Bad_File_Magic,
	Bad_Frame_Magic,
	Unsupported_Color_Depth,
	Invalid_Layer_Hierarchy,
	Invalid_Layer_Index,
	Invalid_Cel,
	Inflate_Failed,
}

// ---------------------------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------------------------

load_from_file :: proc(path: string, allocator := context.allocator) -> (ase: ^Ase, err: Error) {
	data, read_err := os.read_entire_file(path, allocator)
	if read_err != nil {
		return nil, .File_Read_Failed
	}
	defer delete(data, allocator)
	return load_from_memory(data, allocator)
}

load_from_memory :: proc(data: []u8, allocator := context.allocator) -> (ase: ^Ase, err: Error) {
	context.allocator = allocator

	ase = new(Ase)
	ase.allocator = allocator
	defer if err != .None {
		destroy(ase)
		ase = nil
	}

	p := Parser {
		r = Reader{data = data},
		full = data,
		ase = ase,
	}
	defer delete(p.layer_stack)
	r := &p.r

	// Header (128 bytes).
	skip(r, 4) // file size
	if read_u16(r) != 0xA5E0 {
		return ase, .Bad_File_Magic
	}
	frame_count := int(read_u16(r))
	ase.w = int(read_u16(r))
	ase.h = int(read_u16(r))
	bits_per_pixel := int(read_u16(r))
	header_flags := read_u32(r)
	speed := int(read_u16(r))
	skip(r, 8) // zeroed
	ase.transparent_palette_entry_index = int(read_u8(r))
	skip(r, 3)
	ase.number_of_colors = int(read_u16(r))
	ase.pixel_w = int(read_u8(r))
	ase.pixel_h = int(read_u8(r))
	ase.grid_x = int(read_i16(r))
	ase.grid_y = int(read_i16(r))
	ase.grid_w = int(read_u16(r))
	ase.grid_h = int(read_u16(r))
	skip(r, 84)
	if r.overrun {
		return ase, .Truncated
	}

	switch bits_per_pixel {
	case 32:
		ase.mode = .RGBA
	case 16:
		ase.mode = .Grayscale
	case 8:
		ase.mode = .Indexed
	case:
		return ase, .Unsupported_Color_Depth
	}
	p.bpp = bits_per_pixel / 8
	p.valid_layer_opacity = header_flags & 1 != 0

	ase.frames = make([]Frame, frame_count)

	for &frame in ase.frames {
		skip(r, 4) // frame size
		if read_u16(r) != 0xF1FA {
			return ase, .Bad_Frame_Magic
		}
		chunk_count := int(read_u16(r))
		frame.duration_ms = int(read_u16(r))
		if frame.duration_ms == 0 {
			frame.duration_ms = speed
		}
		skip(r, 2)
		if new_chunk_count := read_u32(r); new_chunk_count != 0 {
			chunk_count = int(new_chunk_count)
		}
		if r.overrun {
			return ase, .Truncated
		}

		for _ in 0 ..< chunk_count {
			chunk_start := r.pos
			chunk_size := int(read_u32(r))
			chunk_type := read_u16(r)
			chunk_end := chunk_start + chunk_size
			if r.overrun || chunk_size < 6 || chunk_end > len(data) {
				return ase, .Truncated
			}

			// Confine all reads to this chunk.
			r.data = data[:chunk_end]
			chunk_err := parse_chunk(&p, &frame, chunk_type, chunk_end)
			if chunk_err != .None {
				return ase, chunk_err
			}
			if r.overrun {
				return ase, .Truncated
			}
			r.data = data
			r.pos = chunk_end
		}
	}

	// Blend all cel pixels into each frame, for convenience.
	for &frame in ase.frames {
		compose_frame(ase, &frame)
	}

	return ase, .None
}

destroy :: proc(ase: ^Ase) {
	if ase == nil {
		return
	}
	context.allocator = ase.allocator

	for &frame in ase.frames {
		delete(frame.pixels)
		for &cel in frame.cels {
			delete(cel.pixels)
			delete(cel.udata.text)
		}
		delete(frame.cels)
	}
	delete(ase.frames)

	for &layer in ase.layers {
		delete(layer.name)
		delete(layer.udata.text)
	}
	delete(ase.layers)

	for &tag in ase.tags {
		delete(tag.name)
		delete(tag.udata.text)
	}
	delete(ase.tags)

	for &slice in ase.slices {
		delete(slice.name)
		delete(slice.udata.text)
	}
	delete(ase.slices)

	for &entry in ase.palette {
		delete(entry.color_name)
	}
	delete(ase.palette)

	delete(ase.color_profile.icc_profile_data)
	free(ase)
}

// Follows linked cels to the cel that actually owns the pixels. Returns nil if the link is broken.
resolve_cel :: proc(ase: ^Ase, cel: ^Cel) -> ^Cel {
	cel := cel
	for hops := 0; cel.is_linked; hops += 1 {
		if hops > len(ase.frames) ||
		   cel.linked_frame_index < 0 ||
		   cel.linked_frame_index >= len(ase.frames) {
			return nil
		}
		target := &ase.frames[cel.linked_frame_index]
		found: ^Cel
		for &c in target.cels {
			if c.layer == cel.layer {
				found = &c
				break
			}
		}
		if found == nil {
			return nil
		}
		cel = found
	}
	return cel
}

// True if the layer and every group above it is visible.
layer_is_visible :: proc(ase: ^Ase, layer_index: int) -> bool {
	i := layer_index
	for hops := 0; i >= 0 && hops <= len(ase.layers); hops += 1 {
		if .Visible not_in ase.layers[i].flags {
			return false
		}
		i = ase.layers[i].parent
	}
	return true
}

// ---------------------------------------------------------------------------------------------
// Byte reader
// ---------------------------------------------------------------------------------------------

@(private)
Reader :: struct {
	data:    []u8,
	pos:     int,
	overrun: bool, // set once any read went past the end of `data`; reads then return zeros
}

@(private)
read_u8 :: proc(r: ^Reader) -> u8 {
	if r.pos + 1 > len(r.data) {
		r.overrun = true
		return 0
	}
	v := r.data[r.pos]
	r.pos += 1
	return v
}

@(private)
read_u16 :: proc(r: ^Reader) -> u16 {
	if r.pos + 2 > len(r.data) {
		r.overrun = true
		return 0
	}
	v := u16(r.data[r.pos]) | u16(r.data[r.pos + 1]) << 8
	r.pos += 2
	return v
}

@(private)
read_u32 :: proc(r: ^Reader) -> u32 {
	if r.pos + 4 > len(r.data) {
		r.overrun = true
		return 0
	}
	d := r.data[r.pos:]
	v := u32(d[0]) | u32(d[1]) << 8 | u32(d[2]) << 16 | u32(d[3]) << 24
	r.pos += 4
	return v
}

@(private)
read_i16 :: proc(r: ^Reader) -> i16 {return i16(read_u16(r))}

@(private)
read_i32 :: proc(r: ^Reader) -> i32 {return i32(read_u32(r))}

@(private)
read_fixed :: proc(r: ^Reader) -> Fixed {return Fixed(read_i32(r))}

@(private)
skip :: proc(r: ^Reader, n: int) {
	if n < 0 || r.pos + n > len(r.data) {
		r.overrun = true
		return
	}
	r.pos += n
}

@(private)
remaining :: proc(r: ^Reader) -> int {
	return len(r.data) - r.pos
}

// Length-prefixed string that points into the input; clone it if you keep it.
@(private)
read_string_view :: proc(r: ^Reader) -> string {
	n := int(read_u16(r))
	if r.overrun || r.pos + n > len(r.data) {
		r.overrun = true
		return ""
	}
	s := string(r.data[r.pos:r.pos + n])
	r.pos += n
	return s
}

@(private)
read_string :: proc(r: ^Reader) -> string {
	s := read_string_view(r)
	if len(s) == 0 {
		return ""
	}
	return strings.clone(s)
}

// ---------------------------------------------------------------------------------------------
// Chunk parsing
// ---------------------------------------------------------------------------------------------

@(private)
UData_Kind :: enum {
	None,
	Layer,
	Cel,
	Slice,
}

@(private)
Parser :: struct {
	r:                   Reader,
	full:                []u8,
	ase:                 ^Ase,
	bpp:                 int,
	valid_layer_opacity: bool,
	layer_stack:         [dynamic]int, // layer_stack[child_level] = most recent layer at that depth
	udata_kind:          UData_Kind,
	udata_index:         int,
	was_on_tags:         bool,
	tag_index:           int,
}

@(private)
parse_chunk :: proc(p: ^Parser, frame: ^Frame, chunk_type: u16, chunk_end: int) -> Error {
	r := &p.r
	ase := p.ase

	// A user data chunk belongs to the chunk right before it. Anything that can't carry user data
	// resets the target (cel extra chunks are the exception, they extend the cel before them).
	if chunk_type != 0x2020 && chunk_type != 0x2006 {
		p.udata_kind = .None
	}

	switch chunk_type {
	case 0x0004:
		// Old palette chunk (used when there are no colors with alpha in the palette).
		packets := int(read_u16(r))
		index := 0
		for _ in 0 ..< packets {
			index += int(read_u8(r)) // entries to skip since the previous packet
			count := int(read_u8(r))
			if count == 0 {
				count = 256
			}
			if r.overrun {
				return .Truncated
			}
			palette_ensure_size(ase, index + count)
			for _ in 0 ..< count {
				entry := &ase.palette[index]
				entry.color = Color{read_u8(r), read_u8(r), read_u8(r), 255}
				index += 1
			}
		}

	case 0x2004:
		// Layer chunk.
		layer: Layer
		flags := read_u16(r)
		layer.flags = transmute(Layer_Flags)flags
		layer.type = Layer_Type(read_u16(r))
		child_level := int(read_u16(r))
		skip(r, 4) // default layer width / height (ignored)
		blend_mode := read_u16(r)
		if blend_mode != 0 {
			log.warnf(
				"aseprite: unsupported blend mode %d, layer will be blended as normal",
				blend_mode,
			)
		}
		layer.opacity = f32(read_u8(r)) / 255.0
		if !p.valid_layer_opacity {
			layer.opacity = 1.0
		}
		skip(r, 3)
		if r.overrun {
			return .Truncated
		}

		if child_level > len(p.layer_stack) {
			return .Invalid_Layer_Hierarchy
		}
		layer.name = read_string(r)
		layer.parent = -1
		resize(&p.layer_stack, child_level + 1)
		p.layer_stack[child_level] = len(ase.layers)
		if child_level > 0 {
			layer.parent = p.layer_stack[child_level - 1]
		}

		append(&ase.layers, layer)
		p.udata_kind = .Layer
		p.udata_index = len(ase.layers) - 1

	case 0x2005:
		// Cel chunk.
		cel: Cel
		cel.layer = int(read_u16(r))
		cel.x = int(read_i16(r))
		cel.y = int(read_i16(r))
		cel.opacity = f32(read_u8(r)) / 255.0
		cel_type := read_u16(r)
		skip(r, 7)
		if r.overrun {
			return .Truncated
		}
		if cel.layer >= len(ase.layers) {
			return .Invalid_Layer_Index
		}

		switch cel_type {
		case 0:
			// Raw cel.
			cel.w = int(read_u16(r))
			cel.h = int(read_u16(r))
			size := cel.w * cel.h * p.bpp
			if r.overrun || size > remaining(r) {
				return .Invalid_Cel
			}
			cel.pixels = make([]u8, size)
			copy(cel.pixels, r.data[r.pos:r.pos + size])
			r.pos += size

		case 1:
			// Linked cel.
			cel.is_linked = true
			cel.linked_frame_index = int(read_u16(r))
			if cel.linked_frame_index >= len(ase.frames) {
				return .Invalid_Cel
			}

		case 2:
			// Compressed image cel (zlib stream, RFC 1950).
			cel.w = int(read_u16(r))
			cel.h = int(read_u16(r))
			if r.overrun {
				return .Truncated
			}
			size := cel.w * cel.h * p.bpp
			stream := r.data[r.pos:chunk_end]
			r.pos = chunk_end
			pixels, ok := inflate_cel(stream, size)
			if !ok {
				return .Inflate_Failed
			}
			cel.pixels = pixels

		case:
			// Compressed tilemap (3) or something newer. Keep the cel so that user data still
			// lines up, but it has no pixels and is skipped when blending.
			log.warnf("aseprite: unsupported cel type %d, cel will be ignored", cel_type)
		}

		append(&frame.cels, cel)
		p.udata_kind = .Cel
		p.udata_index = len(frame.cels) - 1

	case 0x2006:
		// Cel extra chunk: applies to the cel that came right before it.
		if len(frame.cels) == 0 {
			break
		}
		cel := &frame.cels[len(frame.cels) - 1]
		cel.has_extra = true
		cel.extra.precise_bounds_are_set = read_u32(r) != 0
		cel.extra.precise_x = read_fixed(r)
		cel.extra.precise_y = read_fixed(r)
		cel.extra.w = read_fixed(r)
		cel.extra.h = read_fixed(r)

	case 0x2007:
		// Color profile chunk.
		ase.has_color_profile = true
		cp := &ase.color_profile
		cp.type = Color_Profile_Type(read_u16(r))
		cp.use_fixed_gamma = read_u16(r) & 1 != 0
		cp.gamma = read_fixed(r)
		skip(r, 8)
		if cp.type == .Embedded_ICC {
			n := int(read_u32(r))
			if r.overrun || n > remaining(r) {
				return .Truncated
			}
			delete(cp.icc_profile_data)
			cp.icc_profile_data = make([]u8, n)
			copy(cp.icc_profile_data, r.data[r.pos:r.pos + n])
			r.pos += n
		}

	case 0x2018:
		// Tags chunk.
		count := int(read_u16(r))
		skip(r, 8)
		for _ in 0 ..< count {
			tag: Tag
			tag.from_frame = int(read_u16(r))
			tag.to_frame = int(read_u16(r))
			tag.loop_animation_direction = Animation_Direction(read_u8(r))
			tag.repeat = int(read_u16(r))
			skip(r, 6)
			tag.r = read_u8(r)
			tag.g = read_u8(r)
			tag.b = read_u8(r)
			skip(r, 1)
			if r.overrun {
				return .Truncated
			}
			tag.name = read_string(r)
			append(&ase.tags, tag)
		}
		p.was_on_tags = true

	case 0x2019:
		// Palette chunk.
		entry_count := int(read_u32(r))
		first := int(read_u32(r))
		last := int(read_u32(r))
		skip(r, 8)
		if r.overrun {
			return .Truncated
		}
		if first <= last {
			// Each entry takes at least 6 bytes, which bounds the allocation by the chunk size.
			if (last - first + 1) * 6 > remaining(r) {
				return .Truncated
			}
			palette_ensure_size(ase, max(entry_count, last + 1))
		}
		resize(&ase.palette, entry_count)
		for k in first ..= last {
			has_name := read_u16(r) & 1 != 0
			entry := Palette_Entry {
				color = Color{read_u8(r), read_u8(r), read_u8(r), read_u8(r)},
			}
			if has_name {
				entry.color_name = read_string(r)
			}
			if r.overrun {
				return .Truncated
			}
			if k < len(ase.palette) {
				delete(ase.palette[k].color_name)
				ase.palette[k] = entry
			} else {
				delete(entry.color_name)
			}
		}

	case 0x2020:
		// User data chunk: belongs to whatever came right before it.
		udata: ^UData
		switch p.udata_kind {
		case .Layer:
			udata = &ase.layers[p.udata_index].udata
		case .Cel:
			udata = &frame.cels[p.udata_index].udata
		case .Slice:
			udata = &ase.slices[p.udata_index].udata
		case .None:
			// After a tags chunk, user data chunks apply to the tags in order.
			if p.was_on_tags && p.tag_index < len(ase.tags) {
				udata = &ase.tags[p.tag_index].udata
				p.tag_index += 1
			}
		}
		p.udata_kind = .None
		if udata == nil {
			break
		}
		flags := read_u32(r)
		if flags & 1 != 0 {
			udata.has_text = true
			delete(udata.text)
			udata.text = read_string(r)
		}
		if flags & 2 != 0 {
			udata.has_color = true
			udata.color = Color{read_u8(r), read_u8(r), read_u8(r), read_u8(r)}
		}

	case 0x2022:
		// Slice chunk.
		count := int(read_u32(r))
		flags := read_u32(r)
		skip(r, 4)
		name := read_string_view(r)
		if r.overrun {
			return .Truncated
		}
		if count * 20 > remaining(r) { 	// each key is at least 20 bytes
			return .Truncated
		}
		for _ in 0 ..< count {
			slice: Slice
			slice.frame_number = int(read_u32(r))
			slice.origin_x = int(read_i32(r))
			slice.origin_y = int(read_i32(r))
			slice.w = int(read_u32(r))
			slice.h = int(read_u32(r))
			if flags & 1 != 0 {
				// 9-patch slice.
				slice.has_center_as_9_slice = true
				slice.center_x = int(read_i32(r))
				slice.center_y = int(read_i32(r))
				slice.center_w = int(read_u32(r))
				slice.center_h = int(read_u32(r))
			}
			if flags & 2 != 0 {
				slice.has_pivot = true
				slice.pivot_x = int(read_i32(r))
				slice.pivot_y = int(read_i32(r))
			}
			if r.overrun {
				return .Truncated
			}
			slice.name = strings.clone(name)
			append(&ase.slices, slice)
			p.udata_kind = .Slice
			p.udata_index = len(ase.slices) - 1
		}

	case:
	// Unknown chunk: skipped by the caller.
	}

	return .None
}

@(private)
palette_ensure_size :: proc(ase: ^Ase, n: int) {
	if len(ase.palette) < n {
		resize(&ase.palette, n)
	}
}

@(private)
inflate_cel :: proc(stream: []u8, expected: int) -> (pixels: []u8, ok: bool) {
	if expected == 0 {
		return nil, true
	}
	buf: [dynamic]u8
	defer delete(buf)

	if err := deflate.inflate_zlib(&buf, stream, expected); err != nil {
		return nil, false
	}
	if len(buf) < expected {
		return nil, false
	}
	pixels = make([]u8, expected)
	copy(pixels, buf[:expected])
	return pixels, true
}

// ---------------------------------------------------------------------------------------------
// Blending
// ---------------------------------------------------------------------------------------------

@(private)
mul_un8 :: proc "contextless" (a, b: int) -> int {
	t := a * b + 0x80
	return ((t >> 8) + t) >> 8
}

@(private)
blend :: proc "contextless" (src, dst: Color, opacity: u8) -> Color {
	sa := mul_un8(int(src.a), int(opacity))
	a := sa + int(dst.a) - mul_un8(sa, int(dst.a))
	r, g, b: int
	if a != 0 {
		r = int(dst.r) + (int(src.r) - int(dst.r)) * sa / a
		g = int(dst.g) + (int(src.g) - int(dst.g)) * sa / a
		b = int(dst.b) + (int(src.b) - int(dst.b)) * sa / a
	}
	return Color{u8(r), u8(g), u8(b), u8(a)}
}

@(private)
pixel_color :: proc(ase: ^Ase, src: []u8, index: int) -> Color {
	switch ase.mode {
	case .RGBA:
		i := index * 4
		return Color{src[i], src[i + 1], src[i + 2], src[i + 3]}
	case .Grayscale:
		i := index * 2
		v := src[i]
		return Color{v, v, v, src[i + 1]}
	case .Indexed:
		pi := int(src[index])
		if pi == ase.transparent_palette_entry_index || pi >= len(ase.palette) {
			return Color{}
		}
		return ase.palette[pi].color
	}
	return Color{}
}

@(private)
compose_frame :: proc(ase: ^Ase, frame: ^Frame) {
	frame.pixels = make([]Color, ase.w * ase.h)
	dst := frame.pixels

	for &cel in frame.cels {
		if !layer_is_visible(ase, cel.layer) {
			continue
		}
		src_cel := resolve_cel(ase, &cel)
		if src_cel == nil || len(src_cel.pixels) == 0 {
			continue
		}

		opacity := u8(src_cel.opacity * ase.layers[cel.layer].opacity * 255.0)
		cx, cy, cw, ch := src_cel.x, src_cel.y, src_cel.w, src_cel.h

		cl := -min(cx, 0) // first source column
		ct := -min(cy, 0) // first source row
		dl := max(cx, 0) // first destination column
		dt := max(cy, 0) // first destination row
		dr := min(ase.w, cw + cx)
		db := min(ase.h, ch + cy)

		for row in 0 ..< db - dt {
			dy := dt + row
			sy := ct + row
			for col in 0 ..< dr - dl {
				dx := dl + col
				sx := cl + col
				di := ase.w * dy + dx
				src_color := pixel_color(ase, src_cel.pixels, cw * sy + sx)
				dst[di] = blend(src_color, dst[di], opacity)
			}
		}
	}
}
