package classes

import kineffi "../bindings"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:math"

Water_Class := Class_Info {
	name   = "Water",
	parent = &Instance_Class,
}

Water :: struct {
	using object:       Object,
	adornee:            ^Object,
	enabled:            bool,
	speed:              f32,
	strength:           f32,
	octaves:            f32,
	height:             f32,
	roughness:          f32,
	ior:                f32,
	thickness:          f32,
	transmission:       f32,
	foamAmount:         f32,
	absorption:         datatypes.Color3,
	clearCoat:          f32,
	clearCoatRoughness: f32,
}

Water_Init :: proc() -> Water {
	return Water {
		object = Object_Init(&Water_Class),
		adornee = nil,
		enabled = true,
		speed = 1.0,
		strength = 1.0,
		octaves = 6.0,
		height = 1.0,
		roughness = 0.08,
		ior = 1.333,
		thickness = 0.12,
		transmission = 0.88,
		foamAmount = 0.55,
		absorption = datatypes.Color3{R = 0.35, G = 0.09, B = 0.04},
		clearCoat = 1.0,
		clearCoatRoughness = 0.04,
	}
}

Water_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	water := new(Water)
	water^ = Water_Init()
	water.name = "Water"
	return &water.object
}

Water_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	water := cast(^Water)object
	Object_Destroy(object)
	free(water)
}

Water_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^Water)source
	dst := cast(^Water)destination

	dst.enabled = src.enabled
	dst.speed = src.speed
	dst.strength = src.strength
	dst.octaves = src.octaves
	dst.height = src.height
	dst.roughness = src.roughness
	dst.ior = src.ior
	dst.thickness = src.thickness
	dst.transmission = src.transmission
	dst.foamAmount = src.foamAmount
	dst.clearCoat = src.clearCoat
	dst.clearCoatRoughness = src.clearCoatRoughness
	dst.absorption = src.absorption
	dst.adornee = src.adornee
}

Water_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	water := cast(^Water)object

	switch key {
	case "Enabled":
		vm.PushBoolean(L, water.enabled)
	case "Speed":
		vm.PushNumber(L, f64(water.speed))
	case "Strength":
		vm.PushNumber(L, f64(water.strength))
	case "Octaves":
		vm.PushNumber(L, f64(water.octaves))
	case "Height":
		vm.PushNumber(L, f64(water.height))
	case "Adornee":
		Push_Object(L, water.adornee)
	case "Roughness":
		vm.PushNumber(L, f64(water.roughness))
	case "IOR":
		vm.PushNumber(L, f64(water.ior))
	case "Thickness":
		vm.PushNumber(L, f64(water.thickness))
	case "Transmission":
		vm.PushNumber(L, f64(water.transmission))
	case "FoamAmount":
		vm.PushNumber(L, f64(water.foamAmount))
	case "ClearCoat":
		vm.PushNumber(L, f64(water.clearCoat))
	case "ClearCoatRoughness":
		vm.PushNumber(L, f64(water.clearCoatRoughness))
	case "Absorption":
		if datatype_registry == nil {
			return false
		}
		datatypes.Push_Color3(L, datatype_registry, water.absorption)
	case:
		return false
	}

	return true
}

Water_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	water := cast(^Water)object

	switch key {
	case "Enabled":
		water.enabled = vm.ArgBoolean(L, value_index)
	case "Speed":
		water.speed = math.clamp(f32(vm.ArgNumber(L, value_index)), 0, 10)
	case "Strength":
		water.strength = math.clamp(f32(vm.ArgNumber(L, value_index)), 0, 10)
	case "Octaves":
		water.octaves = math.clamp(f32(vm.ArgNumber(L, value_index)), 1, 32)
	case "Height":
		water.height = math.clamp(f32(vm.ArgNumber(L, value_index)), 0, 10)
	case "Adornee":
		water.adornee = object_from_argument(L, value_index)
	case "Roughness":
		water.roughness = math.clamp(f32(vm.ArgNumber(L, value_index)), 0, 1)
	case "IOR":
		water.ior = math.clamp(f32(vm.ArgNumber(L, value_index)), 1, 3)
	case "Thickness":
		water.thickness = math.clamp(f32(vm.ArgNumber(L, value_index)), 0, 1)
	case "Transmission":
		water.transmission = math.clamp(f32(vm.ArgNumber(L, value_index)), 0, 1)
	case "FoamAmount":
		water.foamAmount = math.clamp(f32(vm.ArgNumber(L, value_index)), 0, 1)
	case "ClearCoat":
		water.clearCoat = math.clamp(f32(vm.ArgNumber(L, value_index)), 0, 1)
	case "ClearCoatRoughness":
		water.clearCoatRoughness = math.clamp(f32(vm.ArgNumber(L, value_index)), 0, 1)
	case "Absorption":
		if datatype_registry == nil {
			return false
		}
		water.absorption = datatypes.Arg_Color3(L, value_index, datatype_registry)
	case:
		return false
	}

	return true
}

Water_Render_Params :: proc(water: ^Water) -> kineffi.KineFilamentWaterParams {
	if water == nil {
		return kineffi.KineFilamentWaterParams {
			speed = 1,
			strength = 1,
			octaves = 6,
			height = 1,
			waveScale = 1,
			foamAmount = 0.55,
			absorptionR = 0.35,
			absorptionG = 0.09,
			absorptionB = 0.04,
			clearCoat = 1,
			clearCoatRoughness = 0.04,
		}
	}
	return kineffi.KineFilamentWaterParams {
		speed = water.speed,
		strength = water.strength,
		octaves = water.octaves,
		height = water.height,
		waveScale = 1.0,
		foamAmount = water.foamAmount,
		absorptionR = water.absorption.R,
		absorptionG = water.absorption.G,
		absorptionB = water.absorption.B,
		clearCoat = water.clearCoat,
		clearCoatRoughness = water.clearCoatRoughness,
	}

}

Register_Water :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&Water_Class,
		Water_construct,
		Water_destroy,
		clone = Water_clone,
		get = Water_get,
		set = Water_set,
		properties = []string {
			"Enabled",
			"Speed",
			"Strength",
			"Octaves",
			"Height",
			"Adornee",
			"Roughness",
			"IOR",
			"Thickness",
			"Transmission",
			"FoamAmount",
			"ClearCoat",
			"ClearCoatRoughness",
			"Absorption",
		},
	)
}
