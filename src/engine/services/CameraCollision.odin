package services

import k "../bindings"
import classes "../classes"
import datatypes "../datatypes"
import jolt "../physics"
import "core:math"

camera_resolve_obstruction :: proc(
	ctx: rawptr,
	camera: ^classes.Camera,
	target, desired: datatypes.Vector3,
) -> datatypes.Vector3 {
	model := cast(^DataModel)ctx
	physics := cast(^Physics)DataModel_Get_Service(model, "Physics")
	workspace := DataModel_Get_Service(model, "Workspace")
	if physics == nil || !physics.initialized || workspace == nil {return desired}
	displacement := datatypes.Vec3_Subtract(desired, target)
	distance := datatypes.Vec3_Magnitude(displacement)
	if distance < 0.0001 {return desired}
	Physics_Synchronize(physics, workspace)
	candidates: [dynamic]k.JPH_BodyID
	defer delete(candidates)
	for _, id in physics.terrain_bodies {if id != k.JPH_BODY_ID_INVALID {append(&candidates, id)}}
	subject := camera.CameraSubject
	if subject != nil && classes.Is_A(subject, "Humanoid") {subject = subject.parent}
	for body in physics.bodies {
		part := cast(^classes.Part)body.object
		if part == nil ||
		   part.destroyed ||
		   !part.can_collide ||
		   part.transparency >= 1 ||
		   part.material == .Water {continue}
		if subject != nil &&
		   (&part.object == subject || classes.Is_Descendant_Of(&part.object, subject)) {continue}
		append(&candidates, body.body_id)
	}
	if len(candidates) == 0 {return desired}
	width, height := classes.Camera_Effective_Viewport(camera)
	half_y := f32(math.tan(math.to_radians(f64(camera.field_of_view)) * 0.5)) * 0.1
	half_x := half_y * width / max(height, 1)
	radius := max(0.25, math.sqrt(half_x * half_x + half_y * half_y + 0.01) + 0.08)
	sphere := k.JPH_SphereShape_Create(radius)
	if sphere == nil {return desired}
	defer k.JPH_Shape_Destroy(sphere)
	hit, collided := jolt.System_Cast_Shape(
		&physics.system,
		{f64(target.x), f64(target.y), f64(target.z)},
		{displacement.x, displacement.y, displacement.z},
		sphere,
		candidates[:],
		.Include,
		distance + radius,
	)
	if !collided {return desired}
	fraction := max(0, hit.fraction - 0.05 / distance)
	return datatypes.Vec3_Add(target, datatypes.Vec3_Multiply(displacement, fraction))
}
