package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

Frame_Class := Class_Info{
    name   = "Frame",
    parent = &GuiObject_Class,
}

Frame :: struct {
    using gui_object: GuiObject,
}

Frame_Init :: proc() -> Frame {
    gui := GuiObject_Init()
    gui.object.class = &Frame_Class

    return Frame{
        gui_object = gui,
    }
}

Frame_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
    frame := new(Frame)
    frame^ = Frame_Init()
    frame.name = "Frame"

    return &frame.object
}

Frame_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
    Object_Destroy(object)
    free(cast(^Frame)object)
}

Frame_get :: proc(
    L: ^vm.State,
    object: ^Object,
    datatype_registry: ^datatypes.Registry,
    enum_registry: ^enums.Registry,
    key: string,
) -> bool {
    return GuiObject_get(
        L,
        object,
        datatype_registry,
        enum_registry,
        key,
    )
}

Frame_set :: proc(
    L: ^vm.State,
    object: ^Object,
    datatype_registry: ^datatypes.Registry,
    enum_registry: ^enums.Registry,
    key: string,
    value_index: int,
) -> bool {
    return GuiObject_set(
        L,
        object,
        datatype_registry,
        enum_registry,
        key,
        value_index,
    )
}

Frame_render :: proc(
    object: ^Object,
    ctx: ^Class_Step_Context,
) {
    GuiObject_render(object, ctx)
}

Frame_clone :: proc(source: ^Object, destination: ^Object) {
	// No extra properties
}

Register_Frame :: proc(registry: ^Registry) {
    Register_Class(
        registry,
        &Frame_Class,
        Frame_construct,
        Frame_destroy,
        get = Frame_get,
        set = Frame_set,
        clone = Frame_clone,
    )
}
