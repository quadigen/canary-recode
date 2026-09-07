package classes

import "core:fmt"
import datatypes "../datatypes"
import enums "../enum"

Part_Class := Class_Info{
    name   = "Part",
    parent = &Object_Class,
}

Part :: struct {
    using object: Object,

    cframe: datatypes.CFrame,
    color: datatypes.Color3,
    transparency: i32,
    anchored: bool,
    material: enums.Material,
}

Part_Init :: proc() -> Part {
    return Part{
        object = Object_Init(&Part_Class),
        cframe = datatypes.CFrame_Identity,
        color = datatypes.Color3{
            R = 1, G = 1, B = 1
        },
        anchored = false,
        transparency = 0,
        material = enums.Material.SmoothPlastic
    }
}