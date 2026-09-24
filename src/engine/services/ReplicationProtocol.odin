#+build !js
package services

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

replication_put_u32 :: proc(bytes: ^[dynamic]u8, value: u32) {
	for shift := 0; shift < 32; shift += 8 {append(bytes, u8(value >> u32(shift)))}
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

replication_read_u32 :: proc(reader: ^Replication_Reader) -> u32 {
	if !reader.valid || reader.offset + 4 > len(reader.data) {reader.valid = false; return 0}
	value: u32
	for shift := 0; shift < 32; shift += 8 {
		value |= u32(reader.data[reader.offset]) << u32(shift)
		reader.offset += 1
	}
	return value
}

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
