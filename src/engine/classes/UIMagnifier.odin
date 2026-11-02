package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

UIMagnifier_Class := Class_Info {
	name   = "UIMagnifier",
	parent = &Instance_Class,
}

UIMagnifier :: struct {
	using object: Object,
	enabled:      bool,
	zoom:         f64,
	inset:        f64,
	transparency: f64,
}

UIMagnifier_Init :: proc() -> UIMagnifier {
	return UIMagnifier {
		object = Object_Init(&UIMagnifier_Class),
		enabled = true,
		zoom = 1.5,
		inset = 12,
		transparency = 0,
	}
}

UIMagnifier_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	magnifier := new(UIMagnifier)
	magnifier^ = UIMagnifier_Init()
	magnifier.name = "UIMagnifier"
	return &magnifier.object
}

UIMagnifier_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^UIMagnifier)object)
}

UIMagnifier_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	magnifier := cast(^UIMagnifier)object

	switch key {
	case "Enabled":
		vm.PushBoolean(L, magnifier.enabled)
	case "Zoom":
		vm.PushNumber(L, magnifier.zoom)
	case "Inset":
		vm.PushNumber(L, magnifier.inset)
	case "Transparency":
		vm.PushNumber(L, magnifier.transparency)
	case:
		return false
	}
	return true
}

UIMagnifier_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	magnifier := cast(^UIMagnifier)object

	switch key {
	case "Enabled":
		magnifier.enabled = vm.ArgBoolean(L, value_index)
	case "Zoom":
		magnifier.zoom = max(1.0, vm.ArgNumber(L, value_index))
	case "Inset":
		magnifier.inset = max(0.0, vm.ArgNumber(L, value_index))
	case "Transparency":
		magnifier.transparency = clamp(vm.ArgNumber(L, value_index), 0.0, 1.0)
	case:
		return false
	}
	return true
}

UIMagnifier_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^UIMagnifier)source
	dst := cast(^UIMagnifier)destination

	dst.enabled = src.enabled
	dst.zoom = src.zoom
	dst.inset = src.inset
	dst.transparency = src.transparency
}

Register_UIMagnifier :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&UIMagnifier_Class,
		UIMagnifier_construct,
		UIMagnifier_destroy,
		get = UIMagnifier_get,
		set = UIMagnifier_set,
		clone = UIMagnifier_clone,
		properties = []string{"Enabled", "Zoom", "Inset", "Transparency"},
	)
}
