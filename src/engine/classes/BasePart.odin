package classes

BasePart_Class := Class_Info{
	name   = "BasePart",
	parent = &Instance_Class,
}

BasePart :: struct {
	using object: Object,
}

base_part_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	part := new(BasePart)
	part^ = BasePart{object = Object_Init(&BasePart_Class, "BasePart")}
	return &part.object
}

base_part_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^BasePart)object)
}

base_part_clone :: proc(source: ^Object, destination: ^Object) {
	// No properties of its own to copy.
}

Register_BasePart :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&BasePart_Class,
		base_part_construct,
		base_part_destroy,
		creatable = false,
		clone      = base_part_clone,
	)
}