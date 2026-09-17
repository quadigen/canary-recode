package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

ValueBase_Class := Class_Info{
	name   = "ValueBase",
	parent = &Instance_Class,
}

ValueBase :: struct {
	using object: Object,
}

ValueBase_Init :: proc() -> ValueBase {
	return ValueBase{
		object = Object_Init(&ValueBase_Class),
	}
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

Register_ValueBase :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&ValueBase_Class,
		ValueBase_construct,
		ValueBase_destroy,
		false,
	)
}