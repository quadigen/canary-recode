package services

import "core:math"
import "core:strings"
import classes "../classes"
import datatypes "../datatypes"
import jolt "../physics"
import kineffi "../bindings"

physics_finite_f32 :: proc(value: f32) -> bool {
	return value == value && value > -1.0e20 && value < 1.0e20
}

physics_valid_cframe :: proc(cf: datatypes.CFrame) -> bool {
	return physics_finite_f32(cf.x) && physics_finite_f32(cf.y) && physics_finite_f32(cf.z) &&
		physics_finite_f32(cf.r00) && physics_finite_f32(cf.r01) && physics_finite_f32(cf.r02) &&
		physics_finite_f32(cf.r10) && physics_finite_f32(cf.r11) && physics_finite_f32(cf.r12) &&
		physics_finite_f32(cf.r20) && physics_finite_f32(cf.r21) && physics_finite_f32(cf.r22)
}

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

physics_shape_for_part :: proc(
	part: ^classes.Part,
	mesh_context: ^kineffi.KineFilamentContext = nil,
) -> kineffi.JPH_ShapeRef {
	if classes.Is_A(&part.object, "MeshPart") && mesh_context != nil {
		mesh_part := cast(^classes.MeshPart)part
		if mesh_part.mesh_id != "" {
			path := mesh_part.mesh_id
			if strings.has_prefix(path, "file://") {
				path = path[len("file://"):]
			}
			c_path := strings.clone_to_cstring(path)
			defer delete(c_path)
			data := kineffi.Kine_Filament_LoadMeshDataFromPath(c_path)
			if data != nil {
				defer _ = kineffi.Kine_Filament_DestroyMeshData(data)
				vertex_count := kineffi.Kine_Filament_GetMeshDataVertexCount(data)
				index_count := kineffi.Kine_Filament_GetMeshDataIndexCount(data)
				if vertex_count > 0 && index_count >= 3 && index_count % 3 == 0 {
					positions := make([]f32, vertex_count*3)
					indices := make([]u32, index_count)
					defer delete(positions)
					defer delete(indices)
					if kineffi.Kine_Filament_CopyMeshDataPositions(data, raw_data(positions), i32(len(positions))) != 0 &&
					   kineffi.Kine_Filament_CopyMeshDataIndices(data, raw_data(indices), i32(len(indices))) != 0 {
						triangles: [dynamic]kineffi.JPH_Triangle
						defer delete(triangles)
						for index := i32(0); index < index_count; index += 3 {
							a, b, c := indices[index], indices[index+1], indices[index+2]
							if a >= u32(vertex_count) || b >= u32(vertex_count) || c >= u32(vertex_count) {
								continue
							}
							v1 := kineffi.JPH_Vec3{positions[a*3]*part.size.x, positions[a*3+1]*part.size.y, positions[a*3+2]*part.size.z}
							v2 := kineffi.JPH_Vec3{positions[b*3]*part.size.x, positions[b*3+1]*part.size.y, positions[b*3+2]*part.size.z}
							v3 := kineffi.JPH_Vec3{positions[c*3]*part.size.x, positions[c*3+1]*part.size.y, positions[c*3+2]*part.size.z}
							if !physics_finite_f32(v1.x) || !physics_finite_f32(v1.y) || !physics_finite_f32(v1.z) ||
							   !physics_finite_f32(v2.x) || !physics_finite_f32(v2.y) || !physics_finite_f32(v2.z) ||
							   !physics_finite_f32(v3.x) || !physics_finite_f32(v3.y) || !physics_finite_f32(v3.z) {
								continue
							}
							append(&triangles, kineffi.JPH_Triangle{v1 = v1, v2 = v2, v3 = v3})
						}
						if len(triangles) > 0 {
							shape := kineffi.JPH_MeshShape_Create(raw_data(triangles), u32(len(triangles)))
							if shape != nil {
								return shape
							}
						}
					}
				}
			}
		}
	}
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
	mesh_context: ^kineffi.KineFilamentContext

	if service.data_model != nil &&
	   service.data_model.registry != nil &&
	   service.data_model.registry.classes != nil &&
	   service.data_model.registry.classes.renderer != nil {
		mesh_context = service.data_model.registry.classes.renderer.Filament
	}

	shape := physics_shape_for_part(part, mesh_context)
	if shape == nil {
		return Physics_Body{}, false
	}
	defer kineffi.JPH_Shape_Destroy(shape)

	position := kineffi.JPH_RVec3{
		f64(part.cframe.x),
		f64(part.cframe.y),
		f64(part.cframe.z),
	}

	rotation := physics_quaternion_from_cframe(part.cframe)

	motion_type: kineffi.JPH_MotionType =
		part.anchored ? .Static : .Dynamic

	layer: kineffi.JPH_ObjectLayer = part.anchored ? jolt.OBJECT_LAYER_NON_MOVING : jolt.OBJECT_LAYER_MOVING

	settings := kineffi.JPH_BodyCreationSettings_Create3(
		shape,
		&position,
		&rotation,
		motion_type,
		layer,
	)

	if settings == nil {
		return Physics_Body{}, false
	}
	defer kineffi.JPH_BodyCreationSettings_Destroy(settings)

	properties := jolt.Material_Get_Properties(part.material)

	kineffi.JPH_BodyCreationSettings_SetFriction(
		settings,
		properties.friction,
	)

	kineffi.JPH_BodyCreationSettings_SetRestitution(
		settings,
		properties.restitution,
	)

	body := kineffi.JPH_BodyInterface_CreateBody(
		service.system.body_interface,
		settings,
	)

	if body == nil {
		return Physics_Body{}, false
	}

	body_id := kineffi.JPH_Body_GetID(body)

	if body_id == kineffi.JPH_BODY_ID_INVALID {
		return Physics_Body{}, false
	}

	activation: kineffi.JPH_ActivationMode =
		part.anchored ? .DontActivate : .Activate

	kineffi.JPH_BodyInterface_AddBody(
		service.system.body_interface,
		body_id,
		activation,
	)

	mesh_id := ""

	if classes.Is_A(&part.object, "MeshPart") {
		mesh_id = strings.clone(
			(cast(^classes.MeshPart)part).mesh_id,
		)
	}

	return Physics_Body{
		&part.object,
		body_id,
		part.size,
		part.shape,
		part.anchored,
		part.cframe,
		mesh_id,
	}, true
}

physics_destroy_body :: proc(service: ^Physics, body: Physics_Body) {
	if service.system.body_interface != nil && body.body_id != kineffi.JPH_BODY_ID_INVALID {
		kineffi.JPH_BodyInterface_RemoveAndDestroyBody(service.system.body_interface, body.body_id)
	}
	delete(body.mesh_id)
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
	topology_changed := false
	for i > 0 {
		i -= 1
		if !physics_contains_part(parts[:], service.bodies[i].object) {
			physics_destroy_body(service, service.bodies[i])
			ordered_remove(&service.bodies, i)
			topology_changed = true
		}
	}
	for part in parts {
		body_index := physics_find_body_index(service, &part.object)
		if body_index < 0 {
			body, ok := physics_create_body(service, part)
			if ok {
				append(&service.bodies, body)
				topology_changed = true
			}
			continue
		}
		body := &service.bodies[body_index]
		mesh_id := ""
		if classes.Is_A(&part.object, "MeshPart") {
			mesh_id = (cast(^classes.MeshPart)part).mesh_id
		}
		if body.size != part.size || body.shape != part.shape || body.anchored != part.anchored || body.mesh_id != mesh_id {
			physics_destroy_body(service, body^)
			new_body, ok := physics_create_body(service, part)
			if ok {
				body^ = new_body
			} else {
				ordered_remove(&service.bodies, body_index)
			}
			topology_changed = true
			continue
		}
		if body.last_cframe != part.cframe {
			position := kineffi.JPH_RVec3{f64(part.cframe.x), f64(part.cframe.y), f64(part.cframe.z)}
			activation: kineffi.JPH_ActivationMode = part.anchored ? .DontActivate : .Activate
			if body.last_cframe.r00 == part.cframe.r00 &&
			   body.last_cframe.r01 == part.cframe.r01 &&
			   body.last_cframe.r02 == part.cframe.r02 &&
			   body.last_cframe.r10 == part.cframe.r10 &&
			   body.last_cframe.r11 == part.cframe.r11 &&
			   body.last_cframe.r12 == part.cframe.r12 &&
			   body.last_cframe.r20 == part.cframe.r20 &&
			   body.last_cframe.r21 == part.cframe.r21 &&
			   body.last_cframe.r22 == part.cframe.r22 {
				kineffi.JPH_BodyInterface_SetPosition(
					service.system.body_interface,
					body.body_id,
					&position,
					activation,
				)
			} else {
				rotation := physics_quaternion_from_cframe(part.cframe)
				kineffi.JPH_BodyInterface_SetPositionAndRotation(
					service.system.body_interface,
					body.body_id,
					&position,
					&rotation,
					activation,
				)
			}
			body.last_cframe = part.cframe
		}
	}
	if topology_changed {
		kineffi.JPH_PhysicsSystem_OptimizeBroadPhase(service.system.handle)
	}
}
