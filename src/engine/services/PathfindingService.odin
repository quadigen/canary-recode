package services
// wire:service


import "core:fmt"
import "core:math"
import "core:time"

import kineffi "../bindings"
import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import signals "../signals"
import vm "../vm"

PathfindingService_Class := classes.Class_Info {
	name   = "PathfindingService",
	parent = &Service_Class,
}

PathfindingService :: struct {
	using service:     Service,
	nav_mesh:          kineffi.RCN_NavMeshRef,
	nav_query:         kineffi.RCN_NavQueryRef,
	nav_filter:        kineffi.RCN_FilterRef,
	built:             bool,
	agent_radius:      f32,
	agent_height:      f32,
	agent_can_jump:    bool,
	agent_can_climb:   bool,
	waypoint_spacing:  f32,
	built_fingerprint: u64,
	rebuild_interval:  time.Duration,
	last_rebuild:      time.Time,
}

Path_Class := classes.Class_Info {
	name   = "Path",
	parent = &classes.Instance_Class,
}

Path_Waypoint :: struct {
	position: datatypes.Vector3,
	action:   enums.PathWaypointAction,
	label:    string,
	on_mesh:  bool,
}

Path :: struct {
	using object:       classes.Object,
	agent_radius:       f32,
	agent_height:       f32,
	agent_can_jump:     bool,
	agent_can_climb:    bool,
	waypoint_spacing:   f32,
	status:             enums.PathStatus,
	waypoints:          [dynamic]Path_Waypoint,
	blocked_signal:     ^signals.Signal,
	unblocked_signal:   ^signals.Signal,
	occlusion_reported: bool,
	blocked_index:      int,
}


Pathfinding_Mesh_Input :: struct {
	verts:           [dynamic]f32,
	tris:            [dynamic]i32,
	truncated_parts: int,
}


PATHFINDING_TRIANGLE_CHUNK :: i32(256)


PATHFINDING_TRIANGLE_MAX_ATTEMPTS :: int(4)


pathfinding_append_triangles :: proc(
	input: ^Pathfinding_Mesh_Input,
	vertices: []kineffi.JPH_Vec3,
	triangle_count: int,
) {
	base := i32(len(input.verts) / 3)

	for index in 0 ..< triangle_count * 3 {
		append(&input.verts, vertices[index].x, vertices[index].y, vertices[index].z)
	}

	for index in 0 ..< triangle_count {
		corner := base + i32(index) * 3
		append(&input.tris, corner, corner + 1, corner + 2)
	}
}


pathfinding_append_part_geometry :: proc(
	physics: ^Physics,
	part: ^classes.Part,
	input: ^Pathfinding_Mesh_Input,
) {
	if physics == nil {
		return
	}


	shape := physics_shape_for_part(physics, part)
	if shape == nil {
		return
	}
	defer kineffi.JPH_Shape_Destroy(shape)

	position := datatypes.CFrame_Position(part.cframe)
	jph_position := kineffi.JPH_RVec3{f64(position.x), f64(position.y), f64(position.z)}
	jph_rotation := physics_quaternion_from_cframe(part.cframe)

	capacity := PATHFINDING_TRIANGLE_CHUNK


	best_count: i32 = 0
	best_vertices: [dynamic]kineffi.JPH_Vec3

	for attempt in 0 ..< PATHFINDING_TRIANGLE_MAX_ATTEMPTS {
		vertices := make([dynamic]kineffi.JPH_Vec3, int(capacity) * 3)

		truncated: i32 = 0
		count := kineffi.JPH_Shape_CollectTriangles(
			shape,
			&jph_position,
			&jph_rotation,
			&vertices[0],
			capacity,
			&truncated,
		)

		if truncated == 0 {
			delete(best_vertices)
			pathfinding_append_triangles(input, vertices[:int(count) * 3], int(count))
			delete(vertices)
			return
		}

		best_count = count
		delete(best_vertices)
		best_vertices = vertices
		capacity *= 4
	}

	if best_count > 0 {
		input.truncated_parts += 1
		pathfinding_append_triangles(input, best_vertices[:int(best_count) * 3], int(best_count))
	}

	delete(best_vertices)
}


pathfinding_walk_parts :: proc(
	object: ^classes.Object,
	physics: ^Physics,
	input: ^Pathfinding_Mesh_Input,
) {
	if object == nil {
		return
	}

	for child in object.children {
		if child == nil || child.destroyed {
			continue
		}


		if classes.Is_A(child, "Part") || classes.Is_A(child, "MeshPart") {
			part := cast(^classes.Part)child


			if part.can_collide && part.can_query {
				pathfinding_append_part_geometry(physics, part, input)
			}
		}

		pathfinding_walk_parts(child, physics, input)
	}
}


pathfinding_collect_geometry :: proc(
	workspace: ^Workspace,
	physics: ^Physics,
) -> Pathfinding_Mesh_Input {
	input := Pathfinding_Mesh_Input {
		verts = make([dynamic]f32, 0, 512),
		tris  = make([dynamic]i32, 0, 512),
	}

	if workspace == nil || workspace.object.destroyed {
		return input
	}

	pathfinding_walk_parts(&workspace.object, physics, &input)
	return input
}


Pathfinding_Hash :: struct {
	state: u64,
}


PATHFINDING_FNV_OFFSET :: u64(0xcbf29ce484222325)
PATHFINDING_FNV_PRIME :: u64(0x100000001b3)


pathfinding_hash_byte :: proc(hash: ^Pathfinding_Hash, value: u8) {
	hash.state ~= u64(value)
	hash.state *= PATHFINDING_FNV_PRIME
}


pathfinding_hash_raw :: proc(hash: ^Pathfinding_Hash, value: ^$T) {
	bytes := cast([^]u8)value
	for byte in bytes[:size_of(T)] {
		pathfinding_hash_byte(hash, byte)
	}
}


pathfinding_hash_f32 :: proc(hash: ^Pathfinding_Hash, value: f32) {
	local := value
	pathfinding_hash_raw(hash, &local)
}

pathfinding_hash_f64 :: proc(hash: ^Pathfinding_Hash, value: f64) {
	local := value
	pathfinding_hash_raw(hash, &local)
}

pathfinding_hash_bool :: proc(hash: ^Pathfinding_Hash, value: bool) {
	pathfinding_hash_byte(hash, value ? 1 : 0)
}

pathfinding_hash_string :: proc(hash: ^Pathfinding_Hash, value: string) {

	length := len(value)
	pathfinding_hash_raw(hash, &length)
	for character in value {
		pathfinding_hash_byte(hash, u8(character))
	}
}


pathfinding_hash_part :: proc(hash: ^Pathfinding_Hash, part: ^classes.Part) {


	pathfinding_hash_raw(hash, &part.object)

	pathfinding_hash_bool(hash, part.can_collide)
	pathfinding_hash_bool(hash, part.can_query)
	pathfinding_hash_raw(hash, &part.shape)

	pathfinding_hash_f32(hash, part.size.x)
	pathfinding_hash_f32(hash, part.size.y)
	pathfinding_hash_f32(hash, part.size.z)

	frame := part.cframe
	pathfinding_hash_f32(hash, frame.x)
	pathfinding_hash_f32(hash, frame.y)
	pathfinding_hash_f32(hash, frame.z)
	pathfinding_hash_f32(hash, frame.r00)
	pathfinding_hash_f32(hash, frame.r01)
	pathfinding_hash_f32(hash, frame.r02)
	pathfinding_hash_f32(hash, frame.r10)
	pathfinding_hash_f32(hash, frame.r11)
	pathfinding_hash_f32(hash, frame.r12)
	pathfinding_hash_f32(hash, frame.r20)
	pathfinding_hash_f32(hash, frame.r21)
	pathfinding_hash_f32(hash, frame.r22)

	if classes.Is_A(&part.object, "MeshPart") {
		mesh_part := cast(^classes.MeshPart)part
		pathfinding_hash_string(hash, mesh_part.mesh_id)
		pathfinding_hash_raw(hash, &mesh_part.mesh_index)
		pathfinding_hash_raw(hash, &mesh_part.collision_fidelity)
	}
}


pathfinding_fingerprint_geometry :: proc(object: ^classes.Object, hash: ^Pathfinding_Hash) {
	if object == nil {
		return
	}

	for child in object.children {
		if child == nil || child.destroyed {
			continue
		}

		if classes.Is_A(child, "Part") || classes.Is_A(child, "MeshPart") {
			part := cast(^classes.Part)child
			if part.can_collide && part.can_query {
				pathfinding_hash_part(hash, part)
			}
		}

		pathfinding_fingerprint_geometry(child, hash)
	}
}


pathfinding_geometry_fingerprint :: proc(workspace: ^Workspace) -> u64 {
	hash := Pathfinding_Hash {
		state = PATHFINDING_FNV_OFFSET,
	}

	if workspace == nil || workspace.object.destroyed {
		return hash.state
	}

	pathfinding_fingerprint_geometry(&workspace.object, &hash)
	return hash.state
}


pathfinding_rebuild_navigation :: proc(
	service: ^PathfindingService,
	agent_radius: f32,
	agent_height: f32,
	agent_can_jump: bool,
) -> bool {
	if service == nil {
		return false
	}


	if service.nav_query != nil {
		kineffi.RCN_FreeNavQuery(service.nav_query)
		service.nav_query = nil
	}
	if service.nav_mesh != nil {
		kineffi.RCN_FreeNavMesh(service.nav_mesh)
		service.nav_mesh = nil
	}
	if service.nav_filter != nil {
		kineffi.RCN_FreeQueryFilter(service.nav_filter)
		service.nav_filter = nil
	}

	service.built = false

	world := cast(^Workspace)Ensure_Service(service.data_model.registry, "Workspace")

	if world == nil {
		return false
	}


	physics := cast(^Physics)Ensure_Service(service.data_model.registry, "Physics")

	input := pathfinding_collect_geometry(world, physics)
	defer delete(input.verts)
	defer delete(input.tris)


	if input.truncated_parts > 0 {
		fmt.eprintf(
			"[PathfindingService] %d part(s) were too complex to tessellate in full and were added partially. Raise PATHFINDING_TRIANGLE_CHUNK or PATHFINDING_TRIANGLE_MAX_ATTEMPTS if the navmesh has holes.\n",
			input.truncated_parts,
		)
	}

	if len(input.verts) < 9 || len(input.tris) < 3 {
		return false
	}

	config: kineffi.RECAST_BuildConfig
	kineffi.RCN_DefaultBuildConfig(&config)

	config.agentRadius = agent_radius
	config.agentHeight = agent_height
	config.agentMaxClimb = agent_can_jump ? 7.0 : 0.0
	config.cellSize = 1.0
	config.cellHeight = 1.0
	config.agentMaxSlope = 60.0

	nav_mesh: kineffi.RCN_NavMeshRef
	build := kineffi.RCN_BuildNavMesh(
		&input.verts[0],
		i32(len(input.verts) / 3),
		&input.tris[0],
		i32(len(input.tris) / 3),
		&config,
		&nav_mesh,
	)

	if build == kineffi.RCN_Error_None && nav_mesh != nil {
		service.nav_mesh = nav_mesh
		service.nav_query = kineffi.RCN_CreateNavQuery(nav_mesh, 0)
		service.agent_radius = agent_radius
		service.agent_height = agent_height
		service.agent_can_jump = agent_can_jump
		service.built = service.nav_query != nil

		if service.built {


			service.built_fingerprint = pathfinding_geometry_fingerprint(world)
			service.last_rebuild = time.now()

			if service.rebuild_interval <= 0 {
				service.rebuild_interval = PATHFINDING_REBUILD_INTERVAL
			}
		}
	}

	return service.built
}


pathfinding_ensure_navigation :: proc(
	service: ^PathfindingService,
	agent_radius: f32,
	agent_height: f32,
	agent_can_jump: bool,
) -> bool {
	if service == nil {
		return false
	}

	if !service.built {
		return pathfinding_rebuild_navigation(service, agent_radius, agent_height, agent_can_jump)
	}


	agent_changed :=
		service.agent_radius != agent_radius ||
		service.agent_height != agent_height ||
		service.agent_can_jump != agent_can_jump

	if agent_changed {
		return pathfinding_rebuild_navigation(service, agent_radius, agent_height, agent_can_jump)
	}

	world := cast(^Workspace)Ensure_Service(service.data_model.registry, "Workspace")

	if world == nil {
		return true
	}

	if pathfinding_geometry_fingerprint(world) == service.built_fingerprint {
		return true
	}


	if time.since(service.last_rebuild) < service.rebuild_interval {
		return true
	}

	return pathfinding_rebuild_navigation(service, agent_radius, agent_height, agent_can_jump)
}


pathfinding_clear_waypoints :: proc(path: ^Path) {
	for waypoint in path.waypoints {
		delete(waypoint.label)
	}
	delete(path.waypoints)
	path.waypoints = nil
}


pathfinding_to_floats :: proc(value: datatypes.Vector3) -> [3]f32 {
	return {value.x, value.y, value.z}
}


pathfinding_compute :: proc(
	path: ^Path,
	start: datatypes.Vector3,
	finish: datatypes.Vector3,
) -> bool {
	pathfinding_clear_waypoints(path)
	path.occlusion_reported = false
	path.blocked_index = -1

	service := PathfindingService_For_Path(path)
	if service == nil {
		path.status = .NoPath
		return false
	}

	if !pathfinding_ensure_navigation(
		service,
		path.agent_radius,
		path.agent_height,
		path.agent_can_jump,
	) {
		path.status = .NoPath
		return false
	}

	if service.nav_filter == nil {
		filter_description: kineffi.RECAST_QueryFilter
		kineffi.RCN_DefaultQueryFilter(&filter_description)
		service.nav_filter = kineffi.RCN_CreateQueryFilter(&filter_description)
	}

	start_floats := pathfinding_to_floats(start)
	finish_floats := pathfinding_to_floats(finish)


	half: [3]f32 = {4.0, 8.0, 4.0}

	snapped_start: kineffi.RCN_PolyRef
	snapped_finish: kineffi.RCN_PolyRef
	snapped_start_pos: [3]f32
	snapped_finish_pos: [3]f32

	if kineffi.RCN_FindNearestPoly(
		   service.nav_query,
		   &start_floats[0],
		   &half[0],
		   service.nav_filter,
		   &snapped_start,
		   &snapped_start_pos[0],
	   ) !=
	   kineffi.RCN_Error_None {
		path.status = .FailStartNotEmpty
		return false
	}

	if kineffi.RCN_FindNearestPoly(
		   service.nav_query,
		   &finish_floats[0],
		   &half[0],
		   service.nav_filter,
		   &snapped_finish,
		   &snapped_finish_pos[0],
	   ) !=
	   kineffi.RCN_Error_None {
		path.status = .FailFinishNotEmpty
		return false
	}


	if snapped_start == kineffi.RCN_POLYREF_INVALID {
		path.status = .FailStartNotEmpty
		return false
	}

	if snapped_finish == kineffi.RCN_POLYREF_INVALID {
		path.status = .FailFinishNotEmpty
		return false
	}

	corridor: [dynamic]kineffi.RCN_PolyRef
	defer delete(corridor)


	capacity: i32 = 512
	corridor = make([dynamic]kineffi.RCN_PolyRef, capacity)

	corridor_count: i32 = 0
	result := kineffi.RCN_FindPath(
		service.nav_query,
		&snapped_start_pos[0],
		&snapped_finish_pos[0],
		service.nav_filter,
		&corridor[0],
		capacity,
		&corridor_count,
	)

	if corridor_count <= 0 {


		path.status = .NoPath
		_ = result
		return false
	}

	corners: [dynamic]kineffi.RECAST_PathPoint
	defer delete(corners)

	corner_capacity: i32 = 512
	corners = make([dynamic]kineffi.RECAST_PathPoint, corner_capacity)

	corner_count: i32 = 0
	kineffi.RCN_FindStraightPath(
		service.nav_query,
		&snapped_start_pos[0],
		&snapped_finish_pos[0],
		&corridor[0],
		corridor_count,
		&corners[0],
		corner_capacity,
		&corner_count,
	)

	if corner_count <= 0 {
		path.status = .NoPath
		return false
	}


	last := corners[corner_count - 1]
	final_position := datatypes.Vector3{f32(last.x), f32(last.y), f32(last.z)}

	spacing := path.waypoint_spacing
	if spacing < 1.0 {
		spacing = 1.0
	}

	previous := datatypes.Vector3 {
		f32(snapped_start_pos[0]),
		f32(snapped_start_pos[1]),
		f32(snapped_start_pos[2]),
	}


	append(&path.waypoints, Path_Waypoint{position = start, action = .Walk, on_mesh = true})

	for corner, index in corners {


		if i32(index) >= corner_count - 1 {
			break
		}

		current := datatypes.Vector3 {
			f32(corners[index].x),
			f32(corners[index].y),
			f32(corners[index].z),
		}


		distance := datatypes.Vec3_Magnitude(datatypes.Vec3_Subtract(current, previous))

		if distance <= spacing || distance <= 0.0001 {
			continue
		}

		steps := i32(math.floor(f64(distance) / f64(spacing)))
		if steps <= 0 {
			continue
		}

		for step in 1 ..= steps {
			t := f32(step) * spacing / distance
			interpolated := datatypes.Vector3 {
				previous.x + (current.x - previous.x) * t,
				previous.y + (current.y - previous.y) * t,
				previous.z + (current.z - previous.z) * t,
			}


			action := enums.PathWaypointAction.Walk
			if interpolated.y - previous.y > PATHFINDING_JUMP_THRESHOLD {
				action = .Jump
			}

			append(&path.waypoints, Path_Waypoint{position = interpolated, action = action})

			previous = interpolated
		}
	}

	append(
		&path.waypoints,
		Path_Waypoint{position = final_position, action = .Walk, on_mesh = true},
	)


	if len(path.waypoints) > 0 {
		waypoint := &path.waypoints[len(path.waypoints) - 1]
		waypoint.position = finish
	}

	path.status = .Success
	return true
}


PathfindingService_For_Path :: proc(path: ^Path) -> ^PathfindingService {
	if path == nil || path.signal_registry == nil {
		return nil
	}


	registry := path.signal_registry
	services := find_pathfinding_service(registry)
	if services == nil {
		return nil
	}

	descriptor := Find_Service(services, "PathfindingService")
	if descriptor == nil || descriptor.object == nil {
		return nil
	}

	return cast(^PathfindingService)descriptor.object
}


find_pathfinding_service :: proc(registry: ^classes.Registry) -> ^Registry {
	if registry == nil || registry.data_model == nil {
		return nil
	}

	model := cast(^DataModel)registry.data_model
	if model.registry == nil {
		return nil
	}

	return model.registry
}


PATHFINDING_JUMP_THRESHOLD :: f32(1.0)


PATHFINDING_REBUILD_INTERVAL :: time.Duration(500 * time.Millisecond)


PATHFINDING_MAX_DISTANCE_LIMIT :: f64(512.0)


PATHFINDING_DEFAULT_AGENT_RADIUS :: f32(2.0)
PATHFINDING_DEFAULT_AGENT_HEIGHT :: f32(5.0)
PATHFINDING_DEFAULT_AGENT_CAN_JUMP :: bool(true)
PATHFINDING_DEFAULT_AGENT_CAN_CLIMB :: bool(false)
PATHFINDING_DEFAULT_WAYPOINT_SPACING :: f32(4.0)


pathfinding_read_agent_params :: proc(L: ^vm.State, path: ^Path, index: int) {
	path.agent_radius = PATHFINDING_DEFAULT_AGENT_RADIUS
	path.agent_height = PATHFINDING_DEFAULT_AGENT_HEIGHT
	path.agent_can_jump = PATHFINDING_DEFAULT_AGENT_CAN_JUMP
	path.agent_can_climb = PATHFINDING_DEFAULT_AGENT_CAN_CLIMB
	path.waypoint_spacing = PATHFINDING_DEFAULT_WAYPOINT_SPACING

	if !vm.IsTable(L, index) {
		return
	}

	vm.GetField(L, index, "AgentRadius")
	if vm.IsNumber(L, -1) {
		radius := f32(vm.ArgOptionalNumber(L, -1))
		if radius > 0.0 {
			path.agent_radius = radius
		}
	}
	vm.Pop(L)

	vm.GetField(L, index, "AgentHeight")
	if vm.IsNumber(L, -1) {
		height := f32(vm.ArgOptionalNumber(L, -1))
		if height > 0.0 {
			path.agent_height = height
		}
	}
	vm.Pop(L)

	vm.GetField(L, index, "AgentCanJump")
	if vm.IsBoolean(L, -1) {
		path.agent_can_jump = vm.ArgBoolean(L, -1)
	}
	vm.Pop(L)

	vm.GetField(L, index, "AgentCanClimb")
	if vm.IsBoolean(L, -1) {
		path.agent_can_climb = vm.ArgBoolean(L, -1)
	}
	vm.Pop(L)

	vm.GetField(L, index, "WaypointSpacing")
	if vm.IsNumber(L, -1) {
		spacing := f32(vm.ArgOptionalNumber(L, -1))
		if spacing > 0.0 {
			path.waypoint_spacing = spacing
		}
	}
	vm.Pop(L)
}


path_ensure_signals :: proc(path: ^Path) {
	if path == nil || path.signal_registry == nil {
		return
	}

	registry := path.signal_registry
	if registry.signal_registry == nil {
		return
	}

	if path.blocked_signal == nil {
		path.blocked_signal = signals.Create(registry.signal_registry)
	}

	if path.unblocked_signal == nil {
		path.unblocked_signal = signals.Create(registry.signal_registry)
	}
}


path_signal_state :: proc(path: ^Path) -> ^vm.State {
	if path == nil || path.signal_registry == nil {
		return nil
	}

	registry := path.signal_registry
	if registry.signal_registry == nil {
		return nil
	}

	return registry.signal_registry.L
}


pathfinding_create_path :: proc(
	service: ^PathfindingService,
	L: ^vm.State,
	agent_index: int,
) -> (
	^Path,
	bool,
) {
	class_registry := service.signal_registry
	if class_registry == nil || class_registry.vm_state == nil {
		return nil, false
	}

	vm_state := vm.VM {
		L = L,
	}

	object, ok := classes.Push_New(class_registry, &vm_state, "Path", false)
	if !ok || object == nil {
		return nil, false
	}

	path := cast(^Path)object
	path.status = .NoPath
	path.blocked_index = -1
	pathfinding_read_agent_params(L, path, agent_index)

	return path, true
}


pathfinding_compute_path :: proc(
	service: ^PathfindingService,
	L: ^vm.State,
	start: datatypes.Vector3,
	finish: datatypes.Vector3,
) -> (
	i32,
	bool,
) {
	path, ok := pathfinding_create_path(service, L, 0)
	if !ok {
		return vm.RaiseError(L, "failed to create Path"), true
	}

	path_ensure_signals(path)
	pathfinding_compute(path, start, finish)
	return 1, true
}


pathfinding_push_waypoints :: proc(L: ^vm.State, enum_registry: ^enums.Registry, path: ^Path) {
	vm.NewTable(L, len(path.waypoints), 0)

	index := 1
	for waypoint in path.waypoints {
		vm.NewTable(L, 0, 3)

		datatypes.Push_Vector3(L, waypoint.position)
		vm.SetField(L, -2, "Position")

		_ = enums.Push_Item_By_Value(L, enum_registry, "PathWaypointAction", i64(waypoint.action))
		vm.SetField(L, -2, "Action")


		vm.PushNil(L)
		vm.SetField(L, -2, "Label")

		vm.SetArrayValue(L, -2, index)
		index += 1
	}
}


path_check_occlusion :: proc(path: ^Path, start_index: int) -> int {
	service := PathfindingService_For_Path(path)
	if service == nil || len(path.waypoints) == 0 {
		return -1
	}


	if start_index < 1 || start_index > len(path.waypoints) {
		return -1
	}

	if !pathfinding_ensure_navigation(
		service,
		path.agent_radius,
		path.agent_height,
		path.agent_can_jump,
	) {
		return start_index
	}

	if service.nav_filter == nil {
		filter_description: kineffi.RECAST_QueryFilter
		kineffi.RCN_DefaultQueryFilter(&filter_description)
		service.nav_filter = kineffi.RCN_CreateQueryFilter(&filter_description)
	}


	half: [3]f32 = {8.0, 24.0, 8.0}

	for index := start_index - 1; index < len(path.waypoints); index += 1 {
		waypoint := path.waypoints[index]
		if !waypoint.on_mesh {
			continue
		}

		target := pathfinding_to_floats(waypoint.position)

		poly: kineffi.RCN_PolyRef
		point: [3]f32

		if kineffi.RCN_FindNearestPoly(
			   service.nav_query,
			   &target[0],
			   &half[0],
			   service.nav_filter,
			   &poly,
			   &point[0],
		   ) !=
			   kineffi.RCN_Error_None ||
		   poly == kineffi.RCN_POLYREF_INVALID {


			return index + 1
		}
	}

	return -1
}


path_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	path := cast(^Path)object

	switch key {
	case "Status":
		if enum_registry == nil {
			return false
		}
		_ = enums.Push_Item_By_Value(L, enum_registry, "PathStatus", i64(path.status))
	case "Blocked":
		signals.Push(L, path.blocked_signal)
	case "Unblocked":
		signals.Push(L, path.unblocked_signal)
	case "ComputeAsync", "GetWaypoints", "GetPointCoordinates", "CheckOcclusionAsync":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}

	return true
}


path_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	path := cast(^Path)object

	switch method {
	case "ComputeAsync":
		start := datatypes.Arg_Vector3(L, 2)
		finish := datatypes.Arg_Vector3(L, 3)

		pathfinding_compute(path, start, finish)
		return 0, true

	case "GetWaypoints":
		pathfinding_push_waypoints(L, enum_registry, path)
		return 1, true

	case "GetPointCoordinates":
		vm.NewTable(L, len(path.waypoints), 0)

		index := 1
		for waypoint in path.waypoints {
			datatypes.Push_Vector3(L, waypoint.position)
			vm.SetArrayValue(L, -2, index)
			index += 1
		}
		return 1, true

	case "CheckOcclusionAsync":
		start_index := int(vm.ArgNumber(L, 2))
		blocked := path_check_occlusion(path, start_index)


		if blocked >= 0 {
			if !path.occlusion_reported {
				path.occlusion_reported = true
				path.blocked_index = blocked

				state := path_signal_state(path)
				if state != nil && path.blocked_signal != nil {
					vm.PushInteger(state, i64(blocked))
					signals.Signal_Fire_Arguments(
						state,
						path.blocked_signal,
						vm.StackTop(state),
						1,
					)
					vm.Pop(state, 1)
				}
			}
		} else if path.occlusion_reported {
			path.occlusion_reported = false
			unblocked := path.blocked_index
			path.blocked_index = -1

			state := path_signal_state(path)
			if state != nil && path.unblocked_signal != nil {
				vm.PushInteger(state, i64(unblocked))
				signals.Signal_Fire_Arguments(state, path.unblocked_signal, vm.StackTop(state), 1)
				vm.Pop(state, 1)
			}
		}

		vm.PushNumber(L, f64(blocked))
		return 1, true
	}

	return 0, false
}

path_construct :: proc(renderer: ^classes.Renderer_Object, data_model: rawptr) -> ^classes.Object {
	path := new(Path)
	path.object = classes.Object_Init(&Path_Class, "Path")
	path.status = .NoPath
	path.blocked_index = -1
	return &path.object
}

path_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	path := cast(^Path)object
	pathfinding_clear_waypoints(path)

	registry := path.signal_registry
	if registry != nil && registry.signal_registry != nil {
		signals.Destroy(path.blocked_signal)
		signals.Destroy(path.unblocked_signal)
	}

	classes.Object_Destroy(object)
	free(path)
}


pathfinding_service_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(PathfindingService)
	service.service = Service_Init(&PathfindingService_Class, "PathfindingService", data_model)
	return &service.object
}


pathfinding_service_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "EmptyCutoff":
		vm.PushNumber(L, 0.16)
	case "CreatePath", "FindPathAsync", "ComputeRawPathAsync", "ComputeSmoothPathAsync":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}

	return true
}


pathfinding_service_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	service := cast(^PathfindingService)object

	switch method {
	case "CreatePath":
		path, ok := pathfinding_create_path(service, L, 2)
		if !ok {
			return vm.RaiseError(L, "PathfindingService:CreatePath failed"), true
		}

		path_ensure_signals(path)

		return 1, true

	case "FindPathAsync":
		start := datatypes.Arg_Vector3(L, 2)
		finish := datatypes.Arg_Vector3(L, 3)
		return pathfinding_compute_path(service, L, start, finish)

	case "ComputeRawPathAsync", "ComputeSmoothPathAsync":
		start := datatypes.Arg_Vector3(L, 2)
		finish := datatypes.Arg_Vector3(L, 3)
		max_distance := vm.ArgOptionalNumber(L, 4, 0.0)


		if max_distance > PATHFINDING_MAX_DISTANCE_LIMIT {
			return vm.RaiseError(
					L,
					fmt.tprintf(
						"MaxDistance must be less than or equal to %.0f",
						PATHFINDING_MAX_DISTANCE_LIMIT,
					),
				),
				true
		}

		return pathfinding_compute_path(service, L, start, finish)
	}

	return 0, false
}

pathfinding_service_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	service := cast(^PathfindingService)object


	if service.nav_query != nil {
		kineffi.RCN_FreeNavQuery(service.nav_query)
		service.nav_query = nil
	}

	if service.nav_filter != nil {
		kineffi.RCN_FreeQueryFilter(service.nav_filter)
		service.nav_filter = nil
	}

	if service.nav_mesh != nil {
		kineffi.RCN_FreeNavMesh(service.nav_mesh)
		service.nav_mesh = nil
	}

	service.built = false

	classes.Object_Destroy(object)
	free(service)
}

Register_PathfindingService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&PathfindingService_Class,
		pathfinding_service_construct,
		pathfinding_service_destroy,
		creatable = false,
		get = pathfinding_service_get,
		namecall = pathfinding_service_namecall,
		properties = []string{"EmptyCutoff"},
		methods = []string {
			"CreatePath",
			"FindPathAsync",
			"ComputeRawPathAsync",
			"ComputeSmoothPathAsync",
		},
	)
}

Register_Path_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&Path_Class,
		path_construct,
		path_destroy,
		creatable = false,
		get = path_get,
		namecall = path_namecall,
		properties = []string{"Status"},
		methods = []string {
			"ComputeAsync",
			"GetWaypoints",
			"GetPointCoordinates",
			"CheckOcclusionAsync",
		},
		events = []string{"Blocked", "Unblocked"},
	)
}
