package classes

import datatypes "../datatypes"

UICorner_Class := Class_Info{
    name   = "UICorner",
    parent = &Instance_Class,
}

UICorner :: struct {
    using object: Object,

    bottom_left_radius: datatypes.UDim,
    bottom_right_radius: datatypes.UDim,
    top_left_radius: datatypes.UDim,
    top_right_radius: datatypes.UDim,
    corner_radius: datatypes.UDim,
}

UICorner_Init :: proc() -> UICorner {
    return UICorner{
        object = Object_Init(&UICorner_Class),

        bottom_left_radius = datatypes.UDim{0, 0},
        bottom_right_radius = datatypes.UDim{0, 0},
        top_right_radius = datatypes.UDim{0, 0},
        top_left_radius = datatypes.UDim{0, 0},
        corner_radius = datatypes.UDim{0, 15},
    }
}

ui_corner_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
    corner := new(UICorner)
    corner^ = UICorner_Init()
    corner.name = "UICorner"

    return &corner.object
}

ui_corner_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
    Object_Destroy(object)
    free(cast(^UICorner)object)
}

Register_UICorner :: proc(registry: ^Registry) {
    Register_Class(
        registry,
        &UICorner_Class,
        ui_corner_construct,
        ui_corner_destroy,
    )
}