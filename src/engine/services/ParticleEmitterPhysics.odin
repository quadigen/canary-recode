package services

import kineffi "../bindings"
import classes "../classes"

ParticleEmitter_Physics_Step :: proc(registry: ^Registry, delta_time: f32) {
	workspace := Find_Service(registry, "Workspace")
	if workspace == nil || workspace.object == nil {return}
	wind := (cast(^Workspace)workspace.object).global_wind
	physics := Find_Service(registry, "Physics")
	if physics == nil ||
	   physics.object == nil ||
	   !classes.ParticleEmitter_Has_Collisions(registry.classes) {
		classes.ParticleEmitter_Step(registry.classes, delta_time, wind)
		return
	}
	service := cast(^Physics)physics.object
	if !service.initialized {
		classes.ParticleEmitter_Step(registry.classes, delta_time, wind)
		return
	}

	Physics_Synchronize(service, workspace.object)
	excluded: [dynamic]kineffi.JPH_BodyID
	defer delete(excluded)
	for body in service.bodies {
		if body.object == nil ||
		   body.object.destroyed ||
		   body.body_id == kineffi.JPH_BODY_ID_INVALID {continue}
		if !(cast(^classes.Part)body.object).can_collide {append(&excluded, body.body_id)}
	}
	classes.ParticleEmitter_Step(
		registry.classes,
		delta_time,
		wind,
		&service.system,
		service.body_ids[:],
		excluded[:],
	)
}
