package classes

import kineffi "../bindings"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:math"
import "core:strings"

SoftBody_Class := Class_Info {
	name   = "SoftBody",
	parent = &Instance_Class,
}

SoftBody :: struct {
	using object:                           Object,
	mesh_id, material_variant:              string,
	mesh_content:                           datatypes.Content,
	mesh_index:                             u32,
	cframe:                                 datatypes.CFrame, // Authored pose for spawning and serialization.
	simulation_cframe:                      datatypes.CFrame,
	scale:                                  datatypes.Vector3,
	color:                                  datatypes.Color3,
	material:                               enums.Material,
	transparency:                           f32,
	settings:                               kineffi.JPH_MeshSoftBodySettings,
	shape_retention:                        f32,
	enabled, anchored:                      bool,
	mesh_dirty, settings_dirty, pose_dirty: bool,
	last_error:                             string,
	editable_version:                       u64,
	impulse:                                kineffi.JPH_Vec3,

	// Keep render vertices separate so welded particles can share UV seams.
	vertices:                               [][8]f32,
	indices:                                []u32,
	vertex_particles:                       []u32,
	rest_positions:                         [dynamic]kineffi.JPH_Vec3,
	geometry_scale:                         datatypes.Vector3,
	faces:                                  [dynamic]u32,
	positions:                              []kineffi.JPH_Vec3,
	closed_surface:                         bool,
	system:                                 kineffi.JPH_PhysicsSystemRef,
	body_id:                                kineffi.JPH_BodyID,
	anchor_body_id:                         kineffi.JPH_BodyID,
	was_active:                             bool,
	mesh:                                   ^kineffi.KineFilamentMesh,
	mesh_context:                           ^kineffi.KineFilamentContext,
	revision, mesh_revision:                u64,
}

softbody_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	body := new(SoftBody)
	body.object = Object_Init(&SoftBody_Class, "SoftBody")
	body.enabled = true
	body.mesh_dirty = true
	body.body_id = kineffi.JPH_BODY_ID_INVALID
	body.anchor_body_id = kineffi.JPH_BODY_ID_INVALID
	body.material = .SmoothPlastic
	body.cframe = datatypes.CFrame_Identity
	body.scale = {1, 1, 1}
	body.color = {1, 1, 1}
	body.settings = {
		mass              = 1,
		spring_compliance = 0.00005,
		bend_compliance   = 0.001,
		linear_damping    = 0.1,
		friction          = 0.4,
		gravity_factor    = 1,
		vertex_radius     = 0.03,
		iterations        = 8,
	}
	return &body.object
}

SoftBody_Release_Physics :: proc(body: ^SoftBody) {
	SoftBody_Release_Anchor(body)
	if body.system != nil && body.body_id != kineffi.JPH_BODY_ID_INVALID {
		kineffi.JPH_MeshSoftBody_Destroy(body.system, body.body_id)
	}
	body.system = nil
	body.body_id = kineffi.JPH_BODY_ID_INVALID
	body.was_active = false
}

SoftBody_Release_Anchor :: proc(body: ^SoftBody) {
	if body.system != nil && body.anchor_body_id != kineffi.JPH_BODY_ID_INVALID {
		interface := kineffi.JPH_PhysicsSystem_GetBodyInterface(body.system)
		kineffi.JPH_BodyInterface_RemoveAndDestroyBody(interface, body.anchor_body_id)
	}
	body.anchor_body_id = kineffi.JPH_BODY_ID_INVALID
}

SoftBody_Release_Render_Mesh :: proc(body: ^SoftBody) {
	if body.mesh != nil {
		kineffi.Kine_Filament_DestroyMesh(body.mesh_context, body.mesh)
	}
	body.mesh = nil
	body.mesh_context = nil
}

SoftBody_Clear_Geometry :: proc(body: ^SoftBody) {
	SoftBody_Release_Physics(body)
	SoftBody_Release_Render_Mesh(body)
	delete(body.vertices)
	delete(body.indices)
	delete(body.vertex_particles)
	delete(body.rest_positions)
	delete(body.faces)
	delete(body.positions)
	body.vertices, body.indices, body.vertex_particles = nil, nil, nil
	body.rest_positions, body.faces, body.positions = nil, nil, nil
	body.closed_surface = false
}

softbody_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	body := cast(^SoftBody)object
	handles_forget_softbody(object)
	SoftBody_Clear_Geometry(body)
	delete(body.mesh_id)
	delete(body.mesh_content.uri)
	delete(body.material_variant)
	Object_Destroy(object)
	free(body)
}

SoftBody_Current_CFrame :: proc(body: ^SoftBody) -> datatypes.CFrame {
	return body.system != nil && !body.pose_dirty ? body.simulation_cframe : body.cframe
}

softbody_clone :: proc(source, destination: ^Object) {
	src, dst := cast(^SoftBody)source, cast(^SoftBody)destination
	dst.mesh_id = strings.clone(src.mesh_id)
	dst.mesh_content = datatypes.Content_Clone(src.mesh_content)
	dst.material_variant = strings.clone(src.material_variant)
	dst.mesh_index, dst.cframe, dst.scale = src.mesh_index, src.cframe, src.scale
	dst.color, dst.settings, dst.enabled = src.color, src.settings, src.enabled
	dst.material, dst.transparency, dst.anchored = src.material, src.transparency, src.anchored
	dst.shape_retention = src.shape_retention
}

softbody_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatypes_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	body := cast(^SoftBody)object
	switch key {
	case "MeshId":
		vm.PushString(L, body.mesh_id)
	case "MeshIndex":
		vm.PushNumber(L, f64(body.mesh_index))
	case "MeshContent":
		datatypes.Push_Content(L, datatypes_registry, datatypes.Content_Clone(body.mesh_content))
	case "CFrame":
		datatypes.Push_CFrame(L, datatypes_registry, body.cframe)
	case "Scale":
		datatypes.Push_Vector3(L, body.scale)
	case "Color":
		datatypes.Push_Color3(L, datatypes_registry, body.color)
	case "Material":
		if enum_registry == nil {return false}
		_ = enums.Push_Item_By_Value(L, enum_registry, "Material", i64(body.material))
	case "MaterialVariant":
		vm.PushString(L, body.material_variant)
	case "Transparency":
		vm.PushNumber(L, f64(body.transparency))
	case "Enabled":
		vm.PushBoolean(L, body.enabled)
	case "Anchored":
		vm.PushBoolean(L, body.anchored)
	case "LastError":
		vm.PushString(L, body.last_error)
	case "SolverIterations":
		vm.PushNumber(L, f64(body.settings.iterations))
	case "ApplyImpulse", "GetSimulationCFrame":
		vm.PushUserdataMethod(L, key)
	case:
		field, _, _ := softbody_number(body, key)
		if field == nil {return false}
		vm.PushNumber(L, f64(field^))
	}
	return true
}

softbody_number :: proc(body: ^SoftBody, key: string) -> (^f32, f32, f32) {
	switch key {
	case "Mass":
		return &body.settings.mass, 0.001, 1e6
	case "SpringCompliance":
		return &body.settings.spring_compliance, 0, 1
	case "BendCompliance":
		return &body.settings.bend_compliance, 0, 1
	case "ShapeRetention":
		return &body.shape_retention, 0, 1
	case "Damping":
		return &body.settings.linear_damping, 0, 100
	case "Pressure":
		return &body.settings.pressure, 0, 1e6
	case "Friction":
		return &body.settings.friction, 0, 1
	case "GravityScale":
		return &body.settings.gravity_factor, 0, 10
	case "VertexRadius":
		return &body.settings.vertex_radius, 0, 10
	}
	return nil, 0, 0
}

softbody_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatypes_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	index: int,
) -> bool {
	body := cast(^SoftBody)object
	switch key {
	case "MeshId", "MaterialVariant":
		field := key == "MeshId" ? &body.mesh_id : &body.material_variant
		value := strings.clone(vm.ArgString(L, index))
		delete(field^)
		field^ = value
		if key == "MeshId" {body.mesh_dirty = true}
	case "MeshIndex":
		value := vm.ArgNumber(L, index)
		if !(value >= 0 && value <= f64(max(u32)) && value == math.floor(value)) {
			_ = vm.RaiseError(L, "SoftBody.MeshIndex must be an unsigned integer")
			return true
		}
		body.mesh_index = u32(value)
		body.mesh_dirty = true
	case "MeshContent":
		content := datatypes.Content_Clone(datatypes.Arg_Content(L, index, datatypes_registry))
		delete(body.mesh_content.uri)
		body.mesh_content = content
		body.mesh_dirty = true
	case "CFrame":
		body.cframe = datatypes.Arg_CFrame(L, index, datatypes_registry)
		body.pose_dirty = true
	case "Scale":
		scale := datatypes.Arg_Vector3(L, index)
		if !(scale.x >= 0.001 &&
			   scale.x <= 1000 &&
			   scale.y >= 0.001 &&
			   scale.y <= 1000 &&
			   scale.z >= 0.001 &&
			   scale.z <= 1000) {
			_ = vm.RaiseError(L, "SoftBody.Scale components must be between 0.001 and 1000")
			return true
		}
		if body.scale != scale {
			body.scale = scale
			body.mesh_dirty = true
		}
	case "Color":
		body.color = datatypes.Arg_Color3(L, index, datatypes_registry)
	case "Material":
		if enum_registry == nil {return false}
		item := enums.Arg_Item(L, index, enum_registry, "Material")
		if item == nil {return false}
		body.material = enums.Material(item.value)
	case "Transparency":
		value := f32(vm.ArgNumber(L, index))
		if math.is_nan(value) {return false}
		body.transparency = clamp(value, 0, 1)
	case "Anchored":
		anchored := vm.ArgBoolean(L, index)
		if body.anchored != anchored {
			body.anchored = anchored
			body.settings_dirty = true
		}
		if body.anchored {body.impulse = {}}
	case "Enabled":
		body.enabled = vm.ArgBoolean(L, index)
		if !body.enabled {body.impulse = {}}
	case "SolverIterations":
		value := vm.ArgNumber(L, index)
		if !(value >= 1 && value <= 64 && value == math.floor(value)) {
			_ = vm.RaiseError(L, "SoftBody.SolverIterations must be an integer from 1 to 64")
			return true
		}
		if body.settings.iterations != u32(value) {
			body.settings.iterations = u32(value)
			body.settings_dirty = true
		}
	case:
		field, lower, upper := softbody_number(body, key)
		if field == nil {return false}
		value := f32(vm.ArgNumber(L, index))
		if !(value >= lower && value <= upper) {
			_ = vm.RaiseError(L, "SoftBody setting is outside its supported range")
			return true
		}
		if field^ != value {
			field^ = value
			body.settings_dirty = true
		}
	}
	return true
}

softbody_namecall :: proc(
	L: ^vm.State,
	object: ^Object,
	datatypes_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	body := cast(^SoftBody)object
	if method == "GetSimulationCFrame" {
		datatypes.Push_CFrame(L, datatypes_registry, SoftBody_Current_CFrame(body))
		return 1, true
	}
	if method != "ApplyImpulse" {return 0, false}
	value := datatypes.Arg_Vector3(L, 2)
	total := kineffi.JPH_Vec3 {
		body.impulse.x + value.x,
		body.impulse.y + value.y,
		body.impulse.z + value.z,
	}
	if !(abs(total.x) <= 1e8 && abs(total.y) <= 1e8 && abs(total.z) <= 1e8) {
		return vm.RaiseError(L, "SoftBody impulse components must be finite and at most 1e8"), true
	}
	if body.enabled && !body.anchored {body.impulse = total}
	return 0, true
}

Register_SoftBody :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&SoftBody_Class,
		softbody_construct,
		softbody_destroy,
		get = softbody_get,
		set = softbody_set,
		namecall = softbody_namecall,
		clone = softbody_clone,
		properties = []string {
			"MeshId",
			"MeshIndex",
			"MeshContent",
			"CFrame",
			"Scale",
			"Color",
			"Material",
			"MaterialVariant",
			"Transparency",
			"Enabled",
			"Anchored",
			"Mass",
			"SpringCompliance",
			"BendCompliance",
			"ShapeRetention",
			"Damping",
			"Pressure",
			"Friction",
			"GravityScale",
			"VertexRadius",
			"SolverIterations",
			"LastError",
		},
		methods = []string{"ApplyImpulse", "GetSimulationCFrame"},
	)
}
