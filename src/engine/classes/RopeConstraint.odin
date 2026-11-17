package classes

import kineffi "../bindings"
import datatypes "../datatypes"
import enums "../enum"
import jolt "../physics"
import vm "../vm"
import "core:math/linalg"

RopeConstraint_Class := Class_Info {
	name   = "RopeConstraint",
	parent = &Constraint_Class,
}

ROPE_DEFAULT_LENGTH :: 10.0

RopeConstraint :: struct {
	using constraint: Constraint,
	length:           f32,
	thickness:        f32,
	visible:          bool,
	can_collide:      bool,
	jolt_system:      kineffi.JPH_PhysicsSystemRef,
	jolt_constraint:  kineffi.JPH_ConstraintRef,
	jolt_rope:        kineffi.JPH_RopeRef,
	jolt_body0:       kineffi.JPH_BodyID,
	jolt_body1:       kineffi.JPH_BodyID,
	jolt_offset0:     kineffi.JPH_Vec3,
	jolt_offset1:     kineffi.JPH_Vec3,
	jolt_length:      f32,
	jolt_world0:      kineffi.JPH_RVec3,
	jolt_world1:      kineffi.JPH_RVec3,
	static_end0:      bool,
	static_end1:      bool,
	mesh:             ^kineffi.KineFilamentMesh,
	mesh_context:     ^kineffi.KineFilamentContext,
	mesh_points:      [kineffi.JPH_ROPE_MAX_POINTS]kineffi.JPH_RVec3,
	mesh_point_count: int,
	mesh_radius:      f32,
	mesh_revision:    u64,
}

RopeConstraint_Init :: proc() -> RopeConstraint {
	constraint := Constraint_Init()
	constraint.active = false
	return RopeConstraint {
		constraint = constraint,
		length = ROPE_DEFAULT_LENGTH,
		thickness = 0.2,
		visible = true,
		can_collide = true,
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
	RopeConstraint_Release_Mesh(rope)

	rope.attachment0 = nil
	rope.attachment1 = nil

	Object_Destroy(object)
	free(rope)
}

RopeConstraint_release :: proc(object: ^RopeConstraint) {
	if object.jolt_rope != nil {kineffi.JPH_Rope_Destroy(object.jolt_rope)}
	object.jolt_rope = nil
	object.active = false
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

	if system == nil || !rope.enabled {
		RopeConstraint_release(rope)
		return
	}

	id0, local0, world0, ok0 := resolve_attachment(rope.attachment0, system, body_ids)
	id1, local1, world1, ok1 := resolve_attachment(rope.attachment1, system, body_ids)

	if !ok0 || !ok1 || id0 == id1 || !rope_valid_point(world0) || !rope_valid_point(world1) {
		RopeConstraint_release(rope)
		return
	}

	if rope.jolt_system != system ||
	   rope.jolt_body0 != id0 || rope.jolt_body1 != id1 ||
	   rope.jolt_offset0 != local0 || rope.jolt_offset1 != local1 {
		RopeConstraint_release(rope)
		rope.jolt_system = system
		rope.jolt_body0, rope.jolt_body1 = id0, id1
		rope.jolt_offset0, rope.jolt_offset1 = local0, local1
		bi := kineffi.JPH_PhysicsSystem_GetBodyInterface(system)
		rope.static_end0 = kineffi.JPH_BodyInterface_GetMotionType(bi, id0) != .Dynamic
		rope.static_end1 = kineffi.JPH_BodyInterface_GetMotionType(bi, id1) != .Dynamic
		if !rope.static_end0 || !rope.static_end1 {
			settings: kineffi.JPH_DistanceConstraintSettings
			kineffi.JPH_DistanceConstraintSettings_Init(&settings)
			settings.space = .WorldSpace
			settings.point1, settings.point2 = world0, world1
			settings.minDistance, settings.maxDistance = 0, rope.length
			constraint := kineffi.JPH_DistanceConstraint_CreateFromIDs(system, &settings, id0, id1)
			if constraint != nil {
				kineffi.JPH_Constraint_AddRef(constraint)
				kineffi.JPH_PhysicsSystem_AddConstraint(system, constraint)
				rope.jolt_constraint = constraint
				kineffi.JPH_BodyInterface_ActivateBody(bi, id0)
				kineffi.JPH_BodyInterface_ActivateBody(bi, id1)
			}
		}
	}

	span := linalg.length([3]f64{world1.x - world0.x, world1.y - world0.y, world1.z - world0.z})
	length := rope.length
	if rope.static_end0 && rope.static_end1 {
		// Fixed anchors cannot be pulled closer when their span exceeds Length.
		length = max(length, f32(span))
	}
	if rope.jolt_rope != nil &&
	   (abs(rope.jolt_length - length) > max(0.05, 0.02 * length) || span > f64(length) * 1.2) {
		kineffi.JPH_Rope_Destroy(rope.jolt_rope)
		rope.jolt_rope = nil
	}
	// Let the distance constraint close an initially overextended span before adding the links.
	if rope.jolt_rope == nil && length >= 0.01 && span <= f64(length) * 1.02 {
		rope.jolt_rope = kineffi.JPH_Rope_Create(
			system, id0, id1, &world0, &world1, length, rope.thickness * 0.5,
			rope.can_collide ? 1 : 0, jolt.OBJECT_LAYER_MOVING,
		)
		rope.jolt_length = length
	}
	if (rope.static_end0 && rope.jolt_world0 != world0) || (rope.static_end1 && rope.jolt_world1 != world1) {
		kineffi.JPH_Rope_Wake(rope.jolt_rope)
	}
	rope.jolt_world0, rope.jolt_world1 = world0, world1
	rope.active = rope.jolt_constraint != nil || rope.jolt_rope != nil
}

rope_valid_point :: proc(point: kineffi.JPH_RVec3) -> bool {
	return abs(point.x) < 1e20 && abs(point.y) < 1e20 && abs(point.z) < 1e20
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
	case "Thickness":
		vm.PushNumber(L, f64(rope.thickness))
	case "Visible":
		vm.PushBoolean(L, rope.visible)
	case "CanCollide":
		vm.PushBoolean(L, rope.can_collide)
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

		if !vm.IsNil(L, value_index) && (value == nil || value.destroyed || !Is_A_Class(value, &Attachment_Class)) {
			return false
		}

		slot := &rope.attachment0 if key == "Attachment0" else &rope.attachment1
		if slot^ != value {
			slot^ = value
			RopeConstraint_release(rope)
		}
	case "Length", "Thickness":
		value := f32(vm.ArgNumber(L, value_index))
		minimum := f32(0.01) if key == "Thickness" else 0
		if !(value >= minimum && value < 1e7) {
			_ = vm.RaiseError(L, "rope dimension is out of range")
			return true
		}
		dimension := &rope.thickness if key == "Thickness" else &rope.length
		if dimension^ != value {
			dimension^ = value
			RopeConstraint_release(rope)
		}
	case "Visible":
		rope.visible = vm.ArgBoolean(L, value_index)
	case "CanCollide":
		rope.can_collide = vm.ArgBoolean(L, value_index)
		kineffi.JPH_Rope_SetCanCollide(rope.jolt_rope, rope.can_collide ? 1 : 0)
	case "Enabled":
		rope.enabled = vm.ArgBoolean(L, value_index)
		if !rope.enabled {RopeConstraint_release(rope)}
	case "Active":
		// Older saves include this derived property.
		return true
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
	dst.thickness = src.thickness
	dst.visible = src.visible
	dst.can_collide = src.can_collide
	dst.active = false
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
		properties = []string{"Attachment0", "Attachment1", "Length", "Thickness", "Visible", "CanCollide"},
	)
}
