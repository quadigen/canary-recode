package services
// wire:service

import aero "../aerodynamics"
import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:fmt"
import "core:math"

Aerodynamics_Class := classes.Class_Info {
	name   = "Aerodynamics",
	parent = &Service_Class,
}

Aerodynamics :: struct {
	using service:        Service,
	enabled:              bool,
	atmosphere:           enums.AerodynamicsAtmosphere,
	density:              f32,
	meters_per_unit:      f32,
	reference_height:     f64,
	density_scale_height: f32,
	wind:                 datatypes.Vector3,
	wind_shear:           datatypes.Vector3,
	gust:                 datatypes.Vector3,
	gust_frequency:       f32,
	gust_wavelength:      f32,
	min_speed:            f32,
	max_speed:            f32,
	thin_ratio:           f32,
	min_dimension:        f32,
	max_force:            f32,
	max_torque:           f32,
	mode:                 enums.AerodynamicsMode,
	normal_axis:          enums.AerodynamicsNormalAxis,
	drag_coefficient:     f32,
	profile_drag:         f32,
	lift_multiplier:      f32,
	stall_angle_deg:      f32,
	efficiency:           f32,
	max_lift:             f32,
	area_multiplier:      f32,
	directional_drag:     datatypes.Vector3,
	pressure_offset:      datatypes.Vector3,
	incidence_deg:        f32,
	wave_drag:            f32,
	sound_speed:          f32,
	wake_sleeping:        bool,
}

aerodynamics_apply_defaults :: proc(service: ^Aerodynamics) {
	service.enabled = false
	service.atmosphere = .Standard
	service.density = aero.DEFAULT_SETTINGS.density
	service.meters_per_unit = aero.DEFAULT_SETTINGS.meters_per_unit
	service.reference_height = aero.DEFAULT_SETTINGS.reference_height
	service.density_scale_height = aero.DEFAULT_SETTINGS.density_scale_height
	service.wind = {}
	service.wind_shear = {}
	service.gust = {}
	service.gust_frequency = 0
	service.gust_wavelength = 0
	service.min_speed = aero.DEFAULT_SETTINGS.min_speed
	service.max_speed = aero.DEFAULT_SETTINGS.max_speed
	service.thin_ratio = aero.DEFAULT_SETTINGS.thin_ratio
	service.min_dimension = aero.DEFAULT_SETTINGS.min_dimension
	service.max_force = aero.DEFAULT_SETTINGS.max_force_newtons
	service.max_torque = aero.DEFAULT_SETTINGS.max_torque_nm
	service.mode = .Auto
	service.normal_axis = .Auto
	service.drag_coefficient = aero.DEFAULT_BODY_OPTIONS.drag_coefficient
	service.profile_drag = aero.DEFAULT_BODY_OPTIONS.profile_drag
	service.lift_multiplier = aero.DEFAULT_BODY_OPTIONS.lift_multiplier
	service.stall_angle_deg = aero.DEFAULT_BODY_OPTIONS.stall_angle_deg
	service.efficiency = aero.DEFAULT_BODY_OPTIONS.efficiency
	service.max_lift = aero.DEFAULT_BODY_OPTIONS.max_lift
	service.area_multiplier = aero.DEFAULT_BODY_OPTIONS.area_multiplier
	service.directional_drag = {}
	service.pressure_offset = {
		aero.DEFAULT_BODY_OPTIONS.pressure_offset[0],
		aero.DEFAULT_BODY_OPTIONS.pressure_offset[1],
		aero.DEFAULT_BODY_OPTIONS.pressure_offset[2],
	}
	service.incidence_deg = aero.DEFAULT_BODY_OPTIONS.incidence_deg
	service.wave_drag = aero.DEFAULT_BODY_OPTIONS.wave_drag
	service.sound_speed = aero.DEFAULT_BODY_OPTIONS.sound_speed
	service.wake_sleeping = aero.DEFAULT_BODY_OPTIONS.wake_sleeping
}

aerodynamics_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(Aerodynamics)
	service.service = Service_Init(&Aerodynamics_Class, "Aerodynamics", data_model)
	aerodynamics_apply_defaults(service)
	return &service.object
}

aerodynamics_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	classes.Object_Destroy(object)
	free(cast(^Aerodynamics)object)
}

aerodynamics_mode :: proc(value: enums.AerodynamicsMode) -> aero.Mode {
	switch value {
	case .Auto:
		return .Auto
	case .DragOnly:
		return .Drag_Only
	case .Wing:
		return .Wing
	case .Disabled:
		return .Disabled
	}
	return .Auto
}

aerodynamics_atmosphere :: proc(value: enums.AerodynamicsAtmosphere) -> aero.Atmosphere_Model {
	switch value {
	case .Legacy:
		return .Legacy
	case .Standard:
		return .Standard
	}
	return .Standard
}

aerodynamics_normal_axis :: proc(value: enums.AerodynamicsNormalAxis) -> aero.Normal_Axis {
	switch value {
	case .Auto:
		return .Auto
	case .X:
		return .X
	case .Y:
		return .Y
	case .Z:
		return .Z
	}
	return .Auto
}

Aerodynamics_Settings :: proc(service: ^Aerodynamics, workspace: ^Workspace) -> aero.Settings {
	settings := aero.DEFAULT_SETTINGS
	settings.atmosphere = aerodynamics_atmosphere(service.atmosphere)
	settings.density = service.density
	settings.meters_per_unit = service.meters_per_unit
	settings.reference_height = service.reference_height
	settings.density_scale_height = service.density_scale_height
	settings.wind = {
		(workspace != nil ? workspace.global_wind.x : 0) + service.wind.x,
		(workspace != nil ? workspace.global_wind.y : 0) + service.wind.y,
		(workspace != nil ? workspace.global_wind.z : 0) + service.wind.z,
	}
	settings.wind_shear = {service.wind_shear.x, service.wind_shear.y, service.wind_shear.z}
	settings.gust = {service.gust.x, service.gust.y, service.gust.z}
	settings.gust_frequency = service.gust_frequency
	settings.gust_wavelength = service.gust_wavelength
	settings.time_seconds = workspace != nil ? workspace.distributed_game_time : 0
	settings.min_speed = service.min_speed
	settings.max_speed = service.max_speed
	settings.max_force_newtons = service.max_force
	settings.max_torque_nm = service.max_torque
	settings.thin_ratio = service.thin_ratio
	settings.min_dimension = service.min_dimension
	return settings
}

Aerodynamics_Options :: proc(service: ^Aerodynamics) -> aero.Body_Options {
	options := aero.DEFAULT_BODY_OPTIONS
	options.mode = aerodynamics_mode(service.mode)
	options.normal_axis = aerodynamics_normal_axis(service.normal_axis)
	options.drag_coefficient = service.drag_coefficient
	options.profile_drag = service.profile_drag
	options.lift_multiplier = service.lift_multiplier
	options.stall_angle_deg = service.stall_angle_deg
	options.efficiency = service.efficiency
	options.max_lift = service.max_lift
	options.area_multiplier = service.area_multiplier
	options.directional_drag = {
		service.directional_drag.x,
		service.directional_drag.y,
		service.directional_drag.z,
	}
	options.pressure_offset = {
		service.pressure_offset.x,
		service.pressure_offset.y,
		service.pressure_offset.z,
	}
	options.incidence_deg = service.incidence_deg
	options.wave_drag = service.wave_drag
	options.sound_speed = service.sound_speed
	options.wake_sleeping = service.wake_sleeping
	return options
}

aerodynamics_set_f32 :: proc(
	L: ^vm.State,
	index: int,
	target: ^f32,
	label: string,
	minimum, maximum: f32,
) {
	value := f32(vm.ArgNumber(L, index))
	if !physics_finite_f32(value) {
		_ = vm.RaiseError(L, fmt.tprintf("Aerodynamics.%s must be finite", label))
		return
	}
	target^ = clamp(value, minimum, maximum)
}

aerodynamics_set_f64 :: proc(
	L: ^vm.State,
	index: int,
	target: ^f64,
	label: string,
	minimum, maximum: f64,
) {
	value := vm.ArgNumber(L, index)
	if math.is_nan(value) || math.is_inf(value) {
		_ = vm.RaiseError(L, fmt.tprintf("Aerodynamics.%s must be finite", label))
		return
	}
	target^ = clamp(value, minimum, maximum)
}

aerodynamics_set_vector :: proc(
	L: ^vm.State,
	index: int,
	target: ^datatypes.Vector3,
	label: string,
	non_negative := false,
) {
	value := datatypes.Arg_Vector3(L, index)
	if !physics_finite_f32(value.x) ||
	   !physics_finite_f32(value.y) ||
	   !physics_finite_f32(value.z) {
		_ = vm.RaiseError(L, fmt.tprintf("Aerodynamics.%s must be finite", label))
		return
	}
	if non_negative {
		value.x = max(0, value.x)
		value.y = max(0, value.y)
		value.z = max(0, value.z)
	}
	target^ = value
}

aerodynamics_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	service := cast(^Aerodynamics)object
	switch key {
	case "Enabled":
		vm.PushBoolean(L, service.enabled)
	case "Atmosphere":
		if enum_registry == nil {return false}
		_ = enums.Push_Item_By_Value(
			L,
			enum_registry,
			"AerodynamicsAtmosphere",
			i64(service.atmosphere),
		)
	case "Mode":
		if enum_registry == nil {return false}
		_ = enums.Push_Item_By_Value(L, enum_registry, "AerodynamicsMode", i64(service.mode))
	case "NormalAxis":
		if enum_registry == nil {return false}
		_ = enums.Push_Item_By_Value(
			L,
			enum_registry,
			"AerodynamicsNormalAxis",
			i64(service.normal_axis),
		)
	case "Density":
		vm.PushNumber(L, f64(service.density))
	case "MetersPerUnit":
		vm.PushNumber(L, f64(service.meters_per_unit))
	case "ReferenceHeight":
		vm.PushNumber(L, service.reference_height)
	case "DensityScaleHeight":
		vm.PushNumber(L, f64(service.density_scale_height))
	case "Wind":
		datatypes.Push_Vector3(L, service.wind)
	case "WindShear":
		datatypes.Push_Vector3(L, service.wind_shear)
	case "Gust":
		datatypes.Push_Vector3(L, service.gust)
	case "GustFrequency":
		vm.PushNumber(L, f64(service.gust_frequency))
	case "GustWavelength":
		vm.PushNumber(L, f64(service.gust_wavelength))
	case "MinSpeed":
		vm.PushNumber(L, f64(service.min_speed))
	case "MaxSpeed":
		vm.PushNumber(L, f64(service.max_speed))
	case "ThinRatio":
		vm.PushNumber(L, f64(service.thin_ratio))
	case "MinimumDimension":
		vm.PushNumber(L, f64(service.min_dimension))
	case "MaxForce":
		vm.PushNumber(L, f64(service.max_force))
	case "MaxTorque":
		vm.PushNumber(L, f64(service.max_torque))
	case "DragCoefficient":
		vm.PushNumber(L, f64(service.drag_coefficient))
	case "ProfileDrag":
		vm.PushNumber(L, f64(service.profile_drag))
	case "LiftMultiplier":
		vm.PushNumber(L, f64(service.lift_multiplier))
	case "StallAngle":
		vm.PushNumber(L, f64(service.stall_angle_deg))
	case "Efficiency":
		vm.PushNumber(L, f64(service.efficiency))
	case "MaxLift":
		vm.PushNumber(L, f64(service.max_lift))
	case "AreaMultiplier":
		vm.PushNumber(L, f64(service.area_multiplier))
	case "DirectionalDrag":
		datatypes.Push_Vector3(L, service.directional_drag)
	case "PressureOffset":
		datatypes.Push_Vector3(L, service.pressure_offset)
	case "IncidenceAngle":
		vm.PushNumber(L, f64(service.incidence_deg))
	case "WaveDrag":
		vm.PushNumber(L, f64(service.wave_drag))
	case "SoundSpeed":
		vm.PushNumber(L, f64(service.sound_speed))
	case "WakeSleeping":
		vm.PushBoolean(L, service.wake_sleeping)
	case "ResetToDefaults":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}
	return true
}

aerodynamics_set :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	service := cast(^Aerodynamics)object
	switch key {
	case "Enabled":
		service.enabled = vm.ArgBoolean(L, value_index)
	case "Atmosphere":
		if enum_registry == nil {return false}
		item := enums.Arg_Item(L, value_index, enum_registry, "AerodynamicsAtmosphere")
		if item == nil {return true}
		service.atmosphere = enums.AerodynamicsAtmosphere(item.value)
	case "Mode":
		if enum_registry == nil {return false}
		item := enums.Arg_Item(L, value_index, enum_registry, "AerodynamicsMode")
		if item == nil {return true}
		service.mode = enums.AerodynamicsMode(item.value)
	case "NormalAxis":
		if enum_registry == nil {return false}
		item := enums.Arg_Item(L, value_index, enum_registry, "AerodynamicsNormalAxis")
		if item == nil {return true}
		service.normal_axis = enums.AerodynamicsNormalAxis(item.value)
	case "Density":
		aerodynamics_set_f32(L, value_index, &service.density, "Density", 0, 100)
	case "MetersPerUnit":
		aerodynamics_set_f32(
			L,
			value_index,
			&service.meters_per_unit,
			"MetersPerUnit",
			0.001,
			1000,
		)
	case "ReferenceHeight":
		aerodynamics_set_f64(
			L,
			value_index,
			&service.reference_height,
			"ReferenceHeight",
			-1.0e7,
			1.0e7,
		)
	case "DensityScaleHeight":
		aerodynamics_set_f32(
			L,
			value_index,
			&service.density_scale_height,
			"DensityScaleHeight",
			0,
			1.0e7,
		)
	case "Wind":
		aerodynamics_set_vector(L, value_index, &service.wind, "Wind")
	case "WindShear":
		aerodynamics_set_vector(L, value_index, &service.wind_shear, "WindShear")
	case "Gust":
		aerodynamics_set_vector(L, value_index, &service.gust, "Gust")
	case "GustFrequency":
		aerodynamics_set_f32(L, value_index, &service.gust_frequency, "GustFrequency", 0, 1000)
	case "GustWavelength":
		aerodynamics_set_f32(L, value_index, &service.gust_wavelength, "GustWavelength", 0, 1.0e6)
	case "MinSpeed":
		aerodynamics_set_f32(L, value_index, &service.min_speed, "MinSpeed", 0, 1.0e6)
	case "MaxSpeed":
		aerodynamics_set_f32(L, value_index, &service.max_speed, "MaxSpeed", 0, 1.0e6)
	case "ThinRatio":
		aerodynamics_set_f32(L, value_index, &service.thin_ratio, "ThinRatio", 0.0001, 1)
	case "MinimumDimension":
		aerodynamics_set_f32(
			L,
			value_index,
			&service.min_dimension,
			"MinimumDimension",
			0.000001,
			1000,
		)
	case "MaxForce":
		aerodynamics_set_f32(L, value_index, &service.max_force, "MaxForce", 0, 1.0e12)
	case "MaxTorque":
		aerodynamics_set_f32(L, value_index, &service.max_torque, "MaxTorque", 0, 1.0e12)
	case "DragCoefficient":
		aerodynamics_set_f32(L, value_index, &service.drag_coefficient, "DragCoefficient", 0, 100)
	case "ProfileDrag":
		aerodynamics_set_f32(L, value_index, &service.profile_drag, "ProfileDrag", 0, 100)
	case "LiftMultiplier":
		aerodynamics_set_f32(L, value_index, &service.lift_multiplier, "LiftMultiplier", 0, 100)
	case "StallAngle":
		aerodynamics_set_f32(L, value_index, &service.stall_angle_deg, "StallAngle", 0.001, 89.999)
	case "Efficiency":
		aerodynamics_set_f32(L, value_index, &service.efficiency, "Efficiency", 0.001, 10)
	case "MaxLift":
		aerodynamics_set_f32(L, value_index, &service.max_lift, "MaxLift", 0, 100)
	case "AreaMultiplier":
		aerodynamics_set_f32(L, value_index, &service.area_multiplier, "AreaMultiplier", 0, 1000)
	case "DirectionalDrag":
		aerodynamics_set_vector(L, value_index, &service.directional_drag, "DirectionalDrag", true)
	case "PressureOffset":
		aerodynamics_set_vector(L, value_index, &service.pressure_offset, "PressureOffset")
	case "IncidenceAngle":
		aerodynamics_set_f32(
			L,
			value_index,
			&service.incidence_deg,
			"IncidenceAngle",
			-89.999,
			89.999,
		)
	case "WaveDrag":
		aerodynamics_set_f32(L, value_index, &service.wave_drag, "WaveDrag", 0, 100)
	case "SoundSpeed":
		aerodynamics_set_f32(L, value_index, &service.sound_speed, "SoundSpeed", 0, 1.0e6)
	case "WakeSleeping":
		service.wake_sleeping = vm.ArgBoolean(L, value_index)
	case:
		return false
	}
	return true
}

aerodynamics_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	service := cast(^Aerodynamics)object
	switch method {
	case "ResetToDefaults":
		aerodynamics_apply_defaults(service)
		return 0, true
	}
	return 0, false
}

Register_Aerodynamics_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&Aerodynamics_Class,
		aerodynamics_construct,
		aerodynamics_destroy,
		creatable = false,
		get = aerodynamics_get,
		set = aerodynamics_set,
		namecall = aerodynamics_namecall,
		properties = []string {
			"Enabled",
			"Atmosphere",
			"Density",
			"MetersPerUnit",
			"ReferenceHeight",
			"DensityScaleHeight",
			"Wind",
			"WindShear",
			"Gust",
			"GustFrequency",
			"GustWavelength",
			"MinSpeed",
			"MaxSpeed",
			"ThinRatio",
			"MinimumDimension",
			"MaxForce",
			"MaxTorque",
			"Mode",
			"NormalAxis",
			"DragCoefficient",
			"ProfileDrag",
			"LiftMultiplier",
			"StallAngle",
			"Efficiency",
			"MaxLift",
			"AreaMultiplier",
			"DirectionalDrag",
			"PressureOffset",
			"IncidenceAngle",
			"WaveDrag",
			"SoundSpeed",
			"WakeSleeping",
		},
		methods = []string{"ResetToDefaults"},
	)
}
