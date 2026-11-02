package services
// wire:service


import "core:math"

import kineffi "../bindings"
import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import guilib "../gui"
import vm "../vm"

Lighting_Class := classes.Class_Info {
	name   = "Lighting",
	parent = &Service_Class,
}


CLOCK_TIME_DAY :: f64(24.0)


SUN_ARC_TILT :: 0.62


SHADOW_FILTER_HARD :: i32(0)
SHADOW_FILTER_SOFT :: i32(2)
SHADOW_FILTER_SOFTEST :: i32(3)


NIGHT_SKY_COLOR :: datatypes.Color3{0.012, 0.018, 0.048}
NIGHT_HORIZON_COLOR :: datatypes.Color3{0.030, 0.038, 0.075}
NIGHT_GROUND_COLOR :: datatypes.Color3{0.010, 0.012, 0.020}

Lighting :: struct {
	using service:         Service,
	call_count:            i64,
	applied_context:       ^kineffi.KineFilamentContext,
	clock_time:            f64,
	brightness:            f64,
	ambient:               datatypes.Color3,
	outdoor_ambient:       datatypes.Color3,
	sun_color:             datatypes.Color3,
	global_shadows:        bool,
	shadow_softness:       f64,
	exposure_compensation: f64,
	dynamic_resolution:    bool,
	resolution_min_scale:  f64,
	shadow_cascades:       i64,
	shadow_map_size:       i64,
	applied_fingerprint:   u64,
}


Lighting_Default_Effects :: []struct {
	class_name: string,
	name:       string,
	enabled:    bool,
} {
	{"Clouds", "Clouds", true},
	{"Atmosphere", "Atmosphere", true},
	{"BloomEffect", "BloomEffect", true},
	{"ColorCorrectionEffect", "ColorCorrectionEffect", true},
	{"DepthOfFieldEffect", "DepthOfFieldEffect", false},
	{"SunRaysEffect", "SunRaysEffect", true},
	{"SSAOEffect", "SSAOEffect", true},
	{"BlurEffect", "BlurEffect", false},
	{"AntiAliasingEffect", "AntiAliasingEffect", false},
	{"DitheringEffect", "DitheringEffect", false},
	{"RenderQualityEffect", "RenderQualityEffect", false},
	{"VignetteEffect", "VignetteEffect", false},
	{"ScreenSpaceReflectionsEffect", "ScreenSpaceReflectionsEffect", true},
	{"ReflectionProbeEffect", "ReflectionProbeEffect", true},
	{"SSGIEffect", "SSGIEffect", false},
	{"FogEffect", "FogEffect", false},
	{"ScreenSpaceConeTracingEffect", "ScreenSpaceConeTracingEffect", false},
	{"TemporalAntiAliasingEffect", "TemporalAntiAliasingEffect", false},
	{"DynamicResolutionEffect", "DynamicResolutionEffect", false},
	{"ToneMappingEffect", "ToneMappingEffect", false},
}


LIGHTING_CLOUD_HEIGHT :: f32(700)
LIGHTING_CLOUD_THICKNESS :: f32(240)


DEFAULT_BLOOM_INTENSITY :: 0.25

lighting_tune_default_effect :: proc(object: ^classes.Object) {
	if object == nil {
		return
	}
	switch classes.Get_Class_Name(object) {
	case "BloomEffect":
		bloom := cast(^classes.BloomEffect)object
		bloom.intensity = DEFAULT_BLOOM_INTENSITY

	case "SSAOEffect":
		ao := cast(^classes.SSAOEffect)object
		ao.radius = 0.5
		ao.intensity = 0.6
	case "ScreenSpaceReflectionsEffect":
		reflections := cast(^classes.ScreenSpaceReflectionsEffect)object
		reflections.max_distance = 100
		reflections.thickness = 0.2
		reflections.bias = 0.01
	}
}


lighting_wrap_clock_time :: proc(clock_time: f64) -> f64 {


	wrapped := clock_time - math.trunc(clock_time / CLOCK_TIME_DAY) * CLOCK_TIME_DAY
	if wrapped < 0 {
		wrapped += CLOCK_TIME_DAY
	}
	if wrapped >= CLOCK_TIME_DAY {
		wrapped -= CLOCK_TIME_DAY
	}
	return wrapped
}


lighting_sun_direction :: proc(clock_time: f64) -> datatypes.Vector3 {
	phase := (clock_time / CLOCK_TIME_DAY) * 2.0 * math.PI - (math.PI * 0.5)
	horizontal := math.cos(phase)

	return datatypes.Vector3 {
		x = f32(horizontal * math.cos(SUN_ARC_TILT)),
		y = f32(math.sin(phase)),
		z = f32(horizontal * math.sin(SUN_ARC_TILT)),
	}
}

lighting_smoothstep :: proc(edge0, edge1, x: f32) -> f32 {
	t := clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
}

color3_lerp :: proc(from, to: datatypes.Color3, t: f32) -> datatypes.Color3 {
	return datatypes.Color3 {
		R = from.R + (to.R - from.R) * t,
		G = from.G + (to.G - from.G) * t,
		B = from.B + (to.B - from.B) * t,
	}
}


lighting_ambient_gain :: proc(ambient: datatypes.Color3) -> f32 {
	luma := (ambient.R + ambient.G + ambient.B) / 3.0
	return 0.25 + 0.75 * clamp(luma, 0.0, 1.0)
}


lerp_night :: proc(
	night: datatypes.Color3,
	day: datatypes.Color3,
	daylight: f32,
	gain: f32,
) -> datatypes.Color3 {
	base := color3_lerp(night, day, daylight)
	return color3_lerp(night, base, gain)
}

lighting_shadow_filter :: proc(softness: f64) -> i32 {
	switch {
	case softness < 0.25:
		return SHADOW_FILTER_HARD
	case softness < 0.75:
		return SHADOW_FILTER_SOFT
	case:
		return SHADOW_FILTER_SOFTEST
	}
}


Lighting_Effect_Set :: struct {
	clouds:       ^classes.Clouds,
	atmosphere:   ^classes.Atmosphere,
	blur:         ^classes.BlurEffect,
	bloom:        ^classes.BloomEffect,
	ao:           ^classes.SSAOEffect,
	dof:          ^classes.DepthOfFieldEffect,
	color:        ^classes.ColorCorrectionEffect,
	sun_rays:     ^classes.SunRaysEffect,
	antialiasing: ^classes.AntiAliasingEffect,
	dithering:    ^classes.DitheringEffect,
	quality:      ^classes.RenderQualityEffect,
	vignette:     ^classes.VignetteEffect,
	reflections:  ^classes.ScreenSpaceReflectionsEffect,
}


lighting_hash_mix :: proc(hash: u64, value: u64) -> u64 {
	return (hash ~ value) * 0x100000001B3
}

lighting_hash_f32 :: proc(hash: u64, value: f32) -> u64 {
	return lighting_hash_mix(hash, u64(transmute(u32)value))
}

lighting_hash_f64 :: proc(hash: u64, value: f64) -> u64 {
	return lighting_hash_mix(hash, transmute(u64)value)
}

lighting_hash_bool :: proc(hash: u64, value: bool) -> u64 {
	return lighting_hash_mix(hash, value ? 1 : 0)
}

lighting_hash_color3 :: proc(hash: u64, value: datatypes.Color3) -> u64 {
	result := lighting_hash_f32(hash, value.R)
	result = lighting_hash_f32(result, value.G)
	return lighting_hash_f32(result, value.B)
}


lighting_hash_ptr :: proc(hash: u64, value: rawptr) -> u64 {
	return lighting_hash_mix(hash, u64(uintptr(value)))
}


lighting_effects_fingerprint :: proc(service: ^Lighting, effects: Lighting_Effect_Set) -> u64 {
	hash := lighting_hash_mix(0xCBF29CE484222325, 0x4C696768)

	hash = lighting_hash_f64(hash, service.clock_time)
	hash = lighting_hash_f64(hash, service.brightness)
	hash = lighting_hash_color3(hash, service.ambient)
	hash = lighting_hash_color3(hash, service.outdoor_ambient)
	hash = lighting_hash_color3(hash, service.sun_color)
	hash = lighting_hash_bool(hash, service.global_shadows)
	hash = lighting_hash_f64(hash, service.shadow_softness)
	hash = lighting_hash_f64(hash, service.exposure_compensation)
	hash = lighting_hash_bool(hash, service.dynamic_resolution)
	hash = lighting_hash_f64(hash, service.resolution_min_scale)
	hash = lighting_hash_f64(hash, f64(service.shadow_cascades))
	hash = lighting_hash_f64(hash, f64(service.shadow_map_size))

	hash = lighting_hash_ptr(hash, rawptr(effects.atmosphere))
	hash = lighting_hash_ptr(hash, rawptr(effects.blur))
	hash = lighting_hash_ptr(hash, rawptr(effects.bloom))
	hash = lighting_hash_ptr(hash, rawptr(effects.ao))
	hash = lighting_hash_ptr(hash, rawptr(effects.dof))
	hash = lighting_hash_ptr(hash, rawptr(effects.color))
	hash = lighting_hash_ptr(hash, rawptr(effects.sun_rays))
	hash = lighting_hash_ptr(hash, rawptr(effects.antialiasing))
	hash = lighting_hash_ptr(hash, rawptr(effects.dithering))
	hash = lighting_hash_ptr(hash, rawptr(effects.quality))
	hash = lighting_hash_ptr(hash, rawptr(effects.vignette))
	hash = lighting_hash_ptr(hash, rawptr(effects.reflections))


	if atmosphere := effects.atmosphere; atmosphere != nil {
		hash = lighting_hash_bool(hash, atmosphere.enabled)
		hash = lighting_hash_color3(hash, atmosphere.sky_color)
		hash = lighting_hash_color3(hash, atmosphere.horizon_color)
		hash = lighting_hash_color3(hash, atmosphere.ground_color)
		hash = lighting_hash_f64(hash, atmosphere.sun_intensity)
	}
	if bloom := effects.bloom; bloom != nil {
		hash = lighting_hash_bool(hash, bloom.enabled)
		hash = lighting_hash_f64(hash, bloom.intensity)
		hash = lighting_hash_f64(hash, bloom.size)
		hash = lighting_hash_f64(hash, bloom.threshold)
		hash = lighting_hash_bool(hash, bloom.lens_flare)
	}
	if blur := effects.blur; blur != nil {
		hash = lighting_hash_bool(hash, blur.enabled)
		hash = lighting_hash_f64(hash, blur.size)
	}
	if ao := effects.ao; ao != nil {
		hash = lighting_hash_bool(hash, ao.enabled)
		hash = lighting_hash_f64(hash, ao.radius)
		hash = lighting_hash_f64(hash, ao.power)
		hash = lighting_hash_f64(hash, ao.intensity)
		hash = lighting_hash_f64(hash, f64(ao.quality))
		hash = lighting_hash_f64(hash, f64(ao.ao_type))
	}
	if dof := effects.dof; dof != nil {
		hash = lighting_hash_bool(hash, dof.enabled)
		hash = lighting_hash_f64(hash, dof.near_intensity)
		hash = lighting_hash_f64(hash, dof.far_intensity)
		hash = lighting_hash_f64(hash, dof.focus_distance)
		hash = lighting_hash_f64(hash, dof.in_focus_radius)
	}
	if color := effects.color; color != nil {
		hash = lighting_hash_bool(hash, color.enabled)
		hash = lighting_hash_f64(hash, color.brightness)
		hash = lighting_hash_f64(hash, color.contrast)
		hash = lighting_hash_f64(hash, color.saturation)
	}
	if sun_rays := effects.sun_rays; sun_rays != nil {
		hash = lighting_hash_bool(hash, sun_rays.enabled)
		hash = lighting_hash_f64(hash, sun_rays.intensity)
		hash = lighting_hash_f64(hash, sun_rays.spread)
	}
	if aa := effects.antialiasing; aa != nil {
		hash = lighting_hash_bool(hash, aa.enabled)
		hash = lighting_hash_bool(hash, aa.fxaa)
		hash = lighting_hash_bool(hash, aa.taa)
		hash = lighting_hash_bool(hash, aa.msaa)
		hash = lighting_hash_f64(hash, aa.sample_count)
	}
	if dithering := effects.dithering; dithering != nil {
		hash = lighting_hash_bool(hash, dithering.enabled)
	}
	if quality := effects.quality; quality != nil {
		hash = lighting_hash_bool(hash, quality.enabled)
		hash = lighting_hash_f64(hash, quality.quality)
	}
	if vignette := effects.vignette; vignette != nil {
		hash = lighting_hash_bool(hash, vignette.enabled)
		hash = lighting_hash_f64(hash, vignette.midpoint)
		hash = lighting_hash_f64(hash, vignette.roundness)
		hash = lighting_hash_f64(hash, vignette.feather)
		hash = lighting_hash_color3(hash, vignette.color)
		hash = lighting_hash_f64(hash, vignette.transparency)
	}
	if reflections := effects.reflections; reflections != nil {
		hash = lighting_hash_bool(hash, reflections.enabled)
		hash = lighting_hash_f64(hash, reflections.thickness)
		hash = lighting_hash_f64(hash, reflections.bias)
		hash = lighting_hash_f64(hash, reflections.max_distance)
		hash = lighting_hash_f64(hash, reflections.stride)
	}

	return hash
}


Lighting_Sun_Profile :: struct {
	direction:     datatypes.Vector3,
	sky_color:     datatypes.Color3,
	horizon_color: datatypes.Color3,
	ground_color:  datatypes.Color3,
	daylight:      f32,
	intensity:     f64,
}

lighting_sun_profile :: proc(
	service: ^Lighting,
	atmosphere: ^classes.Atmosphere,
) -> Lighting_Sun_Profile {
	direction := lighting_sun_direction(service.clock_time)


	daylight := lighting_smoothstep(-0.12, 0.28, direction.y)

	gain := lighting_ambient_gain(
		datatypes.Color3 {
			R = (service.ambient.R + service.outdoor_ambient.R) * 0.5,
			G = (service.ambient.G + service.outdoor_ambient.G) * 0.5,
			B = (service.ambient.B + service.outdoor_ambient.B) * 0.5,
		},
	)

	profile := Lighting_Sun_Profile {
		direction     = direction,
		daylight      = daylight,
		intensity     = max(
			0.0,
			atmosphere.sun_intensity,
		) * max(0.0, service.brightness / 2.0) * f64(daylight),
		sky_color     = lerp_night(NIGHT_SKY_COLOR, atmosphere.sky_color, daylight, gain),
		horizon_color = lerp_night(NIGHT_HORIZON_COLOR, atmosphere.horizon_color, daylight, gain),
		ground_color  = lerp_night(NIGHT_GROUND_COLOR, atmosphere.ground_color, daylight, gain),
	}

	return profile
}

Lighting_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(Lighting)
	service.service = Service_Init(&Lighting_Class, "Lighting", data_model)

	service.clock_time = 10.5
	service.brightness = 2.0
	service.ambient = datatypes.Color3{1, 1, 1}
	service.outdoor_ambient = datatypes.Color3{1, 1, 1}
	service.sun_color = datatypes.Color3{1.0, 0.98, 0.95}
	service.global_shadows = true
	service.shadow_softness = 0.0
	service.exposure_compensation = 0.0
	service.dynamic_resolution = true
	service.resolution_min_scale = 0.5
	service.shadow_cascades = 2
	service.shadow_map_size = 2048

	if model := cast(^DataModel)data_model;
	   model != nil && model.registry != nil && model.registry.vm_state != nil {
		for def in Lighting_Default_Effects {
			object, ok := classes.Push_New(
				model.registry.classes,
				model.registry.vm_state,
				def.class_name,
				false,
			)
			if !ok || object == nil {
				continue
			}

			classes.Set_Name(object, def.name)
			if effect := cast(^classes.LightingEffect)object; effect != nil {
				effect.enabled = def.enabled
			}
			lighting_tune_default_effect(object)


			classes.Set_Can_Replicate(object, false)

			classes.Set_Parent(object, &service.object)
			vm.Pop(model.registry.vm_state.L)
		}
	}

	return &service.object
}


lighting_collect_effects :: proc(service: ^Lighting) -> Lighting_Effect_Set {
	effects := Lighting_Effect_Set{}

	for child in classes.Get_Children(&service.object) {
		if child == nil {
			continue
		}
		switch classes.Get_Class_Name(child) {
		case "Clouds":
			effects.clouds = cast(^classes.Clouds)child
		case "Atmosphere":
			effects.atmosphere = cast(^classes.Atmosphere)child
		case "BlurEffect":
			effects.blur = cast(^classes.BlurEffect)child
		case "BloomEffect":
			effects.bloom = cast(^classes.BloomEffect)child
		case "SSAOEffect":
			effects.ao = cast(^classes.SSAOEffect)child
		case "DepthOfFieldEffect":
			effects.dof = cast(^classes.DepthOfFieldEffect)child
		case "ColorCorrectionEffect":
			effects.color = cast(^classes.ColorCorrectionEffect)child
		case "SunRaysEffect":
			effects.sun_rays = cast(^classes.SunRaysEffect)child
		case "AntiAliasingEffect":
			effects.antialiasing = cast(^classes.AntiAliasingEffect)child
		case "DitheringEffect":
			effects.dithering = cast(^classes.DitheringEffect)child
		case "RenderQualityEffect":
			effects.quality = cast(^classes.RenderQualityEffect)child
		case "VignetteEffect":
			effects.vignette = cast(^classes.VignetteEffect)child
		case "ScreenSpaceReflectionsEffect":
			effects.reflections = cast(^classes.ScreenSpaceReflectionsEffect)child
		}
	}

	return effects
}

Lighting_Apply :: proc(service: ^Lighting, renderer: ^classes.Renderer_Object) {
	if service == nil || renderer == nil || renderer.Filament == nil {
		return
	}

	filament := renderer.Filament

	effects := lighting_collect_effects(service)


	if clouds := effects.clouds; clouds != nil && clouds.enabled {
		kineffi.Kine_Filament_SetClouds(
			filament,
			true,
			f32(clouds.cover),
			f32(clouds.density),
			f32(clouds.height),
			f32(clouds.thickness),
			f32(clouds.color.R),
			f32(clouds.color.G),
			f32(clouds.color.B),
		)
	} else {
		kineffi.Kine_Filament_SetClouds(
			filament,
			false,
			0,
			0,
			LIGHTING_CLOUD_HEIGHT,
			LIGHTING_CLOUD_THICKNESS,
			1,
			1,
			1,
		)
	}


	fingerprint := lighting_effects_fingerprint(service, effects)
	fingerprint = lighting_hash_mix(fingerprint, lighting_advanced_fingerprint(service))
	if fingerprint == service.applied_fingerprint && service.applied_context == filament {
		return
	}


	borrowed_atmosphere := effects.atmosphere == nil
	if borrowed_atmosphere {
		effects.atmosphere = new(classes.Atmosphere)
		effects.atmosphere^ = classes.Atmosphere_Init()
	}
	defer if borrowed_atmosphere {
		free(effects.atmosphere)
	}

	atmosphere := effects.atmosphere
	blur := effects.blur
	bloom := effects.bloom
	ao := effects.ao
	dof := effects.dof
	color := effects.color
	sun_rays := effects.sun_rays
	antialiasing := effects.antialiasing
	dithering := effects.dithering
	quality := effects.quality
	vignette := effects.vignette

	profile := lighting_sun_profile(service, atmosphere)

	_ = kineffi.Kine_Filament_SetSkyAtmosphere(
		filament,
		f32(profile.direction.x),
		f32(profile.direction.y),
		f32(profile.direction.z),
		f32(profile.sky_color.R),
		f32(profile.sky_color.G),
		f32(profile.sky_color.B),
		f32(profile.horizon_color.R),
		f32(profile.horizon_color.G),
		f32(profile.horizon_color.B),
		f32(profile.ground_color.R),
		f32(profile.ground_color.G),
		f32(profile.ground_color.B),
		f32(profile.intensity),
	)


	_ = kineffi.Kine_Filament_SetShadowOptions(
		filament,
		service.global_shadows,
		lighting_shadow_filter(service.shadow_softness),
	)
	_ = kineffi.Kine_Filament_SetSunShadowOptions(
		filament,
		i32(service.shadow_map_size),
		i32(service.shadow_cascades),
		0.0,
		0.5,
		160.0,
		true,
		service.shadow_softness > 0.25,
	)


	_ = kineffi.Kine_Filament_SetDynamicResolution(
		filament,
		service.dynamic_resolution,
		f32(service.resolution_min_scale),
		1.0,
		2,
		0.0,
	)


	if bloom != nil {
		_ = kineffi.Kine_Filament_SetBloom(
			filament,
			bloom.enabled,
			f32(max(0.0, bloom.intensity)),
			i32(max(1.0, bloom.size)),
			6,
			bloom.threshold > 0,
			bloom.lens_flare,
		)
	} else if blur != nil {


		_ = kineffi.Kine_Filament_SetBloom(
			filament,
			blur.enabled,
			f32(blur.size / 100),
			i32(max(1.0, blur.size)),
			6,
			false,
			false,
		)
	} else {
		_ = kineffi.Kine_Filament_SetBloom(filament, false, 0, 256, 5, true, false)
	}

	if ao != nil {
		_ = kineffi.Kine_Filament_SetAmbientOcclusion(
			filament,
			ao.enabled,
			f32(ao.radius),
			f32(ao.power),
			f32(ao.intensity),
			i32(ao.quality),
			i32(ao.ao_type),
		)
	} else {
		_ = kineffi.Kine_Filament_SetAmbientOcclusion(filament, false, 0.3, 1, 1, 2, 0)
	}

	if dof != nil {
		options := classes.DepthOfFieldEffect_Render_Options(dof)
		_ = kineffi.Kine_Filament_SetDepthOfField(
			filament,
			options[0] > 0,
			options[1],
			1,
			options[2],
			i32(options[4]),
			i32(options[5]),
		)
		_ = kineffi.Kine_Filament_SetFocusDistance(filament, options[3])
	} else {
		_ = kineffi.Kine_Filament_SetDepthOfField(filament, false, 0, 1, 0, 0, 0)
	}


	night_lift := (1.0 - f64(profile.daylight)) * 0.15
	if color != nil && color.enabled {
		_ = kineffi.Kine_Filament_SetColorGrading(
			filament,
			f32(color.brightness + service.exposure_compensation + night_lift),
			f32(1 + color.contrast),
			f32(1 + color.saturation),
			1,
			0,
			0,
		)
	} else if service.exposure_compensation != 0.0 || night_lift > 0.0 {
		_ = kineffi.Kine_Filament_SetColorGrading(
			filament,
			f32(service.exposure_compensation + night_lift),
			1,
			1,
			1,
			0,
			0,
		)
	} else {
		_ = kineffi.Kine_Filament_ClearColorGrading(filament)
	}


	if sun_rays != nil {
		ray_intensity := f32(sun_rays.intensity) * profile.daylight
		_ = kineffi.Kine_Filament_SetSunRays(
			filament,
			sun_rays.enabled && profile.daylight > 0.01,
			0,
			1000,
			ray_intensity,
			0,
			1,
			ray_intensity,
			0,
			max(0.001, f32(sun_rays.spread)),
			1,
			1,
			1,
			true,
		)
	} else {
		_ = kineffi.Kine_Filament_SetSunRays(
			filament,
			false,
			0,
			1000,
			0,
			0,
			1,
			0,
			0,
			0.001,
			1,
			1,
			1,
			true,
		)
	}


	if antialiasing != nil && antialiasing.enabled {
		_ = kineffi.Kine_Filament_SetAntiAliasing(
			filament,
			antialiasing.fxaa,
			antialiasing.taa,
			antialiasing.msaa,
			i32(antialiasing.sample_count),
		)
	} else {
		_ = kineffi.Kine_Filament_SetAntiAliasing(filament, false, false, false, 1)
	}

	if dithering != nil {
		_ = kineffi.Kine_Filament_SetDithering(filament, dithering.enabled)
	} else {
		_ = kineffi.Kine_Filament_SetDithering(filament, false)
	}

	if quality != nil && quality.enabled {
		_ = kineffi.Kine_Filament_SetRenderQuality(filament, i32(quality.quality))
	}


	if reflections := effects.reflections; reflections != nil && reflections.enabled {
		_ = kineffi.Kine_Filament_SetScreenSpaceReflections(
			filament,
			true,
			f32(reflections.thickness),
			f32(reflections.bias),
			f32(reflections.max_distance),
			f32(reflections.stride),
		)
	} else {
		_ = kineffi.Kine_Filament_SetScreenSpaceReflections(filament, false, 0.5, 0.05, 10.0, 0.5)
	}

	if vignette != nil && vignette.enabled {
		_ = kineffi.Kine_Filament_SetVignette(
			filament,
			true,
			f32(vignette.midpoint),
			f32(vignette.roundness),
			f32(vignette.feather),
			f32(vignette.color.R),
			f32(vignette.color.G),
			f32(vignette.color.B),
			f32(1.0 - vignette.transparency),
		)
	} else {
		_ = kineffi.Kine_Filament_SetVignette(filament, false, 0.5, 0.4, 0.5, 0, 0, 0, 0)
	}

	_ = kineffi.Kine_Filament_SetPostProcessing(filament, true)
	lighting_apply_advanced(service, filament)


	service.applied_fingerprint = fingerprint
	service.applied_context = filament
}

lighting_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	service := cast(^Lighting)object
	if service == nil {
		return false
	}

	switch key {
	case "ClockTime":
		vm.PushNumber(L, service.clock_time)

	case "Brightness":
		vm.PushNumber(L, service.brightness)

	case "Ambient":
		datatypes.Push_Color3(L, datatype_registry, service.ambient)

	case "OutdoorAmbient":
		datatypes.Push_Color3(L, datatype_registry, service.outdoor_ambient)

	case "SunColor":
		datatypes.Push_Color3(L, datatype_registry, service.sun_color)

	case "GlobalShadows":
		vm.PushBoolean(L, service.global_shadows)

	case "ShadowSoftness":
		vm.PushNumber(L, service.shadow_softness)

	case "ExposureCompensation":
		vm.PushNumber(L, service.exposure_compensation)

	case "DynamicResolution":
		vm.PushBoolean(L, service.dynamic_resolution)

	case "ResolutionScale":
		vm.PushNumber(L, service.resolution_min_scale)

	case "ShadowCascades":
		vm.PushNumber(L, f64(service.shadow_cascades))

	case "ShadowMapSize":
		vm.PushNumber(L, f64(service.shadow_map_size))

	case:
		return false
	}

	return true
}

lighting_set :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	service := cast(^Lighting)object
	if service == nil {
		return false
	}

	switch key {
	case "ClockTime":
		service.clock_time = lighting_wrap_clock_time(vm.ArgNumber(L, value_index))

	case "Brightness":
		service.brightness = max(0.0, vm.ArgNumber(L, value_index))

	case "Ambient":
		service.ambient = datatypes.Arg_Color3(L, value_index, datatype_registry)

	case "OutdoorAmbient":
		service.outdoor_ambient = datatypes.Arg_Color3(L, value_index, datatype_registry)

	case "SunColor":
		service.sun_color = datatypes.Arg_Color3(L, value_index, datatype_registry)

	case "GlobalShadows":
		service.global_shadows = vm.ArgBoolean(L, value_index)

	case "ShadowSoftness":
		service.shadow_softness = clamp(vm.ArgNumber(L, value_index), 0.0, 1.0)

	case "ExposureCompensation":
		service.exposure_compensation = vm.ArgNumber(L, value_index)

	case "DynamicResolution":
		service.dynamic_resolution = vm.ArgBoolean(L, value_index)

	case "ResolutionScale":
		service.resolution_min_scale = clamp(vm.ArgNumber(L, value_index), 0.1, 1.0)

	case "ShadowCascades":
		service.shadow_cascades = clamp(i64(vm.ArgNumber(L, value_index)), 1, 4)

	case "ShadowMapSize":
		service.shadow_map_size = clamp(i64(vm.ArgNumber(L, value_index)), 256, 8192)

	case:
		return false
	}

	return true
}

Lighting_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	classes.Object_Destroy(object)
	free(cast(^Lighting)object)
}

Register_Lighting_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&Lighting_Class,
		Lighting_construct,
		Lighting_destroy,
		creatable = false,
		get = lighting_get,
		set = lighting_set,
		properties = []string {
			"Ambient",
			"Brightness",
			"ClockTime",
			"DynamicResolution",
			"ExposureCompensation",
			"GlobalShadows",
			"OutdoorAmbient",
			"ResolutionScale",
			"ShadowCascades",
			"ShadowMapSize",
			"ShadowSoftness",
			"SunColor",
		},
	)
}
