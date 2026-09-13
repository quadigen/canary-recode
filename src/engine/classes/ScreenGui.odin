package classes

import datatypes "../datatypes"
import enums "../enum"
import guilib "../gui"
import vm "../vm"

ScreenGui_Class := Class_Info{
    name   = "ScreenGui",
    parent = &Instance_Class,
}

ScreenGui :: struct {
    using object: Object,

    // ill make this long for no reason <:
    clip_to_device_safe_area: bool,

    displayorder: f64,
    ignore_gui_inset: bool,
    safe_area_compat: enums.SafeAreaCompatibility,
    screen_insets: enums.ScreenInsets,
    enabled: bool,
	render_on_top: bool,

    // kinemium-specific props
    render_offset: datatypes.Vector2,
    size: datatypes.Vector2,
}

ScreenGui_Init :: proc() -> ScreenGui {
    return ScreenGui{
        object = Object_Init(&ScreenGui_Class),
        displayorder = 0,
        clip_to_device_safe_area = true,
        ignore_gui_inset = false,
        safe_area_compat = enums.SafeAreaCompatibility.None,
        screen_insets = enums.ScreenInsets.None,
        enabled = true,
    }
}

ScreenGui_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
    ScreenGui := new(ScreenGui)
    ScreenGui^ = ScreenGui_Init()
    ScreenGui.name = "ScreenGui"
    return &ScreenGui.object
}

ScreenGui_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
    Object_Destroy(object)
    free(cast(^ScreenGui)object)
}

ScreenGui_get :: proc(L: ^vm.State, object: ^Object, datatype_registry: ^datatypes.Registry, enum_registry: ^enums.Registry, key: string) -> bool {
    ScreenGui := cast(^ScreenGui)object
    switch key {
    case "Enabled":
		vm.PushBoolean(L, ScreenGui.enabled)
	case "DisplayOrder":
		vm.PushNumber(L, ScreenGui.displayorder)
	case "ClipToDeviceSafeArea":
		vm.PushBoolean(L, ScreenGui.clip_to_device_safe_area)
	case "IgnoreGuiInset":
		vm.PushBoolean(L, ScreenGui.ignore_gui_inset)
	case "RenderOnTop":
		vm.PushBoolean(L, ScreenGui.render_on_top)
    case:
        return false
    }
    return true
}

ScreenGui_RenderChildren :: proc(
	object: ^Object,
	ctx: ^Class_Step_Context,
) {
	for child in object.children {
		switch {
		case Is_A(child, "ScrollingFrame"):
			ScrollingFrame_render(
				child,
				ctx,
			)

		case Is_A(child, "TextBox"):
			TextBox_render(
				child,
				ctx,
			)

		case Is_A(child, "TextLabel"):
			TextLabel_render(
				child,
				ctx,
			)

		case Is_A(child, "Frame"):
			Frame_render(
				child,
				ctx,
			)

		case Is_A(child, "ImageLabel"):
			ImageLabel_render(
				child,
				ctx,
			)

		case Is_A(child, "GuiObject"):
			GuiObject_render(
				child,
				ctx,
			)
		}
	}
}

ScreenGui_render :: proc(
    object: ^Object,
    ctx: ^Class_Step_Context,
) {
    gui := cast(^ScreenGui)object

	if !gui.enabled {
		return
	}

	wants_overlay := gui.render_on_top
	if object.parent != nil && object.parent.name == "StarterGui" {
		wants_overlay = true
	}
	if wants_overlay != ctx.gui_overlay { return }

	if ctx == nil || ctx.renderer == nil || ctx.renderer.SkiaSurface == nil { return }

    ScreenGui_RenderChildren(object, ctx)
}

ScreenGui_set :: proc(
    L: ^vm.State,
    object: ^Object,
    datatype_registry: ^datatypes.Registry,
    enum_registry: ^enums.Registry,
    key: string,
    value_index: int,
) -> bool {
    screen_gui := cast(^ScreenGui)object

    switch key {
    case "Enabled":
        screen_gui.enabled = vm.ArgBoolean(L, value_index)

    case "DisplayOrder":
        screen_gui.displayorder = vm.ArgNumber(L, value_index)

    case "ClipToDeviceSafeArea":
        screen_gui.clip_to_device_safe_area = vm.ArgBoolean(L, value_index)

    case "Size":
        screen_gui.size = datatypes.Arg_Vector2(L, value_index, datatype_registry)

    case "RenderOffset":
        screen_gui.render_offset = datatypes.Arg_Vector2(L, value_index, datatype_registry)

    case "IgnoreGuiInset":
        screen_gui.ignore_gui_inset = vm.ArgBoolean(L, value_index)

	case "RenderOnTop":
		screen_gui.render_on_top = vm.ArgBoolean(L, value_index)

    case "SafeAreaCompatibility":
        if enum_registry == nil {
            return false
        }

        screen_gui.safe_area_compat = enums.SafeAreaCompatibility(
            enums.Arg_Item(
                L,
                value_index,
                enum_registry,
                "SafeAreaCompatibility",
            ).value,
        )

    case "ScreenInsets":
        if enum_registry == nil {
            return false
        }

        screen_gui.screen_insets = enums.ScreenInsets(
            enums.Arg_Item(
                L,
                value_index,
                enum_registry,
                "ScreenInsets",
            ).value,
        )

    case:
        return false
    }

    return true
}

ScreenGui_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^ScreenGui)source
	dst := cast(^ScreenGui)destination

	dst.clip_to_device_safe_area = src.clip_to_device_safe_area
	dst.displayorder             = src.displayorder
	dst.ignore_gui_inset         = src.ignore_gui_inset
	dst.safe_area_compat         = src.safe_area_compat
	dst.screen_insets            = src.screen_insets
	dst.enabled                  = src.enabled
	dst.render_on_top            = src.render_on_top
	dst.render_offset            = src.render_offset
	dst.size                     = src.size
}

Register_ScreenGui :: proc(registry: ^Registry) {
    Register_Class(
        registry,
        &ScreenGui_Class,
        ScreenGui_construct,
        ScreenGui_destroy,
		get = ScreenGui_get,
		set = ScreenGui_set,
		clone = ScreenGui_clone,
		_step = ScreenGui_render,
		properties = []string{"DisplayOrder", "ClipToDeviceSafeArea", "Enabled", "IgnoreGuiInset", "RenderOnTop"},
	)
}

