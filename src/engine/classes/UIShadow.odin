package classes

import datatypes "../datatypes"
import "core:strings"
import enums "../enum"
import vm "../vm"
import guilib "../gui"

UIShadow_Class := Class_Info{
    name   = "UIShadow",
    parent = &Instance_Class,
}

UIShadow :: struct {
    using object: Object,

    blur_radius: datatypes.UDim,
    color: datatypes.Color3,
    enabled: bool,
    offset: datatypes.UDim2,
    spread: datatypes.UDim2,
    transparency: f64,
    zindex: f64,
    exponent: f64,
}

UIShadow_Init :: proc() -> UIShadow {
    return UIShadow{
        object = Object_Init(&UIShadow_Class),

        blur_radius = datatypes.UDim{0, 15},
        color = datatypes.Color3{1, 1, 1},
        enabled = true,
        offset = datatypes.UDim2{0, 0, 0, 0},
        spread = datatypes.UDim2{0, 15, 0, 15},
        transparency = 0,
        zindex = 0,
        exponent = 2,
    }
}

UIShadow_get :: proc(L: ^vm.State, object: ^Object, datatype_registry: ^datatypes.Registry, enum_registry: ^enums.Registry, key: string) -> bool { 
    shadow := cast(^UIShadow)object

	switch key {
	case "BlurRadius":
		datatypes.Push_UDim(L, datatype_registry, shadow.blur_radius)
		return true
	case "Offset":
		datatypes.Push_UDim2(L, datatype_registry, shadow.offset)
		return true
    case "Spread":
		datatypes.Push_UDim2(L, datatype_registry, shadow.spread)
		return true
    case "Color3":
		datatypes.Push_Color3(L, datatype_registry, shadow.color)
		return true
    case "Transparency":
		vm.PushNumber(L, shadow.transparency)
		return true
    case "Exponent":
		vm.PushNumber(L, shadow.exponent)
		return true
    case "ZIndex":
		vm.PushNumber(L, shadow.zindex)
		return true
    case "Enabled":
		vm.PushBoolean(L, shadow.enabled)
		return true
	}

	return false
}

UIShadow_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
    corner := new(UIShadow)
    corner^ = UIShadow_Init()
    corner.name = "UIShadow"

    return &corner.object
}

UIShadow_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
    Object_Destroy(object)
    free(cast(^UIShadow)object)
}

Register_UIShadow :: proc(registry: ^Registry) {
    Register_Class(
        registry,
        &UIShadow_Class,
        UIShadow_construct,
        UIShadow_destroy,
        get = UIShadow_get
    )
}
