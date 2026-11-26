package native_api

import classes "../classes"
import datatypes "../datatypes"
import odin_runtime "base:runtime"
import "core:math"

sdk_valid_vector :: proc(v: SDK_Vector3) -> bool {
	return(
		!math.is_nan(v.x) &&
		!math.is_inf(v.x) &&
		!math.is_nan(v.y) &&
		!math.is_inf(v.y) &&
		!math.is_nan(v.z) &&
		!math.is_inf(v.z) \
	)
}

sdk_physics_part :: proc(ctx: ^Context, handle: u64) -> ^classes.Object {
	object := resolve_handle(ctx, handle)
	if object == nil || !classes.Is_A(object, "Part") {return nil}
	return object
}

@(export)
Kinemium_PhysicsGetLinearVelocity :: proc "c" (
	ctx: ^Context,
	part_handle: u64,
	output: ^SDK_Vector3,
) -> bool {
	context = odin_runtime.default_context()
	object := sdk_physics_part(ctx, part_handle)
	if object == nil || output == nil {return false}
	velocity := classes.Part_Linear_Velocity(ctx.classes, object)
	output^ = {velocity.x, velocity.y, velocity.z}
	return true
}

@(export)
Kinemium_PhysicsSetLinearVelocity :: proc "c" (
	ctx: ^Context,
	part_handle: u64,
	velocity: SDK_Vector3,
) -> bool {
	context = odin_runtime.default_context()
	object := sdk_physics_part(ctx, part_handle)
	if object == nil || !sdk_valid_vector(velocity) {return false}
	return sdk_property_set(ctx, object, "AssemblyLinearVelocity", .Vector3, vector = velocity)
}

@(export)
Kinemium_PhysicsGetAngularVelocity :: proc "c" (
	ctx: ^Context,
	part_handle: u64,
	output: ^SDK_Vector3,
) -> bool {
	context = odin_runtime.default_context()
	object := sdk_physics_part(ctx, part_handle)
	if object == nil || output == nil {return false}
	velocity := classes.Part_Angular_Velocity(ctx.classes, object)
	output^ = {velocity.x, velocity.y, velocity.z}
	return true
}

@(export)
Kinemium_PhysicsSetAngularVelocity :: proc "c" (
	ctx: ^Context,
	part_handle: u64,
	velocity: SDK_Vector3,
) -> bool {
	context = odin_runtime.default_context()
	object := sdk_physics_part(ctx, part_handle)
	if object == nil || !sdk_valid_vector(velocity) {return false}
	return sdk_property_set(ctx, object, "AssemblyAngularVelocity", .Vector3, vector = velocity)
}

@(export)
Kinemium_PhysicsGetPartMass :: proc "c" (ctx: ^Context, part_handle: u64, output: ^f64) -> bool {
	context = odin_runtime.default_context()
	object := sdk_physics_part(ctx, part_handle)
	if object == nil || output == nil {return false}
	registry := object.signal_registry
	if registry == nil || registry.part_body.get_mass == nil {return false}
	output^ = registry.part_body.get_mass(registry.part_body_ctx, object)
	return true
}

@(export)
Kinemium_PhysicsGetVelocityAtPosition :: proc "c" (
	ctx: ^Context,
	part_handle: u64,
	position: SDK_Vector3,
	output: ^SDK_Vector3,
) -> bool {
	context = odin_runtime.default_context()
	object := sdk_physics_part(ctx, part_handle)
	if object == nil || output == nil || !sdk_valid_vector(position) {return false}
	part := cast(^classes.Part)object
	linear := classes.Part_Linear_Velocity(ctx.classes, object)
	angular := classes.Part_Angular_Velocity(ctx.classes, object)
	offset := datatypes.Vector3 {
		position.x - part.cframe.x,
		position.y - part.cframe.y,
		position.z - part.cframe.z,
	}
	velocity := datatypes.Vec3_Add(linear, datatypes.Vec3_Cross(angular, offset))
	output^ = {velocity.x, velocity.y, velocity.z}
	return true
}

@(export)
Kinemium_PhysicsApplyImpulseAtPosition :: proc "c" (
	ctx: ^Context,
	part_handle: u64,
	impulse, position: SDK_Vector3,
) -> bool {
	context = odin_runtime.default_context()
	object := sdk_physics_part(ctx, part_handle)
	if object == nil || !sdk_valid_vector(impulse) || !sdk_valid_vector(position) {return false}
	return classes.Part_Apply_Impulse_At_Position(
		ctx.classes,
		object,
		datatypes.Vector3{impulse.x, impulse.y, impulse.z},
		datatypes.Vector3{position.x, position.y, position.z},
	)
}
