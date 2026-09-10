package classes

import "core:strings"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import guilib "../gui"

TextLabel_Class := Class_Info{
    name   = "TextLabel",
    parent = &GuiObject_Class,
}

TextLabel :: struct {
    using gui_object: GuiObject,

	text:              string,
	text_size:         f32,
	text_color3:       datatypes.Color3,
	text_transparency: f32,
}

TextLabel_Init :: proc() -> TextLabel {
	gui := GuiObject_Init()
	gui.object.class = &TextLabel_Class

	return TextLabel{
		gui_object        = gui,
		text              = "Hello World!",
		text_size         = 16,
		text_color3       = datatypes.Color3{1, 1, 1},
		text_transparency = 0,
	}
}

TextLabel_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
    TextLabel := new(TextLabel)
    TextLabel^ = TextLabel_Init()
    TextLabel.name = "TextLabel"

    return &TextLabel.object
}

TextLabel_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
    Object_Destroy(object)
    free(cast(^TextLabel)object)
}

TextLabel_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	label := cast(^TextLabel)object

	switch key {
	case "Text":
		vm.PushString(L, label.text)
		return true

	case "TextSize":
		vm.PushNumber(L, f64(label.text_size))
		return true

	case "TextColor3":
		if datatype_registry == nil {
			return false
		}

		datatypes.Push_Color3(
			L,
			datatype_registry,
			label.text_color3,
		)
		return true

	case "TextTransparency":
		vm.PushNumber(L, f64(label.text_transparency))
		return true
	}

	return GuiObject_get(
		L,
		object,
		datatype_registry,
		enum_registry,
		key,
	)
}

TextLabel_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	label := cast(^TextLabel)object

	switch key {
	case "Text":
		label.text = vm.ArgString(L, value_index)
		return true

	case "TextSize":
		label.text_size = max(f32(vm.ArgNumber(L, value_index)), 1)
		return true

	case "TextColor3":
		if datatype_registry == nil {
			return false
		}

		label.text_color3 = datatypes.Arg_Color3(L, value_index, datatype_registry)
		return true

	case "TextTransparency":
		label.text_transparency = clamp(
			f32(vm.ArgNumber(L, value_index)),
			0,
			1,
		)
		return true
	}

	return GuiObject_set(
		L,
		object,
		datatype_registry,
		enum_registry,
		key,
		value_index,
	)
}

TextLabel_render :: proc(
	object: ^Object,
	ctx: ^Class_Step_Context,
) {
	rect, visible := GuiObject_get_rect(object, ctx)
	if !visible {
		return
	}

	label := cast(^TextLabel)object

	text := strings.clone_to_cstring(label.text)
	defer delete(text)

	params := guilib.TextParams{
		x            = rect.x,
		y            = rect.y + label.text_size,
		TextSize     = label.text_size,
		color        = label.text_color3,
		transparency = label.text_transparency,
		font         = "",
	}

	guilib.drawText(
		ctx.renderer.SkiaSurface,
		text,
		params,
	)
}

Register_TextLabel :: proc(registry: ^Registry) {
    Register_Class(
        registry,
        &TextLabel_Class,
        TextLabel_construct,
        TextLabel_destroy,
        get = TextLabel_get,
        set = TextLabel_set,
    )
}
