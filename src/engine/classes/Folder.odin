package classes

Folder_Class := Class_Info{
    name   = "Folder",
    parent = &Instance_Class,
}

Folder :: struct {
    using object: Object,
}

Folder_Init :: proc() -> Folder {
    return Folder{
        object = Object_Init(&Folder_Class),
    }
}

Folder_construct :: proc(renderer: ^Renderer_Object, data_Folder: rawptr) -> ^Object {
    corner := new(Folder)
    corner^ = Folder_Init()
    corner.name = "Folder"

    return &corner.object
}

Folder_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
    Object_Destroy(object)
    free(cast(^Folder)object)
}

Folder_clone :: proc(source: ^Object, destination: ^Object) {
	// No extra properties
}

Register_Folder :: proc(registry: ^Registry) {
    Register_Class(
        registry,
        &Folder_Class,
        Folder_construct,
        Folder_destroy,
        clone = Folder_clone,
    )
}
