package services


import "core:fmt"
import "core:math"
import "core:strconv"

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
	using service:                  Service,
	sun_rays_distance:              f32,
	sun_rays_animated:              bool,
	call_count:                     i64,
	applied_context:                ^kineffi.KineFilamentContext,
	clock_time:                     f64,
	brightness:                     f64,
	ambient:                        datatypes.Color3,
	outdoor_ambient:                datatypes.Color3,
	sun_color:                      datatypes.Color3,
	global_shadows:                 bool,
	shadow_softness:                f64,
	exposure_compensation:          f64,
	quality_preset:                 enums.QualityPreset,
	dynamic_resolution:             bool,
	adaptive_shadow_resolution:     bool,
	resolution_min_scale:           f64,
	shadow_cascades:                i64,
	shadow_map_size:                i64,
	shadow_type:                    enums.ShadowType,
	shadow_distance:                f64,
	shadow_near_hint:               f64,
	shadow_far_hint:                f64,
	shadow_cascade_split_lambda:    f64,
	shadow_stable:                  bool,
	shadow_lispsm:                  bool,
	shadow_contact_shadows:         bool,
	shadow_contact_steps:           i64,
	shadow_contact_distance:        f64,
	shadow_bias:                    f64,
	shadow_normal_bias:             f64,
	shadow_polygon_offset_constant: f64,
	shadow_polygon_offset_slope:    f64,
	shadow_bulb_radius:             f64,
	shadow_penumbra_scale:          f64,
	shadow_penumbra_ratio_scale:    f64,
	shadow_vsm_blur:                f64,
	shadow_vsm_high_precision:      bool,
	shadow_vsm_bleed_reduction:     f64,
	shadow_vsm_elvsm:               bool,
	shadow_contact_auto:            bool,
	shadow_pcss_max_penumbra_ratio: f64,
	shadow_pcss_max_search_radius:  f64,
	shadow_vsm_anisotropy:          i64,
	shadow_vsm_mipmapping:          bool,
	shadow_vsm_msaa_samples:        i64,
	sun_angular_radius:             f64,
	sun_halo_size:                  f64,
	sun_halo_falloff:               f64,
	applied_fingerprint:            u64,
	sky_hash:                       u64,
	sky_uploaded:                   bool,
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
	{"SunRaysEffect", "SunRaysEffect", false},
	{"SSAOEffect", "SSAOEffect", true},
	{"BlurEffect", "BlurEffect", false},
	{"AntiAliasingEffect", "AntiAliasingEffect", false},
	{"DitheringEffect", "DitheringEffect", false},
	{"RenderQualityEffect", "RenderQualityEffect", false},
	{"VignetteEffect", "VignetteEffect", false},
	{"ScreenSpaceReflectionsEffect", "ScreenSpaceReflectionsEffect", false},
	{"ReflectionProbeEffect", "ReflectionProbeEffect", false},
	{"SSGIEffect", "SSGIEffect", false},
	{"FogEffect", "FogEffect", false},
	{"VolumetricFogEffect", "VolumetricFogEffect", false},
	{"ChromaticAberrationEffect", "ChromaticAberrationEffect", false},
	{"FilmGrainEffect", "FilmGrainEffect", false},
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

	case "SunRaysEffect":
		(cast(^classes.SunRaysEffect)object).dust_amount = 0

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
		x = f64(f32(horizontal * math.cos(SUN_ARC_TILT))),
		y = f64(f32(math.sin(phase))),
		z = f64(f32(horizontal * math.sin(SUN_ARC_TILT))),
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


lighting_shadow_clamp_number :: proc(
	L: ^vm.State,
	value_index: int,
	minimum, maximum: f64,
) -> f64 {
	value := vm.ArgNumber(L, value_index)
	if math.is_nan(value) || math.is_inf(value) {
		_ = vm.RaiseError(L, "shadow setting must be a finite number")
		return minimum
	}
	return clamp(value, minimum, maximum)
}

lighting_shadow_type :: proc(service: ^Lighting) -> i32 {
	switch service.shadow_type {
	case .PCF:
		return SHADOW_FILTER_HARD
	case .VSM:
		return 1
	case .DPCF:
		return SHADOW_FILTER_SOFT
	case .PCSS:
		return SHADOW_FILTER_SOFTEST
	case .Auto:
		return lighting_shadow_filter(service.shadow_softness)
	}
	return SHADOW_FILTER_HARD
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
	hash = lighting_hash_mix(hash, u64(service.quality_preset))
	hash = lighting_hash_bool(hash, service.dynamic_resolution)
	hash = lighting_hash_bool(hash, service.adaptive_shadow_resolution)
	hash = lighting_hash_f64(hash, service.resolution_min_scale)
	hash = lighting_hash_f64(hash, f64(service.shadow_cascades))
	hash = lighting_hash_f64(hash, f64(service.shadow_map_size))
	hash = lighting_hash_mix(hash, u64(lighting_shadow_type(service)))
	hash = lighting_hash_f64(hash, service.shadow_distance)
	hash = lighting_hash_f64(hash, service.shadow_near_hint)
	hash = lighting_hash_f64(hash, service.shadow_far_hint)
	hash = lighting_hash_f64(hash, service.shadow_cascade_split_lambda)
	hash = lighting_hash_bool(hash, service.shadow_stable)
	hash = lighting_hash_bool(hash, service.shadow_lispsm)
	hash = lighting_hash_bool(hash, service.shadow_contact_shadows)
	hash = lighting_hash_mix(hash, u64(service.shadow_contact_steps))
	hash = lighting_hash_f64(hash, service.shadow_contact_distance)
	hash = lighting_hash_f64(hash, service.shadow_bias)
	hash = lighting_hash_f64(hash, service.shadow_normal_bias)
	hash = lighting_hash_f64(hash, service.shadow_polygon_offset_constant)
	hash = lighting_hash_f64(hash, service.shadow_polygon_offset_slope)
	hash = lighting_hash_f64(hash, service.shadow_bulb_radius)
	hash = lighting_hash_f64(hash, service.shadow_penumbra_scale)
	hash = lighting_hash_f64(hash, service.shadow_penumbra_ratio_scale)
	hash = lighting_hash_f64(hash, service.shadow_vsm_blur)
	hash = lighting_hash_bool(hash, service.shadow_vsm_high_precision)
	hash = lighting_hash_f64(hash, service.shadow_vsm_bleed_reduction)
	hash = lighting_hash_bool(hash, service.shadow_vsm_elvsm)
	hash = lighting_hash_bool(hash, service.shadow_contact_auto)
	hash = lighting_hash_f64(hash, service.shadow_pcss_max_penumbra_ratio)
	hash = lighting_hash_f64(hash, service.shadow_pcss_max_search_radius)
	hash = lighting_hash_mix(hash, u64(service.shadow_vsm_anisotropy))
	hash = lighting_hash_bool(hash, service.shadow_vsm_mipmapping)
	hash = lighting_hash_mix(hash, u64(service.shadow_vsm_msaa_samples))
	hash = lighting_hash_f64(hash, service.sun_angular_radius)
	hash = lighting_hash_f64(hash, service.sun_halo_size)
	hash = lighting_hash_f64(hash, service.sun_halo_falloff)

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
		hash = lighting_hash_f64(hash, sun_rays.dust_amount)
		hash = lighting_hash_f64(hash, sun_rays.max_distance)
		hash = lighting_hash_f64(hash, f64(sun_rays.sample_count))
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

lighting_effective_sun_direction :: proc(service: ^Lighting) -> datatypes.Vector3 {
	sun := lighting_scene_effect(service, &classes.SunLightEffect_Class)
	if sun == nil || !sun.enabled {return lighting_sun_direction(service.clock_time)}

	azimuth := f64(sun.values[0]) * (math.PI / 180)
	elevation := f64(sun.values[1]) * (math.PI / 180)
	horizontal := math.cos(elevation)
	return {horizontal * math.cos(azimuth), math.sin(elevation), horizontal * math.sin(azimuth)}
}

lighting_sun_profile :: proc(
	service: ^Lighting,
	atmosphere: ^classes.Atmosphere,
) -> Lighting_Sun_Profile {
	direction := lighting_effective_sun_direction(service)


	daylight := lighting_smoothstep(-0.12, 0.28, f32(direction.y))

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
	service.quality_preset = .Custom
	service.dynamic_resolution = true
	service.adaptive_shadow_resolution = true
	service.resolution_min_scale = 0.5
	service.shadow_cascades = 2
	service.shadow_map_size = 2048
	service.shadow_type = .Auto
	service.shadow_distance = 0.0
	service.shadow_near_hint = 0.5
	service.shadow_far_hint = 160.0
	service.shadow_cascade_split_lambda = 0.65
	service.shadow_stable = true
	service.shadow_lispsm = false
	service.shadow_contact_shadows = false
	service.shadow_contact_steps = 16
	service.shadow_contact_distance = 0.75
	service.shadow_bias = 0.004
	service.shadow_normal_bias = 1.25
	service.shadow_polygon_offset_constant = 0.75
	service.shadow_polygon_offset_slope = 2.5
	service.shadow_bulb_radius = -1.0
	service.shadow_penumbra_scale = 1.0
	service.shadow_penumbra_ratio_scale = 1.0
	service.shadow_vsm_blur = 0.0
	service.shadow_vsm_high_precision = false
	service.shadow_vsm_bleed_reduction = 0.15
	service.shadow_vsm_elvsm = false
	service.shadow_contact_auto = true
	service.shadow_pcss_max_penumbra_ratio = 10.0
	service.shadow_pcss_max_search_radius = 1.0
	service.shadow_vsm_anisotropy = 0
	service.shadow_vsm_mipmapping = false
	service.shadow_vsm_msaa_samples = 1
	service.sun_angular_radius = 1.9
	service.sun_halo_size = 10.0
	service.sun_halo_falloff = 80.0

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

Lighting_Quality_Settings :: struct {
	dynamic_resolution: bool,
	adaptive_shadows:   bool,
	min_scale:          f32,
	shadow_size:        i32,
	shadow_cascades:    i32,
	shadow_filter:      i32,
	contact_steps:      i32,
	cloud_scale:        f32,
	hdr_quality:        i32,
	ao_quality:         i32,
}

Lighting_Get_Quality_Settings :: proc(service: ^Lighting) -> Lighting_Quality_Settings {
	switch service.quality_preset {
	case .Low:
		return {true, true, 0.5, 512, 1, SHADOW_FILTER_HARD, 8, 0.25, 0, 0}
	case .Medium:
		return {true, true, 0.75, 1024, 2, SHADOW_FILTER_HARD, 16, 0.5, 1, 1}
	case .High:
		return {false, false, 1, 2048, 3, SHADOW_FILTER_SOFT, 32, 0.75, 2, 2}
	case .Ultra:
		return {false, false, 1, 4096, 4, SHADOW_FILTER_SOFTEST, 64, 1, 3, 3}
	case .Custom:
		return {
			service.dynamic_resolution,
			service.adaptive_shadow_resolution,
			f32(service.resolution_min_scale),
			i32(service.shadow_map_size),
			i32(service.shadow_cascades),
			lighting_shadow_type(service),
			i32(service.shadow_contact_steps),
			0,
			2,
			2,
		}
	}
	return {}
}

Lighting_Apply :: proc(
	service: ^Lighting,
	renderer: ^classes.Renderer_Object,
	fast_viewport := false,
) {
	if service == nil || renderer == nil || renderer.Filament == nil {
		return
	}

	filament := renderer.Filament

	effects := lighting_collect_effects(service)
	preset := Lighting_Get_Quality_Settings(service)
	custom := service.quality_preset == .Custom

	if clouds := effects.clouds; !fast_viewport && service.quality_preset != .Low && clouds != nil && clouds.enabled {
		when ODIN_OS != .JS {kineffi.Kine_Filament_SetCloudResolutionScale(filament, custom ? clouds.resolution_scale : preset.cloud_scale)}
		kineffi.Kine_Filament_SetCloudShadowOptions(
			filament,
			clouds.cast_shadows,
			clouds.shadow_intensity,
			clouds.shadow_scale,
			clouds.shadow_speed,
			clouds.shadow_softness,
			clouds.shadow_distance,
		)
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
		kineffi.Kine_Filament_SetCloudShadowOptions(filament, false, 0, 1, 1, 1, 1500)
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
	fingerprint = lighting_hash_bool(fingerprint, fast_viewport)
	sky: ^classes.Sky
	for child in service.children {
		if child != nil &&
		   !child.destroyed &&
		   child.class == &classes.Sky_Class {sky = cast(^classes.Sky)child; break}
	}
	sky_hash := lighting_hash_ptr(0, rawptr(sky))
	if sky != nil {
		sky_hash = lighting_hash_mix(sky_hash, sky.revision)
		for path in sky.faces {for byte_value in transmute([]u8)path {sky_hash = lighting_hash_mix(sky_hash, u64(byte_value))}}
	}
	fingerprint = lighting_hash_mix(fingerprint, sky_hash)
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

	if service.sky_hash != sky_hash || service.applied_context != filament {
		service.sky_uploaded = classes.Sky_Upload(sky, filament)
		service.sky_hash = sky_hash
	}
	if !service.sky_uploaded {
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
	} else {
		_ = kineffi.Kine_Filament_SetSun(
			filament,
			f32(profile.direction.x),
			f32(profile.direction.y),
			f32(profile.direction.z),
			f32(profile.intensity),
		)
	}


	_ = kineffi.Kine_Filament_SetShadowOptions(
		filament,
		service.global_shadows && !fast_viewport && service.quality_preset != .Low,
		preset.shadow_filter,
	)
	kineffi.Kine_Filament_SetShadowViewQuality(
		filament,
		f32(service.shadow_penumbra_scale),
		f32(service.shadow_penumbra_ratio_scale),
		service.shadow_vsm_high_precision,
		f32(service.shadow_vsm_bleed_reduction),
	)
	kineffi.Kine_Filament_SetShadowExtraOptions(
		filament,
		f32(service.shadow_pcss_max_penumbra_ratio),
		f32(service.shadow_pcss_max_search_radius),
		i32(service.shadow_vsm_anisotropy),
		service.shadow_vsm_mipmapping,
		i32(service.shadow_vsm_msaa_samples),
		f32(service.sun_angular_radius),
		f32(service.sun_halo_size),
		f32(service.sun_halo_falloff),
	)
	kineffi.Kine_Filament_SetSunShadowOptionsAdvanced(
		filament,
		preset.shadow_size,
		preset.shadow_cascades,
		f32(service.shadow_distance),
		f32(service.shadow_near_hint),
		f32(service.shadow_far_hint),
		service.shadow_stable,
		service.shadow_lispsm,
		f32(service.shadow_cascade_split_lambda),
		service.shadow_contact_auto ? service.shadow_softness > 0.25 : service.shadow_contact_shadows,
		preset.contact_steps,
		f32(service.shadow_contact_distance),
		f32(service.shadow_bias),
		f32(service.shadow_normal_bias),
		f32(service.shadow_polygon_offset_constant),
		f32(service.shadow_polygon_offset_slope),
		f32(service.shadow_bulb_radius),
		f32(service.shadow_vsm_blur),
		service.shadow_vsm_elvsm,
	)


	when ODIN_OS != .JS {kineffi.Kine_Filament_SetAdaptiveShadowResolution(filament, preset.adaptive_shadows)}
	_ = kineffi.Kine_Filament_SetDynamicResolution(
		filament,
		preset.dynamic_resolution,
		preset.min_scale,
		1.0,
		2,
		0.0,
	)


	if bloom != nil {
		_ = kineffi.Kine_Filament_SetBloom(
			filament,
			bloom.enabled && !fast_viewport,
			f32(max(0.0, bloom.intensity)),
			i32(max(1.0, bloom.size)),
			6,
			bloom.threshold > 0,
			bloom.lens_flare,
		)
	} else if blur != nil {


		_ = kineffi.Kine_Filament_SetBloom(
			filament,
			blur.enabled && !fast_viewport,
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
			ao.enabled && !fast_viewport && service.quality_preset != .Low,
			f32(ao.radius),
			f32(ao.power),
			f32(ao.intensity),
			custom ? i32(ao.quality) : preset.ao_quality,
			i32(ao.ao_type),
		)
	} else {
		_ = kineffi.Kine_Filament_SetAmbientOcclusion(filament, false, 0.3, 1, 1, 2, 0)
	}

	if dof != nil {
		options := classes.DepthOfFieldEffect_Render_Options(dof)
		_ = kineffi.Kine_Filament_SetDepthOfField(
			filament,
			options[0] > 0 && !fast_viewport,
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
	if color != nil && color.enabled && !fast_viewport {
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


	ray_values: [5]f32
	rays_enabled :=
		sun_rays != nil &&
		sun_rays.enabled &&
		sun_rays.intensity > 0 &&
		profile.direction.y > 0 &&
		profile.intensity > 0 &&
		!fast_viewport &&
		service.quality_preset != .Low
	service.sun_rays_distance = 0
	service.sun_rays_animated = false
	if rays_enabled {
		ray_values = {
			f32(sun_rays.intensity),
			f32(sun_rays.spread),
			f32(sun_rays.dust_amount),
			f32(sun_rays.max_distance),
			f32(sun_rays.sample_count),
		}
		service.sun_rays_distance = ray_values[3]
		service.sun_rays_animated = ray_values[2] > 0
	}
	kineffi.Kine_Filament_SetAdvancedEffect(
		filament,
		15,
		rays_enabled,
		&ray_values[0],
		i32(len(ray_values)),
	)


	if antialiasing != nil && antialiasing.enabled && !fast_viewport {
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
		_ = kineffi.Kine_Filament_SetDithering(filament, dithering.enabled && !fast_viewport)
	} else {
		_ = kineffi.Kine_Filament_SetDithering(filament, false)
	}

	if custom && quality != nil && quality.enabled {
		_ = kineffi.Kine_Filament_SetRenderQuality(filament, i32(quality.quality))
	} else {
		_ = kineffi.Kine_Filament_SetRenderQuality(filament, preset.hdr_quality)
	}


	if reflections := effects.reflections;
	   reflections != nil && reflections.enabled && !fast_viewport && service.quality_preset != .Low {
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

	if vignette != nil && vignette.enabled && !fast_viewport {
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
	lighting_apply_advanced(service, filament, fast_viewport)
	if fast_viewport {
		kineffi.Kine_Filament_SetDynamicResolution(filament, true, 0.5, 0.5, 0, 0)
	}


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

	case "TimeOfDay":
		seconds := int(math.round(service.clock_time * 3600)) % 86400
		vm.PushString(
			L,
			fmt.tprintf("%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60),
		)

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

	case "QualityPreset":
		return enums.Push_Item_By_Value(
			L,
			enum_registry,
			"QualityPreset",
			i64(service.quality_preset),
		)

	case "DynamicResolution":
		vm.PushBoolean(L, service.dynamic_resolution)

	case "ResolutionScale":
		vm.PushNumber(L, service.resolution_min_scale)

	case "AdaptiveShadowResolution":
		vm.PushBoolean(L, service.adaptive_shadow_resolution)
	case "ShadowCascades":
		vm.PushNumber(L, f64(service.shadow_cascades))

	case "ShadowMapSize":
		vm.PushNumber(L, f64(service.shadow_map_size))

	case "ShadowType":
		return enums.Push_Item_By_Value(L, enum_registry, "ShadowType", i64(service.shadow_type))

	case "ShadowDistance":
		vm.PushNumber(L, service.shadow_distance)

	case "ShadowNearHint":
		vm.PushNumber(L, service.shadow_near_hint)

	case "ShadowFarHint":
		vm.PushNumber(L, service.shadow_far_hint)

	case "ShadowCascadeSplitLambda":
		vm.PushNumber(L, service.shadow_cascade_split_lambda)

	case "ShadowStable":
		vm.PushBoolean(L, service.shadow_stable)

	case "ShadowLiSPSM":
		vm.PushBoolean(L, service.shadow_lispsm)

	case "ShadowContactShadows":
		vm.PushBoolean(
			L,
			service.shadow_contact_auto ? service.shadow_softness > 0.25 : service.shadow_contact_shadows,
		)

	case "ShadowContactSteps":
		vm.PushNumber(L, f64(service.shadow_contact_steps))

	case "ShadowContactDistance":
		vm.PushNumber(L, service.shadow_contact_distance)

	case "ShadowBias":
		vm.PushNumber(L, service.shadow_bias)

	case "ShadowNormalBias":
		vm.PushNumber(L, service.shadow_normal_bias)

	case "ShadowPolygonOffsetConstant":
		vm.PushNumber(L, service.shadow_polygon_offset_constant)

	case "ShadowPolygonOffsetSlope":
		vm.PushNumber(L, service.shadow_polygon_offset_slope)

	case "ShadowBulbRadius":
		vm.PushNumber(L, service.shadow_bulb_radius)

	case "ShadowPenumbraScale":
		vm.PushNumber(L, service.shadow_penumbra_scale)

	case "ShadowPenumbraRatioScale":
		vm.PushNumber(L, service.shadow_penumbra_ratio_scale)

	case "ShadowVSMBlur":
		vm.PushNumber(L, service.shadow_vsm_blur)

	case "ShadowVSMHighPrecision":
		vm.PushBoolean(L, service.shadow_vsm_high_precision)

	case "ShadowVSMBleedReduction":
		vm.PushNumber(L, service.shadow_vsm_bleed_reduction)

	case "ShadowVSMELVSM":
		vm.PushBoolean(L, service.shadow_vsm_elvsm)

	case "ShadowPCSSMaxPenumbraRatio":
		vm.PushNumber(L, service.shadow_pcss_max_penumbra_ratio)

	case "ShadowPCSSMaxSearchRadius":
		vm.PushNumber(L, service.shadow_pcss_max_search_radius)

	case "ShadowVSMAnisotropy":
		vm.PushNumber(L, f64(service.shadow_vsm_anisotropy))

	case "ShadowVSMMipmapping":
		vm.PushBoolean(L, service.shadow_vsm_mipmapping)

	case "ShadowVSMMSAASamples":
		vm.PushNumber(L, f64(service.shadow_vsm_msaa_samples))

	case "SunAngularRadius":
		vm.PushNumber(L, service.sun_angular_radius)

	case "SunHaloSize":
		vm.PushNumber(L, service.sun_halo_size)

	case "SunHaloFalloff":
		vm.PushNumber(L, service.sun_halo_falloff)

	case "GetSunDirection", "GetMinutesAfterMidnight", "SetMinutesAfterMidnight":
		vm.PushUserdataMethod(L, key)

	case:
		return false
	}

	return true
}

lighting_render_state :: proc(object: ^classes.Object, key: string) -> ([3]f64, bool) {
	service := cast(^Lighting)object
	color: datatypes.Color3
	switch key {
	case "Ambient":
		color = service.ambient
	case "OutdoorAmbient":
		color = service.outdoor_ambient
	case "SunColor":
		color = service.sun_color
	case "ClockTime", "TimeOfDay":
		return {service.clock_time, 0, 0}, true
	case "Brightness":
		return {service.brightness, 0, 0}, true
	case "ExposureCompensation":
		return {service.exposure_compensation, 0, 0}, true
	case "GlobalShadows":
		return {f64(1 if service.global_shadows else 0), 0, 0}, true
	case "QualityPreset":
		return {f64(service.quality_preset), 0, 0}, true
	case "DynamicResolution":
		return {f64(1 if service.dynamic_resolution else 0), 0, 0}, true
	case "ResolutionScale":
		return {service.resolution_min_scale, 0, 0}, true
	case:
		return {}, false
	}
	return {f64(color.R), f64(color.G), f64(color.B)}, true
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

	case "TimeOfDay":
		time := vm.ArgString(L, value_index)
		if len(time) != 8 || time[2] != ':' || time[5] != ':' {
			_ = vm.RaiseError(L, "TimeOfDay must be in HH:MM:SS format")
			return true
		}
		hour, hour_ok := strconv.parse_int(time[:2], 10)
		minute, minute_ok := strconv.parse_int(time[3:5], 10)
		second, second_ok := strconv.parse_int(time[6:], 10)
		if !hour_ok ||
		   !minute_ok ||
		   !second_ok ||
		   hour < 0 ||
		   hour > 23 ||
		   minute < 0 ||
		   minute > 59 ||
		   second < 0 ||
		   second > 59 {
			_ = vm.RaiseError(L, "TimeOfDay must be in HH:MM:SS format")
			return true
		}
		service.clock_time = f64(hour * 3600 + minute * 60 + second) / 3600

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

	case "QualityPreset":
		if enum_registry == nil {return false}
		item := enums.Arg_Item(L, value_index, enum_registry, "QualityPreset")
		if item == nil {return true}
		service.quality_preset = enums.QualityPreset(item.value)

	case "DynamicResolution":
		service.dynamic_resolution = vm.ArgBoolean(L, value_index)

	case "ResolutionScale":
		service.resolution_min_scale = clamp(vm.ArgNumber(L, value_index), 0.1, 1.0)

	case "AdaptiveShadowResolution":
		service.adaptive_shadow_resolution = vm.ArgBoolean(L, value_index)
	case "ShadowCascades":
		service.shadow_cascades = clamp(i64(vm.ArgNumber(L, value_index)), 1, 4)

	case "ShadowMapSize":
		service.shadow_map_size = clamp(i64(vm.ArgNumber(L, value_index)), 256, 8192)

	case "ShadowType":
		if enum_registry == nil {return false}
		item := enums.Arg_Item(L, value_index, enum_registry, "ShadowType")
		if item == nil {return true}
		service.shadow_type = enums.ShadowType(item.value)

	case "ShadowDistance":
		service.shadow_distance = clamp(vm.ArgNumber(L, value_index), 0.0, 4096.0)

	case "ShadowNearHint":
		service.shadow_near_hint = clamp(vm.ArgNumber(L, value_index), 0.001, 4096.0)

	case "ShadowFarHint":
		service.shadow_far_hint = clamp(vm.ArgNumber(L, value_index), 0.01, 8192.0)

	case "ShadowCascadeSplitLambda":
		service.shadow_cascade_split_lambda = clamp(vm.ArgNumber(L, value_index), 0.0, 1.0)

	case "ShadowStable":
		service.shadow_stable = vm.ArgBoolean(L, value_index)

	case "ShadowLiSPSM":
		service.shadow_lispsm = vm.ArgBoolean(L, value_index)

	case "ShadowContactShadows":
		service.shadow_contact_shadows = vm.ArgBoolean(L, value_index)
		service.shadow_contact_auto = false

	case "ShadowContactSteps":
		service.shadow_contact_steps = clamp(i64(vm.ArgNumber(L, value_index)), 1, 64)

	case "ShadowContactDistance":
		service.shadow_contact_distance = clamp(vm.ArgNumber(L, value_index), 0.0, 100.0)

	case "ShadowBias":
		service.shadow_bias = clamp(vm.ArgNumber(L, value_index), 0.0, 1.0)

	case "ShadowNormalBias":
		service.shadow_normal_bias = clamp(vm.ArgNumber(L, value_index), 0.0, 16.0)

	case "ShadowPolygonOffsetConstant":
		service.shadow_polygon_offset_constant = clamp(vm.ArgNumber(L, value_index), 0.0, 16.0)

	case "ShadowPolygonOffsetSlope":
		service.shadow_polygon_offset_slope = clamp(vm.ArgNumber(L, value_index), 0.0, 16.0)

	case "ShadowBulbRadius":
		service.shadow_bulb_radius = clamp(vm.ArgNumber(L, value_index), -1.0, 100.0)

	case "ShadowPenumbraScale":
		service.shadow_penumbra_scale = clamp(vm.ArgNumber(L, value_index), 0.0, 20.0)

	case "ShadowPenumbraRatioScale":
		service.shadow_penumbra_ratio_scale = clamp(vm.ArgNumber(L, value_index), 0.0, 20.0)

	case "ShadowVSMBlur":
		service.shadow_vsm_blur = clamp(vm.ArgNumber(L, value_index), 0.0, 125.0)

	case "ShadowVSMHighPrecision":
		service.shadow_vsm_high_precision = vm.ArgBoolean(L, value_index)

	case "ShadowVSMBleedReduction":
		service.shadow_vsm_bleed_reduction = clamp(vm.ArgNumber(L, value_index), 0.0, 1.0)

	case "ShadowVSMELVSM":
		service.shadow_vsm_elvsm = vm.ArgBoolean(L, value_index)

	case "ShadowPCSSMaxPenumbraRatio":
		service.shadow_pcss_max_penumbra_ratio = lighting_shadow_clamp_number(
			L,
			value_index,
			0.01,
			100.0,
		)

	case "ShadowPCSSMaxSearchRadius":
		service.shadow_pcss_max_search_radius = lighting_shadow_clamp_number(
			L,
			value_index,
			0.001,
			100.0,
		)

	case "ShadowVSMAnisotropy":
		service.shadow_vsm_anisotropy = i64(lighting_shadow_clamp_number(L, value_index, 0, 4))

	case "ShadowVSMMipmapping":
		service.shadow_vsm_mipmapping = vm.ArgBoolean(L, value_index)

	case "ShadowVSMMSAASamples":
		samples := lighting_shadow_clamp_number(L, value_index, 1, 8)
		if samples != 1 && samples != 2 && samples != 4 && samples != 8 {
			_ = vm.RaiseError(L, "ShadowVSMMSAASamples must be 1, 2, 4 or 8")
			return true
		}
		service.shadow_vsm_msaa_samples = i64(samples)

	case "SunAngularRadius":
		service.sun_angular_radius = lighting_shadow_clamp_number(L, value_index, 0.0, 10.0)

	case "SunHaloSize":
		service.sun_halo_size = lighting_shadow_clamp_number(L, value_index, 0.0, 100.0)

	case "SunHaloFalloff":
		service.sun_halo_falloff = lighting_shadow_clamp_number(L, value_index, 0.0, 1000.0)

	case:
		return false
	}

	return true
}

lighting_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	service := cast(^Lighting)object
	switch method {
	case "GetMinutesAfterMidnight":
		vm.PushNumber(L, service.clock_time * 60)
		return 1, true
	case "SetMinutesAfterMidnight":
		minutes := vm.ArgNumber(L, 2)
		if math.is_nan(minutes) ||
		   math.is_inf(minutes) {return vm.RaiseError(L, "minutes must be finite"), true}
		service.clock_time = lighting_wrap_clock_time(minutes / 60)
		return 0, true
	case "GetSunDirection":
		datatypes.Push_Vector3(L, lighting_effective_sun_direction(service))
		return 1, true
	}
	return 0, false
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
		render_state = lighting_render_state,
		namecall = lighting_namecall,
		methods = []string {
			"GetSunDirection",
			"GetMinutesAfterMidnight",
			"SetMinutesAfterMidnight",
		},
		properties = []string {
			"Ambient",
			"Brightness",
			"ClockTime",
			"QualityPreset",
			"DynamicResolution",
			"ExposureCompensation",
			"GlobalShadows",
			"OutdoorAmbient",
			"ResolutionScale",
			"AdaptiveShadowResolution",
			"ShadowCascades",
			"ShadowMapSize",
			"ShadowSoftness",
			"ShadowType",
			"ShadowDistance",
			"ShadowNearHint",
			"ShadowFarHint",
			"ShadowCascadeSplitLambda",
			"ShadowStable",
			"ShadowLiSPSM",
			"ShadowContactShadows",
			"ShadowContactSteps",
			"ShadowContactDistance",
			"ShadowBias",
			"ShadowNormalBias",
			"ShadowPolygonOffsetConstant",
			"ShadowPolygonOffsetSlope",
			"ShadowBulbRadius",
			"ShadowPenumbraScale",
			"ShadowPenumbraRatioScale",
			"ShadowVSMBlur",
			"ShadowVSMHighPrecision",
			"ShadowVSMBleedReduction",
			"ShadowVSMELVSM",
			"ShadowPCSSMaxPenumbraRatio",
			"ShadowPCSSMaxSearchRadius",
			"ShadowVSMAnisotropy",
			"ShadowVSMMipmapping",
			"ShadowVSMMSAASamples",
			"SunAngularRadius",
			"SunHaloSize",
			"SunHaloFalloff",
			"SunColor",
		},
	)
}
