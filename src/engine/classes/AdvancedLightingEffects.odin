
package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

ReflectionProbeEffect_Class := Class_Info {
	name   = "ReflectionProbeEffect",
	parent = &LightingEffect_Class,
}
ReflectionProbeEffect :: struct {
	using effect:    LightingEffect,
	auto_position:   bool,
	position:        datatypes.Vector3,
	resolution:      f64,
	update_interval: f64,
	intensity:       f64,
	near_plane:      f64,
	max_distance:    f64,
}
ReflectionProbeEffect_Init :: proc() -> ReflectionProbeEffect {return ReflectionProbeEffect {
		effect = lighting_effect_init(&ReflectionProbeEffect_Class, "ReflectionProbeEffect"),
		auto_position = true,
		position = {},
		resolution = 128,
		update_interval = 1,
		intensity = 1,
		near_plane = 0.1,
		max_distance = 1000,
	}}
ReflectionProbeEffect_construct :: proc(
	renderer: ^Renderer_Object,
	data_model: rawptr,
) -> ^Object {value := new(ReflectionProbeEffect); value^ = ReflectionProbeEffect_Init(); return(
		&value.object \
	)}

SSGIEffect_Class := Class_Info {
	name   = "SSGIEffect",
	parent = &LightingEffect_Class,
}
SSGIEffect :: struct {
	using effect: LightingEffect,
	intensity:    f64,
	radius:       f64,
	bias:         f64,
	sample_count: f64,
	max_distance: f64,
}
SSGIEffect_Init :: proc() -> SSGIEffect {return SSGIEffect {
		effect = lighting_effect_init(&SSGIEffect_Class, "SSGIEffect"),
		intensity = 1,
		radius = 3,
		bias = 0.05,
		sample_count = 16,
		max_distance = 100,
	}}
SSGIEffect_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {value :=
		new(SSGIEffect)
	value^ = SSGIEffect_Init()
	return &value.object}

FogEffect_Class := Class_Info {
		name   = "FogEffect",
		parent = &LightingEffect_Class,
	}
FogEffect :: struct {
	using effect:    LightingEffect,
	density:         f64,
	distance:        f64,
	height:          f64,
	height_falloff:  f64,
	maximum_opacity: f64,
	color:           datatypes.Color3,
}
FogEffect_Init :: proc() -> FogEffect {return FogEffect {
		effect = lighting_effect_init(&FogEffect_Class, "FogEffect"),
		density = 0.01,
		distance = 0,
		height = 0,
		height_falloff = 0.1,
		maximum_opacity = 1,
		color = {0.7, 0.8, 0.9},
	}}
FogEffect_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {value :=
		new(FogEffect)
	value^ = FogEffect_Init()
	return &value.object}

ScreenSpaceConeTracingEffect_Class := Class_Info {
		name   = "ScreenSpaceConeTracingEffect",
		parent = &LightingEffect_Class,
	}
ScreenSpaceConeTracingEffect :: struct {
	using effect:     LightingEffect,
	intensity:        f64,
	shadow_distance:  f64,
	contact_distance: f64,
	light_cone:       f64,
	sample_count:     f64,
	ray_count:        f64,
	bias:             f64,
}
ScreenSpaceConeTracingEffect_Init :: proc(
) -> ScreenSpaceConeTracingEffect {return ScreenSpaceConeTracingEffect {
		effect = lighting_effect_init(
			&ScreenSpaceConeTracingEffect_Class,
			"ScreenSpaceConeTracingEffect",
		),
		intensity = 0.8,
		shadow_distance = 3,
		contact_distance = 1,
		light_cone = 1,
		sample_count = 8,
		ray_count = 2,
		bias = 0.01,
	}}
ScreenSpaceConeTracingEffect_construct :: proc(
	renderer: ^Renderer_Object,
	data_model: rawptr,
) -> ^Object {value := new(ScreenSpaceConeTracingEffect); value^ =
		ScreenSpaceConeTracingEffect_Init()
	return &value.object}

TemporalAntiAliasingEffect_Class := Class_Info {
		name   = "TemporalAntiAliasingEffect",
		parent = &LightingEffect_Class,
	}
TemporalAntiAliasingEffect :: struct {
	using effect: LightingEffect,
	feedback:     f64,
	filter_width: f64,
	sharpness:    f64,
	lod_bias:     f64,
}
TemporalAntiAliasingEffect_Init :: proc(
) -> TemporalAntiAliasingEffect {return TemporalAntiAliasingEffect {
		effect = lighting_effect_init(
			&TemporalAntiAliasingEffect_Class,
			"TemporalAntiAliasingEffect",
		),
		feedback = 0.12,
		filter_width = 1,
		sharpness = 0.2,
		lod_bias = -1,
	}}
TemporalAntiAliasingEffect_construct :: proc(
	renderer: ^Renderer_Object,
	data_model: rawptr,
) -> ^Object {value := new(TemporalAntiAliasingEffect); value^ = TemporalAntiAliasingEffect_Init()
	return &value.object}

DynamicResolutionEffect_Class := Class_Info {
		name   = "DynamicResolutionEffect",
		parent = &LightingEffect_Class,
	}
DynamicResolutionEffect :: struct {
	using effect: LightingEffect,
	min_scale:    f64,
	max_scale:    f64,
	sharpness:    f64,
	quality:      f64,
}
DynamicResolutionEffect_Init :: proc(
) -> DynamicResolutionEffect {return DynamicResolutionEffect {
		effect = lighting_effect_init(&DynamicResolutionEffect_Class, "DynamicResolutionEffect"),
		min_scale = 0.75,
		max_scale = 1,
		sharpness = 0.5,
		quality = 2,
	}}
DynamicResolutionEffect_construct :: proc(
	renderer: ^Renderer_Object,
	data_model: rawptr,
) -> ^Object {value := new(DynamicResolutionEffect); value^ = DynamicResolutionEffect_Init()
	return &value.object}

ToneMappingEffect_Class := Class_Info {
		name   = "ToneMappingEffect",
		parent = &LightingEffect_Class,
	}
ToneMappingEffect :: struct {
	using effect:          LightingEffect,
	mode:                  f64,
	exposure_compensation: f64,
	temperature:           f64,
	tint:                  f64,
}
ToneMappingEffect_Init :: proc() -> ToneMappingEffect {return ToneMappingEffect {
		effect = lighting_effect_init(&ToneMappingEffect_Class, "ToneMappingEffect"),
		mode = 2,
		exposure_compensation = 0,
		temperature = 0,
		tint = 0,
	}}
ToneMappingEffect_construct :: proc(
	renderer: ^Renderer_Object,
	data_model: rawptr,
) -> ^Object {value := new(ToneMappingEffect); value^ = ToneMappingEffect_Init(); return(
		&value.object \
	)}

advanced_lighting_get :: proc(
	L: ^vm.State,
	object: ^Object,
	dr: ^datatypes.Registry,
	er: ^enums.Registry,
	key: string,
) -> bool {
	if key ==
	   "Enabled" {value := cast(^LightingEffect)object; vm.PushBoolean(L, value.enabled); return true}
	switch Get_Class_Name(object) {
	case "ReflectionProbeEffect":
		value := cast(^ReflectionProbeEffect)object
		switch key {
		case "AutoPosition":
			vm.PushBoolean(L, value.auto_position)
		case "Position":
			datatypes.Push_Vector3(L, value.position)
		case "Resolution":
			vm.PushNumber(L, value.resolution)
		case "UpdateInterval":
			vm.PushNumber(L, value.update_interval)
		case "Intensity":
			vm.PushNumber(L, value.intensity)
		case "NearPlane":
			vm.PushNumber(L, value.near_plane)
		case "MaxDistance":
			vm.PushNumber(L, value.max_distance)
		case:
			return false
		}
	case "SSGIEffect":
		value := cast(^SSGIEffect)object
		switch key {
		case "Intensity":
			vm.PushNumber(L, value.intensity)
		case "Radius":
			vm.PushNumber(L, value.radius)
		case "Bias":
			vm.PushNumber(L, value.bias)
		case "SampleCount":
			vm.PushNumber(L, value.sample_count)
		case "MaxDistance":
			vm.PushNumber(L, value.max_distance)
		case:
			return false
		}
	case "FogEffect":
		value := cast(^FogEffect)object
		switch key {
		case "Density":
			vm.PushNumber(L, value.density)
		case "Distance":
			vm.PushNumber(L, value.distance)
		case "Height":
			vm.PushNumber(L, value.height)
		case "HeightFalloff":
			vm.PushNumber(L, value.height_falloff)
		case "MaximumOpacity":
			vm.PushNumber(L, value.maximum_opacity)
		case "Color":
			datatypes.Push_Color3(L, dr, value.color)
		case:
			return false
		}
	case "ScreenSpaceConeTracingEffect":
		value := cast(^ScreenSpaceConeTracingEffect)object
		switch key {
		case "Intensity":
			vm.PushNumber(L, value.intensity)
		case "ShadowDistance":
			vm.PushNumber(L, value.shadow_distance)
		case "ContactDistance":
			vm.PushNumber(L, value.contact_distance)
		case "LightCone":
			vm.PushNumber(L, value.light_cone)
		case "SampleCount":
			vm.PushNumber(L, value.sample_count)
		case "RayCount":
			vm.PushNumber(L, value.ray_count)
		case "Bias":
			vm.PushNumber(L, value.bias)
		case:
			return false
		}
	case "TemporalAntiAliasingEffect":
		value := cast(^TemporalAntiAliasingEffect)object
		switch key {
		case "Feedback":
			vm.PushNumber(L, value.feedback)
		case "FilterWidth":
			vm.PushNumber(L, value.filter_width)
		case "Sharpness":
			vm.PushNumber(L, value.sharpness)
		case "LodBias":
			vm.PushNumber(L, value.lod_bias)
		case:
			return false
		}
	case "DynamicResolutionEffect":
		value := cast(^DynamicResolutionEffect)object
		switch key {
		case "MinScale":
			vm.PushNumber(L, value.min_scale)
		case "MaxScale":
			vm.PushNumber(L, value.max_scale)
		case "Sharpness":
			vm.PushNumber(L, value.sharpness)
		case "Quality":
			vm.PushNumber(L, value.quality)
		case:
			return false
		}
	case "ToneMappingEffect":
		value := cast(^ToneMappingEffect)object
		switch key {
		case "Mode":
			vm.PushNumber(L, value.mode)
		case "ExposureCompensation":
			vm.PushNumber(L, value.exposure_compensation)
		case "Temperature":
			vm.PushNumber(L, value.temperature)
		case "Tint":
			vm.PushNumber(L, value.tint)
		case:
			return false
		}
	case:
		return false
	}
	return true
}
advanced_lighting_set :: proc(
	L: ^vm.State,
	object: ^Object,
	dr: ^datatypes.Registry,
	er: ^enums.Registry,
	key: string,
	index: int,
) -> bool {
	if key ==
	   "Enabled" {value := cast(^LightingEffect)object; value.enabled = vm.ArgBoolean(L, index); return true}
	switch Get_Class_Name(object) {
	case "ReflectionProbeEffect":
		value := cast(^ReflectionProbeEffect)object
		switch key {
		case "AutoPosition":
			value.auto_position = vm.ArgBoolean(L, index)
		case "Position":
			value.position = datatypes.Arg_Vector3(L, index)
		case "Resolution":
			value.resolution = clamp(vm.ArgNumber(L, index), 32, 512)
		case "UpdateInterval":
			value.update_interval = clamp(vm.ArgNumber(L, index), 0.1, 60)
		case "Intensity":
			value.intensity = clamp(vm.ArgNumber(L, index), 0, 10)
		case "NearPlane":
			value.near_plane = clamp(vm.ArgNumber(L, index), 0.01, 10)
		case "MaxDistance":
			value.max_distance = clamp(vm.ArgNumber(L, index), 1, 10000)
		case:
			return false
		}
	case "SSGIEffect":
		value := cast(^SSGIEffect)object
		switch key {
		case "Intensity":
			value.intensity = clamp(vm.ArgNumber(L, index), 0, 5)
		case "Radius":
			value.radius = clamp(vm.ArgNumber(L, index), 0.1, 50)
		case "Bias":
			value.bias = clamp(vm.ArgNumber(L, index), 0.001, 1)
		case "SampleCount":
			value.sample_count = clamp(vm.ArgNumber(L, index), 4, 64)
		case "MaxDistance":
			value.max_distance = clamp(vm.ArgNumber(L, index), 1, 1000)
		case:
			return false
		}
	case "FogEffect":
		value := cast(^FogEffect)object
		switch key {
		case "Density":
			value.density = clamp(vm.ArgNumber(L, index), 0, 1)
		case "Distance":
			value.distance = clamp(vm.ArgNumber(L, index), 0, 10000)
		case "Height":
			value.height = clamp(vm.ArgNumber(L, index), -10000, 10000)
		case "HeightFalloff":
			value.height_falloff = clamp(vm.ArgNumber(L, index), 0, 10)
		case "MaximumOpacity":
			value.maximum_opacity = clamp(vm.ArgNumber(L, index), 0, 1)
		case "Color":
			value.color = datatypes.Arg_Color3(L, index, dr)
		case:
			return false
		}
	case "ScreenSpaceConeTracingEffect":
		value := cast(^ScreenSpaceConeTracingEffect)object
		switch key {
		case "Intensity":
			value.intensity = clamp(vm.ArgNumber(L, index), 0, 5)
		case "ShadowDistance":
			value.shadow_distance = clamp(vm.ArgNumber(L, index), 0, 100)
		case "ContactDistance":
			value.contact_distance = clamp(vm.ArgNumber(L, index), 0, 100)
		case "LightCone":
			value.light_cone = clamp(vm.ArgNumber(L, index), 0, 1.57)
		case "SampleCount":
			value.sample_count = clamp(vm.ArgNumber(L, index), 1, 255)
		case "RayCount":
			value.ray_count = clamp(vm.ArgNumber(L, index), 1, 32)
		case "Bias":
			value.bias = clamp(vm.ArgNumber(L, index), 0, 1)
		case:
			return false
		}
	case "TemporalAntiAliasingEffect":
		value := cast(^TemporalAntiAliasingEffect)object
		switch key {
		case "Feedback":
			value.feedback = clamp(vm.ArgNumber(L, index), 0, 1)
		case "FilterWidth":
			value.filter_width = clamp(vm.ArgNumber(L, index), 0.1, 2)
		case "Sharpness":
			value.sharpness = clamp(vm.ArgNumber(L, index), 0, 1)
		case "LodBias":
			value.lod_bias = clamp(vm.ArgNumber(L, index), -4, 0)
		case:
			return false
		}
	case "DynamicResolutionEffect":
		value := cast(^DynamicResolutionEffect)object
		switch key {
		case "MinScale":
			value.min_scale = clamp(vm.ArgNumber(L, index), 0.25, 1)
		case "MaxScale":
			value.max_scale = clamp(vm.ArgNumber(L, index), 0.25, 2)
		case "Sharpness":
			value.sharpness = clamp(vm.ArgNumber(L, index), 0, 1)
		case "Quality":
			value.quality = clamp(vm.ArgNumber(L, index), 0, 3)
		case:
			return false
		}
	case "ToneMappingEffect":
		value := cast(^ToneMappingEffect)object
		switch key {
		case "Mode":
			value.mode = clamp(vm.ArgNumber(L, index), 0, 3)
		case "ExposureCompensation":
			value.exposure_compensation = clamp(vm.ArgNumber(L, index), -10, 10)
		case "Temperature":
			value.temperature = clamp(vm.ArgNumber(L, index), -1, 1)
		case "Tint":
			value.tint = clamp(vm.ArgNumber(L, index), -1, 1)
		case:
			return false
		}
	case:
		return false
	}
	return true
}
advanced_lighting_clone :: proc(source, destination: ^Object) {switch Get_Class_Name(source) {
	case "ReflectionProbeEffect":
		src, dst := cast(^ReflectionProbeEffect)source, cast(^ReflectionProbeEffect)destination
		saved := dst.object
		dst^ = src^
		dst.object = saved
	case "SSGIEffect":
		src, dst := cast(^SSGIEffect)source, cast(^SSGIEffect)destination; saved := dst.object
		dst^ = src^
		dst.object = saved
	case "FogEffect":
		src, dst := cast(^FogEffect)source, cast(^FogEffect)destination; saved := dst.object
		dst^ = src^
		dst.object = saved
	case "ScreenSpaceConeTracingEffect":
		src, dst :=
			cast(^ScreenSpaceConeTracingEffect)source,
			cast(^ScreenSpaceConeTracingEffect)destination
		saved := dst.object
		dst^ = src^
		dst.object = saved
	case "TemporalAntiAliasingEffect":
		src, dst :=
			cast(^TemporalAntiAliasingEffect)source, cast(^TemporalAntiAliasingEffect)destination
		saved := dst.object
		dst^ = src^
		dst.object = saved
	case "DynamicResolutionEffect":
		src, dst := cast(^DynamicResolutionEffect)source, cast(^DynamicResolutionEffect)destination
		saved := dst.object
		dst^ = src^
		dst.object = saved
	case "ToneMappingEffect":
		src, dst := cast(^ToneMappingEffect)source, cast(^ToneMappingEffect)destination
		saved := dst.object
		dst^ = src^
		dst.object = saved
	}}
Register_Advanced_Lighting_Effects :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&ReflectionProbeEffect_Class,
		ReflectionProbeEffect_construct,
		lighting_effect_destroy,
		get = advanced_lighting_get,
		set = advanced_lighting_set,
		clone = advanced_lighting_clone,
		properties = []string {
			"Enabled",
			"AutoPosition",
			"Position",
			"Resolution",
			"UpdateInterval",
			"Intensity",
			"NearPlane",
			"MaxDistance",
		},
	)
	Register_Class(
		registry,
		&SSGIEffect_Class,
		SSGIEffect_construct,
		lighting_effect_destroy,
		get = advanced_lighting_get,
		set = advanced_lighting_set,
		clone = advanced_lighting_clone,
		properties = []string {
			"Enabled",
			"Intensity",
			"Radius",
			"Bias",
			"SampleCount",
			"MaxDistance",
		},
	)
	Register_Class(
		registry,
		&FogEffect_Class,
		FogEffect_construct,
		lighting_effect_destroy,
		get = advanced_lighting_get,
		set = advanced_lighting_set,
		clone = advanced_lighting_clone,
		properties = []string {
			"Enabled",
			"Density",
			"Distance",
			"Height",
			"HeightFalloff",
			"MaximumOpacity",
			"Color",
		},
	)
	Register_Class(
		registry,
		&ScreenSpaceConeTracingEffect_Class,
		ScreenSpaceConeTracingEffect_construct,
		lighting_effect_destroy,
		get = advanced_lighting_get,
		set = advanced_lighting_set,
		clone = advanced_lighting_clone,
		properties = []string {
			"Enabled",
			"Intensity",
			"ShadowDistance",
			"ContactDistance",
			"LightCone",
			"SampleCount",
			"RayCount",
			"Bias",
		},
	)
	Register_Class(
		registry,
		&TemporalAntiAliasingEffect_Class,
		TemporalAntiAliasingEffect_construct,
		lighting_effect_destroy,
		get = advanced_lighting_get,
		set = advanced_lighting_set,
		clone = advanced_lighting_clone,
		properties = []string{"Enabled", "Feedback", "FilterWidth", "Sharpness", "LodBias"},
	)
	Register_Class(
		registry,
		&DynamicResolutionEffect_Class,
		DynamicResolutionEffect_construct,
		lighting_effect_destroy,
		get = advanced_lighting_get,
		set = advanced_lighting_set,
		clone = advanced_lighting_clone,
		properties = []string{"Enabled", "MinScale", "MaxScale", "Sharpness", "Quality"},
	)
	Register_Class(
		registry,
		&ToneMappingEffect_Class,
		ToneMappingEffect_construct,
		lighting_effect_destroy,
		get = advanced_lighting_get,
		set = advanced_lighting_set,
		clone = advanced_lighting_clone,
		properties = []string{"Enabled", "Mode", "ExposureCompensation", "Temperature", "Tint"},
	)
}
