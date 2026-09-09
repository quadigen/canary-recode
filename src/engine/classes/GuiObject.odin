package classes

import datatypes "../datatypes"
import enums "../enum"
import guilib "../gui"
import vm "../vm"

GuiObject_Class := Class_Info{
    name   = "GuiObject",
    parent = &Instance_Class,
}

GuiObject :: struct {
    using object: Object,

    bg_transparency: f64,
    bg_color: datatypes.Color3,
    active: bool,
    border_mode: enums.BorderMode,
    clips_descendants: bool,
    gui_state: enums.GuiState,
    input_sink: bool,
    position: datatypes.UDim2,
    selectable: bool,
    size: datatypes.UDim2,
    visible: bool,
    zindex: i32,
    anchorpoint: datatypes.Vector2,
    border_size_pixels: i32
}

GuiObject_Init :: proc() -> GuiObject {
    return GuiObject{
        object = Object_Init(&GuiObject_Class),
        position = datatypes.UDim2{0, 0, 0, 0},
        bg_color = datatypes.Color3{
            R = 1, G = 1, B = 1
        },
        size = datatypes.UDim2{0, 100, 0, 100},
        anchorpoint = datatypes.Vector2{0, 0},
        active = false,
        selectable = true,
        visible = true,
        zindex = 0,
        border_size_pixels = 0,
        input_sink = false,
        gui_state = enums.GuiState.Idle,
        bg_transparency = 0,
    }
}

GuiObject_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
    GuiObject := new(GuiObject)
    GuiObject^ = GuiObject_Init()
    GuiObject.name = "GuiObject"
    return &GuiObject.object
}

GuiObject_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
    Object_Destroy(object)
    free(cast(^GuiObject)object)
}

GuiObject_get :: proc(L: ^vm.State, object: ^Object, datatype_registry: ^datatypes.Registry, enum_registry: ^enums.Registry, key: string) -> bool {
    GuiObject := cast(^GuiObject)object
    switch key {
    case "Active":
		vm.PushBoolean(L, GuiObject.active)
	case "BackgroundTransparency":
		vm.PushNumber(L, GuiObject.bg_transparency)
	case "ClipsDescendants":
		vm.PushBoolean(L, GuiObject.clips_descendants)
	case "InputSink":
		vm.PushBoolean(L, GuiObject.input_sink)
	case "Selectable":
		vm.PushBoolean(L, GuiObject.selectable)
	case "Visible":
		vm.PushBoolean(L, GuiObject.visible)
	case "ZIndex":
		vm.PushNumber(L, f64(GuiObject.zindex))
	case "BorderSizePixel":
		vm.PushNumber(L, f64(GuiObject.border_size_pixels))
	case "BorderMode":
		if enum_registry == nil { return false }
		_ = enums.Push_Item_By_Value(L, enum_registry, "BorderMode", i64(GuiObject.border_mode))
	case "GuiState":
		if enum_registry == nil { return false }
		_ = enums.Push_Item_By_Value(L, enum_registry, "GuiState", i64(GuiObject.gui_state))
	case "BackgroundColor3":
		if datatype_registry == nil { return false }
		datatypes.Push_Color3(L, datatype_registry, GuiObject.bg_color)
	case "Position":
		if datatype_registry == nil { return false }
		datatypes.Push_UDim2(L, datatype_registry, GuiObject.position)
	case "Size":
		if datatype_registry == nil { return false }
		datatypes.Push_UDim2(L, datatype_registry, GuiObject.size)
	case "AnchorPoint":
		if datatype_registry == nil { return false }
		datatypes.Push_Vector2(L, datatype_registry, GuiObject.anchorpoint)
    case:
        return false
    }
    return true
}

GuiObject_get_rect :: proc(
    object: ^Object,
    ctx: ^Class_Step_Context,
) -> (guilib.Rect, bool) {
    gui := cast(^GuiObject)object

    if !gui.visible {
        return guilib.Rect{}, false
    }

    if ctx == nil || ctx.renderer == nil || ctx.renderer.SkiaSurface == nil {
        return guilib.Rect{}, false
    }

    width := gui.size.X_Scale*f32(ctx.viewport_width) + gui.size.X_Offset
    height := gui.size.Y_Scale*f32(ctx.viewport_height) + gui.size.Y_Offset

    x := gui.position.X_Scale*f32(ctx.viewport_width) +
         gui.position.X_Offset -
         gui.anchorpoint.X*width

    y := gui.position.Y_Scale*f32(ctx.viewport_height) +
         gui.position.Y_Offset -
         gui.anchorpoint.Y*height

    return guilib.Rect{
        x = x,
        y = y,
        width = width,
        height = height,
        color = gui.bg_color,
        bgTransparency = f32(gui.bg_transparency),
    }, true
}

GuiObject_render :: proc(
    object: ^Object,
    ctx: ^Class_Step_Context,
) {
    gui := cast(^GuiObject)object

    rect, visible := GuiObject_get_rect(object, ctx)
    if !visible {
        return
    }

    corner   := Find_First_Child_Of_Class(object, "UICorner")
    shadow   := Find_First_Child_Of_Class(object, "UIShadow")
    backdrop := Find_First_Child_Of_Class(object, "UIBackdrop")

    if corner != nil {
        guilib.drawRoundedRect(ctx.renderer.SkiaSurface, rect, 13)
    } else {
        guilib.drawRect(ctx.renderer.SkiaSurface, rect)
    }

    ScreenGui_RenderChildren(object, ctx)
}

GuiObject_set :: proc(L: ^vm.State, object: ^Object, datatype_registry: ^datatypes.Registry, enum_registry: ^enums.Registry, key: string, value_index: int) -> bool {
    GuiObject := cast(^GuiObject)object
    switch key {
	case "Active":
		GuiObject.active = vm.ArgBoolean(L, value_index)
	case "BackgroundTransparency":
		GuiObject.bg_transparency = vm.ArgNumber(L, value_index)
	case "ClipsDescendants":
		GuiObject.clips_descendants = vm.ArgBoolean(L, value_index)
	case "InputSink":
		GuiObject.input_sink = vm.ArgBoolean(L, value_index)
	case "Selectable":
		GuiObject.selectable = vm.ArgBoolean(L, value_index)
	case "Visible":
		GuiObject.visible = vm.ArgBoolean(L, value_index)
	case "ZIndex":
		GuiObject.zindex = i32(vm.ArgNumber(L, value_index))
	case "BorderSizePixel":
		GuiObject.border_size_pixels = i32(vm.ArgNumber(L, value_index))
	case "BorderMode":
		if enum_registry == nil { return false }
		GuiObject.border_mode = enums.BorderMode(enums.Arg_Item(L, value_index, enum_registry, "BorderMode").value)
	case "BackgroundColor3":
		if datatype_registry == nil { return false }
		GuiObject.bg_color = datatypes.Arg_Color3(L, value_index, datatype_registry)
	case "Position":
		if datatype_registry == nil { return false }
		GuiObject.position = datatypes.Arg_UDim2(L, value_index, datatype_registry)
	case "Size":
		if datatype_registry == nil { return false }
		GuiObject.size = datatypes.Arg_UDim2(L, value_index, datatype_registry)
	case "AnchorPoint":
		if datatype_registry == nil { return false }
		GuiObject.anchorpoint = datatypes.Arg_Vector2(L, value_index, datatype_registry)
    case:
        return false
    }
    return true
}

Register_GuiObject :: proc(registry: ^Registry) {
    Register_Class(
        registry,
        &GuiObject_Class,
        GuiObject_construct,
        GuiObject_destroy,
        get = GuiObject_get,
        set = GuiObject_set,
        // remove _step since screengui is gonna render our stuff!
    )
}
