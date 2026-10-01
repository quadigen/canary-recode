package serializer

import "base:runtime"
import "core:fmt"
import "core:slice"
import "core:sort"
import "core:strings"
import classes "../classes"
import assetstore "../assetstore"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

// Kine is the Kinemium save-file format.
//
// Layout (all multi-byte values little-endian):
//
//   header:
//     4 bytes   magic "KINE"
//     1 byte    format version
//   asset table (version 3 and later, absent in version 2):
//     u32      asset count
//     per asset:
//       string   content id
//       string   original path as authored
//       u8       asset kind
//       varuint  byte length
//       bytes    raw file contents
//   instance record (repeated recursively):
//     string   class name
//     string   instance name
//     u8       archivable
//     i64 + u32 + u32   unique id (Random, Time, Index)
//     u32      property count
//     per property:
//       string   property key
//       value    tagged value record
//     u32      attribute count
//     per attribute:
//       string   attribute name
//       value    tagged value record
//     u32      child count
//     per child:
//       instance record
//   terrain table (version 4 and later, absent before):
//     u8       present flag (0 = no terrain in this map)
//     u8       decoration
//     f32      voxel size
//     f32      iso level
//     f32      grass length
//     f32      water reflectance
//     f32      water transparency
//     f32      water wave size
//     f32      water wave speed
//     color3   water color (3 x f32)
//     u32      material colour count
//     per material:
//       u32     material
//       color3  colour (3 x f32)
//     u32      cell count
//     per cell (17 bytes):
//       i32     x voxel coordinate
//       i32     y voxel coordinate
//       i32     z voxel coordinate
//       u8      material
//       u16     occupancy, fixed point (value * 65535)
//       u16     water level, fixed point (value * 65535)
//
//   string := varuint length + raw bytes
//   value  := u8 tag + payload (see Value_Tag below)
//
// The asset table is read before the instance tree so that every property setter
// runs with its referenced bytes already published. Asset-bearing property
// values are stored as "kineasset://<content-id>", which round-trips losslessly:
// the store keeps the original path so an editor can still show what was used.
//
// The terrain table comes last and is its own section because Terrain is a
// singleton service rather than an Instance, so the tree walk cannot reach it.
// Its cell record is deliberately byte-identical to a replicated terrain batch
// cell, so one decoder shape serves both transports.

KINE_MAGIC :: "KINE"

// KINE_VERSION is the version written by this build.
KINE_VERSION :: 4

// KINE_ASSET_VERSION is the first layout with an asset table and no terrain.
KINE_ASSET_VERSION :: 3

// KINE_LEGACY_VERSION is the last layout without an asset table. Those files
// still decode; they just cannot carry embedded assets.
KINE_LEGACY_VERSION :: 2

KINE_MAX_STRING_LENGTH :: 16 * 1024 * 1024

READ_ONLY_PROPERTIES := [?]string{
	"AbsolutePosition",
	"AbsoluteSize",
	"TextBounds",
	"AbsoluteContentSize",
	"AbsoluteCellCount",
	"AbsoluteCellSize",
}

Value_Tag :: enum u8 {
	Nil,
	Boolean,
	Number,
	Integer,
	String,
	Vector3,
	Userdata,
	EnumItem,
}

// Stable ids for every serializable userdata datatype. New types are appended
// at the end so old files keep decoding.
Datatype_Id :: enum u16 {
	Axes,
	BrickColor,
	CFrame,
	Color3,
	ColorSequence,
	Content,
	DateTime,
	Faces,
	Font,
	NumberRange,
	NumberSequence,
	PathWaypoint,
	PhysicalProperties,
	Quaternion,
	Region3,
	Region3int16,
	SecurityCapabilities,
	TweenInfo,
	UDim,
	UDim2,
	UniqueId,
	Vector2,
	Vector2int16,
	Vector3,
	Vector3int16,
}

Writer :: struct {
	data: [dynamic]u8,
	// Excludes a child during serialization. Called with the child and its
	// immediate parent for every child that would otherwise be written; returning
	// true skips that child and its subtree. The exporter uses it to strip
	// editor-only services (CoreGui, EditorService, ...) from the DataModel root
	// before writing a map file.
	exclude_child: proc(parent: ^classes.Object, object: ^classes.Object) -> bool,
	// Ids this stream actually referenced, in first-use order. Only these are
	// written to the asset table, so assets left in the store by an
	// already-loaded map do not leak into the file being written.
	used_ids: [dynamic]string,
	used_seen: map[string]bool,
	// embed_assets is false for a version 2 stream, where asset properties keep
	// the author's bare paths and no table is written.
	embed_assets: bool,
	// version is the layout being written. A few value records changed shape
	// between versions, so a record can consult it rather than guessing.
	version: u8,
}

Reader :: struct {
	data: []u8,
	pos:  int,
	// version is the layout being read, so a record can tell which shape to
	// expect instead of guessing.
	version: u8,
}

// ---------------------------------------------------------------------------
// Primitive writers
// ---------------------------------------------------------------------------

write_u8 :: proc(w: ^Writer, value: u8) {
	append(&w.data, value)
}

write_u16 :: proc(w: ^Writer, value: u16) {
	bytes := transmute([2]u8)value
	append(&w.data, bytes[0], bytes[1])
}

write_u32 :: proc(w: ^Writer, value: u32) {
	bytes := transmute([4]u8)value
	append(&w.data, bytes[0], bytes[1], bytes[2], bytes[3])
}

write_var_u32 :: proc(w: ^Writer, value: u32) {
	remaining := value
	for remaining >= 0x80 {
		write_u8(w, u8(remaining) | 0x80)
		remaining >>= 7
	}
	write_u8(w, u8(remaining))
}

write_u64 :: proc(w: ^Writer, value: u64) {
	bytes := transmute([8]u8)value
	append(&w.data, ..bytes[:])
}

write_i16 :: proc(w: ^Writer, value: i16) {
	write_u16(w, transmute(u16)value)
}

write_i32 :: proc(w: ^Writer, value: i32) {
	write_u32(w, transmute(u32)value)
}

write_i64 :: proc(w: ^Writer, value: i64) {
	write_u64(w, transmute(u64)value)
}

write_f32 :: proc(w: ^Writer, value: f32) {
	write_u32(w, transmute(u32)value)
}

write_f64 :: proc(w: ^Writer, value: f64) {
	write_u64(w, transmute(u64)value)
}

write_string :: proc(w: ^Writer, value: string) {
	write_var_u32(w, u32(len(value)))
	append(&w.data, ..transmute([]u8)value)
}

// Writes a u32 at a previously reserved offset (used for count patching).
patch_u32 :: proc(w: ^Writer, offset: int, value: u32) {
	bytes := transmute([4]u8)value
	for i in 0 ..< 4 {
		w.data[offset + i] = bytes[i]
	}
}

// ---------------------------------------------------------------------------
// Primitive readers
// ---------------------------------------------------------------------------

read_bytes :: proc(r: ^Reader, count: int) -> ([]u8, bool) {
	if r == nil || count < 0 || r.pos + count > len(r.data) {
		return nil, false
	}
	result := r.data[r.pos:r.pos + count]
	r.pos += count
	return result, true
}

read_u8 :: proc(r: ^Reader) -> (u8, bool) {
	bytes, ok := read_bytes(r, 1)
	if !ok {
		return 0, false
	}
	return bytes[0], true
}

read_u16 :: proc(r: ^Reader) -> (u16, bool) {
	bytes, ok := read_bytes(r, 2)
	if !ok {
		return 0, false
	}
	return transmute(u16)[2]u8{bytes[0], bytes[1]}, true
}

read_u32 :: proc(r: ^Reader) -> (u32, bool) {
	bytes, ok := read_bytes(r, 4)
	if !ok {
		return 0, false
	}
	return transmute(u32)[4]u8{bytes[0], bytes[1], bytes[2], bytes[3]}, true
}

read_var_u32 :: proc(r: ^Reader) -> (u32, bool) {
	value: u32
	for shift: u32 = 0; shift < 35; shift += 7 {
		byte, ok := read_u8(r)
		if !ok || (shift == 28 && byte > 0x0f) {return 0, false}
		value |= u32(byte & 0x7f) << shift
		if byte & 0x80 == 0 {return value, true}
	}
	return 0, false
}

read_u64 :: proc(r: ^Reader) -> (u64, bool) {
	bytes, ok := read_bytes(r, 8)
	if !ok {
		return 0, false
	}
	return transmute(u64)[8]u8{
		bytes[0], bytes[1], bytes[2], bytes[3],
		bytes[4], bytes[5], bytes[6], bytes[7],
	}, true
}

read_i16 :: proc(r: ^Reader) -> (i16, bool) {
	value, ok := read_u16(r)
	return transmute(i16)value, ok
}

read_i32 :: proc(r: ^Reader) -> (i32, bool) {
	value, ok := read_u32(r)
	return transmute(i32)value, ok
}

read_i64 :: proc(r: ^Reader) -> (i64, bool) {
	value, ok := read_u64(r)
	return transmute(i64)value, ok
}

read_f32 :: proc(r: ^Reader) -> (f32, bool) {
	value, ok := read_u32(r)
	return transmute(f32)value, ok
}

read_f64 :: proc(r: ^Reader) -> (f64, bool) {
	value, ok := read_u64(r)
	return transmute(f64)value, ok
}

read_string :: proc(r: ^Reader) -> (string, bool) {
	length, ok := read_var_u32(r)
	if !ok {
		return "", false
	}
	if length > KINE_MAX_STRING_LENGTH || u64(length) > u64(len(r.data) - r.pos) {
		return "", false
	}
	bytes, bytes_ok := read_bytes(r, int(length))
	if !bytes_ok {
		return "", false
	}
	return strings.clone(string(bytes)), true
}

read_f32s :: proc(r: ^Reader, out: []f32) -> bool {
	for i in 0 ..< len(out) {
		value, ok := read_f32(r)
		if !ok {
			return false
		}
		out[i] = value
	}
	return true
}

read_i16s :: proc(r: ^Reader, out: []i16) -> bool {
	for i in 0 ..< len(out) {
		value, ok := read_i16(r)
		if !ok {
			return false
		}
		out[i] = value
	}
	return true
}

// ---------------------------------------------------------------------------
// Asset embedding
// ---------------------------------------------------------------------------

// asset_kind_of reports whether a class property holds a reference to a file
// that belongs inside the .kine file. Keeping this a table means adding a
// consumer is one line, and a property that is not listed keeps its current
// behaviour of storing a bare path.
asset_kind_of :: proc(class_name, property: string) -> (assetstore.Asset_Kind, bool) {
	switch class_name {
	case "MeshPart":
		switch property {
		case "MeshId", "MeshContent":
			return .Mesh, true
		case "TextureId":
			return .Texture, true
		}
	case "ImageLabel", "ImageButton":
		if property == "Image" {
			return .Texture, true
		}
	case "Decal":
		if property == "Texture" {
			return .Texture, true
		}
	}
	return .Unknown, false
}

// is_embeddable_path rejects values that are not the author's own files: an
// already-embedded reference, an empty slot, or any other scheme such as
// builtin://, memory:// or a remote URL.
is_embeddable_path :: proc(path: string) -> bool {
	if path == "" {
		return false
	}
	if assetstore.Is_Uri(path) {
		return false
	}
	return !strings.contains(path, "://")
}

// note_asset records that this stream referenced an asset, so the asset table
// carries it even when the store already held those bytes from an earlier map.
note_asset :: proc(w: ^Writer, id: string) {
	if w.used_seen == nil {
		w.used_seen = make(map[string]bool)
	}
	if w.used_seen[id] {
		return
	}
	w.used_seen[id] = true
	append(&w.used_ids, strings.clone(id))
}

// embed_path turns an authored file path into the value to serialize. When the
// file can be read its bytes are registered and a "kineasset://" reference is
// returned; otherwise the authored path is preserved, so a missing file
// degrades to the current broken-in-the-editor behaviour rather than to nothing.
// The result is owned by the caller.
embed_path :: proc(w: ^Writer, authored: string, kind: assetstore.Asset_Kind) -> string {
	if !w.embed_assets || !is_embeddable_path(authored) {
		return strings.clone(authored)
	}

	data, ok := assetstore.Read_Asset_File(authored)
	if !ok {
		return strings.clone(authored)
	}

	// Register consumes the bytes, so `data` must not be freed here.
	id := assetstore.Register(data, authored, kind)
	defer delete(id)
	if id == "" {
		return strings.clone(authored)
	}
	note_asset(w, id)
	return assetstore.Make_Uri(id)
}

// replace_stack_asset rewrites a string already on the Lua stack with its
// embedded reference, keeping the value at the same stack index.
replace_stack_asset :: proc(w: ^Writer, L: ^vm.State, value_index: int, kind: assetstore.Asset_Kind) -> bool {
	if vm.TypeOf(L, value_index) != .String {
		return false
	}
	authored := vm.ArgString(L, value_index)
	if !is_embeddable_path(authored) {
		return false
	}
	uri := embed_path(w, authored, kind)
	defer delete(uri)
	vm.SetStackTop(L, value_index - 1)
	vm.PushString(L, uri)
	return true
}

// ---------------------------------------------------------------------------
// Value encoding
// ---------------------------------------------------------------------------

datatype_id_of_binding :: proc(name: string) -> (Datatype_Id, bool) {
	switch name {
	case "Axes":
		return .Axes, true
	case "BrickColor":
		return .BrickColor, true
	case "CFrame":
		return .CFrame, true
	case "Color3":
		return .Color3, true
	case "ColorSequence":
		return .ColorSequence, true
	case "Content":
		return .Content, true
	case "DateTime":
		return .DateTime, true
	case "Faces":
		return .Faces, true
	case "Font":
		return .Font, true
	case "NumberRange":
		return .NumberRange, true
	case "NumberSequence":
		return .NumberSequence, true
	case "PathWaypoint":
		return .PathWaypoint, true
	case "PhysicalProperties":
		return .PhysicalProperties, true
	case "Quaternion":
		return .Quaternion, true
	case "Region3":
		return .Region3, true
	case "Region3int16":
		return .Region3int16, true
	case "SecurityCapabilities":
		return .SecurityCapabilities, true
	case "TweenInfo":
		return .TweenInfo, true
	case "UDim":
		return .UDim, true
	case "UDim2":
		return .UDim2, true
	case "UniqueId":
		return .UniqueId, true
	case "Vector2":
		return .Vector2, true
	case "Vector2int16":
		return .Vector2int16, true
	case "Vector3":
		return .Vector3, true
	case "Vector3int16":
		return .Vector3int16, true
	}
	return {}, false
}

write_datatype_value :: proc(w: ^Writer, L: ^vm.State, id: Datatype_Id, value_index: int) -> bool {
	ptr := vm.UserdataValue(L, value_index)
	if ptr == nil {
		return false
	}

	switch id {
	case .Axes:
		value := cast(^datatypes.Axes)ptr
		write_u8(w, value.X ? 1 : 0)
		write_u8(w, value.Y ? 1 : 0)
		write_u8(w, value.Z ? 1 : 0)
	case .BrickColor:
		value := cast(^datatypes.BrickColor)ptr
		write_i32(w, value.number)
	case .CFrame:
		value := cast(^datatypes.CFrame)ptr
		write_f32(w, value.x)
		write_f32(w, value.y)
		write_f32(w, value.z)
		write_f32(w, value.r00)
		write_f32(w, value.r01)
		write_f32(w, value.r02)
		write_f32(w, value.r10)
		write_f32(w, value.r11)
		write_f32(w, value.r12)
		write_f32(w, value.r20)
		write_f32(w, value.r21)
		write_f32(w, value.r22)
	case .Color3:
		value := cast(^datatypes.Color3)ptr
		write_f32(w, value.R)
		write_f32(w, value.G)
		write_f32(w, value.B)
	case .ColorSequence:
		value := cast(^datatypes.ColorSequence)ptr
		write_u32(w, u32(len(value.Keypoints)))
		for keypoint in value.Keypoints {
			write_f32(w, keypoint.Time)
			write_f32(w, keypoint.Value.R)
			write_f32(w, keypoint.Value.G)
			write_f32(w, keypoint.Value.B)
		}
	case .Content:
		value := cast(^datatypes.Content)ptr
		// Content is the generic file handle, so a local path inside one is an
		// asset like any other and embeds as data.
		uri := embed_path(w, value.uri, .Data)
		write_string(w, uri)
		delete(uri)
		// Version 3 added the object handle. Without it a Content pointing at a
		// live engine object (an EditableMesh, say) silently degraded to a
		// dangling empty reference on every reload.
		if w.version >= 3 {
			write_u32(w, value.object_id)
			write_u8(w, value.object_kind)
		}
	case .DateTime:
		value := cast(^datatypes.DateTime)ptr
		write_f64(w, value.UnixTimestampMillis)
	case .Faces:
		value := cast(^datatypes.Faces)ptr
		write_u8(w, value.Top ? 1 : 0)
		write_u8(w, value.Bottom ? 1 : 0)
		write_u8(w, value.Left ? 1 : 0)
		write_u8(w, value.Right ? 1 : 0)
		write_u8(w, value.Front ? 1 : 0)
		write_u8(w, value.Back ? 1 : 0)
	case .Font:
		value := cast(^datatypes.Font)ptr
		write_string(w, value.Family)
		write_i64(w, i64(value.Weight))
		write_i64(w, i64(value.Style))
	case .NumberRange:
		value := cast(^datatypes.NumberRange)ptr
		write_f32(w, value.Min)
		write_f32(w, value.Max)
	case .NumberSequence:
		value := cast(^datatypes.NumberSequence)ptr
		write_u32(w, u32(len(value.Keypoints)))
		for keypoint in value.Keypoints {
			write_f32(w, keypoint.Time)
			write_f32(w, keypoint.Value)
			write_f32(w, keypoint.Envelope)
		}
	case .PathWaypoint:
		value := cast(^datatypes.PathWaypoint)ptr
		write_f32(w, value.Position.x)
		write_f32(w, value.Position.y)
		write_f32(w, value.Position.z)
		write_i64(w, i64(value.Action))
		write_string(w, value.Label)
	case .PhysicalProperties:
		value := cast(^datatypes.PhysicalProperties)ptr
		write_f32(w, value.Density)
		write_f32(w, value.Friction)
		write_f32(w, value.Elasticity)
		write_f32(w, value.FrictionWeight)
		write_f32(w, value.ElasticityWeight)
	case .Quaternion:
		value := cast(^datatypes.Quaternion)ptr
		write_f32(w, value.X)
		write_f32(w, value.Y)
		write_f32(w, value.Z)
		write_f32(w, value.W)
	case .Region3:
		value := cast(^datatypes.Region3)ptr
		write_f32(w, value.Min.x)
		write_f32(w, value.Min.y)
		write_f32(w, value.Min.z)
		write_f32(w, value.Max.x)
		write_f32(w, value.Max.y)
		write_f32(w, value.Max.z)
	case .Region3int16:
		value := cast(^datatypes.Region3int16)ptr
		write_i16(w, value.Min.X)
		write_i16(w, value.Min.Y)
		write_i16(w, value.Min.Z)
		write_i16(w, value.Max.X)
		write_i16(w, value.Max.Y)
		write_i16(w, value.Max.Z)
	case .SecurityCapabilities:
		value := cast(^datatypes.SecurityCapabilities)ptr
		write_u64(w, value.bits_low)
		write_u64(w, value.bits_high)
	case .TweenInfo:
		value := cast(^datatypes.TweenInfo)ptr
		write_f32(w, value.Time)
		write_i64(w, i64(value.EasingStyle))
		write_i64(w, i64(value.EasingDirection))
		write_i32(w, value.RepeatCount)
		write_u8(w, value.Reverses ? 1 : 0)
		write_f32(w, value.DelayTime)
	case .UDim:
		value := cast(^datatypes.UDim)ptr
		write_f32(w, value.Scale)
		write_f32(w, value.Offset)
	case .UDim2:
		value := cast(^datatypes.UDim2)ptr
		write_f32(w, value.X_Scale)
		write_f32(w, value.X_Offset)
		write_f32(w, value.Y_Scale)
		write_f32(w, value.Y_Offset)
	case .UniqueId:
		value := cast(^datatypes.UniqueId)ptr
		write_i64(w, value.Random)
		write_u32(w, value.Time)
		write_u32(w, value.Index)
	case .Vector2:
		value := cast(^datatypes.Vector2)ptr
		write_f32(w, value.X)
		write_f32(w, value.Y)
	case .Vector2int16:
		value := cast(^datatypes.Vector2int16)ptr
		write_i16(w, value.X)
		write_i16(w, value.Y)
	case .Vector3:
		value := cast(^datatypes.Vector3)ptr
		write_f32(w, value.x)
		write_f32(w, value.y)
		write_f32(w, value.z)
	case .Vector3int16:
		value := cast(^datatypes.Vector3int16)ptr
		write_i16(w, value.X)
		write_i16(w, value.Y)
		write_i16(w, value.Z)
	case:
		return false
	}

	return true
}

write_value :: proc(w: ^Writer, L: ^vm.State, registry: ^classes.Registry, value_index: int) -> bool {
	if w == nil || L == nil || registry == nil {
		return false
	}

	#partial switch vm.TypeOf(L, value_index) {
	case .Nil:
		write_u8(w, u8(Value_Tag.Nil))
		return true
	case .Boolean:
		write_u8(w, u8(Value_Tag.Boolean))
		write_u8(w, vm.ArgBoolean(L, value_index) ? 1 : 0)
		return true
	case .Number:
		write_u8(w, u8(Value_Tag.Number))
		write_f64(w, vm.ArgNumber(L, value_index))
		return true
	case .Integer:
		write_u8(w, u8(Value_Tag.Integer))
		write_i64(w, vm.ArgInteger(L, value_index))
		return true
	case .String:
		write_u8(w, u8(Value_Tag.String))
		write_string(w, vm.ArgString(L, value_index))
		return true
	case .Vector:
		write_u8(w, u8(Value_Tag.Vector3))
		x, y, z := vm.ArgVector3(L, value_index)
		write_f32(w, x)
		write_f32(w, y)
		write_f32(w, z)
		return true
	case .Userdata:
		binding := vm.UserdataBindingOf(L, value_index)
		if binding == nil {
			return false
		}
		if binding.name == "EnumItem" {
			item := cast(^enums.Enum_Item)vm.UserdataValue(L, value_index)
			if item == nil || item.enum_type == nil {
				return false
			}
			write_u8(w, u8(Value_Tag.EnumItem))
			write_string(w, item.enum_type.name)
			write_i64(w, item.value)
			return true
		}
		id, ok := datatype_id_of_binding(binding.name)
		if !ok {
			return false
		}
		write_u8(w, u8(Value_Tag.Userdata))
		write_u16(w, u16(id))
		return write_datatype_value(w, L, id, value_index)
	case:
		return false
	}
}

// ---------------------------------------------------------------------------
// Value decoding
// ---------------------------------------------------------------------------

read_datatype_value :: proc(r: ^Reader, L: ^vm.State, registry: ^datatypes.Registry, id: Datatype_Id) -> bool {
	switch id {
	case .Axes:
		x, o1 := read_u8(r)
		y, o2 := read_u8(r)
		z, o3 := read_u8(r)
		if !o1 || !o2 || !o3 {
			return false
		}
		datatypes.Push_Axes(L, registry, datatypes.Axes{X = x != 0, Y = y != 0, Z = z != 0})
	case .BrickColor:
		value, ok := read_i32(r)
		if !ok {
			return false
		}
		datatypes.Push_BrickColor(L, registry, datatypes.BrickColor_From_Number(value))
	case .CFrame:
		values := [12]f32{}
		if !read_f32s(r, values[:]) {
			return false
		}
		datatypes.Push_CFrame(L, registry, datatypes.CFrame{
			x = values[0], y = values[1], z = values[2],
			r00 = values[3], r01 = values[4], r02 = values[5],
			r10 = values[6], r11 = values[7], r12 = values[8],
			r20 = values[9], r21 = values[10], r22 = values[11],
		})
	case .Color3:
		values := [3]f32{}
		if !read_f32s(r, values[:]) {
			return false
		}
		datatypes.Push_Color3(L, registry, datatypes.Color3{R = values[0], G = values[1], B = values[2]})
	case .ColorSequence:
		count, ok := read_u32(r)
		if !ok {
			return false
		}
		if count > u32(len(r.data)) {
			return false
		}
		keypoints := make([]datatypes.ColorSequenceKeypoint, count)
		for i in 0 ..< int(count) {
			values := [4]f32{}
			if !read_f32s(r, values[:]) {
				delete(keypoints)
				return false
			}
			keypoints[i] = datatypes.ColorSequenceKeypoint{
				Time  = values[0],
				Value = datatypes.Color3{R = values[1], G = values[2], B = values[3]},
			}
		}
		datatypes.Push_ColorSequence(L, registry, datatypes.ColorSequence{Keypoints = keypoints})
		delete(keypoints)
	case .Content:
		uri, ok := read_string(r)
		if !ok {
			return false
		}
		content := datatypes.Content{uri = uri}
		if r.version >= 3 {
			object_id, id_ok := read_u32(r)
			object_kind, kind_ok := read_u8(r)
			if !id_ok || !kind_ok {
				return false
			}
			content.object_id = object_id
			content.object_kind = object_kind
		}
		datatypes.Push_Content(L, registry, content)
	case .DateTime:
		millis, ok := read_i64(r)
		if !ok {
			return false
		}
		datatypes.Push_DateTime(L, registry, datatypes.DateTime{UnixTimestampMillis = f64(millis)})
	case .Faces:
		top, o1 := read_u8(r)
		bottom, o2 := read_u8(r)
		left, o3 := read_u8(r)
		right, o4 := read_u8(r)
		front, o5 := read_u8(r)
		back, o6 := read_u8(r)
		if !o1 || !o2 || !o3 || !o4 || !o5 || !o6 {
			return false
		}
		datatypes.Push_Faces(L, registry, datatypes.Faces{
			Top = top != 0, Bottom = bottom != 0, Left = left != 0,
			Right = right != 0, Front = front != 0, Back = back != 0,
		})
	case .Font:
		family, ok := read_string(r)
		if !ok {
			return false
		}
		weight, o1 := read_i64(r)
		style, o2 := read_i64(r)
		if !o1 || !o2 {
			delete(family)
			return false
		}
		font := datatypes.Font{
			Family = strings.clone(family),
			Weight = enums.FontWeight(weight),
			Style  = enums.FontStyle(style),
		}
		datatypes.Push_Font(L, registry, font)
		delete(font.Family)
		delete(family)
	case .NumberRange:
		minimum, o1 := read_f32(r)
		maximum, o2 := read_f32(r)
		if !o1 || !o2 {
			return false
		}
		datatypes.Push_NumberRange(L, registry, datatypes.NumberRange{Min = minimum, Max = maximum})
	case .NumberSequence:
		count, ok := read_u32(r)
		if !ok {
			return false
		}
		if count > u32(len(r.data)) {
			return false
		}
		keypoints := make([]datatypes.NumberSequenceKeypoint, count)
		for i in 0 ..< int(count) {
			values := [3]f32{}
			if !read_f32s(r, values[:]) {
				delete(keypoints)
				return false
			}
			keypoints[i] = datatypes.NumberSequenceKeypoint{
				Time = values[0], Value = values[1], Envelope = values[2],
			}
		}
		// push_number_sequence clones Keypoints internally.
		datatypes.Push_NumberSequence(L, registry, datatypes.NumberSequence{Keypoints = keypoints})
		delete(keypoints)
	case .PathWaypoint:
		values := [3]f32{}
		if !read_f32s(r, values[:]) {
			return false
		}
		action, o1 := read_i64(r)
		label, o2 := read_string(r)
		if !o1 || !o2 {
			return false
		}
		waypoint := datatypes.PathWaypoint{
			Position = datatypes.Vector3{x = values[0], y = values[1], z = values[2]},
			Action   = enums.PathWaypointAction(action),
			Label    = strings.clone(label),
		}
		// push_path_waypoint clones Label internally.
		datatypes.Push_PathWaypoint(L, registry, waypoint)
		delete(waypoint.Label)
		delete(label)
	case .PhysicalProperties:
		values := [5]f32{}
		if !read_f32s(r, values[:]) {
			return false
		}
		datatypes.Push_PhysicalProperties(L, registry, datatypes.PhysicalProperties{
			Density = values[0], Friction = values[1], Elasticity = values[2],
			FrictionWeight = values[3], ElasticityWeight = values[4],
		})
	case .Quaternion:
		values := [4]f32{}
		if !read_f32s(r, values[:]) {
			return false
		}
		datatypes.Push_Quaternion(L, registry, datatypes.Quaternion{
			X = values[0], Y = values[1], Z = values[2], W = values[3],
		})
	case .Region3:
		values := [6]f32{}
		if !read_f32s(r, values[:]) {
			return false
		}
		datatypes.Push_Region3(L, registry, datatypes.Region3{
			Min = datatypes.Vector3{x = values[0], y = values[1], z = values[2]},
			Max = datatypes.Vector3{x = values[3], y = values[4], z = values[5]},
		})
	case .Region3int16:
		values := [6]i16{}
		if !read_i16s(r, values[:]) {
			return false
		}
		datatypes.Push_Region3int16(L, registry, datatypes.Region3int16{
			Min = datatypes.Vector3int16{X = values[0], Y = values[1], Z = values[2]},
			Max = datatypes.Vector3int16{X = values[3], Y = values[4], Z = values[5]},
		})
	case .SecurityCapabilities:
		low, o1 := read_u64(r)
		high, o2 := read_u64(r)
		if !o1 || !o2 {
			return false
		}
		datatypes.Push_SecurityCapabilities(L, registry, datatypes.SecurityCapabilities{bits_low = low, bits_high = high})
	case .TweenInfo:
		time, o1 := read_f32(r)
		style, o2 := read_i64(r)
		direction, o3 := read_i64(r)
		repeat, o4 := read_i32(r)
		reverses, o5 := read_u8(r)
		delay, o6 := read_f32(r)
		if !o1 || !o2 || !o3 || !o4 || !o5 || !o6 {
			return false
		}
		datatypes.Push_TweenInfo(L, registry, datatypes.TweenInfo{
			Time = time,
			EasingStyle = enums.EasingStyle(style),
			EasingDirection = enums.EasingDirection(direction),
			RepeatCount = repeat,
			Reverses = reverses != 0,
			DelayTime = delay,
		})
	case .UDim:
		scale, o1 := read_f32(r)
		offset, o2 := read_f32(r)
		if !o1 || !o2 {
			return false
		}
		datatypes.Push_UDim(L, registry, datatypes.UDim{Scale = scale, Offset = offset})
	case .UDim2:
		values := [4]f32{}
		if !read_f32s(r, values[:]) {
			return false
		}
		datatypes.Push_UDim2(L, registry, datatypes.UDim2{
			X_Scale = values[0], X_Offset = values[1],
			Y_Scale = values[2], Y_Offset = values[3],
		})
	case .UniqueId:
		random, o1 := read_i64(r)
		time, o2 := read_u32(r)
		index, o3 := read_u32(r)
		if !o1 || !o2 || !o3 {
			return false
		}
		datatypes.Push_UniqueId(L, registry, datatypes.UniqueId{Random = random, Time = time, Index = index})
	case .Vector2:
		values := [2]f32{}
		if !read_f32s(r, values[:]) {
			return false
		}
		datatypes.Push_Vector2(L, registry, datatypes.Vector2{X = values[0], Y = values[1]})
	case .Vector2int16:
		x, o1 := read_i16(r)
		y, o2 := read_i16(r)
		if !o1 || !o2 {
			return false
		}
		datatypes.Push_Vector2int16(L, registry, datatypes.Vector2int16{X = x, Y = y})
	case .Vector3:
		values := [3]f32{}
		if !read_f32s(r, values[:]) {
			return false
		}
		datatypes.Push_Vector3(L, datatypes.Vector3{x = values[0], y = values[1], z = values[2]})
	case .Vector3int16:
		values := [3]i16{}
		if !read_i16s(r, values[:]) {
			return false
		}
		datatypes.Push_Vector3int16(L, registry, datatypes.Vector3int16{X = values[0], Y = values[1], Z = values[2]})
	case:
		return false
	}

	return true
}

read_value :: proc(r: ^Reader, L: ^vm.State, registry: ^classes.Registry) -> bool {
	if r == nil || L == nil || registry == nil {
		return false
	}

	tag_byte, ok := read_u8(r)
	if !ok {
		return false
	}

	switch Value_Tag(tag_byte) {
	case .Nil:
		vm.PushNil(L)
		return true
	case .Boolean:
		value, ok := read_u8(r)
		if !ok {
			return false
		}
		vm.PushBoolean(L, value != 0)
		return true
	case .Number:
		value, ok := read_f64(r)
		if !ok {
			return false
		}
		vm.PushNumber(L, value)
		return true
	case .Integer:
		value, ok := read_i64(r)
		if !ok {
			return false
		}
		vm.PushInteger(L, value)
		return true
	case .String:
		value, ok := read_string(r)
		if !ok {
			return false
		}
		vm.PushString(L, value)
		delete(value)
		return true
	case .Vector3:
		x, o1 := read_f32(r)
		y, o2 := read_f32(r)
		z, o3 := read_f32(r)
		if !o1 || !o2 || !o3 {
			return false
		}
		vm.PushVector3(L, x, y, z)
		return true
	case .Userdata:
		id, ok := read_u16(r)
		if !ok {
			return false
		}
		return read_datatype_value(r, L, registry.datatypes, Datatype_Id(id))
	case .EnumItem:
		enum_name, ok := read_string(r)
		if !ok {
			return false
		}
		value, value_ok := read_i64(r)
		if !value_ok {
			delete(enum_name)
			return false
		}
		// Always pushes exactly one value (nil if the item is unknown).
		_ = enums.Push_Item_By_Value(L, registry.enums, enum_name, value)
		delete(enum_name)
		return true
	case:
		return false
	}
}

// ---------------------------------------------------------------------------
// Property reading during serialization
// ---------------------------------------------------------------------------

// Getter calls can RaiseError (read-only members, security). Running them
// inside a protected call keeps a single bad property from aborting the whole
// serialization pass.
serialize_read_context :: struct {
	object:     ^classes.Object,
	descriptor: ^classes.Class_Descriptor,
	key:        string,
}

serialize_read_property :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	value := cast(^serialize_read_context)vm.UpvaluePointer(L, 1)
	if value == nil {
		return 0
	}
	base := vm.StackTop(L)
	handled := classes.descriptor_get(L, value.object, value.descriptor, value.key)
	if handled && vm.StackTop(L) == base + 1 {
		return 1
	}
	vm.SetStackTop(L, base)
	return 0
}

read_class_property :: proc(w: ^Writer, L: ^vm.State, registry: ^classes.Registry, object: ^classes.Object, descriptor: ^classes.Class_Descriptor, class_name: string, property: string) -> bool {
	base := vm.StackTop(L)

	read_context := serialize_read_context{object = object, descriptor = descriptor, key = property}
	vm.PushLightUserdata(L, &read_context)
	vm.PushFunction(L, "kine_read_property", serialize_read_property, 1)

	ok, _ := vm.ProtectedCall(L, 0, 1)
	if !ok {
		vm.SetStackTop(L, base)
		return false
	}
	if vm.StackTop(L) != base + 1 {
		vm.SetStackTop(L, base)
		return false
	}

	// A declared asset property holding a local path is rewritten to point at
	// the embedded copy. This has to happen before write_value runs, because
	// that is what puts the value into the stream.
	if kind, is_asset := asset_kind_of(class_name, property); is_asset {
		_ = replace_stack_asset(w, L, base + 1, kind)
	}
	offset := len(w.data)
	write_string(w, property)
	if !write_value(w, L, registry, base + 1) {
		resize(&w.data, offset)
		vm.SetStackTop(L, base)
		return false
	}
	vm.SetStackTop(L, base)
	return true
}

// ---------------------------------------------------------------------------
// Instance records
// ---------------------------------------------------------------------------

property_is_saveable :: proc(property: string) -> bool {
	for read_only in READ_ONLY_PROPERTIES {
		if read_only == property {
			return false
		}
	}
	return true
}

write_instance :: proc(w: ^Writer, L: ^vm.State, registry: ^classes.Registry, object: ^classes.Object) -> bool {
	if w == nil || L == nil || registry == nil || object == nil {
		return false
	}
	if object.class == nil {
		return false
	}

	descriptor := classes.Find_Class(registry, object.class.name)
	if descriptor == nil {
		return false
	}

	write_string(w, object.class.name)
	write_string(w, object.name)
	write_u8(w, object.archivable ? 1 : 0)
	write_i64(w, object.unique_id.Random)
	write_u32(w, object.unique_id.Time)
	write_u32(w, object.unique_id.Index)

	properties := classes.Get_Properties(registry, object)
	defer delete(properties)

	// Property count is patched in once all decodable properties are written.
	write_u32(w, 0)
	property_count_offset := len(w.data) - 4
	property_count: u32 = 0
	for property in properties {
		if !property_is_saveable(property) {
			continue
		}
		if read_class_property(w, L, registry, object, descriptor, object.class.name, property) {
			property_count += 1
		}
	}
	patch_u32(w, property_count_offset, property_count)

	// Attributes.
	write_u32(w, 0)
	attribute_count_offset := len(w.data) - 4
	attribute_count: u32 = 0
	for attribute in object.attributes {
		base := vm.StackTop(L)
		vm.PushRegistryReference(L, attribute.value_ref)

		offset := len(w.data)
		write_string(w, attribute.name)
		if write_value(w, L, registry, base + 1) {
			attribute_count += 1
		} else {
			resize(&w.data, offset)
		}
		vm.SetStackTop(L, base)
	}
	patch_u32(w, attribute_count_offset, attribute_count)

	// Children (non-archivable children are dropped, matching Clone).
	write_u32(w, 0)
	child_count_offset := len(w.data) - 4
	child_count: u32 = 0
	for child in object.children {
		if child == nil || child == object || !child.archivable {
			continue
		}
		if w.exclude_child != nil && w.exclude_child(object, child) {
			continue
		}
		offset := len(w.data)
		if write_instance(w, L, registry, child) {
			child_count += 1
		} else {
			resize(&w.data, offset)
		}
	}
	patch_u32(w, child_count_offset, child_count)

	return true
}

// ---------------------------------------------------------------------------
// Property application during deserialization
// ---------------------------------------------------------------------------

// Setters can RaiseError (wrong enum type, invalid parent, restricted member).
// Every setter is applied through a protected call to keep a single bad value
// from aborting the whole load.
deserialize_apply_context :: struct {
	registry:   ^classes.Registry,
	object:     ^classes.Object,
	descriptor: rawptr,
	key:        string,
}

deserialize_apply_property :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	value := cast(^deserialize_apply_context)vm.UpvaluePointer(L, 1)
	if value == nil {
		return 0
	}
	_ = classes.descriptor_set(L, value.object, value.descriptor, value.key, 1)
	return 0
}

apply_property :: proc(L: ^vm.State, registry: ^classes.Registry, object: ^classes.Object, descriptor: ^classes.Class_Descriptor, key: string, value_index: int) -> bool {
	if L == nil || object == nil || descriptor == nil {
		return false
	}
	_ = registry

	apply_context := deserialize_apply_context{registry = registry, object = object, descriptor = descriptor, key = key}
	vm.PushLightUserdata(L, &apply_context)
	vm.PushFunction(L, "kine_apply_property", deserialize_apply_property, 1)
	// lua_pcall expects the function below its arguments: push the value on top.
	vm.PushValue(L, value_index)

	ok, _ := vm.ProtectedCall(L, 1, 0)
	vm.SetStackTop(L, value_index - 1)
	return ok
}

deserialize_apply_attribute :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	value := cast(^deserialize_apply_context)vm.UpvaluePointer(L, 1)
	if value == nil {
		return 0
	}
	name := vm.ArgString(L, 1)
	_ = classes.Set_Attribute(L, value.object, name, 2)
	return 0
}

apply_attribute :: proc(L: ^vm.State, registry: ^classes.Registry, object: ^classes.Object, name: string, value_index: int) -> bool {
	if L == nil || object == nil {
		return false
	}
	_ = registry

	apply_context := deserialize_apply_context{registry = registry, object = object, descriptor = nil, key = ""}
	vm.PushLightUserdata(L, &apply_context)
	vm.PushFunction(L, "kine_apply_attribute", deserialize_apply_attribute, 1)
	// The closure expects (name, value) with the function below its arguments.
	vm.PushString(L, name)
	vm.PushValue(L, value_index)

	ok, _ := vm.ProtectedCall(L, 2, 0)
	vm.SetStackTop(L, value_index - 1)
	return ok
}

read_instance :: proc(r: ^Reader, L: ^vm.State, registry: ^classes.Registry, parent: ^classes.Object) -> (^classes.Object, bool) {
	if r == nil || L == nil || registry == nil {
		return nil, false
	}

	class_name, ok := read_string(r)
	if !ok {
		return nil, false
	}
	defer delete(class_name)

	object, object_ok := classes.Push_New(registry, &vm.VM{L = L}, class_name, false)
	if !object_ok || object == nil {
		return nil, false
	}
	// Push_New leaves userdata on the stack; the object stays alive through
	// the retained lua_ref, so we keep the native stack flat.
	vm.Pop(L)

	if parent != nil {
		classes.Set_Parent(object, parent)
	}

	name, name_ok := read_string(r)
	if !name_ok {
		classes.Destroy_Hierarchy(object)
		return nil, false
	}
	classes.Set_Name(object, name)
	delete(name)

	archivable, archivable_ok := read_u8(r)
	if !archivable_ok {
		classes.Destroy_Hierarchy(object)
		return nil, false
	}
	object.archivable = archivable != 0

	random, o1 := read_i64(r)
	time, o2 := read_u32(r)
	index, o3 := read_u32(r)
	if !o1 || !o2 || !o3 {
		classes.Destroy_Hierarchy(object)
		return nil, false
	}
	object.unique_id = datatypes.UniqueId{Random = random, Time = time, Index = index}

	descriptor := classes.Find_Class(registry, class_name)
	if descriptor == nil {
		classes.Destroy_Hierarchy(object)
		return nil, false
	}

	// Properties.
	property_count, property_count_ok := read_u32(r)
	if !property_count_ok {
		classes.Destroy_Hierarchy(object)
		return nil, false
	}
	for i in 0 ..< property_count {
		key, ok := read_string(r)
		if !ok {
			classes.Destroy_Hierarchy(object)
			return nil, false
		}
		if !read_value(r, L, registry) {
			delete(key)
			classes.Destroy_Hierarchy(object)
			return nil, false
		}
		value_index := vm.StackTop(L)
		if !apply_property(L, registry, object, descriptor, key, value_index) {
			fmt.eprintf("[kine] Deserialize skipped un-applyable property %s on %s (%s)\n", key, class_name, classes.Get_Name(object))
		}
		delete(key)
	}

	// Attributes.
	attribute_count, attribute_count_ok := read_u32(r)
	if !attribute_count_ok {
		classes.Destroy_Hierarchy(object)
		return nil, false
	}
	for i in 0 ..< attribute_count {
		name, ok := read_string(r)
		if !ok {
			classes.Destroy_Hierarchy(object)
			return nil, false
		}
		if !read_value(r, L, registry) {
			delete(name)
			classes.Destroy_Hierarchy(object)
			return nil, false
		}
		if !apply_attribute(L, registry, object, name, vm.StackTop(L)) {
			delete(name)
			classes.Destroy_Hierarchy(object)
			return nil, false
		}
		delete(name)
	}

	// Children.
	child_count, child_count_ok := read_u32(r)
	if !child_count_ok {
		classes.Destroy_Hierarchy(object)
		return nil, false
	}
	for i in 0 ..< child_count {
		child, ok := read_instance(r, L, registry, object)
		if !ok {
			classes.Destroy_Hierarchy(object)
			return nil, false
		}
		_ = child
	}

	return object, true
}

// ---------------------------------------------------------------------------
// Asset table
// ---------------------------------------------------------------------------

write_asset_table :: proc(w: ^Writer) -> bool {
	count := len(w.used_ids)
	if count > assetstore.MAX_ASSET_COUNT {
		fmt.eprintf("[kine] refusing to write %d assets (limit %d)\n", count, assetstore.MAX_ASSET_COUNT)
		return false
	}

	total: i64 = 0
	for id in w.used_ids {
		entry, ok := assetstore.Find(id)
		if !ok {
			fmt.eprintf("[kine] asset %s vanished before the table was written\n", id)
			return false
		}
		if len(entry.bytes) > assetstore.MAX_ASSET_BYTES {
			fmt.eprintf("[kine] asset %s is %d bytes, over the %d limit\n", id, len(entry.bytes), assetstore.MAX_ASSET_BYTES)
			return false
		}
		total += i64(len(entry.bytes))
		if total > i64(assetstore.MAX_ASSET_TOTAL_BYTES) {
			fmt.eprintf("[kine] embedded assets total %d bytes, over the %d limit\n", total, assetstore.MAX_ASSET_TOTAL_BYTES)
			return false
		}
	}

	write_u32(w, u32(count))
	for id in w.used_ids {
		entry, _ := assetstore.Find(id)
		write_string(w, entry.id)
		write_string(w, entry.path)
		write_u8(w, u8(entry.kind))
		write_var_u32(w, u32(len(entry.bytes)))
		append(&w.data, ..entry.bytes)
	}
	return true
}

// read_asset_table publishes every embedded blob before the instance tree is
// walked, so a property setter that decodes an asset finds its bytes waiting.
// Bytes are cloned out of the input buffer: Register_As takes ownership and
// `data` outlives this call.
read_asset_table :: proc(r: ^Reader) -> bool {
	count, ok := read_u32(r)
	if !ok {
		return false
	}
	if count > u32(assetstore.MAX_ASSET_COUNT) {
		fmt.eprintf("[kine] asset count %d exceeds the limit\n", count)
		return false
	}

	total: i64 = 0
	for i in 0 ..< int(count) {
		id, id_ok := read_string(r)
		if !id_ok {
			return false
		}
		path, path_ok := read_string(r)
		if !path_ok {
			delete(id)
			return false
		}
		kind_byte, kind_ok := read_u8(r)
		if !kind_ok {
			delete(id)
			delete(path)
			return false
		}
		length, length_ok := read_var_u32(r)
		if !length_ok {
			delete(id)
			delete(path)
			return false
		}
		if length > u32(assetstore.MAX_ASSET_BYTES) {
			fmt.eprintf("[kine] asset %s claims %d bytes, over the limit\n", id, length)
			delete(id)
			delete(path)
			return false
		}
		total += i64(length)
		if total > i64(assetstore.MAX_ASSET_TOTAL_BYTES) {
			fmt.eprintf("[kine] asset table declares %d bytes, over the limit\n", total)
			delete(id)
			delete(path)
			return false
		}

		bytes, bytes_ok := read_bytes(r, int(length))
		if !bytes_ok {
			delete(id)
			delete(path)
			return false
		}

		// Register_As consumes the bytes, so hand it a copy it may own.
		owned := slice.clone(bytes)
		accepted := assetstore.Register_As(id, owned, path, assetstore.Asset_Kind(kind_byte))
		if !accepted {
			fmt.eprintf("[kine] asset table entry %s is corrupt or duplicated\n", id)
			delete(id)
			delete(path)
			return false
		}
		delete(id)
		delete(path)
	}
	return true
}

// ---------------------------------------------------------------------------
// Terrain table
// ---------------------------------------------------------------------------

// KINE_TERRAIN_MAX_CELLS bounds a single cell run. It matches the replication
// snapshot cap so a map cannot hold terrain that a client would be unable to
// receive anyway.
KINE_TERRAIN_MAX_CELLS :: 4 * 1024 * 1024

// KINE_TERRAIN_MAX_COORDINATE matches the replication bound. A file claiming a
// coordinate beyond this is corrupt or hostile, and letting one through would
// place voxels far outside any renderable or collidable range.
KINE_TERRAIN_MAX_COORDINATE :: 16000

// KINE_TERRAIN_MAX_MATERIAL_COLOURS bounds the per-map palette override table.
KINE_TERRAIN_MAX_MATERIAL_COLOURS :: 4096

KINE_TERRAIN_CELL_BYTES :: 17

Kine_Terrain_Cell :: struct {
	x, y, z:   i32,
	material:  u32,
	occupancy: f32,
	water:     f32,
}

// Kine_Terrain is the serialized form of a map's voxel grid plus the terrain
// settings a map owns. It is deliberately plain data with no reference to the
// Terrain service, so the format stays independent of it and the service owns
// the translation in both directions.
Kine_Terrain :: struct {
	cells:                [dynamic]Kine_Terrain_Cell,
	voxel_size:           f32,
	iso_level:            f32,
	decoration:           bool,
	grass_length:         f32,
	water_color:          datatypes.Color3,
	water_reflectance:    f32,
	water_transparency:   f32,
	water_wave_size:      f32,
	water_wave_speed:     f32,
	material_colours:     map[u32]datatypes.Color3,
}

// Kine_Terrain_Destroy releases a table and everything it owns.
Kine_Terrain_Destroy :: proc(terrain: ^Kine_Terrain) {
	if terrain == nil {
		return
	}
	delete(terrain.cells)
	delete(terrain.material_colours)
	terrain^ = Kine_Terrain{}
}

kine_write_fixed16 :: proc(w: ^Writer, value: f32) {
	scaled := u16(clamp(value, 0, 1) * 65535.0 + 0.5)
	write_u16(w, scaled)
}

kine_read_fixed16 :: proc(r: ^Reader) -> (f32, bool) {
	value, ok := read_u16(r)
	if !ok {
		return 0, false
	}
	return f32(value) / 65535.0, true
}

write_terrain_table :: proc(w: ^Writer, terrain: ^Kine_Terrain) -> bool {
	if terrain == nil || !(terrain.voxel_size > 0) {
		// A map with no terrain is a complete map, so this is a valid section
		// rather than a missing one.
		write_u8(w, 0)
		return true
	}

	write_u8(w, 1)
	write_u8(w, terrain.decoration ? 1 : 0)
	write_f32(w, terrain.voxel_size)
	write_f32(w, terrain.iso_level)
	write_f32(w, terrain.grass_length)
	write_f32(w, terrain.water_reflectance)
	write_f32(w, terrain.water_transparency)
	write_f32(w, terrain.water_wave_size)
	write_f32(w, terrain.water_wave_speed)
	write_f32(w, terrain.water_color.R)
	write_f32(w, terrain.water_color.G)
	write_f32(w, terrain.water_color.B)

	colour_count: u32 = 0
	if terrain.material_colours != nil {
		for _ in terrain.material_colours {
			colour_count += 1
		}
	}
	write_u32(w, colour_count)
	if colour_count > 0 {
		// Sorted so the same palette always produces the same bytes, which keeps
		// saving a map free of spurious differences from map iteration order.
		keys := make([dynamic]u32, 0, int(colour_count))
		defer delete(keys)
		for material in terrain.material_colours {
			append(&keys, material)
		}
		sort.quick_sort_proc(keys[:], proc(a, b: u32) -> int {
			if a < b {return -1}
			if a > b {return 1}
			return 0
		})
		for material in keys {
			colour := terrain.material_colours[material]
			write_u32(w, material)
			write_f32(w, colour.R)
			write_f32(w, colour.G)
			write_f32(w, colour.B)
		}
	}

	write_u32(w, u32(len(terrain.cells)))
	for cell in terrain.cells {
		write_i32(w, cell.x)
		write_i32(w, cell.y)
		write_i32(w, cell.z)
		write_u8(w, u8(cell.material))
		kine_write_fixed16(w, cell.occupancy)
		kine_write_fixed16(w, cell.water)
	}
	return true
}

// read_terrain_table parses the section into out, which must be an unowned
// Kine_Terrain the caller already owns (see Kine_Terrain_Destroy).
//
// The section is always parsed and validated even when out is nil, so a caller
// that ignores terrain still rejects a corrupt file instead of quietly accepting
// one whose tail it never looked at.
read_terrain_table :: proc(r: ^Reader, out: ^Kine_Terrain) -> bool {
	present, ok := read_u8(r)
	if !ok {
		return false
	}
	// A map with no terrain is a complete, valid map, so this is not a failure.
	if present == 0 {
		return true
	}

	table: Kine_Terrain
	table.material_colours = make(map[u32]datatypes.Color3)
	// Every early return below runs this, so no partial table is ever leaked.
	// The success path clears the two owning fields after handing them over,
	// which turns this into a no-op.
	defer Kine_Terrain_Destroy(&table)

	decoration, decoration_ok := read_u8(r)
	voxel_size, voxel_size_ok := read_f32(r)
	iso_level, iso_level_ok := read_f32(r)
	grass_length, grass_ok := read_f32(r)
	reflectance, reflectance_ok := read_f32(r)
	transparency, transparency_ok := read_f32(r)
	wave_size, wave_size_ok := read_f32(r)
	wave_speed, wave_speed_ok := read_f32(r)
	red, red_ok := read_f32(r)
	green, green_ok := read_f32(r)
	blue, blue_ok := read_f32(r)
	if !decoration_ok || !voxel_size_ok || !iso_level_ok || !grass_ok ||
	   !reflectance_ok || !transparency_ok || !wave_size_ok || !wave_speed_ok ||
	   !red_ok || !green_ok || !blue_ok {
		fmt.eprintf("[kine] terrain table header is truncated\n")
		return false
	}
	// A zero or negative voxel size makes every world<->cell conversion divide by
	// zero, and an iso level of zero makes the isosurface degenerate. Both are
	// rejected rather than stored, the same rule the replication header decoder
	// applies.
	if !(voxel_size > 0) || !(iso_level > 0) {
		fmt.eprintf("[kine] terrain table has an unusable grid (voxel size %f, iso level %f)\n", voxel_size, iso_level)
		return false
	}

	table.voxel_size = voxel_size
	table.iso_level = iso_level
	table.decoration = decoration != 0
	table.grass_length = grass_length
	table.water_reflectance = reflectance
	table.water_transparency = transparency
	table.water_wave_size = wave_size
	table.water_wave_speed = wave_speed
	table.water_color = datatypes.Color3{red, green, blue}

	colour_count, colour_count_ok := read_u32(r)
	if !colour_count_ok || colour_count > KINE_TERRAIN_MAX_MATERIAL_COLOURS {
		fmt.eprintf("[kine] terrain material colour count %d is invalid\n", colour_count)
		return false
	}
	for _ in 0 ..< int(colour_count) {
		material, material_ok := read_u32(r)
		if !material_ok {
			return false
		}
		colour_red, colour_red_ok := read_f32(r)
		colour_green, colour_green_ok := read_f32(r)
		colour_blue, colour_blue_ok := read_f32(r)
		if !colour_red_ok || !colour_green_ok || !colour_blue_ok {
			return false
		}
		table.material_colours[material] = datatypes.Color3{colour_red, colour_green, colour_blue}
	}

	count, count_ok := read_u32(r)
	if !count_ok {
		return false
	}
	if count > u32(KINE_TERRAIN_MAX_CELLS) {
		fmt.eprintf("[kine] terrain table claims %d cells, over the limit\n", count)
		return false
	}
	// The count is a claim by the file, so it is checked against the bytes that
	// are actually present before a single cell is allocated. Otherwise a short
	// stream could ask for a multi-gigabyte reserve.
	available := len(r.data) - r.pos
	if i64(count) * KINE_TERRAIN_CELL_BYTES > i64(available) {
		fmt.eprintf("[kine] terrain table claims %d cells but only %d bytes remain\n", count, available)
		return false
	}

	table.cells = make([dynamic]Kine_Terrain_Cell, 0, int(count))
	for _ in 0 ..< int(count) {
		x, x_ok := read_i32(r)
		y, y_ok := read_i32(r)
		z, z_ok := read_i32(r)
		material, material_ok := read_u8(r)
		occupancy, occupancy_ok := kine_read_fixed16(r)
		water, water_ok := kine_read_fixed16(r)
		if !x_ok || !y_ok || !z_ok || !material_ok || !occupancy_ok || !water_ok {
			return false
		}
		if x < -KINE_TERRAIN_MAX_COORDINATE || x > KINE_TERRAIN_MAX_COORDINATE ||
		   y < -KINE_TERRAIN_MAX_COORDINATE || y > KINE_TERRAIN_MAX_COORDINATE ||
		   z < -KINE_TERRAIN_MAX_COORDINATE || z > KINE_TERRAIN_MAX_COORDINATE {
			fmt.eprintf("[kine] terrain cell coordinate is out of range\n")
			return false
		}
		append(&table.cells, Kine_Terrain_Cell {
			x = x,
			y = y,
			z = z,
			material = u32(material),
			occupancy = occupancy,
			water = water,
		})
	}

	// Ownership moves to the caller, so the local is emptied to keep the deferred
	// cleanup from releasing what was just handed over.
	if out != nil {
		out^ = table
		table.cells = nil
		table.material_colours = nil
	}
	return true
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

// Serialize writes an Instance hierarchy into a .KINE byte stream, embedding
// every referenced asset so the file is portable. The returned slice is owned
// by the caller (free it with delete).
Serialize :: proc(
	registry: ^classes.Registry,
	L: ^vm.State,
	object: ^classes.Object,
	exclude_child: proc(parent: ^classes.Object, object: ^classes.Object) -> bool = nil,
	terrain: ^Kine_Terrain = nil,
) -> ([]u8, bool) {
	return serialize(registry, L, object, KINE_VERSION, exclude_child, terrain)
}

// Serialize_Legacy writes the version 2 layout: no asset table, and asset
// properties keep the author's bare paths. It exists so the version 2 reader
// stays exercised, and for saves that must stay small and diff-friendly. Such a
// file only works on a machine that still has the referenced files.
Serialize_Legacy :: proc(
	registry: ^classes.Registry,
	L: ^vm.State,
	object: ^classes.Object,
	exclude_child: proc(parent: ^classes.Object, object: ^classes.Object) -> bool = nil,
) -> ([]u8, bool) {
	return serialize(registry, L, object, KINE_LEGACY_VERSION, exclude_child, nil)
}

serialize :: proc(
	registry: ^classes.Registry,
	L: ^vm.State,
	object: ^classes.Object,
	version: u8,
	exclude_child: proc(parent: ^classes.Object, object: ^classes.Object) -> bool,
	terrain: ^Kine_Terrain,
) -> ([]u8, bool) {
	if registry == nil || L == nil || object == nil {
		return nil, false
	}

	base := vm.StackTop(L)
	previous := vm.GetThreadSecurityCapabilities(L)
	vm.SetThreadSecurityCapabilities(L, vm.THREAD_SECURITY_ALL)
	defer vm.SetThreadSecurityCapabilities(L, previous)
	defer vm.SetStackTop(L, base)

	// The instance tree is built first because an asset reference is only
	// discovered while properties are read, and the asset table has to precede
	// the tree in the output. The tree buffer is then copied in one step.
	tree := Writer{
		data         = make([dynamic]u8, 0, 4096),
		exclude_child = exclude_child,
		embed_assets  = version >= KINE_ASSET_VERSION,
		version       = version,
	}
	defer delete(tree.data)
	defer for id in tree.used_ids {
		delete(id)
	}
	defer delete(tree.used_ids)
	defer delete(tree.used_seen)

	if !write_instance(&tree, L, registry, object) {
		return nil, false
	}

	writer := Writer{data = make([dynamic]u8, 0, len(tree.data) + 1024)}
	defer delete(writer.data)
	defer for id in writer.used_ids {
		delete(id)
	}
	defer delete(writer.used_ids)
	defer delete(writer.used_seen)

	// The tree walk is what discovered the assets, so its list is the one the
	// table describes. Hand ownership to the output writer before writing it.
	writer.used_ids = tree.used_ids
	writer.used_seen = tree.used_seen
	tree.used_ids = nil
	tree.used_seen = nil

	append(&writer.data, u8('K'), u8('I'), u8('N'), u8('E'), version)
	if version >= KINE_ASSET_VERSION && !write_asset_table(&writer) {
		return nil, false
	}
	// Copy the tree in one shot rather than element by element.
	tree_start := len(writer.data)
	resize(&writer.data, tree_start + len(tree.data))
	copy(writer.data[tree_start:], tree.data[:])

	// The terrain table trails the tree so a reader that only cares about
	// instances can stop after the tree it already understands. Only the
	// current layout carries one; the older layouts have no section to write.
	if version >= KINE_VERSION && !write_terrain_table(&writer, terrain) {
		return nil, false
	}

	return slice.clone(writer.data[:]), true
}

// Deserialize reads a .KINE byte stream and restores the Instance hierarchy
// under parent (which may be nil for a standalone root).
//
// terrain may be nil, in which case a map's voxel grid is parsed and validated
// but discarded. Pass an owned Kine_Terrain to also receive it.
Deserialize :: proc(
	registry: ^classes.Registry,
	L: ^vm.State,
	parent: ^classes.Object,
	data: []u8,
	terrain: ^Kine_Terrain = nil,
) -> (^classes.Object, bool) {
	if registry == nil || L == nil || data == nil {
		return nil, false
	}

	base := vm.StackTop(L)
	previous := vm.GetThreadSecurityCapabilities(L)
	vm.SetThreadSecurityCapabilities(L, vm.THREAD_SECURITY_ALL)
	defer vm.SetThreadSecurityCapabilities(L, previous)
	defer vm.SetStackTop(L, base)

	reader := Reader{data = data}

	magic, ok := read_bytes(&reader, 4)
	if !ok {
		return nil, false
	}
	if string(magic) != KINE_MAGIC {
		return nil, false
	}

	version, version_ok := read_u8(&reader)
	if !version_ok {
		return nil, false
	}
	// Now that the version is known and accepted, hand it to the reader so each
	// value record knows which layout to expect.
	reader.version = version
	// Version 2 has no asset table and version 3 has no terrain table. Accepting
	// both keeps older maps loadable; they simply have no embedded assets or no
	// voxel grid to restore.
	if version != KINE_VERSION && version != KINE_ASSET_VERSION && version != KINE_LEGACY_VERSION {
		return nil, false
	}

	// Publishing happens before the tree is walked so every property setter sees
	// its bytes. A failure here means the file is unusable, not just degraded.
	if version >= KINE_ASSET_VERSION && !read_asset_table(&reader) {
		return nil, false
	}

	object, root_ok := read_instance(&reader, L, registry, parent)
	if !root_ok {
		return nil, false
	}
	if version >= KINE_VERSION && !read_terrain_table(&reader, terrain) {
		classes.Destroy_Hierarchy(object)
		return nil, false
	}
	// Anything still unconsumed means the reader and the writer disagree about the
	// layout, so the stream is rejected rather than half-applied.
	if reader.pos != len(reader.data) {
		classes.Destroy_Hierarchy(object)
		return nil, false
	}

	return object, true
}
