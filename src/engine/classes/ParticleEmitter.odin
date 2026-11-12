package classes

import "core:math"
import "core:strings"
import kineffi "../bindings"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

ParticleEmitter_Class := Class_Info {
	name = "ParticleEmitter",
	parent = &Instance_Class,
}

ParticleEmitter_Settings :: struct {
	enabled:             bool,
	rate:                f32,
	lifetime:            datatypes.NumberRange,
	speed:               datatypes.NumberRange,
	rotation:            datatypes.NumberRange,
	rot_speed:           datatypes.NumberRange,
	spread_angle:        datatypes.Vector2,
	acceleration:        datatypes.Vector3,
	drag:                f32,
	wind_affects_drag:   bool,
	color:               datatypes.ColorSequence,
	size:                datatypes.NumberSequence,
	transparency:        datatypes.NumberSequence,
	light_emission:      f32,
	brightness:          f32,
	z_offset:            f32,
	texture:             string,
	emission_direction:  enums.NormalId,
	flipbook_layout:     enums.ParticleFlipbookLayout,
	flipbook_mode:       enums.ParticleFlipbookMode,
	flipbook_framerate:  datatypes.NumberRange,
}

ParticleEmitter :: struct {
	using object:    Object,
	using settings:  ParticleEmitter_Settings,
	particles:       [dynamic]Emitter_Particle,
	emission_credit: f32,
	draw_items:      [dynamic]kineffi.KineFilamentParticleItem,
	native_texture:  ^kineffi.KineFilamentTex,
	texture_context: ^kineffi.KineFilamentContext,
}

particle_emitter_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	emitter := new(ParticleEmitter)
	emitter.object = Object_Init(&ParticleEmitter_Class, "ParticleEmitter")
	emitter.settings = {
		enabled              = true,
		rate                 = 20,
		lifetime             = {5, 10},
		speed                = {5, 5},
		color                = datatypes.ColorSequence_New({1, 1, 1}),
		size                 = datatypes.NumberSequence_New(1),
		transparency         = datatypes.NumberSequence_New(0),
		brightness           = 1,
		emission_direction   = .Top,
		flipbook_framerate   = {1, 30},
	}
	return &emitter.object
}

particle_emitter_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	emitter := cast(^ParticleEmitter)object
	particle_emitter_release_texture(emitter, renderer)
	delete(emitter.texture)
	datatypes.ColorSequence_Destroy(emitter.color)
	datatypes.NumberSequence_Destroy(emitter.size)
	datatypes.NumberSequence_Destroy(emitter.transparency)
	delete(emitter.particles)
	delete(emitter.draw_items)
	Object_Destroy(object)
	free(emitter)
}

particle_emitter_clone :: proc(source, destination: ^Object) {
	src := cast(^ParticleEmitter)source
	dst := cast(^ParticleEmitter)destination
	datatypes.ColorSequence_Destroy(dst.color)
	datatypes.NumberSequence_Destroy(dst.size)
	datatypes.NumberSequence_Destroy(dst.transparency)
	dst.settings = src.settings
	dst.texture = strings.clone(src.texture)
	dst.color = datatypes.ColorSequence_Clone(src.color)
	dst.size = datatypes.NumberSequence_Clone(src.size)
	dst.transparency = datatypes.NumberSequence_Clone(src.transparency)
}

particle_emitter_get :: proc(
	L: ^vm.State, object: ^Object, types: ^datatypes.Registry, enum_registry: ^enums.Registry, key: string,
) -> bool {
	emitter := cast(^ParticleEmitter)object
	switch key {
	case "Enabled":
		vm.PushBoolean(L, emitter.enabled)
	case "Rate":
		vm.PushNumber(L, f64(emitter.rate))
	case "Lifetime":
		datatypes.Push_NumberRange(L, types, emitter.lifetime)
	case "Speed":
		datatypes.Push_NumberRange(L, types, emitter.speed)
	case "Rotation":
		datatypes.Push_NumberRange(L, types, emitter.rotation)
	case "RotSpeed":
		datatypes.Push_NumberRange(L, types, emitter.rot_speed)
	case "SpreadAngle":
		datatypes.Push_Vector2(L, types, emitter.spread_angle)
	case "Acceleration":
		datatypes.Push_Vector3(L, emitter.acceleration)
	case "Drag":
		vm.PushNumber(L, f64(emitter.drag))
	case "WindAffectsDrag":
		vm.PushBoolean(L, emitter.wind_affects_drag)
	case "Color":
		datatypes.Push_ColorSequence(L, types, emitter.color)
	case "Size":
		datatypes.Push_NumberSequence(L, types, emitter.size)
	case "Transparency":
		datatypes.Push_NumberSequence(L, types, emitter.transparency)
	case "LightEmission":
		vm.PushNumber(L, f64(emitter.light_emission))
	case "Brightness":
		vm.PushNumber(L, f64(emitter.brightness))
	case "ZOffset":
		vm.PushNumber(L, f64(emitter.z_offset))
	case "Texture":
		vm.PushString(L, emitter.texture)
	case "EmissionDirection":
		enums.Push_Item_By_Value(L, enum_registry, "NormalId", i64(emitter.emission_direction))
	case "FlipbookLayout":
		enums.Push_Item_By_Value(L, enum_registry, "ParticleFlipbookLayout", i64(emitter.flipbook_layout))
	case "FlipbookMode":
		enums.Push_Item_By_Value(L, enum_registry, "ParticleFlipbookMode", i64(emitter.flipbook_mode))
	case "FlipbookFramerate":
		datatypes.Push_NumberRange(L, types, emitter.flipbook_framerate)
	case "VelocitySpread":
		vm.PushNumber(L, f64(emitter.spread_angle.X))
	case "Emit", "Clear":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}
	return true
}

particle_emitter_set :: proc(
	L: ^vm.State, object: ^Object, types: ^datatypes.Registry, enum_registry: ^enums.Registry,
	key: string, index: int,
) -> bool {
	emitter := cast(^ParticleEmitter)object
	switch key {
	case "Enabled":
		emitter.enabled = vm.ArgBoolean(L, index)
	case "Rate":
		emitter.rate = particle_emitter_number(L, index, 0, 2048)
	case "Lifetime":
		value := datatypes.Arg_NumberRange(L, index, types)
		emitter.lifetime = {clamp(value.Min, 0, 120), clamp(value.Max, 0, 120)}
	case "Speed":
		value := datatypes.Arg_NumberRange(L, index, types)
		emitter.speed = {clamp(value.Min, -10000, 10000), clamp(value.Max, -10000, 10000)}
	case "Rotation":
		value := datatypes.Arg_NumberRange(L, index, types)
		emitter.rotation = {clamp(value.Min, -100000, 100000), clamp(value.Max, -100000, 100000)}
	case "RotSpeed":
		value := datatypes.Arg_NumberRange(L, index, types)
		emitter.rot_speed = {clamp(value.Min, -100000, 100000), clamp(value.Max, -100000, 100000)}
	case "SpreadAngle":
		value := datatypes.Arg_Vector2(L, index, types)
		if math.is_nan(value.X) || math.is_nan(value.Y) {
			_ = vm.RaiseError(L, "SpreadAngle must contain numbers")
			return true
		}
		emitter.spread_angle = {clamp(value.X, 0, 360), clamp(value.Y, 0, 360)}
	case "Acceleration":
		value := datatypes.Arg_Vector3(L, index)
		if math.is_nan(value.x + value.y + value.z) || math.is_inf(value.x) ||
		   math.is_inf(value.y) || math.is_inf(value.z) {
			_ = vm.RaiseError(L, "Acceleration must be finite")
			return true
		}
		emitter.acceleration = value
	case "Drag":
		emitter.drag = particle_emitter_number(L, index, 0, 1000)
	case "WindAffectsDrag":
		emitter.wind_affects_drag = vm.ArgBoolean(L, index)
	case "Color":
		value := datatypes.ColorSequence_Clone(datatypes.Arg_ColorSequence(L, index, types))
		datatypes.ColorSequence_Destroy(emitter.color)
		emitter.color = value
	case "Size":
		value := datatypes.NumberSequence_Clone(datatypes.Arg_NumberSequence(L, index, types))
		datatypes.NumberSequence_Destroy(emitter.size)
		emitter.size = value
	case "Transparency":
		value := datatypes.NumberSequence_Clone(datatypes.Arg_NumberSequence(L, index, types))
		datatypes.NumberSequence_Destroy(emitter.transparency)
		emitter.transparency = value
	case "LightEmission":
		emitter.light_emission = particle_emitter_number(L, index, 0, 1)
	case "Brightness":
		emitter.brightness = particle_emitter_number(L, index, 0, 100)
	case "ZOffset":
		emitter.z_offset = particle_emitter_number(L, index, -10000, 10000)
	case "Texture":
		texture := vm.ArgString(L, index)
		if texture != emitter.texture {
			particle_emitter_release_texture(emitter, object.signal_registry.renderer)
			delete(emitter.texture)
			emitter.texture = strings.clone(texture)
		}
	case "EmissionDirection":
		item := enums.Arg_Item(L, index, enum_registry, "NormalId")
		emitter.emission_direction = enums.NormalId(item.value)
	case "FlipbookLayout":
		item := enums.Arg_Item(L, index, enum_registry, "ParticleFlipbookLayout")
		emitter.flipbook_layout = enums.ParticleFlipbookLayout(item.value)
	case "FlipbookMode":
		item := enums.Arg_Item(L, index, enum_registry, "ParticleFlipbookMode")
		emitter.flipbook_mode = enums.ParticleFlipbookMode(item.value)
	case "FlipbookFramerate":
		value := datatypes.Arg_NumberRange(L, index, types)
		emitter.flipbook_framerate = {clamp(value.Min, 0, 120), clamp(value.Max, 0, 120)}
	case "VelocitySpread":
		value := particle_emitter_number(L, index, 0, 360)
		emitter.spread_angle = {value, value}
	case:
		return false
	}
	return true
}

particle_emitter_number :: proc(L: ^vm.State, index: int, minimum, maximum: f32) -> f32 {
	value := f32(vm.ArgNumber(L, index))
	if math.is_nan(value) {
		_ = vm.RaiseError(L, "ParticleEmitter expects a number")
		return minimum
	}
	return clamp(value, minimum, maximum)
}

particle_emitter_namecall :: proc(
	L: ^vm.State, object: ^Object, types: ^datatypes.Registry, enum_registry: ^enums.Registry, method: string,
) -> (i32, bool) {
	emitter := cast(^ParticleEmitter)object
	switch method {
	case "Emit":
		count := 16
		if !vm.IsNoneOrNil(L, 2) {
			count = int(particle_emitter_number(L, 2, 0, PARTICLE_EMITTER_LIMIT))
		}
		particle_emitter_emit(emitter, count)
	case "Clear":
		clear(&emitter.particles)
		Render_3D_Mark_Dirty()
	case:
		return 0, false
	}
	return 0, true
}

Register_ParticleEmitter :: proc(registry: ^Registry) {
	Register_Class(
		registry, &ParticleEmitter_Class, particle_emitter_construct, particle_emitter_destroy,
		get = particle_emitter_get, set = particle_emitter_set,
		namecall = particle_emitter_namecall, clone = particle_emitter_clone,
		properties = []string{
			"Enabled",
			"Rate",
			"Lifetime",
			"Speed",
			"Rotation",
			"RotSpeed",
			"SpreadAngle",
			"Acceleration",
			"Drag",
			"WindAffectsDrag",
			"Color",
			"Size",
			"Transparency",
			"LightEmission",
			"Brightness",
			"ZOffset",
			"Texture",
			"EmissionDirection",
			"FlipbookLayout",
			"FlipbookMode",
			"FlipbookFramerate",
		},
		methods = []string{"Emit", "Clear"},
	)
}
