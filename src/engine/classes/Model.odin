package classes

Model_Class := Class_Info{
    name   = "Model",
    parent = &Instance_Class,
}

Model :: struct {
    using object: Object,
}

Model_Init :: proc() -> Model {
    return Model{
        object = Object_Init(&Model_Class),
    }
}

Model_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
    corner := new(Model)
    corner^ = Model_Init()
    corner.name = "Model"

    return &corner.object
}

Model_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
    Object_Destroy(object)
    free(cast(^Model)object)
}

Model_clone :: proc(source: ^Object, destination: ^Object) {
	// No extra properties
}

Register_Model :: proc(registry: ^Registry) {
    Register_Class(
        registry,
        &Model_Class,
        Model_construct,
        Model_destroy,
        clone = Model_clone,
    )
}
