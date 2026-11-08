package services

import kineffi "../bindings"
import classes "../classes"
import datatypes "../datatypes"
import jolt "../physics"

physics_prepare_softbodies :: proc(
	service: ^Physics,
	workspace: ^classes.Object,
	delta_time: f32,
) {
	descriptor := classes.Find_Class(service.signal_registry, "SoftBody")
	if descriptor == nil {return}
	if physics_replication_client(service.data_model) {
		for object in descriptor.instances {
			body := cast(^classes.SoftBody)object
			if body.system == service.system.handle {classes.SoftBody_Release_Physics(body)}
		}
		return
	}
	colliders: [dynamic]kineffi.JPH_SoftBodyCollider
	defer delete(colliders)
	anchors: [dynamic]kineffi.JPH_BodyID
	defer delete(anchors)
	for object in descriptor.instances {
		body := cast(^classes.SoftBody)object
		if body.destroyed || !body.enabled || !classes.Is_Descendant_Of(object, workspace) {
			classes.SoftBody_Release_Physics(body)
			body.impulse = {}
			continue
		}
		softbody_prepare_geometry(body)
		if len(body.faces) == 0 {continue}
		if !physics_valid_cframe(body.cframe) {
			classes.SoftBody_Release_Physics(body)
			body.last_error = "SoftBody.CFrame must be finite and orthonormal"
			continue
		}

		settings := body.settings
		if settings.pressure > 0 && !body.closed_surface {
			settings.pressure = 0
		}
		position := kineffi.JPH_RVec3{f64(body.cframe.x), f64(body.cframe.y), f64(body.cframe.z)}
		rotation := physics_quaternion_from_cframe(body.cframe)
		if body.system == nil {
			body.body_id = kineffi.JPH_MeshSoftBody_Create(
				service.system.handle,
				raw_data(body.rest_positions[:]),
				u32(len(body.rest_positions)),
				raw_data(body.faces[:]),
				u32(len(body.faces)),
				&position,
				&rotation,
				jolt.OBJECT_LAYER_MOVING,
				&settings,
			)
			if body.body_id == kineffi.JPH_BODY_ID_INVALID {
				body.last_error = "Jolt could not create a soft body"
				continue
			}
			body.system = service.system.handle
			body.simulation_cframe = body.cframe
			body.was_active = true
		}
		if body.anchored {
			physics_anchor_softbody(service, body, &position, &rotation)
			if body.anchor_body_id !=
			   kineffi.JPH_BODY_ID_INVALID {append(&anchors, body.anchor_body_id)}
			continue
		}
		if body.anchor_body_id != kineffi.JPH_BODY_ID_INVALID {
			classes.SoftBody_Release_Anchor(body)
			kineffi.JPH_BodyInterface_ActivateBody(service.system.body_interface, body.body_id)
		}
		if body.settings_dirty {
			kineffi.JPH_MeshSoftBody_Configure(body.system, body.body_id, &settings)
			body.was_active = true
		}
		if body.pose_dirty {
			kineffi.JPH_BodyInterface_SetPositionAndRotation(
				service.system.body_interface,
				body.body_id,
				&position,
				&rotation,
				.Activate,
			)
			body.was_active = true
		}
		body.pose_dirty, body.settings_dirty = false, false
		body.last_error =
			"Pressure requires a closed mesh with consistent winding" if settings.pressure != body.settings.pressure else ""
		if body.impulse != {} {
			kineffi.JPH_MeshSoftBody_ApplyImpulse(body.system, body.body_id, &body.impulse)
			body.impulse = {}
			body.was_active = true
		}
		if body.shape_retention > 0 && delta_time > 0 {
			kineffi.JPH_MeshSoftBody_RetainShape(
				body.system,
				body.body_id,
				body.shape_retention,
				delta_time,
			)
		}
		if delta_time > 0 {
			append(
				&colliders,
				kineffi.JPH_SoftBodyCollider{body.body_id, body.closed_surface ? 1 : 0},
			)
		}
	}
	if len(colliders) > 0 {
		rigid_bodies := service.body_ids[:]
		if len(anchors) > 0 {
			append(&anchors, ..rigid_bodies)
			rigid_bodies = anchors[:]
		}
		kineffi.JPH_MeshSoftBody_Collide(
			service.system.handle,
			raw_data(colliders[:]),
			u32(len(colliders)),
			raw_data(rigid_bodies),
			u32(len(rigid_bodies)),
			delta_time,
		)
	}
}

// A static mesh lets Jolt use the frozen, possibly deformed surface in its
// rigid-body collision solver. Keep the inactive soft body for unanchoring.
physics_anchor_softbody :: proc(
	service: ^Physics,
	body: ^classes.SoftBody,
	position: ^kineffi.JPH_RVec3,
	rotation: ^kineffi.JPH_Quat,
) {
	interface := service.system.body_interface
	if body.anchor_body_id == kineffi.JPH_BODY_ID_INVALID {
		kineffi.JPH_MeshSoftBody_Freeze(body.system, body.body_id)
	}
	if body.pose_dirty {
		kineffi.JPH_BodyInterface_SetPositionAndRotation(
			interface,
			body.body_id,
			position,
			rotation,
			.DontActivate,
		)
		body.simulation_cframe = body.cframe
		body.pose_dirty = false
		if body.anchor_body_id != kineffi.JPH_BODY_ID_INVALID {
			kineffi.JPH_BodyInterface_SetPositionAndRotation(
				interface,
				body.anchor_body_id,
				position,
				rotation,
				.DontActivate,
			)
		}
	}
	if body.anchor_body_id == kineffi.JPH_BODY_ID_INVALID {
		body.anchor_body_id = physics_create_softbody_anchor(service, body)
	}
	if body.anchor_body_id == kineffi.JPH_BODY_ID_INVALID {
		body.last_error = "Jolt could not create the anchored SoftBody collision mesh"
	} else {
		body.last_error = ""
		kineffi.JPH_BodyInterface_SetFriction(
			interface,
			body.anchor_body_id,
			body.settings.friction,
		)
	}
	body.impulse = {}
	body.was_active = false
}

physics_create_softbody_anchor :: proc(
	service: ^Physics,
	body: ^classes.SoftBody,
) -> kineffi.JPH_BodyID {
	triangles := make([dynamic]kineffi.JPH_Triangle, 0, len(body.faces) / 3)
	defer delete(triangles)
	for i := 0; i < len(body.faces); i += 3 {
		a, b, c :=
			body.positions[body.faces[i]],
			body.positions[body.faces[i + 1]],
			body.positions[body.faces[i + 2]]
		append(&triangles, kineffi.JPH_Triangle{a, b, c, 0})
		if !body.closed_surface {append(&triangles, kineffi.JPH_Triangle{a, c, b, 0})}
	}
	shape := kineffi.JPH_MeshShape_Create(raw_data(triangles[:]), u32(len(triangles)))
	if shape == nil {return kineffi.JPH_BODY_ID_INVALID}
	defer kineffi.JPH_Shape_Destroy(shape)
	frame := body.simulation_cframe
	position := kineffi.JPH_RVec3{f64(frame.x), f64(frame.y), f64(frame.z)}
	rotation := physics_quaternion_from_cframe(frame)
	settings := kineffi.JPH_BodyCreationSettings_Create3(
		shape,
		&position,
		&rotation,
		.Static,
		jolt.OBJECT_LAYER_NON_MOVING,
	)
	if settings == nil {return kineffi.JPH_BODY_ID_INVALID}
	defer kineffi.JPH_BodyCreationSettings_Destroy(settings)
	interface := service.system.body_interface
	native := kineffi.JPH_BodyInterface_CreateBody(interface, settings)
	if native == nil {return kineffi.JPH_BODY_ID_INVALID}
	id := kineffi.JPH_Body_GetID(native)
	kineffi.JPH_BodyInterface_AddBody(interface, id, .DontActivate)
	return id
}

physics_read_softbodies :: proc(service: ^Physics) {
	descriptor := classes.Find_Class(service.signal_registry, "SoftBody")
	if descriptor == nil {return}
	if physics_replication_client(service.data_model) {return}
	for object in descriptor.instances {
		body := cast(^classes.SoftBody)object
		if body.destroyed || body.system != service.system.handle {continue}
		active :=
			kineffi.JPH_BodyInterface_IsActive(service.system.body_interface, body.body_id) != 0
		if !active && !body.was_active {continue}
		// Read the final pose once when the body transitions to sleep.
		body.was_active = active
		position: kineffi.JPH_RVec3
		rotation: kineffi.JPH_Quat
		if kineffi.JPH_MeshSoftBody_Read(
			   body.system,
			   body.body_id,
			   raw_data(body.positions),
			   u32(len(body.positions)),
			   &position,
			   &rotation,
		   ) ==
		   0 {continue}
		frame := datatypes.CFrame_New_Quaternion(
			f32(position.x),
			f32(position.y),
			f32(position.z),
			rotation.x,
			rotation.y,
			rotation.z,
			rotation.w,
		)
		body.simulation_cframe = frame
		body.revision += 1
	}
}

physics_release_softbodies :: proc(service: ^Physics) {
	descriptor := classes.Find_Class(service.signal_registry, "SoftBody")
	if descriptor == nil {return}
	for object in descriptor.instances {
		body := cast(^classes.SoftBody)object
		if body.system == service.system.handle {classes.SoftBody_Release_Physics(body)}
	}
}
