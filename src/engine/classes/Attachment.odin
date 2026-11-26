package classes

import kineffi "../bindings"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:math"
import "core:math/linalg"

Attachment_Class := Class_Info {
	name   = "Attachment",
	parent = &Instance_Class,
}

Attachment :: struct {
	using object:   Object,
	position:       datatypes.Vector3,
	orientation:    datatypes.Vector3,
	axis:           datatypes.Vector3,
	secondary_axis: datatypes.Vector3,
}

Attachment_Init :: proc() -> Attachment {
	return Attachment {
		object = Object_Init(&Attachment_Class),
		position = {0, 0, 0},
		orientation = {0, 0, 0},
		axis = {1, 0, 0},
		secondary_axis = {0, 1, 0},
	}
}

Attachment_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	attachment := new(Attachment)
	attachment^ = Attachment_Init()
	attachment.name = "Attachment"
	return &attachment.object
}

Attachment_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Cloth_Forget_Attachment(object)
	handles_forget_adornee(object)
	Object_Destroy(object)
	free(cast(^Attachment)object)
}

Attachment_Local_Frame :: proc(attachment: ^Attachment) -> datatypes.CFrame {
	axis, normal, valid := constraint_attachment_axes(attachment)
	if !valid {return datatypes.CFrame_New_Position(attachment.position)}
	back := linalg.cross(axis, normal)
	return datatypes.CFrame_FromMatrix(
		attachment.position,
		{f64(axis.x), f64(axis.y), f64(axis.z)},
		{f64(normal.x), f64(normal.y), f64(normal.z)},
		{f64(back.x), f64(back.y), f64(back.z)},
	)
}

Attachment_Parent_Frame :: proc(attachment: ^Attachment) -> datatypes.CFrame {
	if attachment != nil &&
	   Is_A_Class(&attachment.object, &BoneAttachment_Class) &&
	   attachment.parent != nil &&
	   Is_A_Class(attachment.parent, &MeshPart_Class) {
		mesh := cast(^MeshPart)attachment.parent
		bone_name := (cast(^BoneAttachment)attachment).bone_name
		if mesh.native_mesh != nil && bone_name != "" {
			index := Animation_MeshPart_Find_Bone(mesh.native_mesh, bone_name)
			if index >= 0 {
				if frame, ok := Animation_MeshPart_Bone_World_CFrame(mesh, int(index)); ok {
					return frame
				}
			}
		}
	}
	for parent := attachment.parent; parent != nil; parent = parent.parent {
		if parent.destroyed {continue}
		if Is_A_Class(parent, &Part_Class) {return (cast(^Part)parent).cframe}
		if Is_A_Class(
			parent,
			&Attachment_Class,
		) {return Attachment_World_Frame(cast(^Attachment)parent)}
	}
	return datatypes.CFrame_Identity
}

Attachment_World_Frame :: proc(attachment: ^Attachment) -> datatypes.CFrame {
	return datatypes.CFrame_Mul_CFrame(
		Attachment_Parent_Frame(attachment),
		Attachment_Local_Frame(attachment),
	)
}

attachment_set_local_frame :: proc(attachment: ^Attachment, frame: datatypes.CFrame) {
	attachment.position = datatypes.CFrame_Position(frame)
	attachment.axis = datatypes.CFrame_RightVector(frame)
	attachment.secondary_axis = datatypes.CFrame_UpVector(frame)
	attachment.orientation = {}
}

attachment_orientation :: proc(frame: datatypes.CFrame) -> datatypes.Vector3 {
	x, y, z := datatypes.CFrame_ToEulerAnglesYXZ(frame)
	return {math.to_degrees(x), math.to_degrees(y), math.to_degrees(z)}
}

attachment_namecall :: proc(
	L: ^vm.State,
	object: ^Object,
	dt: ^datatypes.Registry,
	en: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	if method != "GetConstraints" {return 0, false}
	vm.NewTable(L, 0)
	registry := object.signal_registry
	if registry == nil {return 1, true}
	index := 1
	for descriptor in registry.classes {
		if !Is_Class_A(descriptor.info, &Constraint_Class) {continue}
		for candidate in descriptor.instances {
			if candidate == nil ||
			   candidate.destroyed ||
			   !Object_Is_Accessible(L, candidate) {continue}
			constraint := cast(^Constraint)candidate
			if constraint.attachment0 != object && constraint.attachment1 != object {continue}
			Push_Object(L, candidate)
			vm.SetArrayValue(L, -2, index)
			index += 1
		}
	}
	return 1, true
}

Attachment_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	attachment := cast(^Attachment)object

	switch key {
	case "CFrame":
		if datatype_registry == nil {return false}
		datatypes.Push_CFrame(L, datatype_registry, Attachment_Local_Frame(attachment))
	case "WorldCFrame":
		datatypes.Push_CFrame(L, datatype_registry, Attachment_World_Frame(attachment))
	case "WorldPosition":
		datatypes.Push_Vector3(L, datatypes.CFrame_Position(Attachment_World_Frame(attachment)))
	case "WorldOrientation":
		datatypes.Push_Vector3(L, attachment_orientation(Attachment_World_Frame(attachment)))
	case "WorldAxis":
		datatypes.Push_Vector3(L, datatypes.CFrame_RightVector(Attachment_World_Frame(attachment)))
	case "WorldSecondaryAxis":
		datatypes.Push_Vector3(L, datatypes.CFrame_UpVector(Attachment_World_Frame(attachment)))
	case "GetConstraints":
		vm.PushUserdataMethod(L, key)
	case "Position":
		datatypes.Push_Vector3(L, attachment.position)
	case "Orientation":
		datatypes.Push_Vector3(L, attachment_orientation(Attachment_Local_Frame(attachment)))
	case "Axis":
		datatypes.Push_Vector3(L, datatypes.CFrame_RightVector(Attachment_Local_Frame(attachment)))
	case "SecondaryAxis":
		datatypes.Push_Vector3(L, datatypes.CFrame_UpVector(Attachment_Local_Frame(attachment)))
	case:
		return false
	}

	return true
}

Attachment_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	attachment := cast(^Attachment)object

	switch key {
	case "CFrame":
		if datatype_registry == nil {return false}
		frame := datatypes.Arg_CFrame(L, value_index, datatype_registry)
		attachment_set_local_frame(attachment, frame)
	case "WorldCFrame":
		frame := datatypes.Arg_CFrame(L, value_index, datatype_registry)
		attachment_set_local_frame(
			attachment,
			datatypes.CFrame_Mul_CFrame(
				datatypes.CFrame_Inverse(Attachment_Parent_Frame(attachment)),
				frame,
			),
		)
	case "WorldPosition":
		attachment.position = datatypes.CFrame_PointToObjectSpace(
			Attachment_Parent_Frame(attachment),
			datatypes.Arg_Vector3(L, value_index),
		)
	case "WorldOrientation":
		angles := datatypes.Arg_Vector3(L, value_index)
		frame := datatypes.CFrame_FromEulerAnglesYXZ(
			math.to_radians(angles.x),
			math.to_radians(angles.y),
			math.to_radians(angles.z),
		)
		world_position := datatypes.CFrame_Position(Attachment_World_Frame(attachment))
		frame.x, frame.y, frame.z = world_position.x, world_position.y, world_position.z
		attachment_set_local_frame(
			attachment,
			datatypes.CFrame_Mul_CFrame(
				datatypes.CFrame_Inverse(Attachment_Parent_Frame(attachment)),
				frame,
			),
		)
	case "Position":
		attachment.position = datatypes.Arg_Vector3(L, value_index)
	case "Orientation":
		angles := datatypes.Arg_Vector3(L, value_index)
		frame := datatypes.CFrame_FromEulerAnglesYXZ(
			math.to_radians(angles.x),
			math.to_radians(angles.y),
			math.to_radians(angles.z),
		)
		frame.x, frame.y, frame.z =
			attachment.position.x, attachment.position.y, attachment.position.z
		attachment_set_local_frame(attachment, frame)
	case "Axis", "WorldAxis":
		attachment.secondary_axis = datatypes.CFrame_UpVector(Attachment_Local_Frame(attachment))
		axis := datatypes.Arg_Vector3(L, value_index)
		if key == "WorldAxis" {
			axis = datatypes.CFrame_VectorToObjectSpace(Attachment_Parent_Frame(attachment), axis)
		}
		attachment.axis = axis
		attachment.orientation = {}
	case "SecondaryAxis", "WorldSecondaryAxis":
		attachment.axis = datatypes.CFrame_RightVector(Attachment_Local_Frame(attachment))
		axis := datatypes.Arg_Vector3(L, value_index)
		if key == "WorldSecondaryAxis" {
			axis = datatypes.CFrame_VectorToObjectSpace(Attachment_Parent_Frame(attachment), axis)
		}
		attachment.secondary_axis = axis
		attachment.orientation = {}
	case:
		return false
	}

	return true
}

Attachment_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^Attachment)source
	dst := cast(^Attachment)destination

	dst.position = src.position
	dst.orientation = src.orientation
	dst.axis = src.axis
	dst.secondary_axis = src.secondary_axis
}

rotate_by_quat :: proc(q: kineffi.JPH_Quat, v: kineffi.JPH_Vec3) -> kineffi.JPH_Vec3 {

	tx := 2 * (q.y * v.z - q.z * v.y)
	ty := 2 * (q.z * v.x - q.x * v.z)
	tz := 2 * (q.x * v.y - q.y * v.x)
	return {
		v.x + q.w * tx + (q.y * tz - q.z * ty),
		v.y + q.w * ty + (q.z * tx - q.x * tz),
		v.z + q.w * tz + (q.x * ty - q.y * tx),
	}
}

resolve_attachment :: proc(
	object: ^Object,
	system: kineffi.JPH_PhysicsSystemRef,
	body_ids: []kineffi.JPH_BodyID,
) -> (
	id: kineffi.JPH_BodyID,
	local: kineffi.JPH_Vec3,
	world: kineffi.JPH_RVec3,
	ok: bool,
) {
	if object == nil || object.destroyed || !Is_A_Class(object, &Attachment_Class) {return}
	attachment := cast(^Attachment)object

	id, ok = Attachment_GetPhysicsBody(attachment, body_ids)
	if !ok {return}

	local = {f32(attachment.position.x), f32(attachment.position.y), f32(attachment.position.z)}

	bi := kineffi.JPH_PhysicsSystem_GetBodyInterface(system)
	pos: kineffi.JPH_RVec3
	rot: kineffi.JPH_Quat
	kineffi.JPH_BodyInterface_GetPositionAndRotation(bi, id, &pos, &rot)

	offset := rotate_by_quat(rot, local)
	world = {pos.x + f64(offset.x), pos.y + f64(offset.y), pos.z + f64(offset.z)}
	return id, local, world, true
}

Attachment_GetPhysicsBody :: proc(
	attachment: ^Attachment,
	body_ids: []kineffi.JPH_BodyID,
) -> (
	id: kineffi.JPH_BodyID,
	ok: bool,
) {
	parent := cast(^Part)attachment.parent
	if Is_A(parent, "Part") {
		body_id, ok := get_body_id(parent, body_ids)

		return body_id, ok
	} else {
		return 0, false
	}
}

attachment_parallel_get :: proc(
	L: ^vm.State,
	object: ^Object,
	d: ^datatypes.Registry,
	e: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "CFrame",
	     "WorldCFrame",
	     "WorldPosition",
	     "WorldOrientation",
	     "WorldAxis",
	     "WorldSecondaryAxis",
	     "Position",
	     "Orientation",
	     "Axis",
	     "SecondaryAxis",
	     "GetConstraints":
		return Attachment_get(L, object, d, e, key)
	}
	return false
}

attachment_parallel_namecall :: proc(
	L: ^vm.State,
	object: ^Object,
	d: ^datatypes.Registry,
	e: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	switch method {
	case "GetConstraints":
		return attachment_namecall(L, object, d, e, method)
	}
	return 0, false
}

Register_Attachment :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&Attachment_Class,
		Attachment_construct,
		Attachment_destroy,
		get = Attachment_get,
		parallel_get = attachment_parallel_get,
		set = Attachment_set,
		clone = Attachment_clone,
		namecall = attachment_namecall,
		parallel_namecall = attachment_parallel_namecall,
		properties = []string {
			"Position",
			"Orientation",
			"Axis",
			"SecondaryAxis",
			"CFrame",
			"WorldCFrame",
			"WorldPosition",
			"WorldOrientation",
			"WorldAxis",
			"WorldSecondaryAxis",
		},
		methods = []string{"GetConstraints"},
	)
}
