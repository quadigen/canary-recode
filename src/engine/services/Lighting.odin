package services

import "core:fmt"
// wire:service global="Lighting"

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import guilib "../gui"
import kineffi "../bindings"

Lighting_Class := classes.Class_Info{name = "Lighting", parent = &Service_Class}

Lighting :: struct {
	using service: Service,
	call_count: i64,
}

Lighting_construct :: proc(renderer: ^classes.Renderer_Object, data_model: rawptr) -> ^classes.Object {
	service := new(Lighting)
	service.service = Service_Init(&Lighting_Class, "Lighting", data_model)

    result := kineffi.Kine_Filament_SetSkyAtmosphere(
        renderer.Filament,

        // Sun direction
        -0.35, -0.85, -0.25,

        // Sky color
        0.32, 0.58, 0.95,

        // Horizon color
        0.78, 0.86, 1.0,

        // Ground color
        0.10, 0.12, 0.14,

        // Sun intensity
        8.0,
    )

	return &service.object
}

Lighting_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	classes.Object_Destroy(object)
	free(cast(^Lighting)object)
}

Register_Lighting_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(registry, &Lighting_Class, Lighting_construct, Lighting_destroy, creatable = false)
}
