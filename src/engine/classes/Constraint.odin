package classes

import kineffi "../bindings"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

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
)

Constraint_Step_Entry :: struct {
	class: ^Class_Info,
	step:  Constraint_Step,
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
