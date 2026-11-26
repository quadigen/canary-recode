package classes

import datatypes "../datatypes"
import enums "../enum"
import signals "../signals"
import vm "../vm"

ValueBase_Class := Class_Info {
	name   = "ValueBase",
	parent = &Instance_Class,
}

ValueBase :: struct {
	using object: Object,
}

ValueBase_Init :: proc() -> ValueBase {
	return ValueBase{object = Object_Init(&ValueBase_Class)}
}

ValueBase_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	value_base := new(ValueBase)
	value_base^ = ValueBase_Init()
	value_base.name = "ValueBase"
	return &value_base.object
}

ValueBase_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^ValueBase)object)
}


ValueBase_Changed_Signal :: proc(L: ^vm.State, object: ^Object, slot: ^^signals.Signal) -> bool {
	if slot^ == nil {
		if object.signal_registry == nil || object.signal_registry.signal_registry == nil {
			return false
		}
		slot^ = signals.Create(object.signal_registry.signal_registry)
	}
	signals.Push(L, slot^)
	return true
}

ValueBase_Destroy_Changed_Signal :: proc(slot: ^^signals.Signal) {
	if slot^ != nil {
		signals.Destroy(slot^)
		slot^ = nil
	}
}


ValueBase_Fire_Changed :: proc(L: ^vm.State, signal: ^signals.Signal) {
	signals.Fire(L, signal, 1)
	vm.Pop(L, 1)
}

Register_ValueBase :: proc(registry: ^Registry) {
	Register_Class(registry, &ValueBase_Class, ValueBase_construct, ValueBase_destroy, false)
}
