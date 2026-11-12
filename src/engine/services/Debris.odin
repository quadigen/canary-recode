package services

// wire:service global="debris"

import "core:math"

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

Debris_Class := classes.Class_Info{
	name   = "Debris",
	parent = &Service_Class,
}

Debris :: struct {
	using service: Service,
	elapsed: f64,
	items: [dynamic]Debris_Item,
}

Debris_Item :: struct {
	reference: i32,
	deadline: f64,
}

debris_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(Debris)
	service.service = Service_Init(
		&Debris_Class,
		"Debris",
		data_model,
	)
	return &service.object
}

debris_destroy :: proc(
	object: ^classes.Object,
	renderer: ^classes.Renderer_Object,
) {
	debris := cast(^Debris)object
	if registry := object.signal_registry; registry != nil && registry.vm_state != nil && registry.vm_state.L != nil {
		for item in debris.items {
			vm.ReleaseValue(registry.vm_state.L, item.reference)
		}
	}
	delete(debris.items)
	classes.Object_Destroy(object)
	free(debris)
}

debris_step :: proc(object: ^classes.Object, ctx: ^classes.Class_Step_Context) {
	debris := cast(^Debris)object
	debris.elapsed += f64(max(ctx.delta_time, 0))
	for index := len(debris.items) - 1; index >= 0; index -= 1 {
		if debris.items[index].deadline > debris.elapsed {
			continue
		}
		item := debris.items[index]
		unordered_remove(&debris.items, index)
		vm.PushRegistryReference(ctx.L, item.reference)
		instance := cast(^classes.Object)vm.UserdataValue(ctx.L, -1)
		vm.Pop(ctx.L)
		vm.ReleaseValue(ctx.L, item.reference)
		classes.Destroy_Hierarchy(instance)
	}
}

debris_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method_name: string,
) -> (i32, bool) {
	switch method_name {
	case "AddItem":
		item := classes.Object_From_Argument(L, 2)
		if item != nil && !item.destroyed {
			lifetime := vm.ArgOptionalNumber(L, 3, 10)
			if math.is_nan(lifetime) || math.is_inf(lifetime) {
				return vm.RaiseError(L, "Debris lifetime must be finite"), true
			}
			debris := cast(^Debris)object
			vm.PushValue(L, 2)
			reference := vm.RetainValue(L)
			vm.Pop(L)
			append(&debris.items, Debris_Item{reference, debris.elapsed + max(lifetime, 0)})
		}
		return 0, true
	}
	return 0, false
}

Register_Debris_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&Debris_Class,
		debris_construct,
		debris_destroy,
		creatable = false,
		_step = debris_step,
		_step_phase = .Update,
		namecall  = debris_namecall,
		properties = []string{
			"AddItem",
		},
	)
}
