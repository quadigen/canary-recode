package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:math"

SkyLightEffect_Class := Class_Info {
	name   = "SkyLightEffect",
	parent = &LightingEffect_Class,
}
LensFlareEffect_Class := Class_Info {
	name   = "LensFlareEffect",
	parent = &LightingEffect_Class,
}
ColorGradingEffect_Class := Class_Info {
	name   = "ColorGradingEffect",
	parent = &LightingEffect_Class,
}

SunLightEffect_Class := Class_Info {
	name   = "SunLightEffect",
	parent = &LightingEffect_Class,
}
ScreenSpaceCavityEffect_Class := Class_Info {
	name   = "ScreenSpaceCavityEffect",
	parent = &LightingEffect_Class,
}
ScreenSpaceOutlineEffect_Class := Class_Info {
	name   = "ScreenSpaceOutlineEffect",
	parent = &LightingEffect_Class,
}
DDGIEffect_Class := Class_Info {
	name   = "DDGIEffect",
	parent = &LightingEffect_Class,
}
EmissiveGIEffect_Class := Class_Info {
	name   = "EmissiveGIEffect",
	parent = &LightingEffect_Class,
}
AmbientOcclusionDetailEffect_Class := Class_Info {
	name   = "AmbientOcclusionDetailEffect",
	parent = &LightingEffect_Class,
}


Scene_Lighting_Effect :: struct {
	using effect: LightingEffect,
	values:       [9]f32,
}

Scene_Lighting_Effect_Definition :: struct {
	class:           ^Class_Info,
	renderer_id:     i32,
	parameter_count: i32,
	properties:      []string,
	defaults:        [9]f32,
	numeric_max:     []f32,
}

Scene_Lighting_Effects := [?]Scene_Lighting_Effect_Definition {
	{
		&DDGIEffect_Class,
		19,
		9,
		{"Intensity", "ProbeSpacing", "ProbeCountX", "ProbeCountY", "ProbeCountZ", "RaysPerProbe", "ProbesPerFrame", "Hysteresis", "MaxDistance"},
		{1, 24, 5, 3, 5, 48, 6, 0.85, 100},
		{5, 100, 9, 7, 9, 128, 24, 0.99, 500},
	},
	{
		&EmissiveGIEffect_Class,
		18,
		6,
		{"Intensity", "Radius", "Threshold", "Falloff", "MaxDistance", "SampleCount"},
		{1, 8, 0.7, 2, 100, 16, 0, 0, 0},
		{5, 30, 1, 8, 1000, 32},
	},
	{
		&ScreenSpaceCavityEffect_Class,
		16,
		4,
		{"Intensity", "Radius", "Bias", "MaxDistance"},
		{1, 0.3, 0.02, 100, 0, 0, 0, 0, 0},
		{4, 5, 1, 2000},
	},
	{
		&ScreenSpaceOutlineEffect_Class,
		17,
		4,
		{"Intensity", "Thickness", "DepthThreshold", "NormalThreshold"},
		{0.75, 1.5, 0.06, 0.30, 0, 0, 0, 0, 0},
		{1, 5, 1, 1},
	},
	{&SkyLightEffect_Class, 10, 1, {"Intensity"}, {1, 0, 0, 0, 0, 0, 0, 0, 0}, {4}},
	{
		&LensFlareEffect_Class,
		11,
		8,
		{
			"Starburst",
			"ChromaticAberration",
			"GhostCount",
			"GhostSpacing",
			"GhostThreshold",
			"HaloThickness",
			"HaloRadius",
			"HaloThreshold",
		},
		{1, 0.005, 4, 0.6, 10, 0.1, 0.4, 10, 0},
		{1, 0.1, 8, 0.99, 1000, 1, 0.5, 1000},
	},
	{
		&ColorGradingEffect_Class,
		12,
		9,
		{"Shadows", "Midtones", "Highlights"},
		{1, 1, 1, 1, 1, 1, 1, 1, 1},
		nil,
	},
	{
		&SunLightEffect_Class,
		13,
		5,
		{"Azimuth", "Elevation", "Color"},
		{35.52338, 67.5, 1, 0.98, 0.95, 0, 0, 0, 0},
		{360, 90},
	},
	{
		&AmbientOcclusionDetailEffect_Class,
		14,
		9,
		{
			"FullResolution",
			"BentNormals",
			"Bias",
			"BilateralThreshold",
			"FilterQuality",
			"UpsamplingQuality",
			"SliceCount",
			"StepsPerSlice",
			"VisibilityBitmasks",
		},
		{1, 1, 0.0005, 0.05, 2, 2, 4, 3, 0},
		{1, 1, 0.1, 1, 3, 3, 16, 8, 1},
	},
}

scene_lighting_definition :: proc(class: ^Class_Info) -> ^Scene_Lighting_Effect_Definition {
	for &definition in Scene_Lighting_Effects {
		if definition.class == class {return &definition}
	}
	return nil
}

scene_lighting_construct :: proc(class: ^Class_Info) -> ^Object {
	definition := scene_lighting_definition(class)
	value := new(Scene_Lighting_Effect)
	value.effect = lighting_effect_init(definition.class, definition.class.name)
	value.values = definition.defaults
	return &value.object
}

scene_lighting_get :: proc(
	L: ^vm.State,
	object: ^Object,
	dr: ^datatypes.Registry,
	er: ^enums.Registry,
	key: string,
) -> bool {
	value := cast(^Scene_Lighting_Effect)object
	if key == "Enabled" {
		vm.PushBoolean(L, value.enabled)
		return true
	}
	definition := scene_lighting_definition(object.class)
	for property, index in definition.properties {
		if property != key {continue}
		if key == "Color" || object.class == &ColorGradingEffect_Class {
			offset := key == "Color" ? 2 : index * 3
			datatypes.Push_Color3(
				L,
				dr,
				{value.values[offset], value.values[offset + 1], value.values[offset + 2]},
			)
		} else if key == "Starburst" || key == "FullResolution" || key == "BentNormals" ||
			key == "VisibilityBitmasks" {
			vm.PushBoolean(L, value.values[index] != 0)
		} else {
			vm.PushNumber(L, f64(value.values[index]))
		}
		return true
	}
	return false
}

scene_lighting_finite :: proc(L: ^vm.State, number: f64) -> bool {
	if math.is_nan(number) || math.is_inf(number) {
		_ = vm.RaiseError(L, "Lighting effect values must be finite")
		return false
	}
	return true
}

scene_lighting_set :: proc(
	L: ^vm.State,
	object: ^Object,
	dr: ^datatypes.Registry,
	er: ^enums.Registry,
	key: string,
	arg: int,
) -> bool {
	value := cast(^Scene_Lighting_Effect)object
	if key == "Enabled" {
		value.enabled = vm.ArgBoolean(L, arg)
		return true
	}
	definition := scene_lighting_definition(object.class)
	for property, index in definition.properties {
		if property != key {continue}
		if key == "Color" || object.class == &ColorGradingEffect_Class {
			color := datatypes.Arg_Color3(L, arg, dr)
			for component in ([3]f32{color.R, color.G, color.B}) {
				if !scene_lighting_finite(L, f64(component)) {return true}
			}
			offset := key == "Color" ? 2 : index * 3
			value.values[offset] = clamp(color.R, 0, 1)
			value.values[offset + 1] = clamp(color.G, 0, 1)
			value.values[offset + 2] = clamp(color.B, 0, 1)
		} else if key == "Starburst" || key == "FullResolution" || key == "BentNormals" ||
			key == "VisibilityBitmasks" {
			value.values[index] = vm.ArgBoolean(L, arg) ? 1 : 0
		} else {
			number := vm.ArgNumber(L, arg)
			if !scene_lighting_finite(L, number) {return true}
			switch key {
			case "Azimuth":
				number = math.mod(number, 360)
				if number < 0 {number += 360}
			case "Elevation":
				number = clamp(number, -90, 90)
			case:
				minimum := key == "BilateralThreshold" ? 0.001 : ((key == "ProbeCountX" || key == "ProbeCountY" || key == "ProbeCountZ") ? 2 : ((key == "ProbesPerFrame" || key == "ProbeSpacing" || key == "MaxDistance" || key == "SliceCount" || key == "StepsPerSlice") ? 1 : ((key == "SampleCount" || key == "RaysPerProbe") ? 4 : 0)))
				number = clamp(number, minimum, f64(definition.numeric_max[index]))
				if key == "ProbeCountX" || key == "ProbeCountY" || key == "ProbeCountZ" ||
					key == "RaysPerProbe" || key == "ProbesPerFrame" ||
					key == "GhostCount" || key == "FilterQuality" || key == "UpsamplingQuality" ||
					key == "SliceCount" || key == "StepsPerSlice" || key == "SampleCount" {
					number = math.floor(number)
				}
			}
			value.values[index] = f32(number)
		}
		return true
	}
	return false
}

scene_lighting_clone :: proc(source, destination: ^Object) {
	src, dst := cast(^Scene_Lighting_Effect)source, cast(^Scene_Lighting_Effect)destination
	dst.enabled = src.enabled
	dst.values = src.values
}

SkyLightEffect_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	return scene_lighting_construct(&SkyLightEffect_Class)
}

LensFlareEffect_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	return scene_lighting_construct(&LensFlareEffect_Class)
}

ColorGradingEffect_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	return scene_lighting_construct(&ColorGradingEffect_Class)
}

SunLightEffect_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	return scene_lighting_construct(&SunLightEffect_Class)
}

AmbientOcclusionDetailEffect_construct :: proc(
	renderer: ^Renderer_Object,
	data_model: rawptr,
) -> ^Object {
	return scene_lighting_construct(&AmbientOcclusionDetailEffect_Class)
}

ScreenSpaceCavityEffect_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	return scene_lighting_construct(&ScreenSpaceCavityEffect_Class)
}

ScreenSpaceOutlineEffect_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	return scene_lighting_construct(&ScreenSpaceOutlineEffect_Class)
}

DDGIEffect_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	return scene_lighting_construct(&DDGIEffect_Class)
}

EmissiveGIEffect_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	return scene_lighting_construct(&EmissiveGIEffect_Class)
}

Register_Scene_Lighting_Effects :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&DDGIEffect_Class,
		DDGIEffect_construct,
		lighting_effect_destroy,
		get = scene_lighting_get,
		set = scene_lighting_set,
		clone = scene_lighting_clone,
		properties = {"Enabled", "Intensity", "ProbeSpacing", "ProbeCountX", "ProbeCountY", "ProbeCountZ", "RaysPerProbe", "ProbesPerFrame", "Hysteresis", "MaxDistance"},
	)
	Register_Class(
		registry,
		&EmissiveGIEffect_Class,
		EmissiveGIEffect_construct,
		lighting_effect_destroy,
		get = scene_lighting_get,
		set = scene_lighting_set,
		clone = scene_lighting_clone,
		properties = {"Enabled", "Intensity", "Radius", "Threshold", "Falloff", "MaxDistance", "SampleCount"},
	)
	Register_Class(
		registry,
		&ScreenSpaceCavityEffect_Class,
		ScreenSpaceCavityEffect_construct,
		lighting_effect_destroy,
		get = scene_lighting_get,
		set = scene_lighting_set,
		clone = scene_lighting_clone,
		properties = {"Enabled", "Intensity", "Radius", "Bias", "MaxDistance"},
	)
	Register_Class(
		registry,
		&ScreenSpaceOutlineEffect_Class,
		ScreenSpaceOutlineEffect_construct,
		lighting_effect_destroy,
		get = scene_lighting_get,
		set = scene_lighting_set,
		clone = scene_lighting_clone,
		properties = {"Enabled", "Intensity", "Thickness", "DepthThreshold", "NormalThreshold"},
	)
	Register_Class(
		registry,
		&SkyLightEffect_Class,
		SkyLightEffect_construct,
		lighting_effect_destroy,
		get = scene_lighting_get,
		set = scene_lighting_set,
		clone = scene_lighting_clone,
		properties = {"Enabled", "Intensity"},
	)
	Register_Class(
		registry,
		&LensFlareEffect_Class,
		LensFlareEffect_construct,
		lighting_effect_destroy,
		get = scene_lighting_get,
		set = scene_lighting_set,
		clone = scene_lighting_clone,
		properties = {
			"Enabled",
			"Starburst",
			"ChromaticAberration",
			"GhostCount",
			"GhostSpacing",
			"GhostThreshold",
			"HaloThickness",
			"HaloRadius",
			"HaloThreshold",
		},
	)
	Register_Class(
		registry,
		&ColorGradingEffect_Class,
		ColorGradingEffect_construct,
		lighting_effect_destroy,
		get = scene_lighting_get,
		set = scene_lighting_set,
		clone = scene_lighting_clone,
		properties = {"Enabled", "Shadows", "Midtones", "Highlights"},
	)
	Register_Class(
		registry,
		&SunLightEffect_Class,
		SunLightEffect_construct,
		lighting_effect_destroy,
		get = scene_lighting_get,
		set = scene_lighting_set,
		clone = scene_lighting_clone,
		properties = {"Enabled", "Azimuth", "Elevation", "Color"},
	)
	Register_Class(
		registry,
		&AmbientOcclusionDetailEffect_Class,
		AmbientOcclusionDetailEffect_construct,
		lighting_effect_destroy,
		get = scene_lighting_get,
		set = scene_lighting_set,
		clone = scene_lighting_clone,
		properties = {
			"Enabled",
			"FullResolution",
			"BentNormals",
			"Bias",
			"BilateralThreshold",
			"FilterQuality",
			"UpsamplingQuality",
		},
	)
}
