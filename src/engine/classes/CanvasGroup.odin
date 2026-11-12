package classes

import kineffi "../bindings"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

CanvasGroup_Class := Class_Info {
	name   = "CanvasGroup",
	parent = &GuiObject_Class,
}

CanvasGroup :: struct {
	using gui_object:   GuiObject,
	group_transparency: f32,
}

CanvasGroup_Init :: proc() -> CanvasGroup {
	gui := GuiObject_Init()
	gui.object.class = &CanvasGroup_Class

	return CanvasGroup{gui_object = gui}
}

CanvasGroup_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	CanvasGroup := new(CanvasGroup)
	CanvasGroup^ = CanvasGroup_Init()
	CanvasGroup.name = "CanvasGroup"

	return &CanvasGroup.object
}

CanvasGroup_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	GuiObject_Free_Signals(cast(^GuiObject)object)
	Object_Destroy(object)
	free(cast(^CanvasGroup)object)
}

CanvasGroup_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	if key == "GroupTransparency" {
		vm.PushNumber(L, f64((cast(^CanvasGroup)object).group_transparency))
		return true
	}
	return GuiObject_get(L, object, datatype_registry, enum_registry, key)
}

CanvasGroup_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	if key == "GroupTransparency" {
		(cast(^CanvasGroup)object).group_transparency = f32(
			clamp(vm.ArgNumber(L, value_index), 0, 1),
		)
		Gui_Render_Mark_Dirty()
		return true
	}
	return GuiObject_set(L, object, datatype_registry, enum_registry, key, value_index)
}

CanvasGroup_render :: proc(object: ^Object, ctx: ^Class_Step_Context) {
	group := cast(^CanvasGroup)object
	alpha := 1 - group.group_transparency
	surface := ctx.renderer.SkiaSurface
	if alpha < 1 {kineffi.Kine_Skia_Surface_SaveLayerAlpha(surface, alpha)}
	defer if alpha < 1 {kineffi.Kine_Skia_Surface_Restore(surface)}
	GuiObject_render(object, ctx)
}

CanvasGroup_clone :: proc(source: ^Object, destination: ^Object) {
	(cast(^CanvasGroup)destination).group_transparency =
		(cast(^CanvasGroup)source).group_transparency
}

Register_CanvasGroup :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&CanvasGroup_Class,
		CanvasGroup_construct,
		CanvasGroup_destroy,
		get = CanvasGroup_get,
		set = CanvasGroup_set,
		clone = CanvasGroup_clone,
		properties = []string{"GroupTransparency"},
	)
}
