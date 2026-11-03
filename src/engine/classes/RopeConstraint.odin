package classes

import kineffi "../bindings"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

RopeConstraint_Class := Class_Info {
	name   = "RopeConstraint",
	parent = &Constraint_Class,
}

ROPE_DEFAULT_LENGTH :: 10.0

RopeConstraint :: struct {
	using constraint: Constraint,
	length:           f32,
	jolt_system:      kineffi.JPH_PhysicsSystemRef,
	jolt_constraint:  kineffi.JPH_ConstraintRef,
	jolt_body0:       kineffi.JPH_BodyID,
	jolt_body1:       kineffi.JPH_BodyID,
	jolt_offset0:     kineffi.JPH_Vec3,
	jolt_offset1:     kineffi.JPH_Vec3,
}

RopeConstraint_Init :: proc() -> RopeConstraint {
	return RopeConstraint {
		constraint = Constraint_Init(),
		length = ROPE_DEFAULT_LENGTH,
		jolt_body0 = kineffi.JPH_BODY_ID_INVALID,
		jolt_body1 = kineffi.JPH_BODY_ID_INVALID,
	}
}

RopeConstraint_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	rope := new(RopeConstraint)
	rope^ = RopeConstraint_Init()
	rope.object.class = &RopeConstraint_Class
	rope.name = "RopeConstraint"
	return &rope.object
}

RopeConstraint_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	if object == nil {return}
	rope := cast(^RopeConstraint)object

	RopeConstraint_release(rope)

	rope.attachment0 = nil
	rope.attachment1 = nil

	Object_Destroy(object)
	free(rope)
}

RopeConstraint_release :: proc(object: ^RopeConstraint) {
	if object.jolt_constraint != nil {
		if object.jolt_system != nil {
			kineffi.JPH_PhysicsSystem_RemoveConstraint(object.jolt_system, object.jolt_constraint)
		}
		kineffi.JPH_Constraint_Destroy(object.jolt_constraint)
	}
	object.jolt_constraint = nil
	object.jolt_system = nil
	object.jolt_body0 = kineffi.JPH_BODY_ID_INVALID
	object.jolt_body1 = kineffi.JPH_BODY_ID_INVALID
	object.jolt_offset0 = {}
	object.jolt_offset1 = {}
}

RopeConstraint_step :: proc(
	object: ^Object,
	system: kineffi.JPH_PhysicsSystemRef,
	body_ids: []kineffi.JPH_BodyID,
	delta_time: f32,
) {
	rope := cast(^RopeConstraint)object
	if rope == nil {return}

	if rope.attachment0 != nil && rope.attachment0.destroyed {rope.attachment0 = nil}
	if rope.attachment1 != nil && rope.attachment1.destroyed {rope.attachment1 = nil}

	if system == nil {
		RopeConstraint_release(rope)
		return
	}

	id0, local0, world0, ok0 := resolve_attachment(rope.attachment0, system, body_ids)
	id1, local1, world1, ok1 := resolve_attachment(rope.attachment1, system, body_ids)

	if !ok0 || !ok1 || id0 == id1 {
		RopeConstraint_release(rope)
		return
	}

	if rope.jolt_constraint != nil &&
	   rope.jolt_system == system &&
	   rope.jolt_body0 == id0 &&
	   rope.jolt_body1 == id1 &&
	   rope.jolt_offset0 == local0 &&
	   rope.jolt_offset1 == local1 {
		kineffi.JPH_DistanceConstraint_SetDistance(rope.jolt_constraint, 0, rope.length)
		return
	}

	RopeConstraint_release(rope)

	settings: kineffi.JPH_DistanceConstraintSettings
	kineffi.JPH_DistanceConstraintSettings_Init(&settings)
	settings.space = .WorldSpace
	settings.point1 = world0
	settings.point2 = world1
	settings.minDistance = 0
	settings.maxDistance = rope.length

	constraint := kineffi.JPH_DistanceConstraint_CreateFromIDs(system, &settings, id0, id1)
	if constraint == nil {return}

	kineffi.JPH_Constraint_AddRef(constraint)
	kineffi.JPH_PhysicsSystem_AddConstraint(system, constraint)

	rope.jolt_system = system
	rope.jolt_constraint = constraint
	rope.jolt_body0 = id0
	rope.jolt_body1 = id1
	rope.jolt_offset0 = local0
	rope.jolt_offset1 = local1
}

RopeConstraint_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	rope := cast(^RopeConstraint)object

	switch key {
	case "Attachment0":
		Push_Object(L, rope.attachment0)
	case "Attachment1":
		Push_Object(L, rope.attachment1)
	case "Length":
		vm.PushNumber(L, f64(rope.length))
	case:
		return Constraint_get(L, object, datatype_registry, enum_registry, key)
	}

	return true
}

RopeConstraint_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	rope := cast(^RopeConstraint)object

	switch key {
	case "Attachment0", "Attachment1":
		value := object_from_argument(L, value_index)

		if value != nil && (value.destroyed || !Is_A_Class(value, &Attachment_Class)) {
			return false
		}

		if key == "Attachment0" {
			rope.attachment0 = value
		} else {
			rope.attachment1 = value
		}

		RopeConstraint_release(rope)
	case "Length":
		length := f32(vm.ArgNumber(L, value_index))
		if length < 0 {return false}
		rope.length = length
	case:
		return Constraint_set(L, object, datatype_registry, enum_registry, key, value_index)
	}

	return true
}

RopeConstraint_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^RopeConstraint)source
	dst := cast(^RopeConstraint)destination

	Constraint_clone(source, destination)
	dst.attachment0 = src.attachment0
	dst.attachment1 = src.attachment1
	dst.length = src.length
}

Register_RopeConstraint :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&RopeConstraint_Class,
		RopeConstraint_construct,
		RopeConstraint_destroy,
		get = RopeConstraint_get,
		set = RopeConstraint_set,
		clone = RopeConstraint_clone,
		properties = []string{"Attachment0", "Attachment1", "Length"},
	)
}
