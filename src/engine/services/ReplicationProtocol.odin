#+build !js
package services

import assetstore "../assetstore"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

replication_put_u32 :: proc(bytes: ^[dynamic]u8, value: u32) {
	for shift := 0; shift < 32; shift += 8 {append(bytes, u8(value >> u32(shift)))}
}

replication_put_u64 :: proc(bytes: ^[dynamic]u8, value: u64) {
	for shift := 0; shift < 64; shift += 8 {append(bytes, u8(value >> u64(shift)))}
}

replication_put_string :: proc(bytes: ^[dynamic]u8, value: string) {
	replication_put_u32(bytes, u32(len(value)))
	for byte in transmute([]u8)value {append(bytes, byte)}
}

replication_put_f32 :: proc(bytes: ^[dynamic]u8, value: f32) {
	replication_put_u32(bytes, transmute(u32)value)
}

Replication_Reader :: struct {
	data:   []u8,
	offset: int,
	valid:  bool,
}

replication_read_u8 :: proc(reader: ^Replication_Reader) -> u8 {
	if !reader.valid || reader.offset + 1 > len(reader.data) {reader.valid = false; return 0}
	value := reader.data[reader.offset]
	reader.offset += 1
	return value
}

replication_read_u32 :: proc(reader: ^Replication_Reader) -> u32 {
	if !reader.valid || reader.offset + 4 > len(reader.data) {reader.valid = false; return 0}
	value: u32
	for shift := 0; shift < 32; shift += 8 {
		value |= u32(reader.data[reader.offset]) << u32(shift)
		reader.offset += 1
	}
	return value
}

replication_read_u64 :: proc(reader: ^Replication_Reader) -> u64 {
	if !reader.valid || reader.offset + 8 > len(reader.data) {reader.valid = false; return 0}
	value: u64
	for shift := 0; shift < 64; shift += 8 {
		value |= u64(reader.data[reader.offset]) << u64(shift)
		reader.offset += 1
	}
	return value
}

// The returned string borrows the reader's buffer and is only valid while the
// packet that backs it is. A caller that keeps it past this dispatch -- as the
// chunked asset transfer does with an id and a path -- has to clone it first.
replication_read_string :: proc(reader: ^Replication_Reader) -> string {
	size := replication_read_u32(reader)
	if !reader.valid ||
	   size > 1048576 ||
	   int(size) > len(reader.data) - reader.offset {reader.valid = false; return ""}
	value := string(reader.data[reader.offset:reader.offset + int(size)])
	reader.offset += int(size)
	return value
}

replication_read_f32 :: proc(reader: ^Replication_Reader) -> f32 {
	return transmute(f32)replication_read_u32(reader)
}

// ---------------------------------------------------------------------------
// Terrain frames
// ---------------------------------------------------------------------------
// Terrain is a Service whose state is a sparse voxel map, so none of the
// instance-tree replication machinery can carry it: it has no replicated
// properties and it is not a child of any replicated root. It therefore gets a
// connect-time transfer of its own, shaped like the asset table.
//
// The database is sent as a header frame describing the voxel grid, then a
// series of batch frames, then a closing frame carrying the batch count. The
// client cannot know how many cells a map holds until the header arrives, so
// the header is what makes the rest of the stream self-describing.

Replication_Terrain_Subtype_Header: u8 = 0
Replication_Terrain_Subtype_Batch:  u8 = 1
Replication_Terrain_Subtype_End:    u8 = 2

// A single batch frame is capped so one reliable packet stays under what ENet
// will carry. The cap is a statement about this frame, not the whole database:
// a map larger than it is split across frames rather than truncated.
Replication_Terrain_Max_Cells: u32 = 4096

// Coordinates are bounded by TERRAIN_MAX_EXTENTS, so anything outside that is
// corrupt or hostile and is rejected before it reaches the voxel map.
Replication_Terrain_Max_Coordinate: i32 = 16000

// Voxel occupancies and water depths are fractions in [0, 1] and are stored as
// 16-bit fixed point. That is far finer than a marching-cubes surface needs at
// any voxel size the engine supports, and it halves the wire cost.
replication_put_u16 :: proc(bytes: ^[dynamic]u8, value: u16) {
	append(bytes, u8(value >> 8))
	append(bytes, u8(value & 0xFF))
}

replication_read_u16 :: proc(reader: ^Replication_Reader) -> u16 {
	high := replication_read_u8(reader)
	low := replication_read_u8(reader)
	if !reader.valid {return 0}
	return u16(high) << 8 | u16(low)
}

replication_put_fixed16 :: proc(bytes: ^[dynamic]u8, value: f32) {
	scaled := u16(clamp(value, 0, 1) * 65535.0 + 0.5)
	append(bytes, u8(scaled >> 8))
	append(bytes, u8(scaled & 0xFF))
}

replication_read_fixed16 :: proc(reader: ^Replication_Reader) -> f32 {
	return f32(replication_read_u16(reader)) / 65535.0
}

replication_put_i32 :: proc(bytes: ^[dynamic]u8, value: i32) {
	bits := transmute(u32)value
	append(bytes, u8(bits >> 24))
	append(bytes, u8(bits >> 16))
	append(bytes, u8(bits >> 8))
	append(bytes, u8(bits))
}

replication_read_i32 :: proc(reader: ^Replication_Reader) -> i32 {
	a := replication_read_u8(reader)
	b := replication_read_u8(reader)
	c := replication_read_u8(reader)
	d := replication_read_u8(reader)
	if !reader.valid {return 0}
	return transmute(i32)(u32(a) << 24 | u32(b) << 16 | u32(c) << 8 | u32(d))
}

// encode_terrain_header writes the grid description every later batch is
// measured against. The client refuses batches whose grid does not match, so a
// stale batch from an earlier map cannot be applied to a newer one.
encode_terrain_header :: proc(bytes: ^[dynamic]u8, terrain: ^Terrain) {
	append(bytes, Replication_Terrain_Subtype_Header)
	replication_put_u32(bytes, u32(len(terrain.voxels)))
	replication_put_f32(bytes, terrain.voxel_size)
	replication_put_f32(bytes, terrain.iso_level)
	replication_put_u32(bytes, u32(terrain.draw_version))
}

// encode_terrain_batch writes at most Replication_Terrain_Max_Cells cells as
// fixed-size records. Occupancy and water are 16-bit fixed point, which is far
// finer than a marching-cubes surface needs at any voxel size the engine
// supports and halves the wire cost of a full cell.
encode_terrain_batch :: proc(bytes: ^[dynamic]u8, cells: []Terrain_Cell_Record) {
	append(bytes, Replication_Terrain_Subtype_Batch)
	replication_put_u32(bytes, u32(len(cells)))
	for cell in cells {
		replication_put_i32(bytes, cell.x)
		replication_put_i32(bytes, cell.y)
		replication_put_i32(bytes, cell.z)
		append(bytes, u8(cell.material))
		replication_put_fixed16(bytes, cell.occupancy)
		replication_put_fixed16(bytes, cell.water)
	}
}

// decode_terrain_header reads the grid description. The subtype byte must
// already have been consumed by the caller, the same contract decode_terrain_batch
// has, so a single dispatch site can branch on the subtype and hand the rest of
// the frame to the matching reader.
//
// The cell count is a claim by the sender, so it is only recorded for logging:
// the batches that follow carry their own counts and are what actually build
// the map.
decode_terrain_header :: proc(
	reader: ^Replication_Reader,
) -> (voxel_size, iso_level: f32, draw_version: u32, declared: u32, ok: bool) {
	if !reader.valid {return 0, 0, 0, 0, false}
	// Field order has to match encode_terrain_header exactly: the cell count comes
	// first, then the grid description. Reading these in a different order
	// silently reinterprets the count as a float rather than failing.
	declared = replication_read_u32(reader)
	voxel_size = replication_read_f32(reader)
	iso_level = replication_read_f32(reader)
	draw_version = replication_read_u32(reader)
	if !reader.valid {return 0, 0, 0, 0, false}
	// A zero or negative voxel size would make every world<->cell conversion
	// divide by zero, so it is rejected rather than stored.
	if !(voxel_size > 0) || !(iso_level > 0) {return 0, 0, 0, 0, false}
	return voxel_size, iso_level, draw_version, declared, true
}

// decode_terrain_batch reads one batch into freshly allocated records. The
// declared count is checked against the bytes actually present before a single
// record is allocated, so a hostile count cannot drive an allocation loop.
decode_terrain_batch :: proc(
	reader: ^Replication_Reader,
) -> (cells: [dynamic]Terrain_Cell_Record, ok: bool) {
	if !reader.valid {return}
	count := replication_read_u32(reader)
	if !reader.valid {return}
	if count > Replication_Terrain_Max_Cells {reader.valid = false; return}
	// 17 bytes per cell is the exact record size: three i32 coordinates, one
	// material byte, and two 16-bit fixed-point values. The check is made before
	// a single record is allocated so a hostile count cannot drive an allocation
	// loop; the constant is the real size, not a conservative guess, so a full
	// legitimate batch is never refused.
	if int(count) > (len(reader.data) - reader.offset) / 17 {
		reader.valid = false
		return
	}

	reserve := int(count)
	cells = make([dynamic]Terrain_Cell_Record, 0, reserve)
	for _ in 0..<int(count) {
		cell: Terrain_Cell_Record
		cell.x = replication_read_i32(reader)
		cell.y = replication_read_i32(reader)
		cell.z = replication_read_i32(reader)
		material := replication_read_u8(reader)
		cell.occupancy = replication_read_fixed16(reader)
		cell.water = replication_read_fixed16(reader)
		if !reader.valid {return}
		if cell.x < -Replication_Terrain_Max_Coordinate ||
		   cell.x > Replication_Terrain_Max_Coordinate ||
		   cell.y < -Replication_Terrain_Max_Coordinate ||
		   cell.y > Replication_Terrain_Max_Coordinate ||
		   cell.z < -Replication_Terrain_Max_Coordinate ||
		   cell.z > Replication_Terrain_Max_Coordinate {
			reader.valid = false
			return
		}
		// Air is the last member of the Material enum, so it is the highest value
		// a sender can legally name. Clamping to it rather than to a material that
		// merely happens to matter here keeps every value above it intact instead
		// of folding Water, Sand, debug and Air into one material.
		cell.material = enums.Material(min(int(material), int(enums.Material.Air)))
		append(&cells, cell)
	}
	ok = true
	return
}

// ---------------------------------------------------------------------------
// Asset table frames
// ---------------------------------------------------------------------------
// A network client never loads a map, and the asset store is only ever filled as
// a side effect of deserializing a .kine stream, so the server has to hand the
// client the bytes its `kineasset://` references point at.
//
// One frame per asset, then a closing frame carrying the count. Per asset
// framing keeps each reliable packet a size ENet can carry on its own, and a
// single bad entry cannot take the rest of the table down with it. Every frame
// goes out on the reliable channel, which is ordered, so the whole table is
// applied before the first spawn that can reference it.

Replication_Asset_Subtype_Entry: u8 = 0
Replication_Asset_Subtype_End:   u8 = 1
// A mesh is routinely several megabytes, which is more than a single frame can
// carry, so an asset that does not fit is announced with Begin and then sent as
// a run of Chunks the client stitches back together. Entry stays for the assets
// that fit in one frame, which is the overwhelming majority, so the common case
// still costs exactly one packet.
Replication_Asset_Subtype_Begin: u8 = 2
Replication_Asset_Subtype_Chunk: u8 = 3

// Replication_Asset_Max_Chunk bounds one Chunk's body so the finished frame
// stays inside what a single reliable packet can carry. Like
// Replication_Terrain_Max_Cells this is a statement about a frame and not about
// the asset: something larger is split across frames rather than refused.
Replication_Asset_Max_Chunk: u32 = 256 * 1024

// MAX_ASSET_WIRE_PATH bounds the authored path string on the wire. The path
// only ever supplies a file extension, so anything longer is either corrupt or
// a peer trying to make this frame expensive to parse.
Replication_Asset_Max_Path: u32 = 4096

// Asset keys are content hashes, so they are a fixed 16 lowercase hex digits.
// Register_As re-checks the real rule, so this is only a cheap early reject that
// keeps a hostile length out of the string reader.
Replication_Asset_Max_Id_Length: u32 = 16

encode_asset_entry :: proc(
	bytes: ^[dynamic]u8,
	id: string,
	path: string,
	kind: assetstore.Asset_Kind,
	data: []u8,
) {
	append(bytes, Replication_Asset_Subtype_Entry)
	replication_put_string(bytes, id)
	replication_put_string(bytes, path)
	append(bytes, u8(kind))
	replication_put_u32(bytes, u32(len(data)))
	append(bytes, ..data)
}

// decode_asset_entry_body reads one entry with the leading subtype already
// consumed. `data` borrows from the reader and is only valid while the packet
// that backs it is, so the caller must copy before handing it to the store.
//
// The payload length is checked against both the per asset cap and the bytes
// actually present. A declared length is a claim by the sender, and believing a
// claim larger than the buffer is how a parser ends up reading past its input.
decode_asset_entry_body :: proc(
	reader: ^Replication_Reader,
) -> (id: string, path: string, kind: assetstore.Asset_Kind, data: []u8, ok: bool) {
	if !reader.valid {return "", "", .Unknown, nil, false}
	id = replication_read_string(reader)
	if !reader.valid || id == "" || len(id) > int(Replication_Asset_Max_Id_Length) {
		reader.valid = false
		return
	}
	path = replication_read_string(reader)
	if !reader.valid || len(path) > int(Replication_Asset_Max_Path) {
		reader.valid = false
		return
	}
	kind = assetstore.Asset_Kind(replication_read_u8(reader))
	if !reader.valid {return}
	length := replication_read_u32(reader)
	if !reader.valid {return}
	if length > u32(assetstore.MAX_ASSET_BYTES) ||
	   int(length) > len(reader.data) - reader.offset {
		reader.valid = false
		return
	}
	data = reader.data[reader.offset:reader.offset + int(length)]
	reader.offset += int(length)
	ok = true
	return
}

// decode_asset_entry reads a complete entry frame, subtype included. Used where
// the frame is expected to be an entry rather than the closing marker.
decode_asset_entry :: proc(
	reader: ^Replication_Reader,
) -> (id: string, path: string, kind: assetstore.Asset_Kind, data: []u8, ok: bool) {
	if !reader.valid || reader.offset >= len(reader.data) {
		reader.valid = false
		return "", "", .Unknown, nil, false
	}
	subtype := reader.data[reader.offset]
	reader.offset += 1
	if subtype != Replication_Asset_Subtype_Entry {
		reader.valid = false
		return "", "", .Unknown, nil, false
	}
	return decode_asset_entry_body(reader)
}

// encode_asset_begin opens a chunked transfer: everything an entry frame would
// have carried except the bytes themselves, plus the total they will add up to.
// The total is what lets the client know when the asset is whole, so a truncated
// transfer is detectable instead of registering a short file.
encode_asset_begin :: proc(
	bytes: ^[dynamic]u8,
	id: string,
	path: string,
	kind: assetstore.Asset_Kind,
	total: u32,
) {
	append(bytes, Replication_Asset_Subtype_Begin)
	replication_put_string(bytes, id)
	replication_put_string(bytes, path)
	append(bytes, u8(kind))
	replication_put_u32(bytes, total)
}

// encode_asset_chunk writes one slice of the body. The index is what the client
// checks the next chunk against, so a gap or a repeat is caught rather than
// silently stitched into the wrong place.
encode_asset_chunk :: proc(bytes: ^[dynamic]u8, index: u32, data: []u8) {
	append(bytes, Replication_Asset_Subtype_Chunk)
	replication_put_u32(bytes, index)
	append(bytes, ..data)
}

decode_asset_begin :: proc(
	reader: ^Replication_Reader,
) -> (id: string, path: string, kind: assetstore.Asset_Kind, total: u32, ok: bool) {
	if !reader.valid {return "", "", .Unknown, 0, false}
	id = replication_read_string(reader)
	if !reader.valid || id == "" || len(id) > int(Replication_Asset_Max_Id_Length) {
		reader.valid = false
		return
	}
	path = replication_read_string(reader)
	if !reader.valid || len(path) > int(Replication_Asset_Max_Path) {
		reader.valid = false
		return
	}
	kind = assetstore.Asset_Kind(replication_read_u8(reader))
	if !reader.valid {return}
	total = replication_read_u32(reader)
	// Bounded by the same per asset cap the single frame form uses, so an
	// announced total can never describe more than the store would accept.
	if !reader.valid || total > u32(assetstore.MAX_ASSET_BYTES) {
		reader.valid = false
		return
	}
	ok = true
	return
}

// decode_asset_chunk reads one slice. The bytes run to the end of the frame, so
// there is no length to believe: what arrived is what is there. The slice
// borrows from the packet buffer, so the caller copies before keeping it.
decode_asset_chunk :: proc(
	reader: ^Replication_Reader,
) -> (index: u32, data: []u8, ok: bool) {
	if !reader.valid {return 0, nil, false}
	index = replication_read_u32(reader)
	if !reader.valid {return}
	data = reader.data[reader.offset:]
	reader.offset = len(reader.data)
	if len(data) > int(Replication_Asset_Max_Chunk) {
		reader.valid = false
		return 0, nil, false
	}
	ok = true
	return
}

replication_encode_value :: proc(
	L: ^vm.State,
	index: int,
	bytes: ^[dynamic]u8,
	depth: int,
) -> bool {
	if depth > 8 || len(bytes^) > 1048576 {return false}
	#partial switch vm.TypeOf(L, index) {
	case .Nil, .None:
		append(bytes, 0)
	case .Boolean:
		append(bytes, vm.ArgBoolean(L, index) ? u8(2) : u8(1))
	case .Number, .Integer:
		append(bytes, 3)
		bits := transmute(u64)vm.ArgNumber(L, index)
		for shift := 0; shift < 64; shift += 8 {append(bytes, u8(bits >> u64(shift)))}
	case .String:
		append(bytes, 4)
		value, _ := vm.ToString(L, index)
		replication_put_string(bytes, value)
	case .Table:
		append(bytes, 5)
		count_offset := len(bytes^)
		replication_put_u32(bytes, 0)
		count: u32
		table_index := index < 0 ? vm.StackTop(L) + index + 1 : index
		vm.PushNil(L)
		for vm.Next(L, table_index) {
			if count >= 256 ||
			   (vm.TypeOf(L, -2) != .String &&
					   vm.TypeOf(L, -2) != .Number &&
					   vm.TypeOf(L, -2) != .Integer) {
				vm.Pop(L)
				vm.Pop(L)
				return false
			}
			if !replication_encode_value(L, -2, bytes, depth + 1) ||
			   !replication_encode_value(L, -1, bytes, depth + 1) {
				vm.Pop(L)
				vm.Pop(L)
				return false
			}
			count += 1
			vm.Pop(L)
		}
		for i in 0 ..< 4 {bytes^[count_offset + i] = u8(count >> u32(i * 8))}
	case .Vector:
		append(bytes, 6)
		x, y, z := vm.ArgVector3(L, index)
		replication_put_f32(bytes, x)
		replication_put_f32(bytes, y)
		replication_put_f32(bytes, z)
	case .Userdata:
		binding := vm.UserdataBindingOf(L, index)
		if binding == nil {return false}
		if binding.name == "Color3" {
			append(bytes, 7)
			color := cast(^datatypes.Color3)vm.UserdataValue(L, index)
			replication_put_f32(bytes, color.R)
			replication_put_f32(bytes, color.G)
			replication_put_f32(bytes, color.B)
		} else if binding.name == "CFrame" {
			append(bytes, 8)
			frame := cast(^datatypes.CFrame)vm.UserdataValue(L, index)
			values := [12]f32 {
				frame.x,
				frame.y,
				frame.z,
				frame.r00,
				frame.r01,
				frame.r02,
				frame.r10,
				frame.r11,
				frame.r12,
				frame.r20,
				frame.r21,
				frame.r22,
			}
			for value in values {replication_put_f32(bytes, value)}
		} else if binding.name == "UDim" {
			append(bytes, 9)
			value := cast(^datatypes.UDim)vm.UserdataValue(L, index)
			replication_put_f32(bytes, value.Scale)
			replication_put_f32(bytes, value.Offset)
		} else if binding.name == "UDim2" {
			append(bytes, 10)
			value := cast(^datatypes.UDim2)vm.UserdataValue(L, index)
			replication_put_f32(bytes, value.X_Scale)
			replication_put_f32(bytes, value.X_Offset)
			replication_put_f32(bytes, value.Y_Scale)
			replication_put_f32(bytes, value.Y_Offset)
		} else if binding.name == "Vector2" {
			append(bytes, 11)
			value := cast(^datatypes.Vector2)vm.UserdataValue(L, index)
			replication_put_f32(bytes, value.X)
			replication_put_f32(bytes, value.Y)
		} else if binding.name == "Rect" {
			append(bytes, 12)
			value := cast(^datatypes.Rect)vm.UserdataValue(L, index)
			replication_put_f32(bytes, value.Min.X)
			replication_put_f32(bytes, value.Min.Y)
			replication_put_f32(bytes, value.Max.X)
			replication_put_f32(bytes, value.Max.Y)
		} else if binding.name == "ColorSequence" {
			append(bytes, 13)
			value := cast(^datatypes.ColorSequence)vm.UserdataValue(L, index)
			count := min(len(value.Keypoints), 32)
			replication_put_u32(bytes, u32(count))
			for i in 0 ..< count {
				replication_put_f32(bytes, value.Keypoints[i].Time)
				replication_put_f32(bytes, value.Keypoints[i].Value.R)
				replication_put_f32(bytes, value.Keypoints[i].Value.G)
				replication_put_f32(bytes, value.Keypoints[i].Value.B)
			}
		} else if binding.name == "NumberSequence" {
			append(bytes, 14)
			value := cast(^datatypes.NumberSequence)vm.UserdataValue(L, index)
			count := min(len(value.Keypoints), 32)
			replication_put_u32(bytes, u32(count))
			for i in 0 ..< count {
				replication_put_f32(bytes, value.Keypoints[i].Time)
				replication_put_f32(bytes, value.Keypoints[i].Value)
				replication_put_f32(bytes, value.Keypoints[i].Envelope)
			}
		} else if binding.name == "Font" {
			append(bytes, 15)
			value := cast(^datatypes.Font)vm.UserdataValue(L, index)
			replication_put_string(bytes, value.Family)
			replication_put_f32(bytes, f32(value.Weight))
			replication_put_f32(bytes, f32(value.Style))
		} else if binding.tag == enums.ENUM_ITEM_TAG {
			append(bytes, 16)
			item := cast(^enums.Enum_Item)vm.UserdataValue(L, index)
			if item == nil || item.enum_type == nil || item.value < 0 {return false}
			replication_put_string(bytes, item.enum_type.name)
			replication_put_u32(bytes, u32(item.value))
		} else {return false}
	case:
		return false
	}
	return len(bytes^) <= 1048576
}

replication_decode_value :: proc(
	L: ^vm.State,
	reader: ^Replication_Reader,
	datatype_registry: ^datatypes.Registry,
	depth: int,
) {
	if !reader.valid ||
	   depth > 8 ||
	   reader.offset >= len(reader.data) {reader.valid = false; vm.PushNil(L); return}
	tag := reader.data[reader.offset]
	reader.offset += 1
	switch tag {
	case 0:
		vm.PushNil(L)
	case 1, 2:
		vm.PushBoolean(L, tag == 2)
	case 3:
		if reader.offset + 8 > len(reader.data) {reader.valid = false; vm.PushNil(L); return}
		bits: u64
		for shift := 0;
		    shift < 64;
		    shift += 8 {bits |= u64(reader.data[reader.offset]) << u64(shift); reader.offset += 1}
		vm.PushNumber(L, transmute(f64)bits)
	case 4:
		vm.PushString(L, replication_read_string(reader))
	case 5:
		count := replication_read_u32(reader)
		if count > 256 {reader.valid = false; vm.PushNil(L); return}
		vm.NewTable(L, 0, int(count))
		for _ in 0 ..< int(count) {
			replication_decode_value(L, reader, datatype_registry, depth + 1)
			replication_decode_value(L, reader, datatype_registry, depth + 1)
			if !reader.valid {vm.Pop(L); vm.Pop(L); break}
			if vm.TypeOf(L, -2) == .String {
				key, _ := vm.ToString(L, -2)
				vm.PushValue(L, -1)
				vm.SetField(L, -4, key)
			} else if vm.IsNumber(L, -2) {
				key, valid := vm.ToNumber(L, -2)
				if !valid || key < 1 || key > 65535 || f64(i64(key)) != key {reader.valid = false}
				if reader.valid {
					vm.PushValue(L, -1)
					vm.RawSetIndex(L, -4, int(key))
				}
			} else {reader.valid = false}
			vm.Pop(L)
			vm.Pop(L)
		}
	case 6:
		x := replication_read_f32(reader)
		y := replication_read_f32(reader)
		z := replication_read_f32(reader)
		vm.PushVector3(L, x, y, z)
	case 7:
		color := datatypes.Color3 {
			R = replication_read_f32(reader),
			G = replication_read_f32(reader),
			B = replication_read_f32(reader),
		}
		datatypes.Push_Color3(L, datatype_registry, color)
	case 8:
		frame := datatypes.CFrame{}
		frame.x = replication_read_f32(reader)
		frame.y = replication_read_f32(reader)
		frame.z = replication_read_f32(reader)
		frame.r00 = replication_read_f32(reader)
		frame.r01 = replication_read_f32(reader)
		frame.r02 = replication_read_f32(reader)
		frame.r10 = replication_read_f32(reader)
		frame.r11 = replication_read_f32(reader)
		frame.r12 = replication_read_f32(reader)
		frame.r20 = replication_read_f32(reader)
		frame.r21 = replication_read_f32(reader)
		frame.r22 = replication_read_f32(reader)
		datatypes.Push_CFrame(L, datatype_registry, frame)
	case 9:
		if reader.offset + 8 > len(reader.data) {reader.valid = false; vm.PushNil(L); return}
		value := datatypes.UDim {
			Scale  = replication_read_f32(reader),
			Offset = replication_read_f32(reader),
		}
		datatypes.Push_UDim(L, datatype_registry, value)
	case 10:
		if reader.offset + 16 > len(reader.data) {reader.valid = false; vm.PushNil(L); return}
		value := datatypes.UDim2 {
			X_Scale  = replication_read_f32(reader),
			X_Offset = replication_read_f32(reader),
			Y_Scale  = replication_read_f32(reader),
			Y_Offset = replication_read_f32(reader),
		}
		datatypes.Push_UDim2(L, datatype_registry, value)
	case 11:
		if reader.offset + 8 > len(reader.data) {reader.valid = false; vm.PushNil(L); return}
		value := datatypes.Vector2 {
			X = replication_read_f32(reader),
			Y = replication_read_f32(reader),
		}
		datatypes.Push_Vector2(L, datatype_registry, value)
	case 12:
		if reader.offset + 16 > len(reader.data) {reader.valid = false; vm.PushNil(L); return}
		value := datatypes.Rect {
			Min = datatypes.Vector2 {
				X = replication_read_f32(reader),
				Y = replication_read_f32(reader),
			},
			Max = datatypes.Vector2 {
				X = replication_read_f32(reader),
				Y = replication_read_f32(reader),
			},
		}
		datatypes.Push_Rect(L, datatype_registry, value)
	case 13:
		count := replication_read_u32(reader)
		if count > 32 || reader.offset + int(count) * 16 > len(reader.data) {
			reader.valid = false; vm.PushNil(L); return
		}
		keypoints := make([]datatypes.ColorSequenceKeypoint, count)
		for i in 0 ..< int(count) {
			keypoints[i] = datatypes.ColorSequenceKeypoint {
				Time  = replication_read_f32(reader),
				Value = datatypes.Color3 {
					R = replication_read_f32(reader),
					G = replication_read_f32(reader),
					B = replication_read_f32(reader),
				},
			}
		}
		sequence, ok := datatypes.ColorSequence_FromKeypoints(keypoints)
		delete(keypoints)
		if !ok {reader.valid = false; vm.PushNil(L); return}
		datatypes.Push_ColorSequence(L, datatype_registry, sequence)
	case 14:
		count := replication_read_u32(reader)
		if count > 32 || reader.offset + int(count) * 12 > len(reader.data) {
			reader.valid = false; vm.PushNil(L); return
		}
		keypoints := make([]datatypes.NumberSequenceKeypoint, count)
		for i in 0 ..< int(count) {
			keypoints[i] = datatypes.NumberSequenceKeypoint {
				Time     = replication_read_f32(reader),
				Value    = replication_read_f32(reader),
				Envelope = replication_read_f32(reader),
			}
		}
		sequence, ok := datatypes.NumberSequence_FromKeypoints(keypoints)
		delete(keypoints)
		if !ok {reader.valid = false; vm.PushNil(L); return}
		datatypes.Push_NumberSequence(L, datatype_registry, sequence)
	case 15:
		family := replication_read_string(reader)
		if !reader.valid {vm.PushNil(L); return}
		weight := i32(replication_read_f32(reader))
		style := i32(replication_read_f32(reader))
		font := datatypes.Font {
			Family = family,
			Weight = enums.FontWeight(weight),
			Style  = enums.FontStyle(style),
		}
		datatypes.Push_Font(L, datatype_registry, font)
	case 16:
		enum_name := replication_read_string(reader)
		value := i64(replication_read_u32(reader))
		if !reader.valid ||
		   datatype_registry == nil ||
		   datatype_registry.enums == nil {
			reader.valid = false; vm.PushNil(L); return
		}
		if !enums.Push_Item_By_Value(
			L,
			datatype_registry.enums,
			enum_name,
			value,
		) {
			reader.valid = false
		}
	case:
		reader.valid = false; vm.PushNil(L)
	}
}
