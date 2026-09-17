package services

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
	applied_context: ^kineffi.KineFilamentContext,
}

Lighting_construct :: proc(renderer: ^classes.Renderer_Object, data_model: rawptr) -> ^classes.Object {
	service := new(Lighting)
	service.service = Service_Init(&Lighting_Class, "Lighting", data_model)

	return &service.object
}

Lighting_Apply :: proc(service: ^Lighting, renderer: ^classes.Renderer_Object) {
	if service == nil || renderer == nil || renderer.Filament == nil { return }

	atmosphere: ^classes.Atmosphere = nil
	blur: ^classes.BlurEffect = nil
	bloom: ^classes.BloomEffect = nil
	ao: ^classes.SSAOEffect = nil
	dof: ^classes.DepthOfFieldEffect = nil
	color: ^classes.ColorCorrectionEffect = nil
	sun_rays: ^classes.SunRaysEffect = nil

	for child in classes.Get_Children(&service.object) {
		if child == nil { continue }
		switch classes.Get_Class_Name(child) {
		case "Atmosphere": atmosphere = cast(^classes.Atmosphere)child
		case "BlurEffect": blur = cast(^classes.BlurEffect)child
		case "BloomEffect": bloom = cast(^classes.BloomEffect)child
		case "SSAOEffect": ao = cast(^classes.SSAOEffect)child
		case "DepthOfFieldEffect": dof = cast(^classes.DepthOfFieldEffect)child
		case "ColorCorrectionEffect": color = cast(^classes.ColorCorrectionEffect)child
		case "SunRaysEffect": sun_rays = cast(^classes.SunRaysEffect)child
		}
	}

	if atmosphere == nil {
		atmosphere = new(classes.Atmosphere)
		atmosphere^ = classes.Atmosphere_Init()
	}
	a := atmosphere
	_ = kineffi.Kine_Filament_SetSkyAtmosphere(
		renderer.Filament,
		f32(a.sun_direction.x), f32(a.sun_direction.y), f32(a.sun_direction.z),
		f32(a.sky_color.R), f32(a.sky_color.G), f32(a.sky_color.B),
		f32(a.horizon_color.R), f32(a.horizon_color.G), f32(a.horizon_color.B),
		f32(a.ground_color.R), f32(a.ground_color.G), f32(a.ground_color.B),
		f32(a.sun_intensity),
	)
	if atmosphere != nil && atmosphere.object.parent == nil { free(atmosphere) }

	if bloom != nil {
		_ = kineffi.Kine_Filament_SetBloom(renderer.Filament, bloom.enabled, f32(bloom.intensity), i32(bloom.size), 6, bloom.threshold > 0, bloom.lens_flare)
	} else if blur != nil {
		// Filament has no standalone blur option; its bloom pass is the
		// closest built-in fullscreen softening effect available here.
		_ = kineffi.Kine_Filament_SetBloom(renderer.Filament, blur.enabled, f32(blur.size / 100), i32(blur.size), 6, false, false)
	} else {
		_ = kineffi.Kine_Filament_SetBloom(renderer.Filament, false, 0, 256, 5, true, false)
	}
	if ao != nil {
		_ = kineffi.Kine_Filament_SetAmbientOcclusion(renderer.Filament, ao.enabled, f32(ao.radius), f32(ao.power), f32(ao.intensity), i32(ao.quality), i32(ao.ao_type))
	} else {
		_ = kineffi.Kine_Filament_SetAmbientOcclusion(renderer.Filament, false, 0.3, 1, 1, 2, 0)
	}
	if dof != nil {
		_ = kineffi.Kine_Filament_SetDepthOfField(renderer.Filament, dof.enabled, f32(dof.near_intensity+dof.far_intensity), 1, f32(dof.in_focus_radius), 16, 16)
		_ = kineffi.Kine_Filament_SetFocusDistance(renderer.Filament, f32(dof.focus_distance))
	} else {
		_ = kineffi.Kine_Filament_SetDepthOfField(renderer.Filament, false, 0, 1, 0, 0, 0)
	}
	if color != nil && color.enabled {
		_ = kineffi.Kine_Filament_SetColorGrading(renderer.Filament, f32(color.brightness), f32(1+color.contrast), f32(1+color.saturation), 0, 0, 0)
	} else {
		_ = kineffi.Kine_Filament_ClearColorGrading(renderer.Filament)
	}
	if sun_rays != nil {
		_ = kineffi.Kine_Filament_SetSunRays(renderer.Filament, sun_rays.enabled, 0, 1000, f32(sun_rays.intensity), 0, 1, f32(sun_rays.intensity), 0, max(0.001, f32(sun_rays.spread)), 1, 1, 1, true)
	} else {
		_ = kineffi.Kine_Filament_SetSunRays(renderer.Filament, false, 0, 1000, 0, 0, 1, 0, 0, 0.001, 1, 1, 1, true)
	}
	_ = kineffi.Kine_Filament_SetPostProcessing(renderer.Filament, true)
	service.applied_context = renderer.Filament
}

Lighting_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	classes.Object_Destroy(object)
	free(cast(^Lighting)object)
}

Register_Lighting_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(registry, &Lighting_Class, Lighting_construct, Lighting_destroy, creatable = false)
}
