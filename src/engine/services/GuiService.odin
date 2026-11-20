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
	service := cast(^Service)object
	registry: ^classes.Registry
	if service.data_model != nil &&
	   service.data_model.registry != nil {registry = service.data_model.registry.classes}
	switch key {
	case "SelectedObject":
		if selected := classes.Gui_Get_Selected(registry);
		   selected != nil {classes.Push_Object(L, &selected.object)} else {vm.PushNil(L)}
		return true
	case "GuiNavigationEnabled":
		vm.PushBoolean(L, registry != nil && !registry.gui_navigation_disabled)
		return true
	case "IsWindows":
		vm.PushBoolean(L, ODIN_OS == .Windows)
		return true
	case "GetGuiInset", "IsTenFootInterface":
		vm.PushUserdataMethod(L, key)
		return true
	}
	return false
}

gui_service_set :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	dt: ^datatypes.Registry,
	en: ^enums.Registry,
	key: string,
	index: int,
) -> bool {
	service := cast(^Service)object
	if service.data_model == nil || service.data_model.registry == nil {return false}
	registry := service.data_model.registry.classes
	if registry == nil {return false}
	switch key {
	case "SelectedObject":
		if vm.IsNoneOrNil(L, index) {return classes.Gui_Set_Selected(registry, nil)}
		selected := classes.Object_From_Argument(L, index)
		if selected == nil || !classes.Is_A(selected, "GuiObject") {return false}
		return classes.Gui_Set_Selected(registry, cast(^classes.GuiObject)selected)
	case "GuiNavigationEnabled":
		registry.gui_navigation_disabled = !vm.ArgBoolean(L, index)
		if registry.gui_navigation_disabled {_ = classes.Gui_Set_Selected(registry, nil)}
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
		scale := platform.UI_Scale
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
		set = gui_service_set,
		namecall = gui_service_namecall,
		methods = []string{"GetGuiInset", "IsTenFootInterface"},
		properties = []string{"IsWindows", "SelectedObject", "GuiNavigationEnabled"},
	)
}
