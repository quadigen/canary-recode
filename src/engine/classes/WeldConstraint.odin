package classes

import kineffi "../bindings"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:fmt"

WeldConstraint_Class := Class_Info {
	name   = "WeldConstraint",
	parent = &Constraint_Class,
}

WeldConstraint :: struct {
	using constraint: Constraint,
	part0:            ^Object,
	part1:            ^Object,
	jolt_system:      kineffi.JPH_PhysicsSystemRef,
	jolt_constraint:  kineffi.JPH_ConstraintRef,
	jolt_body0:       kineffi.JPH_BodyID,
	jolt_body1:       kineffi.JPH_BodyID,
}

WeldConstraint_Init :: proc() -> WeldConstraint {
	return WeldConstraint {
		constraint = Constraint_Init(),
		jolt_body0 = kineffi.JPH_BODY_ID_INVALID,
		jolt_body1 = kineffi.JPH_BODY_ID_INVALID,
	}
}

WeldConstraint_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	weld := new(WeldConstraint)
	weld^ = WeldConstraint_Init()
	weld.object.class = &WeldConstraint_Class
	weld.name = "WeldConstraint"
	return &weld.object
}

WeldConstraint_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	if object == nil {return}
	weld := cast(^WeldConstraint)object

	WeldConstraint_release(weld)

	weld.part0 = nil
	weld.part1 = nil

	Object_Destroy(object)
	free(weld)
}

get_body_id :: proc(
	object: ^Object,
	body_ids: []kineffi.JPH_BodyID,
) -> (
	id: kineffi.JPH_BodyID,
	ok: bool,
) {
	if object == nil || object.destroyed {return kineffi.JPH_BODY_ID_INVALID, false}
	if !Is_A_Class(object, &Part_Class) {return kineffi.JPH_BODY_ID_INVALID, false}

	part := cast(^Part)object
	i := part.part_index
	if i < 0 || i >= len(body_ids) {return kineffi.JPH_BODY_ID_INVALID, false}

	id = body_ids[i]
	return id, id != kineffi.JPH_BODY_ID_INVALID
}

WeldConstraint_release :: proc(object: ^WeldConstraint) {
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
}

WeldConstraint_step :: proc(
	object: ^Object,
	system: kineffi.JPH_PhysicsSystemRef,
	body_ids: []kineffi.JPH_BodyID,
	delta_time: f32,
) {
	weld := cast(^WeldConstraint)object
	if weld == nil {return}

	if weld.part0 != nil && weld.part0.destroyed {weld.part0 = nil}
	if weld.part1 != nil && weld.part1.destroyed {weld.part1 = nil}

	if !weld.enabled || system == nil {
		WeldConstraint_release(weld)
		return
	}

	id0, ok0 := get_body_id(weld.part0, body_ids)
	id1, ok1 := get_body_id(weld.part1, body_ids)

	if !ok0 || !ok1 || id0 == id1 {
		WeldConstraint_release(weld)
		return
	}

	if weld.jolt_constraint != nil &&
	   weld.jolt_system == system &&
	   weld.jolt_body0 == id0 &&
	   weld.jolt_body1 == id1 {
		return
	}

	WeldConstraint_release(weld)

	settings: kineffi.JPH_FixedConstraintSettings
	kineffi.JPH_FixedConstraintSettings_Init(&settings)
	settings.space = .WorldSpace
	settings.autoDetectPoint = 1

	constraint := kineffi.JPH_FixedConstraint_CreateFromIDs(system, &settings, id0, id1)
	if constraint == nil {return}

	kineffi.JPH_Constraint_AddRef(constraint)
	kineffi.JPH_PhysicsSystem_AddConstraint(system, constraint)

	weld.jolt_system = system
	weld.jolt_constraint = constraint
	weld.jolt_body0 = id0
	weld.jolt_body1 = id1
}

WeldConstraint_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	weld := cast(^WeldConstraint)object

	switch key {
	case "Part0":
		Push_Object(L, weld.part0)
	case "Part1":
		Push_Object(L, weld.part1)
	case:
		return Constraint_get(L, object, datatype_registry, enum_registry, key)
	}

	return true
}

WeldConstraint_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	weld := cast(^WeldConstraint)object

	switch key {
	case "Part0", "Part1":
		value := object_from_argument(L, value_index)

		if value != nil && (value.destroyed || !Is_A_Class(value, &Part_Class)) {
			return false
		}

		if key == "Part0" {
			weld.part0 = value
		} else {
			weld.part1 = value
		}

		WeldConstraint_release(weld)
		Hierarchy_Touched()
	case "Enabled":
		enabled := vm.ArgBoolean(L, value_index)
		if weld.enabled != enabled {
			weld.enabled = enabled
			WeldConstraint_release(weld)
			Hierarchy_Touched()
		}
	case:
		return Constraint_set(L, object, datatype_registry, enum_registry, key, value_index)
	}

	return true
}

WeldConstraint_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^WeldConstraint)source
	dst := cast(^WeldConstraint)destination

	Constraint_clone(source, destination)
	dst.part0 = src.part0
	dst.part1 = src.part1
}

Register_WeldConstraint :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&WeldConstraint_Class,
		WeldConstraint_construct,
		WeldConstraint_destroy,
		get = WeldConstraint_get,
		set = WeldConstraint_set,
		clone = WeldConstraint_clone,
		properties = []string{"Part0", "Part1"},
	)
}
