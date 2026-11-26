package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:math"

PhysicsModel_Class := Class_Info {
	name   = "PhysicsModel",
	parent = &Model_Class,
}

PhysicsModel :: struct {
	using model:            Model,
	server_authoritative:   bool,
	gravity_scale:          f32,
	aerodynamics_enabled:   bool,
	drag_multiplier:        f32,
	lift_multiplier:        f32,
	max_linear_velocity:    f32,
	network_update_rate:    f32,
	replicate_velocity:     bool,
	interpolation_enabled:  bool,
	interpolation_delay:    f32,
	max_extrapolation_time: f32,
}

PHYSICS_MODEL_PROPERTIES := [?]string {
	"ServerAuthoritative",
	"GravityScale",
	"AerodynamicsEnabled",
	"DragMultiplier",
	"LiftMultiplier",
	"MaxLinearVelocity",
	"NetworkUpdateRate",
	"ReplicateVelocity",
	"InterpolationEnabled",
	"InterpolationDelay",
	"MaxExtrapolationTime",
}

PhysicsModel_For :: proc(object: ^Object) -> ^PhysicsModel {
	for node := object; node != nil; node = node.parent {
		if node.class == &PhysicsModel_Class && !node.destroyed {
			return cast(^PhysicsModel)node
		}
	}
	return nil
}

PhysicsModel_Server_Authoritative :: proc(object: ^Object) -> bool {
	model := PhysicsModel_For(object)
	return model != nil && model.server_authoritative
}

physics_model_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	model := new(PhysicsModel)
	model.model = Model_Init()
	model.object = Object_Init(&PhysicsModel_Class, "PhysicsModel")
	model.server_authoritative = true
	model.gravity_scale = 1
	model.aerodynamics_enabled = true
	model.drag_multiplier = 1
	model.lift_multiplier = 1
	model.max_linear_velocity = 500
	model.replicate_velocity = true
	model.interpolation_enabled = true
	model.interpolation_delay = -1
	model.max_extrapolation_time = 0.3
	return &model.object
}

physics_model_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^PhysicsModel)object)
}

physics_model_clone :: proc(source, destination: ^Object) {
	src, dst := cast(^PhysicsModel)source, cast(^PhysicsModel)destination
	dst.server_authoritative = src.server_authoritative
	dst.gravity_scale = src.gravity_scale
	dst.aerodynamics_enabled = src.aerodynamics_enabled
	dst.drag_multiplier = src.drag_multiplier
	dst.lift_multiplier = src.lift_multiplier
	dst.max_linear_velocity = src.max_linear_velocity
	dst.network_update_rate = src.network_update_rate
	dst.replicate_velocity = src.replicate_velocity
	dst.interpolation_enabled = src.interpolation_enabled
	dst.interpolation_delay = src.interpolation_delay
	dst.max_extrapolation_time = src.max_extrapolation_time
}

physics_model_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	model := cast(^PhysicsModel)object
	switch key {
	case "ServerAuthoritative":
		vm.PushBoolean(L, model.server_authoritative)
	case "GravityScale":
		vm.PushNumber(L, f64(model.gravity_scale))
	case "AerodynamicsEnabled":
		vm.PushBoolean(L, model.aerodynamics_enabled)
	case "DragMultiplier":
		vm.PushNumber(L, f64(model.drag_multiplier))
	case "LiftMultiplier":
		vm.PushNumber(L, f64(model.lift_multiplier))
	case "MaxLinearVelocity":
		vm.PushNumber(L, f64(model.max_linear_velocity))
	case "NetworkUpdateRate":
		vm.PushNumber(L, f64(model.network_update_rate))
	case "ReplicateVelocity":
		vm.PushBoolean(L, model.replicate_velocity)
	case "InterpolationEnabled":
		vm.PushBoolean(L, model.interpolation_enabled)
	case "InterpolationDelay":
		vm.PushNumber(L, f64(model.interpolation_delay))
	case "MaxExtrapolationTime":
		vm.PushNumber(L, f64(model.max_extrapolation_time))
	case:
		return model_get(L, object, datatype_registry, enum_registry, key)
	}
	return true
}

physics_model_set_number :: proc(L: ^vm.State, index: int, dst: ^f32, low, high: f32) {
	value := f32(vm.ArgNumber(L, index))
	if math.is_nan(value) || math.is_inf(value, 0) {
		_ = vm.RaiseError(L, "PhysicsModel settings must be finite")
		return
	}
	dst^ = clamp(value, low, high)
}

physics_model_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	index: int,
) -> bool {
	model := cast(^PhysicsModel)object
	switch key {
	case "ServerAuthoritative":
		model.server_authoritative = vm.ArgBoolean(L, index)
	case "GravityScale":
		physics_model_set_number(L, index, &model.gravity_scale, -10, 10)
	case "AerodynamicsEnabled":
		model.aerodynamics_enabled = vm.ArgBoolean(L, index)
	case "DragMultiplier":
		physics_model_set_number(L, index, &model.drag_multiplier, 0, 100)
	case "LiftMultiplier":
		physics_model_set_number(L, index, &model.lift_multiplier, 0, 100)
	case "MaxLinearVelocity":
		physics_model_set_number(L, index, &model.max_linear_velocity, 1, 10000)
	case "NetworkUpdateRate":
		physics_model_set_number(L, index, &model.network_update_rate, 0, 120)
		if model.network_update_rate >
		   0 {model.network_update_rate = max(1, model.network_update_rate)}
	case "ReplicateVelocity":
		model.replicate_velocity = vm.ArgBoolean(L, index)
	case "InterpolationEnabled":
		model.interpolation_enabled = vm.ArgBoolean(L, index)
	case "InterpolationDelay":
		physics_model_set_number(L, index, &model.interpolation_delay, -1, 1)
	case "MaxExtrapolationTime":
		physics_model_set_number(L, index, &model.max_extrapolation_time, 0, 1)
	case:
		return model_set(L, object, datatype_registry, enum_registry, key, index)
	}
	return true
}

Register_PhysicsModel :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&PhysicsModel_Class,
		physics_model_construct,
		physics_model_destroy,
		clone = physics_model_clone,
		get = physics_model_get,
		set = physics_model_set,
		namecall = model_namecall,
		properties = PHYSICS_MODEL_PROPERTIES[:],
	)
}
