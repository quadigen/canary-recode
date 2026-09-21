package serializer

import "base:runtime"
import "core:slice"
import "core:strings"
import classes "../classes"
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
//
//   string := varuint length + raw bytes
//   value  := u8 tag + payload (see Value_Tag below)

KINE_MAGIC :: "KINE"
KINE_VERSION :: 2
KINE_MAX_STRING_LENGTH :: 16 * 1024 * 1024

// Properties that are read-only in the engine (their setters RaiseError).
// They are skipped so a round trip never tries to write them back.
READ_ONLY_PROPERTIES := [?]string{
	"AbsolutePosition",
	"AbsoluteSize",
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
}

Reader :: struct {
	data: []u8,
	pos:  int,
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
		write_string(w, value.uri)
	case .DateTime:
		value := cast(^datatypes.DateTime)ptr
		write_i64(w, value.UnixTimestampMillis)
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
		datatypes.Push_Content(L, registry, datatypes.Content{uri = uri})
	case .DateTime:
		millis, ok := read_i64(r)
		if !ok {
			return false
		}
		datatypes.Push_DateTime(L, registry, datatypes.DateTime{UnixTimestampMillis = millis})
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

read_class_property :: proc(w: ^Writer, L: ^vm.State, registry: ^classes.Registry, object: ^classes.Object, descriptor: ^classes.Class_Descriptor, property: string) -> bool {
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
		if read_class_property(w, L, registry, object, descriptor, property) {
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
			delete(key)
			classes.Destroy_Hierarchy(object)
			return nil, false
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
// Public API
// ---------------------------------------------------------------------------

// Serialize writes an Instance hierarchy into a .KINE byte stream.
// The returned slice is owned by the caller (free it with delete).
Serialize :: proc(registry: ^classes.Registry, L: ^vm.State, object: ^classes.Object) -> ([]u8, bool) {
	if registry == nil || L == nil || object == nil {
		return nil, false
	}

	base := vm.StackTop(L)
	previous := vm.GetThreadSecurityCapabilities(L)
	vm.SetThreadSecurityCapabilities(L, vm.THREAD_SECURITY_ALL)
	defer vm.SetThreadSecurityCapabilities(L, previous)
	defer vm.SetStackTop(L, base)

	writer := Writer{data = make([dynamic]u8, 0, 4096)}
	defer delete(writer.data)

	append(&writer.data, u8('K'), u8('I'), u8('N'), u8('E'), KINE_VERSION)
	if !write_instance(&writer, L, registry, object) {
		return nil, false
	}

	return slice.clone(writer.data[:]), true
}

// Deserialize reads a .KINE byte stream and restores the Instance hierarchy
// under parent (which may be nil for a standalone root).
Deserialize :: proc(registry: ^classes.Registry, L: ^vm.State, parent: ^classes.Object, data: []u8) -> (^classes.Object, bool) {
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
	if version != KINE_VERSION {
		return nil, false
	}

	object, root_ok := read_instance(&reader, L, registry, parent)
	if !root_ok {
		return nil, false
	}
	if reader.pos != len(reader.data) {
		classes.Destroy_Hierarchy(object)
		return nil, false
	}

	return object, true
}
