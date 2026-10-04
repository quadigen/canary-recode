package services

// wire:service global="debris"

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
	classes.Object_Destroy(object)
	free(cast(^Debris)object)
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
			classes.Object_Destroy(item)
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
		namecall  = debris_namecall,
		properties = []string{
			"AddItem",
		},
	)
}