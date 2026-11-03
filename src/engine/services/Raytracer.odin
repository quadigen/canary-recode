package services

// wire:service global="Raytracer"

import kineffi "../bindings"
import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import renderer_pkg "../renderer"
import tracy "../util/odin-tracy"
import vm "../vm"
import "core:fmt"
import "core:strings"

Raytracer_Class := classes.Class_Info {
	name   = "Raytracer",
	parent = &Service_Class,
}

RAYTRACER_RETRY_FRAMES :: 240

Raytracer :: struct {
	using service: Service,
	call_count:    i64,
	attached:      bool,
	retry_wait:    i32,
	last_error:    string,
	renderer:      ^classes.Renderer_Object,
	params:        kineffi.KineRayProperties,
}

Raytracer_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(Raytracer)
	service.service = Service_Init(&Raytracer_Class, "Raytracer", data_model)
	service.renderer = renderer

	Raytracer_attach(service, renderer)

	return &service.object
}

Raytracer_set_error :: proc(service: ^Raytracer, report: string) {
	if report == service.last_error {
		return
	}
	if service.last_error != "" {
		delete(service.last_error)
	}
	service.last_error = strings.clone(report)
	fmt.eprintln("[Raytracer] Ray is unavailable:", report)
}

Raytracer_attach :: proc(service: ^Raytracer, renderer: ^classes.Renderer_Object) -> bool {
	if service == nil || renderer == nil || renderer.Filament == nil {
		return false
	}
	if service.attached {
		return true
	}

	width, height := renderer_pkg.viewport_size(renderer)
	if width <= 0 || height <= 0 {
		return false
	}

	if !kineffi.Kine_Filament_HasRay(renderer.Filament) {
		tracy.ZoneNC("Raytracer Initialize", 0xC678DD)
		if !kineffi.Kine_Filament_NewRay(renderer.Filament, width, height) {
			report := string(kineffi.Kine_Filament_GetRayError())
			if report == "" {
				report = "unknown error"
			}
			Raytracer_set_error(service, report)
			return false
		}
	}

	if !kineffi.Kine_Filament_SetRenderMode(renderer.Filament, kineffi.KINE_RENDER_MODE_FILAMENT) {
		report := string(kineffi.Kine_Filament_GetRayError())
		if report == "" {
			report = "could not switch to render mode 2"
		}
		Raytracer_set_error(service, report)
		return false
	}

	kineffi.Kine_Ray_GetProperties(renderer.Filament, &service.params)
	kineffi.Kine_Ray_SetProperties(renderer.Filament, &service.params)

	if service.last_error != "" {
		delete(service.last_error)
		service.last_error = ""
	}
	service.attached = true
	service.retry_wait = 0
	fmt.printf(
		"[Raytracer] Ray path tracing enabled on the shared Vulkan device (%dx%d)\n",
		width,
		height,
	)
	return true
}

Raytracer_Prepare_3D :: proc(service: ^Raytracer, renderer: ^classes.Renderer_Object) {
	if service == nil || renderer == nil || renderer.Filament == nil {
		return
	}
	if service.attached {
		return
	}
	if service.retry_wait > 0 {
		service.retry_wait -= 1
		return
	}
	width, height := renderer_pkg.viewport_size(renderer)
	if width <= 0 || height <= 0 {
		return
	}
	if !Raytracer_attach(service, renderer) {
		service.retry_wait = RAYTRACER_RETRY_FRAMES
	}
}

Raytracer_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	service := cast(^Raytracer)object
	switch key {
	case "CallCount":
		vm.PushNumber(L, f64(service.call_count))
	case "Attached":
		vm.PushBoolean(L, service.attached)
	case "MaxTotalDepth":
		vm.PushNumber(L, f64(service.params.maxTotalDepth))
	case "MaxDiffuseDepth":
		vm.PushNumber(L, f64(service.params.maxDiffuseDepth))
	case "MaxSpecularDepth":
		vm.PushNumber(L, f64(service.params.maxSpecularDepth))
	case "MaxRefractionDepth":
		vm.PushNumber(L, f64(service.params.maxRefractionDepth))
	case "SamplesPerFrame":
		vm.PushNumber(L, f64(service.params.samplesPerFrame))
	case "MinSamples":
		vm.PushNumber(L, f64(service.params.minSamples))
	case "VarianceThreshold":
		vm.PushNumber(L, f64(service.params.varianceThreshold))
	case "Exposure":
		vm.PushNumber(L, f64(service.params.exposure))
	case "ClampDirect":
		vm.PushNumber(L, f64(service.params.clampDirect))
	case "ClampIndirect":
		vm.PushNumber(L, f64(service.params.clampIndirect))
	case "Enable", "Disable":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}
	return true
}

Raytracer_set :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	service := cast(^Raytracer)object
	value := vm.ArgNumber(L, 3)

	switch key {
	case "MaxTotalDepth":
		service.params.maxTotalDepth = i32(value)
	case "MaxDiffuseDepth":
		service.params.maxDiffuseDepth = i32(value)
	case "MaxSpecularDepth":
		service.params.maxSpecularDepth = i32(value)
	case "MaxRefractionDepth":
		service.params.maxRefractionDepth = i32(value)
	case "SamplesPerFrame":
		service.params.samplesPerFrame = i32(value)
	case "MinSamples":
		service.params.minSamples = i32(value)
	case "VarianceThreshold":
		service.params.varianceThreshold = f32(value)
	case "Exposure":
		service.params.exposure = f32(value)
	case "ClampDirect":
		service.params.clampDirect = f32(value)
	case "ClampIndirect":
		service.params.clampIndirect = f32(value)
	case:
		return false
	}

	if service.attached && service.renderer != nil && service.renderer.Filament != nil {
		kineffi.Kine_Ray_SetProperties(service.renderer.Filament, &service.params)
		kineffi.Kine_Ray_GetProperties(service.renderer.Filament, &service.params)
	}
	return true
}

Raytracer_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	service := cast(^Raytracer)object
	renderer := service.renderer.Filament

	switch method {
	case "Add":
		service.call_count += 1
		vm.PushNumber(L, vm.ArgNumber(L, 2) + vm.ArgNumber(L, 3))
		return 1, true
	case "Echo":
		service.call_count += 1
		vm.PushValue(L, 2)
		return 1, true
	case "MakeColor":
		service.call_count += 1
		if datatype_registry == nil {return 0, false}
		datatypes.Push_Color3(
			L,
			datatype_registry,
			datatypes.Color3 {
				f32(vm.ArgNumber(L, 2)),
				f32(vm.ArgNumber(L, 3)),
				f32(vm.ArgNumber(L, 4)),
			},
		)
		return 1, true
	case "GetService":
		classes.Push_Object(L, Service_Get_Service(&service.service, vm.ArgString(L, 2)))
		return 1, true
	case "Enable":
		if !kineffi.Kine_Filament_SetRenderMode(renderer, kineffi.KINE_RENDER_MODE_RAY) {
			report := string(kineffi.Kine_Filament_GetRayError())
			if report == "" {
				report = "could not switch to render mode 1"
			}
			Raytracer_set_error(service, report)
			return 1, true
		}
		return 1, true
	case "Disable":
		if !kineffi.Kine_Filament_SetRenderMode(renderer, kineffi.KINE_RENDER_MODE_FILAMENT) {
			report := string(kineffi.Kine_Filament_GetRayError())
			if report == "" {
				report = "could not switch to render mode 2"
			}
			Raytracer_set_error(service, report)
			return 1, true
		}
		return 1, true
	}
	return 0, false
}

Raytracer_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	service := cast(^Raytracer)object
	if service.last_error != "" {
		delete(service.last_error)
		service.last_error = ""
	}
	classes.Object_Destroy(object)
	free(service)
}

Register_Raytracer_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&Raytracer_Class,
		Raytracer_construct,
		Raytracer_destroy,
		creatable = false,
		get = Raytracer_get,
		set = Raytracer_set,
		properties = []string {
			"Exposure",
			"ClampDirect",
			"ClampIndirect",
			"MaxDiffuseDepth",
			"MaxTotalDepth",
			"Attach",
			"VarianceThreshold",
			"MinSamples",
			"SamplesPerFrame",
			"MaxRefractionDepth",
			"MaxSpecularDepth",
		},
		namecall = Raytracer_namecall,
	)
}
