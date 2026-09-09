package services

import "core:math"
import classes "../classes"
import datatypes "../datatypes"
import jolt "../physics"
import kineffi "../bindings"

physics_quaternion_from_cframe :: proc(cf: datatypes.CFrame) -> kineffi.JPH_Quat {
	trace := cf.r00 + cf.r11 + cf.r22
	result: kineffi.JPH_Quat
	if trace > 0 {
		s := math.sqrt(trace+1.0)*2.0
		result = kineffi.JPH_Quat{(cf.r21-cf.r12)/s, (cf.r02-cf.r20)/s, (cf.r10-cf.r01)/s, 0.25*s}
	} else if cf.r00 > cf.r11 && cf.r00 > cf.r22 {
		s := math.sqrt(1.0+cf.r00-cf.r11-cf.r22)*2.0
		result = kineffi.JPH_Quat{0.25*s, (cf.r01+cf.r10)/s, (cf.r02+cf.r20)/s, (cf.r21-cf.r12)/s}
	} else if cf.r11 > cf.r22 {
		s := math.sqrt(1.0+cf.r11-cf.r00-cf.r22)*2.0
		result = kineffi.JPH_Quat{(cf.r01+cf.r10)/s, 0.25*s, (cf.r12+cf.r21)/s, (cf.r02-cf.r20)/s}
	} else {
		s := math.sqrt(1.0+cf.r22-cf.r00-cf.r11)*2.0
		result = kineffi.JPH_Quat{(cf.r02+cf.r20)/s, (cf.r12+cf.r21)/s, 0.25*s, (cf.r10-cf.r01)/s}
	}
	return result
}

physics_shape_for_part :: proc(part: ^classes.Part) -> kineffi.JPH_ShapeRef {
	half := datatypes.Vector3{max(part.size.x*0.5, 0.001), max(part.size.y*0.5, 0.001), max(part.size.z*0.5, 0.001)}
	#partial switch part.shape {
	case .Ball: return kineffi.JPH_SphereShape_Create(max(min(half.x, min(half.y, half.z)), 0.001))
	case .Cylinder: return kineffi.JPH_CylinderShape_Create(half.y, max(min(half.x, half.z), 0.001), 0)
	case:
		value := kineffi.JPH_Vec3{half.x, half.y, half.z}
		return kineffi.JPH_BoxShape_Create(&value, 0)
	}
}

physics_create_body :: proc(service: ^Physics, part: ^classes.Part) -> (Physics_Body, bool) {
	shape := physics_shape_for_part(part)
	if shape == nil { return Physics_Body{}, false }
	defer kineffi.JPH_Shape_Destroy(shape)
	position := kineffi.JPH_RVec3{f64(part.cframe.x), f64(part.cframe.y), f64(part.cframe.z)}
	rotation := physics_quaternion_from_cframe(part.cframe)
	motion_type: kineffi.JPH_MotionType = part.anchored ? .Static : .Dynamic
	layer := part.anchored ? jolt.OBJECT_LAYER_NON_MOVING : jolt.OBJECT_LAYER_MOVING
	settings := kineffi.JPH_BodyCreationSettings_Create3(shape, &position, &rotation, motion_type, layer)
	if settings == nil { return Physics_Body{}, false }
	defer kineffi.JPH_BodyCreationSettings_Destroy(settings)
	body := kineffi.JPH_BodyInterface_CreateBody(service.system.body_interface, settings)
	if body == nil { return Physics_Body{}, false }
	body_id := kineffi.JPH_Body_GetID(body)
	if body_id == kineffi.JPH_BODY_ID_INVALID { return Physics_Body{}, false }
	activation: kineffi.JPH_ActivationMode = part.anchored ? .DontActivate : .Activate
	kineffi.JPH_BodyInterface_AddBody(service.system.body_interface, body_id, activation)
	return Physics_Body{&part.object, body_id, part.size, part.shape, part.anchored, part.cframe}, true
}

physics_destroy_body :: proc(service: ^Physics, body: Physics_Body) {
	if service.system.body_interface != nil && body.body_id != kineffi.JPH_BODY_ID_INVALID {
		kineffi.JPH_BodyInterface_RemoveAndDestroyBody(service.system.body_interface, body.body_id)
	}
}

physics_collect_parts :: proc(object: ^classes.Object, parts: ^[dynamic]^classes.Part) {
	if object == nil { return }
	for child in object.children {
		if child == nil || child.destroyed { continue }
		if classes.Is_A(child, "Part") { append(parts, cast(^classes.Part)child) }
		physics_collect_parts(child, parts)
	}
}

physics_contains_part :: proc(parts: []^classes.Part, object: ^classes.Object) -> bool {
	for part in parts { if &part.object == object { return true } }
	return false
}

physics_find_body_index :: proc(service: ^Physics, object: ^classes.Object) -> int {
	for body, i in service.bodies { if body.object == object { return i } }
	return -1
}

Physics_Synchronize :: proc(service: ^Physics, workspace: ^classes.Object) {
	if service == nil || !service.initialized || workspace == nil { return }
	parts: [dynamic]^classes.Part
	defer delete(parts)
	physics_collect_parts(workspace, &parts)
	i := len(service.bodies)
	changed := false
	for i > 0 {
		i -= 1
		if !physics_contains_part(parts[:], service.bodies[i].object) {
			physics_destroy_body(service, service.bodies[i])
			ordered_remove(&service.bodies, i)
			changed = true
		}
	}
	for part in parts {
		body_index := physics_find_body_index(service, &part.object)
		if body_index < 0 {
			body, ok := physics_create_body(service, part)
			if ok { append(&service.bodies, body); changed = true }
			continue
		}
		body := &service.bodies[body_index]
		if body.size != part.size || body.shape != part.shape || body.anchored != part.anchored {
			physics_destroy_body(service, body^)
			new_body, ok := physics_create_body(service, part)
			if ok { body^ = new_body } else { ordered_remove(&service.bodies, body_index) }
			changed = true
			continue
		}
		if body.last_cframe != part.cframe {
			position := kineffi.JPH_RVec3{f64(part.cframe.x), f64(part.cframe.y), f64(part.cframe.z)}
			rotation := physics_quaternion_from_cframe(part.cframe)
			activation: kineffi.JPH_ActivationMode = part.anchored ? .DontActivate : .Activate
			kineffi.JPH_BodyInterface_SetPositionAndRotation(service.system.body_interface, body.body_id, &position, &rotation, activation)
			body.last_cframe = part.cframe
		}
	}
	if changed { kineffi.JPH_PhysicsSystem_OptimizeBroadPhase(service.system.handle) }
}
