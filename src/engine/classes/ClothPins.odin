package classes

import datatypes "../datatypes"
import vm "../vm"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:strings"

Cloth_Pin_Property_Kind :: enum {Attachment, Offset, Weight}

Cloth_Pin_Property :: proc(key: string) -> (int, Cloth_Pin_Property_Kind, bool) {
	prefixes := [Cloth_Pin_Property_Kind]string{.Attachment = "PinAttachment", .Offset = "PinOffset", .Weight = "PinWeight"}
	for prefix, kind in prefixes {
		if !strings.has_prefix(key, prefix) {continue}
		suffix := key[len(prefix):]
		if len(suffix) == 0 || len(suffix) > 4 || suffix[0] == '0' {break}
		n := 0
		for c in suffix {
			if c < '0' || c > '9' {return 0, {}, false}
			n = n * 10 + int(c - '0')
		}
		return n - 1, kind, n <= (CLOTH_MAX_SEGMENTS + 1) * (CLOTH_MAX_SEGMENTS + 1)
	}
	return 0, {}, false
}

Cloth_Fold_Offset :: proc(cloth: ^Cloth, column: int) -> f32 {
	if cloth.fold_count == 0 || column == 0 || column == cloth.segments_x {return 0}
	// Use at least roughly three samples per fold on coarse meshes.
	folds := min(cloth.fold_count, max(1, cloth.segments_x / 3))
	return cloth.fold_depth * math.sin(f32(column * folds) / f32(cloth.segments_x) * 2 * f32(math.PI))
}

Cloth_Pin_Position :: proc(cloth: ^Cloth, frame: datatypes.CFrame, i: int) -> [3]f32 {
	offset := cloth.pin_offsets[i]
	point := datatypes.CFrame_PointToWorldSpace(frame, {f64(offset.x), f64(offset.y), f64(offset.z)})
	origin := cloth.simulation_origin
	return {f32(point.x - origin.x), f32(point.y - origin.y), f32(point.z - origin.z)}
}

cloth_target_pin :: proc(cloth: ^Cloth, i: int, target: [3]f32, weight: f32 = 1) {
	cloth.pinned[i] = weight == 1
	cloth.active_weights[i] = weight
	cloth.pin_targets[i] = target
}

cloth_pin_vector :: proc(rotation: datatypes.CFrame, offset: [3]f32) -> [3]f32 {
	v := datatypes.CFrame_VectorToWorldSpace(rotation, {f64(offset.x), f64(offset.y), f64(offset.z)})
	return {f32(v.x), f32(v.y), f32(v.z)}
}

Cloth_Pin_Targets :: proc(cloth: ^Cloth, workspace: ^Object, anchors: [2]datatypes.CFrame, count: int) {
	for &pinned, i in cloth.pinned {
		pinned = false
		cloth.active_weights[i] = 0
	}
	if cloth.custom_pins {
		last_pin: ^Object
		frame: datatypes.CFrame
		valid := false
		for pin, i in cloth.pin_attachments {
			if pin == nil {continue}
			if pin != last_pin {
				frame, valid = cloth_anchor_frame(pin, workspace)
				last_pin = pin
			}
			if valid {cloth_target_pin(cloth, i, Cloth_Pin_Position(cloth, frame, i), cloth.pin_weights[i])}
		}
		return
	}
	nx, ny := cloth.segments_x, cloth.segments_y
	stride := nx + 1
	first := Cloth_Local_Position(cloth, anchors[0])
	if count == 0 {first = cloth.rest[0]}
	last := cloth.rest[nx]
	rotation := datatypes.CFrame_Identity
	if count > 0 {
		rotation = datatypes.CFrame_Mul_CFrame(datatypes.CFrame_Rotation(anchors[0]),
			datatypes.CFrame_Inverse(datatypes.CFrame_Rotation(cloth.rest_anchor)))
		last = first + cloth_pin_vector(rotation, cloth.rest[nx] - cloth.rest[0])
	}
	if count == 2 {last = Cloth_Local_Position(cloth, anchors[1])}
	switch cloth.cloth_type {
	case .Custom:
		return
	case .Flag:
		for y in 0..=ny {
			t := f32(y) / f32(ny)
			target := first + cloth_pin_vector(rotation, cloth.rest[y * stride] - cloth.rest[0])
			if count == 2 {target = first + (last - first) * t}
			cloth_target_pin(cloth, y * stride, target)
		}
	case .Cape, .Curtain:
		varied := cloth.rest[nx] - cloth.rest[0]
		normal := linalg.cross(last - first, [3]f32{0, -1, 0})
		if linalg.dot(normal, normal) > 0.000001 {normal = linalg.normalize(normal)} else {normal = {}}
		for x in 0..=nx {
			t := f32(x) / f32(nx)
			profile := cloth_pin_vector(rotation, cloth.rest[x] - cloth.rest[0] - varied * t)
			if count == 2 && normal != {} {profile = normal * Cloth_Fold_Offset(cloth, x)}
			cloth_target_pin(cloth, x, first + (last - first) * t + profile)
		}
	case .Hammock:
		for y in 0..=ny {
			a := y * stride
			offset := cloth_pin_vector(rotation, cloth.rest[a] - cloth.rest[0])
			cloth_target_pin(cloth, a, first + offset)
			cloth_target_pin(cloth, a + nx, last + offset)
		}
	case .Flat:
		if count == 0 {return}
		if count == 1 {
			cloth_target_pin(cloth, nx / 2, first)
			return
		}
		cloth_target_pin(cloth, 0, first)
		cloth_target_pin(cloth, nx, last)
		if cloth.fold_count > 0 && cloth.fold_depth > 0 {
			normal := linalg.cross(last - first, [3]f32{0, -1, 0})
			if linalg.dot(normal, normal) < 0.000001 {return}
			normal = linalg.normalize(normal)
			for i in 1..<nx {
				target := first + (last - first) * (f32(i) / f32(nx)) + normal * Cloth_Fold_Offset(cloth, i)
				cloth_target_pin(cloth, i, target)
			}
		}
	}
}

cloth_set_pin :: proc(cloth: ^Cloth, i: int, pin: ^Object, offset: [3]f32 = {}, weight: f32 = 1) {
	cloth.pin_attachments[i] = pin
	cloth.pin_offsets[i] = offset
	cloth.pin_weights[i] = weight
	cloth.sleep_frames = 0
}

cloth_custom_pin_mode :: proc(L: ^vm.State, cloth: ^Cloth) {
	if cloth.custom_pins {return}
	cloth.custom_pins = true
	cloth.sleep_frames = 0
	Object_Fire_Property_Changed(&cloth.object, "CustomPins", L)
}

cloth_uv_valid :: proc(uv: datatypes.Vector2) -> bool {
	return uv.X >= 0 && uv.X <= 1 && uv.Y >= 0 && uv.Y <= 1
}

cloth_uv_index :: proc(cloth: ^Cloth, uv: datatypes.Vector2) -> int {
	x := int(math.floor(uv.X * f32(cloth.segments_x) + 0.5))
	y := int(math.floor(uv.Y * f32(cloth.segments_y) + 0.5))
	return y * (cloth.segments_x + 1) + x
}

cloth_pin_namecall :: proc(L: ^vm.State, cloth: ^Cloth, registry: ^datatypes.Registry, method: string) -> (i32, bool) {
	count := len(cloth.particles)
	switch method {
	case "PinVertex", "UnpinVertex", "GetVertexPosition", "SetPinWeight", "GetPinWeight":
		n := vm.ArgNumber(L, 2)
		if !(n >= 1 && n <= f64(count) && n == math.floor(n)) {return vm.RaiseError(L, "Invalid cloth vertex index"), true}
		i := int(n) - 1
		if method == "GetVertexPosition" {
			if !cloth.initialized {
				for ancestor := cloth.parent; ancestor != nil; ancestor = ancestor.parent {
					if Is_A(ancestor, "Workspace") {Cloth_Prepare_Surface(cloth, ancestor); break}
				}
				if !cloth.initialized {return vm.RaiseError(L, "Cloth has no initialized pose"), true}
			}
			p := cloth.particles[i].position
			o := cloth.simulation_origin
			datatypes.Push_Vector3(L, {o.x + f64(p.x), o.y + f64(p.y), o.z + f64(p.z)})
			return 1, true
		}
		if method == "GetPinWeight" {
			weight := cloth.pin_weights[i] if cloth.pin_attachments[i] != nil else 0
			vm.PushNumber(L, f64(weight))
			return 1, true
		}
		weight := f32(1)
		if method == "SetPinWeight" {
			n := vm.ArgNumber(L, 4)
			if !(n >= 0 && n <= 1) {return vm.RaiseError(L, "Cloth pin weight must be between zero and one"), true}
			weight = f32(n)
		}
		pin: ^Object
		offset: [3]f32
		if weight > 0 && (method == "PinVertex" || method == "SetPinWeight") {
			pin = object_from_argument(L, 3)
			if !Is_A_Class(pin, &Attachment_Class) || pin.destroyed {return vm.RaiseError(L, "Expected a live Attachment"), true}
			if method == "SetPinWeight" {
				offset = cloth.pin_offsets[i]
				if cloth.pin_attachments[i] != pin && cloth.initialized {
					frame := Attachment_World_Frame(cast(^Attachment)pin)
					p, o := cloth.particles[i].position, cloth.simulation_origin
					local_offset := datatypes.CFrame_PointToObjectSpace(frame, {o.x + f64(p.x), o.y + f64(p.y), o.z + f64(p.z)})
					if !cloth_finite_vector(local_offset) || max(abs(local_offset.x), abs(local_offset.y), abs(local_offset.z)) > 4096 {
						return vm.RaiseError(L, "Cloth vertex is too far from its attachment"), true
					}
					offset = {f32(local_offset.x), f32(local_offset.y), f32(local_offset.z)}
				}
			}
		}
		cloth_set_pin(cloth, i, pin, offset, weight if pin != nil else 1)
		cloth_custom_pin_mode(L, cloth)
		Object_Fire_Property_Changed(&cloth.object, fmt.tprintf("PinAttachment%d", i + 1), L)
	case "PinPoint", "PinRegion", "UnpinPoint":
		a := datatypes.Arg_Vector2(L, 2, registry)
		if !cloth_uv_valid(a) {return vm.RaiseError(L, "Expected normalized cloth coordinates"), true}
		b := a
		arg := 3
		if method == "PinRegion" {
			b = datatypes.Arg_Vector2(L, 3, registry)
			arg = 4
			if !cloth_uv_valid(b) || b.X < a.X || b.Y < a.Y {return vm.RaiseError(L, "Invalid cloth region"), true}
		}
		pin: ^Object
		if method != "UnpinPoint" {
			pin = object_from_argument(L, arg)
			if !Is_A_Class(pin, &Attachment_Class) || pin.destroyed {return vm.RaiseError(L, "Expected a live Attachment"), true}
		}
		stride := cloth.segments_x + 1
		lo, hi := cloth_uv_index(cloth, a), cloth_uv_index(cloth, b)
		if method == "PinRegion" {
			// Degenerate axes select the nearest row or column. Other axes use inclusive bounds.
			x0, x1 := lo % stride, hi % stride
			y0, y1 := lo / stride, hi / stride
			if a.X != b.X {
				x0, x1 = int(math.ceil(a.X * f32(cloth.segments_x) - 0.00001)), int(math.floor(b.X * f32(cloth.segments_x) + 0.00001))
			}
			if a.Y != b.Y {
				y0, y1 = int(math.ceil(a.Y * f32(cloth.segments_y) - 0.00001)), int(math.floor(b.Y * f32(cloth.segments_y) + 0.00001))
			}
			if x0 > x1 || y0 > y1 {return 0, true}
			lo, hi = y0 * stride + x0, y1 * stride + x1
		}
		for row in lo / stride ..= hi / stride {
			for col in lo % stride ..= hi % stride {
				dx, dy := col - lo % stride, row - lo / stride
				us := f32(lo % stride) / f32(cloth.segments_x)
				u := f32(col) / f32(cloth.segments_x)
				offset := [3]f32{
					Cloth_Gathered_Width(cloth) * f32(dx) / f32(cloth.segments_x),
					-cloth.size.Y * f32(dy) / f32(cloth.segments_y) - Cloth_Sag(cloth, u) + Cloth_Sag(cloth, us),
					Cloth_Fold_Offset(cloth, col) - Cloth_Fold_Offset(cloth, lo % stride),
				}
				cloth_set_pin(cloth, row * stride + col, pin, offset)
			}
		}
		cloth_custom_pin_mode(L, cloth)
		for row in lo / stride ..= hi / stride {
			for col in lo % stride ..= hi % stride {
				Object_Fire_Property_Changed(&cloth.object, fmt.tprintf("PinAttachment%d", row * stride + col + 1), L)
			}
		}
	case "ClearPins":
		for pin, i in cloth.pin_attachments {
			if pin != nil {cloth_set_pin(cloth, i, nil)}
		}
		if cloth.custom_pins {Object_Fire_Property_Changed(&cloth.object, "CustomPins", L)}
		else {cloth_custom_pin_mode(L, cloth)}
	case "ResetSimulation":
		cloth.initialized = false
		cloth.impulse = {}
	case "GetPins":
		vm.NewTable(L, 0, count)
		for pin, i in cloth.pin_attachments {
			if pin == nil {continue}
			Push_Object(L, pin)
			vm.RawSetIndex(L, -2, i + 1)
		}
		return 1, true
	case "GetVertexCount":
		vm.PushNumber(L, f64(count))
		return 1, true
	case:
		return 0, false
	}
	cloth.config_revision += 1
	Render_3D_Mark_Dirty()
	return 0, true
}
