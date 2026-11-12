package services

// wire:service

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import platform "../platform"
import vm "../vm"

GuiService_Class := classes.Class_Info {
	name   = "GuiService",
	parent = &Service_Class,
}

gui_service_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(Service)
	service^ = Service_Init(&GuiService_Class, "GuiService", data_model)
	return &service.object
}

gui_service_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	classes.Object_Destroy(object)
	free(cast(^Service)object)
}

gui_service_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	dt: ^datatypes.Registry,
	en: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "IsWindows":
		vm.PushBoolean(L, ODIN_OS == .Windows)
		return true
	case "GetGuiInset", "IsTenFootInterface":
		vm.PushUserdataMethod(L, key)
		return true
	}
	return false
}

gui_service_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	dt: ^datatypes.Registry,
	en: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	switch method {
	case "GetGuiInset":
		scale := max(platform.UI_Scale, 1)
		datatypes.Push_Vector2(
			L,
			dt,
			{platform.UI_Safe_Left / scale, platform.UI_Safe_Top / scale},
		)
		datatypes.Push_Vector2(
			L,
			dt,
			{platform.UI_Safe_Right / scale, platform.UI_Safe_Bottom / scale},
		)
		return 2, true
	case "IsTenFootInterface":
		vm.PushBoolean(L, false)
		return 1, true
	}
	return 0, false
}

Register_GuiService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&GuiService_Class,
		gui_service_construct,
		gui_service_destroy,
		creatable = false,
		get = gui_service_get,
		namecall = gui_service_namecall,
		methods = []string{"GetGuiInset", "IsTenFootInterface"},
		properties = []string{"IsWindows"},
	)
}
