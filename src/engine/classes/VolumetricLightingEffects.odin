package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:math"

VolumetricFogEffect_Class := Class_Info {
	name   = "VolumetricFogEffect",
	parent = &LightingEffect_Class,
}
VolumetricFogEffect :: struct {
	using effect:   LightingEffect,
	density:        f64,
	height:         f64,
	height_falloff: f64,
	max_distance:   f64,
	anisotropy:     f64,
	scattering:     f64,
	noise_strength: f64,
	noise_scale:    f64,
	step_count:     f64,
	color:          datatypes.Color3,
}
VolumetricFogEffect_Init :: proc() -> VolumetricFogEffect {
	return VolumetricFogEffect {
		effect = lighting_effect_init(&VolumetricFogEffect_Class, "VolumetricFogEffect"),
		density = 0.025,
		height = 0,
		height_falloff = 0.05,
		max_distance = 150,
		anisotropy = 0.35,
		scattering = 0.8,
		noise_strength = 0.35,
		noise_scale = 0.08,
		step_count = 24,
		color = {0.7, 0.8, 0.9},
	}
}
VolumetricFogEffect_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	value := new(VolumetricFogEffect); value^ = VolumetricFogEffect_Init(); return &value.object
}
VolumetricFogEffect_get :: proc(
	L: ^vm.State,
	object: ^Object,
	dt: ^datatypes.Registry,
	en: ^enums.Registry,
	key: string,
) -> bool {
	v := cast(^VolumetricFogEffect)object
	switch key {
	case "Enabled":
		vm.PushBoolean(L, v.enabled)
	case "Density":
		vm.PushNumber(L, v.density)
	case "Height":
		vm.PushNumber(L, v.height)
	case "HeightFalloff":
		vm.PushNumber(L, v.height_falloff)
	case "MaxDistance":
		vm.PushNumber(L, v.max_distance)
	case "Anisotropy":
		vm.PushNumber(L, v.anisotropy)
	case "Scattering":
		vm.PushNumber(L, v.scattering)
	case "NoiseStrength":
		vm.PushNumber(L, v.noise_strength)
	case "NoiseScale":
		vm.PushNumber(L, v.noise_scale)
	case "StepCount":
		vm.PushNumber(L, v.step_count)
	case "Color":
		datatypes.Push_Color3(L, dt, v.color)
	case:
		return false
	}
	return true
}
VolumetricFogEffect_set :: proc(
	L: ^vm.State,
	object: ^Object,
	dt: ^datatypes.Registry,
	en: ^enums.Registry,
	key: string,
	index: int,
) -> bool {
	v := cast(^VolumetricFogEffect)object
	switch key {
	case "Enabled":
		v.enabled = vm.ArgBoolean(L, index)
	case "Density":
		n := vm.ArgNumber(L, index)
		if math.is_nan(n) ||
		   math.is_inf(n) {_ = vm.RaiseError(L, "effect property must be finite"); return true}
		v.density = clamp(n, 0, 2)
	case "Height":
		n := vm.ArgNumber(L, index)
		if math.is_nan(n) ||
		   math.is_inf(n) {_ = vm.RaiseError(L, "effect property must be finite"); return true}
		v.height = clamp(n, -10000, 10000)
	case "HeightFalloff":
		n := vm.ArgNumber(L, index)
		if math.is_nan(n) ||
		   math.is_inf(n) {_ = vm.RaiseError(L, "effect property must be finite"); return true}
		v.height_falloff = clamp(n, 0, 5)
	case "MaxDistance":
		n := vm.ArgNumber(L, index)
		if math.is_nan(n) ||
		   math.is_inf(n) {_ = vm.RaiseError(L, "effect property must be finite"); return true}
		v.max_distance = clamp(n, 1, 10000)
	case "Anisotropy":
		n := vm.ArgNumber(L, index)
		if math.is_nan(n) ||
		   math.is_inf(n) {_ = vm.RaiseError(L, "effect property must be finite"); return true}
		v.anisotropy = clamp(n, -0.9, 0.9)
	case "Scattering":
		n := vm.ArgNumber(L, index)
		if math.is_nan(n) ||
		   math.is_inf(n) {_ = vm.RaiseError(L, "effect property must be finite"); return true}
		v.scattering = clamp(n, 0, 5)
	case "NoiseStrength":
		n := vm.ArgNumber(L, index)
		if math.is_nan(n) ||
		   math.is_inf(n) {_ = vm.RaiseError(L, "effect property must be finite"); return true}
		v.noise_strength = clamp(n, 0, 1)
	case "NoiseScale":
		n := vm.ArgNumber(L, index)
		if math.is_nan(n) ||
		   math.is_inf(n) {_ = vm.RaiseError(L, "effect property must be finite"); return true}
		v.noise_scale = clamp(n, 0.001, 10)
	case "StepCount":
		n := vm.ArgNumber(L, index)
		if math.is_nan(n) ||
		   math.is_inf(n) {_ = vm.RaiseError(L, "effect property must be finite"); return true}
		v.step_count = math.floor(clamp(n, 4, 64))
	case "Color":
		v.color = datatypes.Arg_Color3(L, index, dt)
	case:
		return false
	}
	return true
}
VolumetricFogEffect_clone :: proc(source, destination: ^Object) {
	src, dst := cast(^VolumetricFogEffect)source, cast(^VolumetricFogEffect)destination
	dst.enabled = src.enabled
	dst.density = src.density
	dst.height = src.height
	dst.height_falloff = src.height_falloff
	dst.max_distance = src.max_distance
	dst.anisotropy = src.anisotropy
	dst.scattering = src.scattering
	dst.noise_strength = src.noise_strength
	dst.noise_scale = src.noise_scale
	dst.step_count = src.step_count
	dst.color = src.color
}
ChromaticAberrationEffect_Class := Class_Info {
	name   = "ChromaticAberrationEffect",
	parent = &LightingEffect_Class,
}
ChromaticAberrationEffect :: struct {
	using effect: LightingEffect,
	intensity:    f64,
}
ChromaticAberrationEffect_Init :: proc() -> ChromaticAberrationEffect {
	return ChromaticAberrationEffect {
		effect = lighting_effect_init(
			&ChromaticAberrationEffect_Class,
			"ChromaticAberrationEffect",
		),
		intensity = 0.15,
	}
}
ChromaticAberrationEffect_construct :: proc(
	renderer: ^Renderer_Object,
	data_model: rawptr,
) -> ^Object {
	value := new(
		ChromaticAberrationEffect,
	); value^ = ChromaticAberrationEffect_Init(); return &value.object
}
ChromaticAberrationEffect_get :: proc(
	L: ^vm.State,
	object: ^Object,
	dt: ^datatypes.Registry,
	en: ^enums.Registry,
	key: string,
) -> bool {
	v := cast(^ChromaticAberrationEffect)object
	switch key {
	case "Enabled":
		vm.PushBoolean(L, v.enabled)
	case "Intensity":
		vm.PushNumber(L, v.intensity)
	case:
		return false
	}
	return true
}
ChromaticAberrationEffect_set :: proc(
	L: ^vm.State,
	object: ^Object,
	dt: ^datatypes.Registry,
	en: ^enums.Registry,
	key: string,
	index: int,
) -> bool {
	v := cast(^ChromaticAberrationEffect)object
	switch key {
	case "Enabled":
		v.enabled = vm.ArgBoolean(L, index)
	case "Intensity":
		n := vm.ArgNumber(L, index)
		if math.is_nan(n) ||
		   math.is_inf(n) {_ = vm.RaiseError(L, "effect property must be finite"); return true}
		v.intensity = clamp(n, 0, 1)
	case:
		return false
	}
	return true
}
ChromaticAberrationEffect_clone :: proc(source, destination: ^Object) {
	src, dst := cast(^ChromaticAberrationEffect)source, cast(^ChromaticAberrationEffect)destination
	dst.enabled = src.enabled
	dst.intensity = src.intensity
}
FilmGrainEffect_Class := Class_Info {
	name   = "FilmGrainEffect",
	parent = &LightingEffect_Class,
}
FilmGrainEffect :: struct {
	using effect: LightingEffect,
	intensity:    f64,
	grain_size:   f64,
}
FilmGrainEffect_Init :: proc() -> FilmGrainEffect {
	return FilmGrainEffect {
		effect = lighting_effect_init(&FilmGrainEffect_Class, "FilmGrainEffect"),
		intensity = 0.08,
		grain_size = 1,
	}
}
FilmGrainEffect_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	value := new(FilmGrainEffect); value^ = FilmGrainEffect_Init(); return &value.object
}
FilmGrainEffect_get :: proc(
	L: ^vm.State,
	object: ^Object,
	dt: ^datatypes.Registry,
	en: ^enums.Registry,
	key: string,
) -> bool {
	v := cast(^FilmGrainEffect)object
	switch key {
	case "Enabled":
		vm.PushBoolean(L, v.enabled)
	case "Intensity":
		vm.PushNumber(L, v.intensity)
	case "GrainSize":
		vm.PushNumber(L, v.grain_size)
	case:
		return false
	}
	return true
}
FilmGrainEffect_set :: proc(
	L: ^vm.State,
	object: ^Object,
	dt: ^datatypes.Registry,
	en: ^enums.Registry,
	key: string,
	index: int,
) -> bool {
	v := cast(^FilmGrainEffect)object
	switch key {
	case "Enabled":
		v.enabled = vm.ArgBoolean(L, index)
	case "Intensity":
		n := vm.ArgNumber(L, index)
		if math.is_nan(n) ||
		   math.is_inf(n) {_ = vm.RaiseError(L, "effect property must be finite"); return true}
		v.intensity = clamp(n, 0, 1)
	case "GrainSize":
		n := vm.ArgNumber(L, index)
		if math.is_nan(n) ||
		   math.is_inf(n) {_ = vm.RaiseError(L, "effect property must be finite"); return true}
		v.grain_size = clamp(n, 1, 8)
	case:
		return false
	}
	return true
}
FilmGrainEffect_clone :: proc(source, destination: ^Object) {
	src, dst := cast(^FilmGrainEffect)source, cast(^FilmGrainEffect)destination
	dst.enabled = src.enabled
	dst.intensity = src.intensity
	dst.grain_size = src.grain_size
}
Register_Volumetric_Lighting_Effects :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&VolumetricFogEffect_Class,
		VolumetricFogEffect_construct,
		lighting_effect_destroy,
		get = VolumetricFogEffect_get,
		set = VolumetricFogEffect_set,
		clone = VolumetricFogEffect_clone,
		properties = []string {
			"Enabled",
			"Density",
			"Height",
			"HeightFalloff",
			"MaxDistance",
			"Anisotropy",
			"Scattering",
			"NoiseStrength",
			"NoiseScale",
			"StepCount",
			"Color",
		},
	)
	Register_Class(
		registry,
		&ChromaticAberrationEffect_Class,
		ChromaticAberrationEffect_construct,
		lighting_effect_destroy,
		get = ChromaticAberrationEffect_get,
		set = ChromaticAberrationEffect_set,
		clone = ChromaticAberrationEffect_clone,
		properties = []string{"Enabled", "Intensity"},
	)
	Register_Class(
		registry,
		&FilmGrainEffect_Class,
		FilmGrainEffect_construct,
		lighting_effect_destroy,
		get = FilmGrainEffect_get,
		set = FilmGrainEffect_set,
		clone = FilmGrainEffect_clone,
		properties = []string{"Enabled", "Intensity", "GrainSize"},
	)
}
