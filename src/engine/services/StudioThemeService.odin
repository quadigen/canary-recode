package services

// wire:service global="StudioThemeService"

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

StudioThemeService_Class := classes.Class_Info{
	name = "StudioThemeService",
	parent = &Service_Class,
}

StudioThemeService :: struct {
	using service: Service,
}

studio_theme_color :: proc(L: ^vm.State, r, g, b: f64, a: f64 = 1) {
	vm.NewTable(L, 0, 4)
	vm.PushNumber(L, r)
	vm.SetField(L, -2, "R")
	vm.PushNumber(L, g)
	vm.SetField(L, -2, "G")
	vm.PushNumber(L, b)
	vm.SetField(L, -2, "B")
	vm.PushNumber(L, a)
	vm.SetField(L, -2, "A")
}

studio_theme_service_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	if key != "SelectedTheme" { return false }

	vm.NewTable(L, 0, 12)
	studio_theme_color(L, 0.075, 0.086, 0.11)
	vm.SetField(L, -2, "BaseColor")
	studio_theme_color(L, 0.11, 0.12, 0.15)
	vm.SetField(L, -2, "SecondaryColor")
	studio_theme_color(L, 0.96, 0.97, 1)
	vm.SetField(L, -2, "TextColor")
	studio_theme_color(L, 0.7, 0.72, 0.78)
	vm.SetField(L, -2, "SecondaryTextColor")
	studio_theme_color(L, 0.3, 0.55, 1)
	vm.SetField(L, -2, "AccentColor")
	vm.PushString(L, "")
	vm.SetField(L, -2, "Font")
	vm.PushNumber(L, 6)
	vm.SetField(L, -2, "CornerRadius")
	vm.PushNumber(L, 4)
	vm.SetField(L, -2, "ButtonCornerRadius")
	return true
}

StudioThemeService_construct :: proc(renderer: ^classes.Renderer_Object, data_model: rawptr) -> ^classes.Object {
	service := new(StudioThemeService)
	service.service = Service_Init(&StudioThemeService_Class, "StudioThemeService", data_model)
	return &service.object
}

StudioThemeService_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	classes.Object_Destroy(object)
	free(cast(^StudioThemeService)object)
}

Register_StudioThemeService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&StudioThemeService_Class,
		StudioThemeService_construct,
		StudioThemeService_destroy,
		creatable = false,
		get = studio_theme_service_get,
	)
}
