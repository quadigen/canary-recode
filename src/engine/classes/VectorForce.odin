package classes

import kineffi "../bindings"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:math/linalg"

VectorForce_Class := Class_Info {
	name   = "VectorForce",
	parent = &Constraint_Class,
}


Actuator_Relative_To :: enum i64 {
	Attachment0 = 0,
	Attachment1 = 1,
	World       = 2,
}

VectorForce :: struct {
	using constraint:        Constraint,
	force:                   datatypes.Vector3,
	relative_to:             Actuator_Relative_To,
	apply_at_center_of_mass: bool,
}

VectorForce_Init :: proc() -> VectorForce {
	return VectorForce {
		constraint = Constraint_Init(),
		relative_to = .Attachment0,
		apply_at_center_of_mass = true,
	}
}

VectorForce_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	vf := new(VectorForce)
	vf^ = VectorForce_Init()
	vf.object.class = &VectorForce_Class
	vf.name = "VectorForce"
	return &vf.object
}

VectorForce_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	if object == nil {return}
	vf := cast(^VectorForce)object
	vf.attachment0 = nil
	Object_Destroy(object)
	free(vf)
}


VectorForce_step :: proc(
	object: ^Object,
	system: kineffi.JPH_PhysicsSystemRef,
	body_ids: []kineffi.JPH_BodyID,
	delta_time: f32,
) {
	vf := cast(^VectorForce)object
	if vf == nil || system == nil {return}

	if vf.attachment0 != nil && vf.attachment0.destroyed {vf.attachment0 = nil}
	if vf.attachment0 == nil {return}


	if !vf.enabled {return}
	if vf.force.x == 0 && vf.force.y == 0 && vf.force.z == 0 {return}

	id, _, attach_world, ok := resolve_attachment(vf.attachment0, system, body_ids)
	if !ok {return}

	bi := kineffi.JPH_PhysicsSystem_GetBodyInterface(system)
	if bi == nil {return}

	force := kineffi.JPH_Vec3{f32(vf.force.x), f32(vf.force.y), f32(vf.force.z)}

	if vf.relative_to == .Attachment0 {
		attachment := cast(^Attachment)vf.attachment0


		o := attachment.orientation
		aq := linalg.quaternion_from_euler_angles(
			f32(linalg.to_radians(o.y)),
			f32(linalg.to_radians(o.x)),
			f32(linalg.to_radians(o.z)),
			.YXZ,
		)
		force = rotate_by_quat(kineffi.JPH_Quat{aq.x, aq.y, aq.z, aq.w}, force)


		body_rot: kineffi.JPH_Quat
		kineffi.JPH_BodyInterface_GetRotation(bi, id, &body_rot)
		force = rotate_by_quat(body_rot, force)
	}

	if vf.apply_at_center_of_mass {
		kineffi.JPH_BodyInterface_AddForce(bi, id, &force)
	} else {
		pos := attach_world
		kineffi.JPH_BodyInterface_AddForce2(bi, id, &force, &pos)
	}


	kineffi.JPH_BodyInterface_ActivateBody(bi, id)
}

VectorForce_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	vf := cast(^VectorForce)object

	switch key {
	case "Attachment0":
		Push_Object(L, vf.attachment0)
	case "Force":
		datatypes.Push_Vector3(L, vf.force)
	case "RelativeTo":
		if enum_registry == nil {return false}
		_ = enums.Push_Item_By_Value(L, enum_registry, "ActuatorRelativeTo", i64(vf.relative_to))
	case "ApplyAtCenterOfMass":
		vm.PushBoolean(L, vf.apply_at_center_of_mass)
	case:
		return Constraint_get(L, object, datatype_registry, enum_registry, key)
	}

	return true
}

VectorForce_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	vf := cast(^VectorForce)object

	switch key {
	case "Attachment0":
		value := object_from_argument(L, value_index)
		if value != nil && (value.destroyed || !Is_A_Class(value, &Attachment_Class)) {
			return false
		}
		vf.attachment0 = value
	case "Force":
		vf.force = datatypes.Arg_Vector3(L, value_index)
	case "RelativeTo":
		if enum_registry == nil {return false}
		item := enums.Arg_Item(L, value_index, enum_registry, "ActuatorRelativeTo")
		vf.relative_to = Actuator_Relative_To(item.value)
	case "ApplyAtCenterOfMass":
		vf.apply_at_center_of_mass = vm.ArgBoolean(L, value_index)
	case:
		return Constraint_set(L, object, datatype_registry, enum_registry, key, value_index)
	}

	return true
}

VectorForce_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^VectorForce)source
	dst := cast(^VectorForce)destination

	Constraint_clone(source, destination)
	dst.attachment0 = src.attachment0
	dst.force = src.force
	dst.relative_to = src.relative_to
	dst.apply_at_center_of_mass = src.apply_at_center_of_mass
}

Register_VectorForce :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&VectorForce_Class,
		VectorForce_construct,
		VectorForce_destroy,
		get = VectorForce_get,
		set = VectorForce_set,
		clone = VectorForce_clone,
		properties = []string{"Attachment0", "Force", "RelativeTo", "ApplyAtCenterOfMass"},
	)
}
