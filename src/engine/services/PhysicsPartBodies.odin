package services

import kineffi "../bindings"
import classes "../classes"
import datatypes "../datatypes"

physics_hook_service :: proc(ctx: rawptr) -> ^Physics {
	registry := cast(^Registry)ctx
	if registry == nil {return nil}
	descriptor := Find_Service(registry, "Physics")
	if descriptor == nil {return nil}
	return cast(^Physics)descriptor.object
}

physics_hook_body :: proc(ctx: rawptr, object: ^classes.Object) -> (^Physics, kineffi.JPH_BodyID) {
	physics := physics_hook_service(ctx)
	if physics == nil || object == nil {return nil, kineffi.JPH_BODY_ID_INVALID}
	if !physics.initialized {return nil, kineffi.JPH_BODY_ID_INVALID}
	index := physics_find_body_index(physics, object)
	if index < 0 {return nil, kineffi.JPH_BODY_ID_INVALID}
	body := physics.bodies[index]
	if body.body_id == kineffi.JPH_BODY_ID_INVALID || body.remote {


		return nil, kineffi.JPH_BODY_ID_INVALID
	}
	return physics, body.body_id
}

physics_hook_get_linear_velocity :: proc(
	ctx: rawptr,
	object: ^classes.Object,
) -> (
	datatypes.Vector3,
	bool,
) {
	physics, body_id := physics_hook_body(ctx, object)
	if physics == nil {return datatypes.Vector3{}, false}
	velocity: kineffi.JPH_Vec3
	kineffi.JPH_BodyInterface_GetLinearVelocity(physics.system.body_interface, body_id, &velocity)
	return datatypes.Vector3{velocity.x, velocity.y, velocity.z}, true
}

physics_hook_set_linear_velocity :: proc(
	ctx: rawptr,
	object: ^classes.Object,
	value: datatypes.Vector3,
) {
	physics, body_id := physics_hook_body(ctx, object)
	if physics == nil {return}
	velocity := kineffi.JPH_Vec3{value.x, value.y, value.z}
	kineffi.JPH_BodyInterface_SetLinearVelocity(physics.system.body_interface, body_id, &velocity)


	kineffi.JPH_BodyInterface_ActivateBody(physics.system.body_interface, body_id)
}

physics_hook_get_angular_velocity :: proc(
	ctx: rawptr,
	object: ^classes.Object,
) -> (
	datatypes.Vector3,
	bool,
) {
	physics, body_id := physics_hook_body(ctx, object)
	if physics == nil {return datatypes.Vector3{}, false}
	velocity: kineffi.JPH_Vec3
	kineffi.JPH_BodyInterface_GetAngularVelocity(physics.system.body_interface, body_id, &velocity)
	return datatypes.Vector3{velocity.x, velocity.y, velocity.z}, true
}

physics_hook_set_angular_velocity :: proc(
	ctx: rawptr,
	object: ^classes.Object,
	value: datatypes.Vector3,
) {
	physics, body_id := physics_hook_body(ctx, object)
	if physics == nil {return}
	velocity := kineffi.JPH_Vec3{value.x, value.y, value.z}
	kineffi.JPH_BodyInterface_SetAngularVelocity(physics.system.body_interface, body_id, &velocity)
	kineffi.JPH_BodyInterface_ActivateBody(physics.system.body_interface, body_id)
}

physics_hook_apply_impulse :: proc(
	ctx: rawptr,
	object: ^classes.Object,
	impulse: datatypes.Vector3,
) -> bool {
	physics, body_id := physics_hook_body(ctx, object)
	if physics == nil {return false}
	value := kineffi.JPH_Vec3{impulse.x, impulse.y, impulse.z}
	kineffi.JPH_BodyInterface_AddImpulse(physics.system.body_interface, body_id, &value)
	kineffi.JPH_BodyInterface_ActivateBody(physics.system.body_interface, body_id)
	return true
}

Install_Part_Body_Access :: proc(registry: ^Registry) {
	if registry == nil || registry.classes == nil {return}
	classes.Set_Part_Body_Access(
		registry.classes,
		classes.Part_Body_Access {
			get_linear_velocity = physics_hook_get_linear_velocity,
			set_linear_velocity = physics_hook_set_linear_velocity,
			get_angular_velocity = physics_hook_get_angular_velocity,
			set_angular_velocity = physics_hook_set_angular_velocity,
			apply_impulse = physics_hook_apply_impulse,
		},
		rawptr(registry),
	)
}
