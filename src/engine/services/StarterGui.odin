package services

import "core:fmt"
// wire:service global="StarterGui"

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import guilib "../gui"
import vm "../vm"

StarterGui_Class := classes.Class_Info {
	name   = "StarterGui",
	parent = &Service_Class,
}

StarterGui :: struct {
	using service: Service,
	call_count:    i64,
}

StarterGui_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(StarterGui)
	service.service = Service_Init(&StarterGui_Class, "StarterGui", data_model)
	return &service.object
}

StarterGui_Render :: proc(object: ^classes.Object, ctx: ^classes.Class_Step_Context) {
	for child in object.children {
		if classes.Is_A(child, "ScreenGui") {
			classes.ScreenGui_render(child, ctx)
		}
	}
}

StarterGui_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	classes.Object_Destroy(object)
	free(cast(^StarterGui)object)
}

Register_StarterGui_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&StarterGui_Class,
		StarterGui_construct,
		StarterGui_destroy,
		creatable = false,
	)
}
