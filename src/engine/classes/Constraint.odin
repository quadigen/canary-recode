package classes

import kineffi "../bindings"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:math"
import "core:math/linalg"

Constraint_Class := Class_Info {
	name   = "Constraint",
	parent = &Instance_Class,
}

Constraint :: struct {
	using object: Object,
	enabled:      bool,
	active:       bool,
	attachment0:  ^Object,
	attachment1:  ^Object,
}

Constraint_Step :: proc(
	object: ^Object,
	system: kineffi.JPH_PhysicsSystemRef,
	body_ids: []kineffi.JPH_BodyID,
	delta_time: f32,
)

Constraint_Step_Entry :: struct {
	class: ^Class_Info,
	step:  Constraint_Step,
}

Constraint_Frame :: struct {
	body:         kineffi.JPH_BodyID,
	position:     kineffi.JPH_Vec3,
	axis, normal: [3]f32,
}

constraint_attachment_axes :: proc(
	attachment: ^Attachment,
) -> (
	axis, normal: [3]f32,
	valid: bool,
) {
	axis = {attachment.axis.x, attachment.axis.y, attachment.axis.z}
	normal = {
		attachment.secondary_axis.x,
		attachment.secondary_axis.y,
		attachment.secondary_axis.z,
	}
	axis_length := linalg.length(axis)
	if !(axis_length > 0) || math.is_inf(axis_length) {return {}, {}, false}
	axis /= axis_length
	normal -= linalg.dot(normal, axis) * axis
	normal_length := linalg.length(normal)
	if normal_length < 1e-6 {
		// Attachment axes can be edited independently in this engine.
		reference := abs(axis.z) < 0.9 ? [3]f32{0, 0, 1} : [3]f32{0, 1, 0}
		normal = reference - linalg.dot(reference, axis) * axis
		normal_length = linalg.length(normal)
	}
	if !(normal_length > 0) || math.is_inf(normal_length) {return {}, {}, false}
	normal /= normal_length

	o := attachment.orientation
	if math.is_nan(o.x) || math.is_inf(o.x) ||
	   math.is_nan(o.y) || math.is_inf(o.y) ||
	   math.is_nan(o.z) || math.is_inf(o.z) {return {}, {}, false}
	q := linalg.quaternion_from_euler_angles(
		f32(linalg.to_radians(o.y)),
		f32(linalg.to_radians(o.x)),
		f32(linalg.to_radians(o.z)),
		.YXZ,
	)
	rotation := kineffi.JPH_Quat{q.x, q.y, q.z, q.w}
	a := rotate_by_quat(rotation, {axis.x, axis.y, axis.z})
	n := rotate_by_quat(rotation, {normal.x, normal.y, normal.z})
	return {a.x, a.y, a.z}, {n.x, n.y, n.z}, true
}

constraint_frame :: proc(
	object: ^Object,
	body: kineffi.JPH_BodyID,
	position: kineffi.JPH_Vec3,
) -> (
	Constraint_Frame,
	bool,
) {
	axis, normal, valid := constraint_attachment_axes(cast(^Attachment)object)
	return Constraint_Frame{body, position, axis, normal}, valid
}

constraint_world_vector :: proc(rotation: kineffi.JPH_Quat, v: [3]f32) -> kineffi.JPH_Vec3 {
	return rotate_by_quat(rotation, {v.x, v.y, v.z})
}

Constraint_Init :: proc() -> Constraint {
	return Constraint{object = Object_Init(&Constraint_Class), enabled = true, active = true}
}

Constraint_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	constraint := new(Constraint)
	constraint^ = Constraint_Init()
	constraint.name = "Constraint"
	return &constraint.object
}

Constraint_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^Constraint)object)
}

Constraint_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	constraint := cast(^Constraint)object

	switch key {
	case "Enabled":
		vm.PushBoolean(L, constraint.enabled)
	case "Active":
		vm.PushBoolean(L, constraint.active)
	case "Attachment0":
		Push_Object(L, constraint.attachment0)
	case "Attachment1":
		Push_Object(L, constraint.attachment1)
	case:
		return false
	}

	return true
}

Constraint_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	constraint := cast(^Constraint)object

	switch key {
	case "Enabled":
		constraint.enabled = vm.ArgBoolean(L, value_index)
	case "Active":
		constraint.active = vm.ArgBoolean(L, value_index)
	case "Attachment0", "Attachment1":
		value := object_from_argument(L, value_index)
		if value != nil && (value.destroyed || !Is_A_Class(value, &Attachment_Class)) {
			return false
		}
		if key == "Attachment0" {
			constraint.attachment0 = value
		} else {
			constraint.attachment1 = value
		}
	case:
		return false
	}

	return true
}

Constraint_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^Constraint)source
	dst := cast(^Constraint)destination

	dst.enabled = src.enabled
	dst.active = src.active
	dst.attachment0 = src.attachment0
	dst.attachment1 = src.attachment1
}

Register_Constraint :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&Constraint_Class,
		Constraint_construct,
		Constraint_destroy,
		get = Constraint_get,
		set = Constraint_set,
		clone = Constraint_clone,
		properties = []string{"Enabled", "Active", "Attachment0", "Attachment1"},
	)
}
