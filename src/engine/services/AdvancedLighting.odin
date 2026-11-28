
package services
import k "../bindings"
import classes "../classes"

lighting_advanced_fingerprint :: proc(service: ^Lighting) -> u64 {hash := u64(1469598103934665603)
	for object in service.children {switch classes.Get_Class_Name(object) {
		case "ReflectionProbeEffect":
			value := cast(^classes.ReflectionProbeEffect)object
			hash = lighting_hash_ptr(hash, rawptr(value))
			hash = lighting_hash_bool(hash, value.enabled)
			hash = lighting_hash_f64(hash, f64((value.auto_position ? 1 : 0)))
			hash = lighting_hash_f64(hash, f64(value.position.x))
			hash = lighting_hash_f64(hash, f64(value.position.y))
			hash = lighting_hash_f64(hash, f64(value.position.z))
			hash = lighting_hash_f64(hash, f64(value.resolution))
			hash = lighting_hash_f64(hash, f64(value.update_interval))
			hash = lighting_hash_f64(hash, f64(value.intensity))
			hash = lighting_hash_f64(hash, f64(value.near_plane))
			hash = lighting_hash_f64(hash, f64(value.max_distance))
		case "SSGIEffect":
			value := cast(^classes.SSGIEffect)object; hash = lighting_hash_ptr(hash, rawptr(value))
			hash = lighting_hash_bool(hash, value.enabled)
			hash = lighting_hash_f64(hash, f64(value.intensity))
			hash = lighting_hash_f64(hash, f64(value.radius))
			hash = lighting_hash_f64(hash, f64(value.bias))
			hash = lighting_hash_f64(hash, f64(value.sample_count))
			hash = lighting_hash_f64(hash, f64(value.max_distance))
			hash = lighting_hash_f64(hash, f64(value.color_bleeding))
			hash = lighting_hash_f64(hash, f64(value.visibility_steps))
		case "VolumetricFogEffect":
			v := cast(^classes.VolumetricFogEffect)object
			hash = lighting_hash_ptr(hash, rawptr(v))
			hash = lighting_hash_bool(hash, v.enabled)
			hash = lighting_hash_f64(hash, f64(v.density))
			hash = lighting_hash_f64(hash, f64(v.height))
			hash = lighting_hash_f64(hash, f64(v.height_falloff))
			hash = lighting_hash_f64(hash, f64(v.max_distance))
			hash = lighting_hash_f64(hash, f64(v.anisotropy))
			hash = lighting_hash_f64(hash, f64(v.scattering))
			hash = lighting_hash_f64(hash, f64(v.noise_strength))
			hash = lighting_hash_f64(hash, f64(v.noise_scale))
			hash = lighting_hash_f64(hash, f64(v.step_count))
			hash = lighting_hash_f64(hash, f64(v.color.R))
			hash = lighting_hash_f64(hash, f64(v.color.G))
			hash = lighting_hash_f64(hash, f64(v.color.B))
		case "ChromaticAberrationEffect":
			v := cast(^classes.ChromaticAberrationEffect)object
			hash = lighting_hash_ptr(hash, rawptr(v))
			hash = lighting_hash_bool(hash, v.enabled)
			hash = lighting_hash_f64(hash, f64(v.intensity))
		case "FilmGrainEffect":
			v := cast(^classes.FilmGrainEffect)object
			hash = lighting_hash_ptr(hash, rawptr(v))
			hash = lighting_hash_bool(hash, v.enabled)
			hash = lighting_hash_f64(hash, f64(v.intensity))
			hash = lighting_hash_f64(hash, f64(v.grain_size))
		case "FogEffect":
			value := cast(^classes.FogEffect)object; hash = lighting_hash_ptr(hash, rawptr(value))
			hash = lighting_hash_bool(hash, value.enabled)
			hash = lighting_hash_f64(hash, f64(value.density))
			hash = lighting_hash_f64(hash, f64(value.distance))
			hash = lighting_hash_f64(hash, f64(value.height))
			hash = lighting_hash_f64(hash, f64(value.height_falloff))
			hash = lighting_hash_f64(hash, f64(value.maximum_opacity))
			hash = lighting_hash_f64(hash, f64(value.color.R))
			hash = lighting_hash_f64(hash, f64(value.color.G))
			hash = lighting_hash_f64(hash, f64(value.color.B))
		case "ScreenSpaceConeTracingEffect":
			value := cast(^classes.ScreenSpaceConeTracingEffect)object
			hash = lighting_hash_ptr(hash, rawptr(value))
			hash = lighting_hash_bool(hash, value.enabled)
			hash = lighting_hash_f64(hash, f64(value.intensity))
			hash = lighting_hash_f64(hash, f64(value.shadow_distance))
			hash = lighting_hash_f64(hash, f64(value.contact_distance))
			hash = lighting_hash_f64(hash, f64(value.light_cone))
			hash = lighting_hash_f64(hash, f64(value.sample_count))
			hash = lighting_hash_f64(hash, f64(value.ray_count))
			hash = lighting_hash_f64(hash, f64(value.bias))
		case "TemporalAntiAliasingEffect":
			value := cast(^classes.TemporalAntiAliasingEffect)object
			hash = lighting_hash_ptr(hash, rawptr(value))
			hash = lighting_hash_bool(hash, value.enabled)
			hash = lighting_hash_f64(hash, f64(value.feedback))
			hash = lighting_hash_f64(hash, f64(value.filter_width))
			hash = lighting_hash_f64(hash, f64(value.sharpness))
			hash = lighting_hash_f64(hash, f64(value.lod_bias))
		case "DynamicResolutionEffect":
			value := cast(^classes.DynamicResolutionEffect)object
			hash = lighting_hash_ptr(hash, rawptr(value))
			hash = lighting_hash_bool(hash, value.enabled)
			hash = lighting_hash_f64(hash, f64(value.min_scale))
			hash = lighting_hash_f64(hash, f64(value.max_scale))
			hash = lighting_hash_f64(hash, f64(value.sharpness))
			hash = lighting_hash_f64(hash, f64(value.quality))
		case "ToneMappingEffect":
			value := cast(^classes.ToneMappingEffect)object
			hash = lighting_hash_ptr(hash, rawptr(value))
			hash = lighting_hash_bool(hash, value.enabled)
			hash = lighting_hash_f64(hash, f64(value.mode))
			hash = lighting_hash_f64(hash, f64(value.exposure_compensation))
			hash = lighting_hash_f64(hash, f64(value.temperature))
			hash = lighting_hash_f64(hash, f64(value.tint))
		}}
	for definition in classes.Scene_Lighting_Effects {
		value := lighting_scene_effect(service, definition.class)
		if value == nil {continue}
		hash = lighting_hash_ptr(hash, rawptr(value))
		hash = lighting_hash_bool(hash, value.enabled)
		for parameter in value.values {hash = lighting_hash_f64(hash, f64(parameter))}
	}
	return hash
}

lighting_scene_effect :: proc(
	service: ^Lighting,
	class: ^classes.Class_Info,
) -> ^classes.Scene_Lighting_Effect {
	result: ^classes.Scene_Lighting_Effect
	for object in service.children {
		if object != nil && !object.destroyed && object.class == class {
			result = cast(^classes.Scene_Lighting_Effect)object
		}
	}
	return result
}
lighting_apply_advanced :: proc(
	service: ^Lighting,
	ctx: ^k.KineFilamentContext,
	fast_viewport: bool,
) {
	{value: ^classes.ReflectionProbeEffect
		for object in service.children {if classes.Get_Class_Name(object) == "ReflectionProbeEffect" {value = cast(^classes.ReflectionProbeEffect)object}}
		fallback := classes.ReflectionProbeEffect_Init()
		fallback.enabled = false
		if value == nil {value = &fallback}
		values := [9]f32 {
			f32((value.auto_position ? 1 : 0)),
			f32(value.position.x),
			f32(value.position.y),
			f32(value.position.z),
			f32(value.resolution),
			f32(value.update_interval),
			f32(value.intensity),
			f32(value.near_plane),
			f32(value.max_distance),
		}
		k.Kine_Filament_SetAdvancedEffect(
			ctx,
			0,
			value.enabled && !fast_viewport && service.quality_preset != .Low,
			&values[0],
			i32(len(values)),
		)
	}
	{value: ^classes.SSGIEffect
		for object in service.children {if classes.Get_Class_Name(object) == "SSGIEffect" {value = cast(^classes.SSGIEffect)object}}
		fallback := classes.SSGIEffect_Init()
		fallback.enabled = false
		if value == nil {value = &fallback}
		values := [7]f32 {
			f32(value.intensity),
			f32(value.radius),
			f32(value.bias),
			f32(value.sample_count),
			f32(value.max_distance),
			f32(value.color_bleeding),
			f32(value.visibility_steps),
		}
		k.Kine_Filament_SetAdvancedEffect(
			ctx,
			1,
			value.enabled && !fast_viewport,
			&values[0],
			i32(len(values)),
		)
	}
	{value: ^classes.FogEffect
		for object in service.children {if classes.Get_Class_Name(object) == "FogEffect" {value = cast(^classes.FogEffect)object}}
		fallback := classes.FogEffect_Init()
		fallback.enabled = false
		if value == nil {value = &fallback}
		values := [8]f32 {
			f32(value.density),
			f32(value.distance),
			f32(value.height),
			f32(value.height_falloff),
			f32(value.maximum_opacity),
			f32(value.color.R),
			f32(value.color.G),
			f32(value.color.B),
		}
		k.Kine_Filament_SetAdvancedEffect(
			ctx,
			2,
			value.enabled && !fast_viewport,
			&values[0],
			i32(len(values)),
		)
	}
	{value: ^classes.ScreenSpaceConeTracingEffect
		for object in service.children {if classes.Get_Class_Name(object) == "ScreenSpaceConeTracingEffect" {value = cast(^classes.ScreenSpaceConeTracingEffect)object}}
		fallback := classes.ScreenSpaceConeTracingEffect_Init()
		fallback.enabled = false
		if value == nil {value = &fallback}
		values := [7]f32 {
			f32(value.intensity),
			f32(value.shadow_distance),
			f32(value.contact_distance),
			f32(value.light_cone),
			f32(value.sample_count),
			f32(value.ray_count),
			f32(value.bias),
		}
		k.Kine_Filament_SetAdvancedEffect(
			ctx,
			3,
			value.enabled && !fast_viewport,
			&values[0],
			i32(len(values)),
		)
	}
	{value: ^classes.TemporalAntiAliasingEffect
		for object in service.children {if classes.Get_Class_Name(object) == "TemporalAntiAliasingEffect" {value = cast(^classes.TemporalAntiAliasingEffect)object}}
		fallback := classes.TemporalAntiAliasingEffect_Init()
		fallback.enabled = false
		if value == nil {value = &fallback}
		values := [4]f32 {
			f32(value.feedback),
			f32(value.filter_width),
			f32(value.sharpness),
			f32(value.lod_bias),
		}
		k.Kine_Filament_SetAdvancedEffect(
			ctx,
			4,
			value.enabled && !fast_viewport,
			&values[0],
			i32(len(values)),
		)
	}
	{value: ^classes.DynamicResolutionEffect
		for object in service.children {if classes.Get_Class_Name(object) == "DynamicResolutionEffect" {value = cast(^classes.DynamicResolutionEffect)object}}
		fallback := classes.DynamicResolutionEffect_Init()
		fallback.enabled = false
		if value == nil {value = &fallback}
		values := [4]f32 {
			f32(value.min_scale),
			f32(value.max_scale),
			f32(value.sharpness),
			f32(value.quality),
		}
		k.Kine_Filament_SetAdvancedEffect(
			ctx,
			5,
			value.enabled && !fast_viewport && service.quality_preset == .Custom,
			&values[0],
			i32(len(values)),
		)
	}
	{value: ^classes.ToneMappingEffect
		for object in service.children {if classes.Get_Class_Name(object) == "ToneMappingEffect" {value = cast(^classes.ToneMappingEffect)object}}
		fallback := classes.ToneMappingEffect_Init()
		fallback.enabled = false
		if value == nil {value = &fallback}
		values := [4]f32 {
			f32(value.mode),
			f32(value.exposure_compensation),
			f32(value.temperature),
			f32(value.tint),
		}
		k.Kine_Filament_SetAdvancedEffect(
			ctx,
			6,
			value.enabled && !fast_viewport,
			&values[0],
			i32(len(values)),
		)
	}

	{
		fallback := classes.VolumetricFogEffect_Init(); fallback.enabled = false
		v := &fallback
		for object in service.children {if classes.Get_Class_Name(object) == "VolumetricFogEffect" {v = cast(^classes.VolumetricFogEffect)object}}
		values := [12]f32 {
			f32(v.density),
			f32(v.height),
			f32(v.height_falloff),
			f32(v.max_distance),
			f32(v.anisotropy),
			f32(v.scattering),
			f32(v.noise_strength),
			f32(v.noise_scale),
			f32(v.step_count),
			f32(v.color.R),
			f32(v.color.G),
			f32(v.color.B),
		}
		k.Kine_Filament_SetAdvancedEffect(
			ctx,
			7,
			v.enabled && !fast_viewport,
			&values[0],
			i32(len(values)),
		)
	}

	{
		fallback := classes.ChromaticAberrationEffect_Init(); fallback.enabled = false
		v := &fallback
		for object in service.children {if classes.Get_Class_Name(object) == "ChromaticAberrationEffect" {v = cast(^classes.ChromaticAberrationEffect)object}}
		values := [1]f32{f32(v.intensity)}
		k.Kine_Filament_SetAdvancedEffect(
			ctx,
			8,
			v.enabled && !fast_viewport,
			&values[0],
			i32(len(values)),
		)
	}

	{
		fallback := classes.FilmGrainEffect_Init(); fallback.enabled = false
		v := &fallback
		for object in service.children {if classes.Get_Class_Name(object) == "FilmGrainEffect" {v = cast(^classes.FilmGrainEffect)object}}
		values := [2]f32{f32(v.intensity), f32(v.grain_size)}
		k.Kine_Filament_SetAdvancedEffect(
			ctx,
			9,
			v.enabled && !fast_viewport,
			&values[0],
			i32(len(values)),
		)
	}

	for definition in classes.Scene_Lighting_Effects {
		values := definition.defaults
		enabled := false
		if value := lighting_scene_effect(service, definition.class); value != nil {
			values = value.values
			enabled =
				value.enabled &&
				(!fast_viewport || definition.class == &classes.SunLightEffect_Class)
		}
		k.Kine_Filament_SetAdvancedEffect(
			ctx,
			definition.renderer_id,
			enabled,
			&values[0],
			definition.parameter_count,
		)
	}
}
