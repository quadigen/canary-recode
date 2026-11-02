
package services
import k "../bindings"
import classes "../classes"

lighting_advanced_fingerprint :: proc(service: ^Lighting) -> u64 {hash := u64(1469598103934665603)
	for object in service.children {switch
		classes.Get_Class_Name(object) {
		case "ReflectionProbeEffect":
			value := cast(^classes.ReflectionProbeEffect)object; hash = lighting_hash_ptr(
				hash,
				rawptr(value),
			)
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
			value := cast(^classes.ScreenSpaceConeTracingEffect)object; hash = lighting_hash_ptr(
				hash,
				rawptr(value),
			)
			hash = lighting_hash_bool(hash, value.enabled)
			hash = lighting_hash_f64(hash, f64(value.intensity))
			hash = lighting_hash_f64(hash, f64(value.shadow_distance))
			hash = lighting_hash_f64(hash, f64(value.contact_distance))
			hash = lighting_hash_f64(hash, f64(value.light_cone))
			hash = lighting_hash_f64(hash, f64(value.sample_count))
			hash = lighting_hash_f64(hash, f64(value.ray_count))
			hash = lighting_hash_f64(hash, f64(value.bias))
		case "TemporalAntiAliasingEffect":
			value := cast(^classes.TemporalAntiAliasingEffect)object; hash = lighting_hash_ptr(
				hash,
				rawptr(value),
			)
			hash = lighting_hash_bool(hash, value.enabled)
			hash = lighting_hash_f64(hash, f64(value.feedback))
			hash = lighting_hash_f64(hash, f64(value.filter_width))
			hash = lighting_hash_f64(hash, f64(value.sharpness))
			hash = lighting_hash_f64(hash, f64(value.lod_bias))
		case "DynamicResolutionEffect":
			value := cast(^classes.DynamicResolutionEffect)object; hash = lighting_hash_ptr(
				hash,
				rawptr(value),
			)
			hash = lighting_hash_bool(hash, value.enabled)
			hash = lighting_hash_f64(hash, f64(value.min_scale))
			hash = lighting_hash_f64(hash, f64(value.max_scale))
			hash = lighting_hash_f64(hash, f64(value.sharpness))
			hash = lighting_hash_f64(hash, f64(value.quality))
		case "ToneMappingEffect":
			value := cast(^classes.ToneMappingEffect)object; hash = lighting_hash_ptr(
				hash,
				rawptr(value),
			)
			hash = lighting_hash_bool(hash, value.enabled)
			hash = lighting_hash_f64(hash, f64(value.mode))
			hash = lighting_hash_f64(hash, f64(value.exposure_compensation))
			hash = lighting_hash_f64(hash, f64(value.temperature))
			hash = lighting_hash_f64(hash, f64(value.tint))
		}}
	return hash}
lighting_apply_advanced :: proc(service: ^Lighting, ctx: ^k.KineFilamentContext) {
	{value: ^classes.ReflectionProbeEffect; for object in service.children {if classes.Get_Class_Name(
				   object,
			   ) ==
			   "ReflectionProbeEffect" {value = cast(^classes.ReflectionProbeEffect)object}}
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
		k.Kine_Filament_SetAdvancedEffect(ctx, 0, value.enabled, &values[0], i32(len(values)))
	}
	{value: ^classes.SSGIEffect; for object in service.children {if classes.Get_Class_Name(
				   object,
			   ) ==
			   "SSGIEffect" {value = cast(^classes.SSGIEffect)object}}
		fallback := classes.SSGIEffect_Init()
		fallback.enabled = false
		if value == nil {value = &fallback}
		values := [5]f32 {
			f32(value.intensity),
			f32(value.radius),
			f32(value.bias),
			f32(value.sample_count),
			f32(value.max_distance),
		}
		k.Kine_Filament_SetAdvancedEffect(ctx, 1, value.enabled, &values[0], i32(len(values)))
	}
	{value: ^classes.FogEffect; for object in service.children {if classes.Get_Class_Name(
				   object,
			   ) ==
			   "FogEffect" {value = cast(^classes.FogEffect)object}}
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
		k.Kine_Filament_SetAdvancedEffect(ctx, 2, value.enabled, &values[0], i32(len(values)))
	}
	{value: ^classes.ScreenSpaceConeTracingEffect; for object in service.children {if classes.Get_Class_Name(
				   object,
			   ) ==
			   "ScreenSpaceConeTracingEffect" {value = cast(^classes.ScreenSpaceConeTracingEffect)object}}
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
		k.Kine_Filament_SetAdvancedEffect(ctx, 3, value.enabled, &values[0], i32(len(values)))
	}
	{value: ^classes.TemporalAntiAliasingEffect; for object in service.children {if classes.Get_Class_Name(
				   object,
			   ) ==
			   "TemporalAntiAliasingEffect" {value = cast(^classes.TemporalAntiAliasingEffect)object}}
		fallback := classes.TemporalAntiAliasingEffect_Init()
		fallback.enabled = false
		if value == nil {value = &fallback}
		values := [4]f32 {
			f32(value.feedback),
			f32(value.filter_width),
			f32(value.sharpness),
			f32(value.lod_bias),
		}
		k.Kine_Filament_SetAdvancedEffect(ctx, 4, value.enabled, &values[0], i32(len(values)))
	}
	{value: ^classes.DynamicResolutionEffect; for object in service.children {if classes.Get_Class_Name(
				   object,
			   ) ==
			   "DynamicResolutionEffect" {value = cast(^classes.DynamicResolutionEffect)object}}
		fallback := classes.DynamicResolutionEffect_Init()
		fallback.enabled = false
		if value == nil {value = &fallback}
		values := [4]f32 {
			f32(value.min_scale),
			f32(value.max_scale),
			f32(value.sharpness),
			f32(value.quality),
		}
		k.Kine_Filament_SetAdvancedEffect(ctx, 5, value.enabled, &values[0], i32(len(values)))
	}
	{value: ^classes.ToneMappingEffect; for object in service.children {if classes.Get_Class_Name(
				   object,
			   ) ==
			   "ToneMappingEffect" {value = cast(^classes.ToneMappingEffect)object}}
		fallback := classes.ToneMappingEffect_Init()
		fallback.enabled = false
		if value == nil {value = &fallback}
		values := [4]f32 {
			f32(value.mode),
			f32(value.exposure_compensation),
			f32(value.temperature),
			f32(value.tint),
		}
		k.Kine_Filament_SetAdvancedEffect(ctx, 6, value.enabled, &values[0], i32(len(values)))
	}
}
