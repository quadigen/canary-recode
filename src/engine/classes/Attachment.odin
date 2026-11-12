package classes

import kineffi "../bindings"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
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
		attachment.position, {axis.x, axis.y, axis.z}, {normal.x, normal.y, normal.z},
		{back.x, back.y, back.z},
	)
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
	case "Position":
		datatypes.Push_Vector3(L, attachment.position)
	case "Orientation":
		datatypes.Push_Vector3(L, attachment.orientation)
	case "Axis":
		datatypes.Push_Vector3(L, attachment.axis)
	case "SecondaryAxis":
		datatypes.Push_Vector3(L, attachment.secondary_axis)
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
		attachment.position = {frame.x, frame.y, frame.z}
		attachment.axis = {frame.r00, frame.r10, frame.r20}
		attachment.secondary_axis = {frame.r01, frame.r11, frame.r21}
		attachment.orientation = {}
	case "Position":
		attachment.position = datatypes.Arg_Vector3(L, value_index)
	case "Orientation":
		attachment.orientation = datatypes.Arg_Vector3(L, value_index)
	case "Axis":
		attachment.axis = datatypes.Arg_Vector3(L, value_index)
	case "SecondaryAxis":
		attachment.secondary_axis = datatypes.Arg_Vector3(L, value_index)
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

Register_Attachment :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&Attachment_Class,
		Attachment_construct,
		Attachment_destroy,
		get = Attachment_get,
		set = Attachment_set,
		clone = Attachment_clone,
		properties = []string{"Position", "Orientation", "Axis", "SecondaryAxis", "CFrame"},
	)
}
