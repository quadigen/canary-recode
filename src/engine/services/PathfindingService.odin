package services

// wire:service global="PathfindingService"

import "core:fmt"
import "core:math"
import "core:time"

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import kineffi "../bindings"
import signals "../signals"
import vm "../vm"

PathfindingService_Class := classes.Class_Info{
	name   = "PathfindingService",
	parent = &Service_Class,
}

PathfindingService :: struct {
	using service: Service,

	// The navigation mesh is built from Workspace geometry and reused for every
	// path request. Recast is not cheap to build, and Roblox keeps a single grid
	// alive for the same reason, so the mesh is cached until the geometry it was
	// built from changes.
	nav_mesh:         kineffi.RCN_NavMeshRef,
	nav_query:        kineffi.RCN_NavQueryRef,
	nav_filter:       kineffi.RCN_FilterRef,
	built:            bool,
	agent_radius:     f32,
	agent_height:     f32,
	agent_can_jump:   bool,
	agent_can_climb:  bool,
	waypoint_spacing: f32,

	// built_fingerprint is the geometry the cached mesh was built from, so a later
	// request can tell whether Workspace still describes the same navmesh input.
	// Rebuilds are coalesced because a moving part changes the fingerprint every
	// frame, and Recast is far too slow to rebuild at that rate.
	built_fingerprint: u64,
	rebuild_interval:  time.Duration,
	last_rebuild:       time.Time,
}

// Path_Class is the class behind the Path objects PathfindingService hands back.
// Roblox exposes it as a class, and scripts can check `path:IsA("Path")`.
Path_Class := classes.Class_Info{
	name   = "Path",
	parent = &classes.Instance_Class,
}

Path_Waypoint :: struct {
	position: datatypes.Vector3,
	action:   enums.PathWaypointAction,
	label:    string,
	// on_mesh marks a waypoint that came straight from the navigation mesh
	// (the endpoints and each corner) rather than being interpolated between
	// corners. Only these are meaningful to re-test for occlusion, because an
	// interpolated point deliberately sits off the surface.
	on_mesh: bool,
}

Path :: struct {
	using object: classes.Object,

	// Agent parameters are carried from CreatePath so ComputeAsync can build a
	// navigation mesh sized for this path's agent.
	agent_radius:     f32,
	agent_height:     f32,
	agent_can_jump:   bool,
	agent_can_climb:  bool,
	waypoint_spacing: f32,

	status:    enums.PathStatus,
	waypoints: [dynamic]Path_Waypoint,

	blocked_signal:   ^signals.Signal,
	unblocked_signal: ^signals.Signal,
	// Signalling an already-computed path is meaningless, so the first
	// CheckOcclusionAsync is what turns this on.
	occlusion_reported: bool,
	blocked_index:      int,
}

// Pathfinding_Mesh_Input is an indexed triangle soup, which is the form
// Recast builds from. Vertices are world-space xyz triples.
Pathfinding_Mesh_Input :: struct {
	verts: [dynamic]f32,
	tris:  [dynamic]i32,
	// How many parts were too complex to return in full, so the build can report a
	// degraded navmesh instead of quietly shipping a hole in it.
	truncated_parts: int,
}

// PATHFINDING_TRIANGLE_CHUNK is how many triangles are asked for per part on the
// first attempt. A primitive produces at most a few dozen, so this only ever
// matters for a precise convex decomposition, and a truncated result grows it.
PATHFINDING_TRIANGLE_CHUNK :: i32(256)

// PATHFINDING_TRIANGLE_MAX_ATTEMPTS bounds the grow-and-retry loop so a shape
// that somehow never fits cannot spin forever. Four attempts reach
// 256 * 4^3 = 16384 triangles, which is far more than any single part needs.
PATHFINDING_TRIANGLE_MAX_ATTEMPTS :: int(4)

// pathfinding_append_triangles copies `triangle_count` triangles out of a
// Jolt vertex soup and into the build input.
//
// Every triangle is appended as three new vertices rather than shared with another
// face, so parts never have to agree on a common indexing scheme and the soup
// cannot be corrupted by one part shifting another's vertex base.
pathfinding_append_triangles :: proc(
	input: ^Pathfinding_Mesh_Input,
	vertices: []kineffi.JPH_Vec3,
	triangle_count: int,
) {
	base := i32(len(input.verts) / 3)

	for index in 0 ..< triangle_count * 3 {
		append(
			&input.verts,
			vertices[index].x,
			vertices[index].y,
			vertices[index].z,
		)
	}

	for index in 0 ..< triangle_count {
		corner := base + i32(index) * 3
		append(&input.tris, corner, corner + 1, corner + 2)
	}
}

// pathfinding_append_part_geometry appends one part's authoritative collision
// surface to the soup.
//
// The geometry comes from the same Jolt shape the physics engine simulates, so
// a Ball contributes a sphere, a Wedge contributes its ramp, and a precisely
// decomposed mesh contributes its hulls, instead of every part being flattened
// into a box. That matters because a box around a sphere is a ledge an agent
// can stand on that does not exist in the world.
//
// Jolt reports triangles in blocks, so the caller supplies a buffer and grows it
// when the shape does not fit. Nothing is appended until a full fit is known, so
// a retry cannot duplicate the triangles an earlier attempt already reported.
// A shape that still does not fit contributes its largest partial result and is
// counted in `truncated_parts`.
pathfinding_append_part_geometry :: proc(
	physics: ^Physics,
	part: ^classes.Part,
	input: ^Pathfinding_Mesh_Input,
) {
	if physics == nil {
		return
	}

	// The shape is reference counted and this call always returns an owned
	// reference, including on a PCD cache hit where it AddRefs. Releasing it
	// here is what keeps a rebuild from leaking a shape per part per request.
	shape := physics_shape_for_part(physics, part)
	if shape == nil {
		return
	}
	defer kineffi.JPH_Shape_Destroy(shape)

	position := datatypes.CFrame_Position(part.cframe)
	jph_position := kineffi.JPH_RVec3 {
		f64(position.x),
		f64(position.y),
		f64(position.z),
	}
	jph_rotation := physics_quaternion_from_cframe(part.cframe)

	capacity := PATHFINDING_TRIANGLE_CHUNK

	// Whatever the last attempt managed to return. A shape complex enough to exceed
	// the cap on every attempt still contributes the triangles that did fit rather
	// than vanishing from the navmesh, because a partial surface is far more useful
	// to an agent than no surface at all.
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
		pathfinding_append_triangles(
			input,
			best_vertices[:int(best_count) * 3],
			int(best_count),
		)
	}

	delete(best_vertices)
}

// pathfinding_walk_parts recursively descends `object` and appends every
// part an agent can collide with and query against. It is a file-scope proc
// rather than a closure so the recursion and the mutable output array are
// unambiguous.
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

		// This engine has no BasePart class: Part, MeshPart, and the other
		// spatial classes each derive straight from Instance, so they are
		// matched on the shared collision fields instead of a common ancestor.
		if classes.Is_A(child, "Part") || classes.Is_A(child, "MeshPart") {
			part := cast(^classes.Part)child

			// CanQuery is honoured because Roblox treats a part an agent cannot
			// query against as something it also cannot navigate over, and the
			// two flags are set independently. Height is deliberately not
			// filtered: a floor legitimately lives below the origin, and the old
			// y > 0 test silently dropped it.
			if part.can_collide && part.can_query {
				pathfinding_append_part_geometry(physics, part, input)
			}
		}

		pathfinding_walk_parts(child, physics, input)
	}
}

// pathfinding_collect_geometry walks Workspace and returns the world-space
// triangle soup for every part that contributes navigation geometry.
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

// Pathfinding_Hash is an FNV-1a accumulator over the bytes of the inputs that
// decide the navmesh geometry.
Pathfinding_Hash :: struct {
	state: u64,
}

// The FNV-1a 64 offset basis and prime.
PATHFINDING_FNV_OFFSET :: u64(0xcbf29ce484222325)
PATHFINDING_FNV_PRIME :: u64(0x100000001b3)

// pathfinding_hash_byte folds one byte into the accumulator.
pathfinding_hash_byte :: proc(hash: ^Pathfinding_Hash, value: u8) {
	hash.state ~= u64(value)
	hash.state *= PATHFINDING_FNV_PRIME
}

// pathfinding_hash_bits folds a value in as its raw byte representation, so two
// floats that differ only in a low bit are told apart. Hashing f32 as an integer
// instead would collapse -0.0 onto 0.0 and quantise tiny positions.
pathfinding_hash_raw :: proc(hash: ^Pathfinding_Hash, value: ^$T) {
	bytes := cast([^]u8)value
	for byte in bytes[:size_of(T)] {
		pathfinding_hash_byte(hash, byte)
	}
}

// pathfinding_hash_f32 and friends copy their argument into a local first.
// Odin does not allow the address of a parameter to be taken, and the copy is
// free for a four-byte value.
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
	// The length is mixed in first so "ab" + "c" cannot collide with "a" + "bc".
	length := len(value)
	pathfinding_hash_raw(hash, &length)
	for character in value {
		pathfinding_hash_byte(hash, u8(character))
	}
}

// pathfinding_hash_part folds one part's navmesh-relevant state into the hash.
//
// The Jolt shape pointer is deliberately not hashed. Primitives are built fresh
// on every call to physics_shape_for_part and released immediately afterwards, so
// their addresses are allocator noise that would report a change on every single
// request and defeat the cache entirely. The inputs that actually decide the
// extracted triangles are hashed instead: the shape enum, the size, the full
// transform, the two collision flags, and a MeshPart's mesh and fidelity.
pathfinding_hash_part :: proc(hash: ^Pathfinding_Hash, part: ^classes.Part) {
	// The instance pointer separates two otherwise identical parts, because two
	// Parts at the same place with the same size contribute different geometry
	// to the traversal even if the values happen to match.
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
		pathfinding_hash_raw(hash, &mesh_part.collision_fidelity)
	}
}

// pathfinding_fingerprint_geometry hashes the traversal-visible geometry of every
// part that would contribute to the soup, in the same child order the soup is
// built in.
//
// It never asks the physics service for a shape, so it is cheap enough to run on
// every path request, and it does not need the live Physics instance at all.
pathfinding_fingerprint_geometry :: proc(
	object: ^classes.Object,
	hash: ^Pathfinding_Hash,
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
				pathfinding_hash_part(hash, part)
			}
		}

		pathfinding_fingerprint_geometry(child, hash)
	}
}

// pathfinding_geometry_fingerprint returns the fingerprint of the geometry the
// navmesh would be built from right now.
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

// pathfinding_rebuild_navigation tears down and rebuilds the cached navmesh for
// the given agent dimensions. Returns true when a usable mesh was produced.
pathfinding_rebuild_navigation :: proc(
	service: ^PathfindingService,
	agent_radius: f32,
	agent_height: f32,
	agent_can_jump: bool,
) -> bool {
	if service == nil {
		return false
	}

	// Release the previous mesh first so a rebuild does not leak the old one.
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

	world := cast(^Workspace)Ensure_Service(
		service.data_model.registry,
		"Workspace",
	)

	if world == nil {
		return false
	}

	// The shape extraction goes through the Physics service because that is what
	// already owns the authoritative collision shapes and the PCD cache; building
	// a second set of shapes here would diverge from what agents actually collide
	// with.
	physics := cast(^Physics)Ensure_Service(
		service.data_model.registry,
		"Physics",
	)

	input := pathfinding_collect_geometry(world, physics)
	defer delete(input.verts)
	defer delete(input.tris)

	// A part too complex to return in full still contributes the triangles that fit,
	// so the mesh is usable but has a hole in it. That is worth saying out loud,
	// because a silently missing floor is otherwise very hard to diagnose.
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

	// Roblox expresses agent size in studs, and Recast wants world units plus a
	// climb budget. A can-jump agent gets a climb budget so steps are traversable.
	config.agentRadius = agent_radius
	config.agentHeight = agent_height
	config.agentMaxClimb = agent_can_jump ? 7.0 : 0.0
	// Recast works in world units, so one cell is one stud. A finer cell would
	// narrow the gaps between parts that an agent can slip through.
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
			// Recorded only on success, so a failed rebuild leaves the old
			// fingerprint in place and the next request retries instead of
			// treating the stale mesh as current.
			service.built_fingerprint = pathfinding_geometry_fingerprint(world)
			service.last_rebuild = time.now()

			if service.rebuild_interval <= 0 {
				service.rebuild_interval = PATHFINDING_REBUILD_INTERVAL
			}
		}
	}

	return service.built
}

// pathfinding_ensure_navigation builds the navmesh on first use, whenever the
// agent dimensions differ from the cached ones, and whenever the geometry
// fingerprint no longer matches what the cached mesh was built from.
//
// An agent change always rebuilds immediately: a mesh built for a small agent
// would let a large one through a gap, so that must never be deferred. A
// geometry change is coalesced behind a time window instead, because a moving
// part changes the fingerprint every frame and Recast cannot be rebuilt at that
// rate. The stale mesh is still used until the window elapses, which is the
// cheaper failure: an agent briefly routes around a wall that just moved.
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
		return pathfinding_rebuild_navigation(
			service,
			agent_radius,
			agent_height,
			agent_can_jump,
		)
	}

	// A mesh built for a different agent is wrong for this one, so this case is
	// never deferred: a mesh sized for a small agent would let a large one walk
	// through a gap it cannot fit through.
	agent_changed :=
		service.agent_radius != agent_radius ||
		service.agent_height != agent_height ||
		service.agent_can_jump != agent_can_jump

	if agent_changed {
		return pathfinding_rebuild_navigation(
			service,
			agent_radius,
			agent_height,
			agent_can_jump,
		)
	}

	world := cast(^Workspace)Ensure_Service(
		service.data_model.registry,
		"Workspace",
	)

	if world == nil {
		return true
	}

	if pathfinding_geometry_fingerprint(world) == service.built_fingerprint {
		return true
	}

	// The geometry moved. Rebuilding on every request would mean rebuilding every
	// frame, so the change waits out the coalescing window. Until it elapses the
	// previous mesh is kept, because a slightly stale route is far better than a
	// dropped request.
	if time.since(service.last_rebuild) < service.rebuild_interval {
		return true
	}

	return pathfinding_rebuild_navigation(
		service,
		agent_radius,
		agent_height,
		agent_can_jump,
	)
}

// pathfinding_clear_waypoints drops the previous result so a failed recompute
// never leaves a stale path behind that looks current.
pathfinding_clear_waypoints :: proc(path: ^Path) {
	for waypoint in path.waypoints {
		delete(waypoint.label)
	}
	delete(path.waypoints)
	path.waypoints = nil
}

// pathfinding_to_floats converts a Vector3 into the flat array the C wrapper
// expects.
pathfinding_to_floats :: proc(value: datatypes.Vector3) -> [3]f32 {
	return {value.x, value.y, value.z}
}

// pathfinding_compute runs a Recast query and fills the Path. Returns false when
// the service has no usable navmesh, which maps to PathStatus.NoPath.
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

	// Snap both endpoints onto the navmesh before searching. A caller passes a
	// character's feet, which is rarely exactly on a walkable surface.
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
	) != kineffi.RCN_Error_None {
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
	) != kineffi.RCN_Error_None {
		path.status = .FailFinishNotEmpty
		return false
	}

	// Either endpoint landing on nothing means there is no corridor to search, and
	// the reason differs depending on which end failed.
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

	// A corridor of a few hundred polygons is far more than a level of this size
	// needs, and bounds the allocation so a bad query cannot run away. The slice
	// is allocated at full length because the C call fills it in place, which
	// needs a real element to point at rather than an empty array.
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
		// RCN_Error_NoPath means the goal is simply unreachable; anything else is
		// a query failure, which Roblox also reports as NoPath.
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

	// Roblox always emits the destination as the final waypoint, so the straight
	// path's last corner is replaced with the exact requested finish position.
	// That keeps GetWaypoints()[#] equal to the target a caller asked for.
	last := corners[corner_count - 1]
	final_position := datatypes.Vector3 {
		f32(last.x),
		f32(last.y),
		f32(last.z),
	}

	spacing := path.waypoint_spacing
	if spacing < 1.0 {
		spacing = 1.0
	}

	previous := datatypes.Vector3 {
		f32(snapped_start_pos[0]),
		f32(snapped_start_pos[1]),
		f32(snapped_start_pos[2]),
	}

	// The first waypoint is the requested start, again so a caller walking its
	// own waypoint list starts exactly where it asked to.
	append(
		&path.waypoints,
		Path_Waypoint {
			position = start,
			action = .Walk,
			on_mesh = true,
		},
	)

	for corner, index in corners {
		// The last corner is the destination and is appended below, so the loop
		// stops before it to avoid duplicating the final waypoint.
		if i32(index) >= corner_count - 1 {
			break
		}

		current := datatypes.Vector3 {
			f32(corners[index].x),
			f32(corners[index].y),
			f32(corners[index].z),
		}

		// Walk the straight segment in fixed-size steps, emitting a waypoint every
		// `spacing` studs the way Roblox does, so a follower advances smoothly
		// rather than teleporting between corners.
		distance := datatypes.Vec3_Magnitude(datatypes.Vec3_Subtract(current, previous))

		if distance <= spacing || distance <= 0.0001 {
			continue
		}

		steps := i32(math.floor(f64(distance) / f64(spacing)))
		if steps <= 0 {
			continue
		}

		for step in 1..=steps {
			t := f32(step) * spacing / distance
			interpolated := datatypes.Vector3 {
				previous.x + (current.x - previous.x) * t,
				previous.y + (current.y - previous.y) * t,
				previous.z + (current.z - previous.z) * t,
			}

			// A step up between waypoints is what Roblox reports as a Jump action,
			// and it is the signal a follower uses to leave the ground.
			action := enums.PathWaypointAction.Walk
			if interpolated.y - previous.y > PATHFINDING_JUMP_THRESHOLD {
				action = .Jump
			}

			append(
				&path.waypoints,
				Path_Waypoint {
					position = interpolated,
					action = action,
				},
			)

			previous = interpolated
		}
	}

	append(
		&path.waypoints,
		Path_Waypoint {
			position = final_position,
			action = .Walk,
			on_mesh = true,
		},
	)

	// Preserve the exact destination the caller asked for rather than the point
	// Detour snapped it to, which is what callers compare against.
	if len(path.waypoints) > 0 {
		waypoint := &path.waypoints[len(path.waypoints) - 1]
		waypoint.position = finish
	}

	path.status = .Success
	return true
}

// PathfindingService_For_Path resolves the service that owns a Path, which the
// navmesh is cached on.
PathfindingService_For_Path :: proc(path: ^Path) -> ^PathfindingService {
	if path == nil || path.signal_registry == nil {
		return nil
	}

	// The Path is a plain Instance with no back-reference to the service, so the
	// owning service is found through the class registry's service table.
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

// find_pathfinding_service recovers the services registry from a class registry's
// DataModel. Paths are created by the service, so this only resolves when the
// engine is running with a live DataModel.
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

// PATHFINDING_JUMP_THRESHOLD is the rise in studs between two waypoints that
// Roblox reports as a Jump action. Agents standing on a step this size need to
// leave the ground, so anything smaller is a plain walk.
PATHFINDING_JUMP_THRESHOLD :: f32(1.0)

// PATHFINDING_REBUILD_INTERVAL is how long a geometry change waits before the
// navmesh is rebuilt. A moving part changes the fingerprint every frame, and a
// Recast build costs far more than a path query, so the changes are coalesced.
PATHFINDING_REBUILD_INTERVAL :: time.Duration(500 * time.Millisecond)

// PATHFINDING_MAX_DISTANCE_LIMIT is the ceiling the deprecated raw-path methods
// enforce. Roblox raises an error past 512 studs.
PATHFINDING_MAX_DISTANCE_LIMIT :: f64(512.0)

// The documented CreatePath defaults, used when no agent table is supplied.
PATHFINDING_DEFAULT_AGENT_RADIUS     :: f32(2.0)
PATHFINDING_DEFAULT_AGENT_HEIGHT     :: f32(5.0)
PATHFINDING_DEFAULT_AGENT_CAN_JUMP   :: bool(true)
PATHFINDING_DEFAULT_AGENT_CAN_CLIMB  :: bool(false)
PATHFINDING_DEFAULT_WAYPOINT_SPACING :: f32(4.0)

// pathfinding_read_agent_params fills `path` with the documented CreatePath
// defaults, then applies any keys present in the agent table. Unknown keys are
// ignored, which is how Roblox treats them.
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

// path_ensure_signals lazily creates a Path's event signals, which are only
// needed once a script connects to them.
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

// path_signal_state resolves the Luau state used to fire a Path's events.
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

// pathfinding_create_path pushes a fresh Path onto the stack. Push_New leaves the
// new Instance on the stack, so the caller only has to return it.
pathfinding_create_path :: proc(
	service: ^PathfindingService,
	L: ^vm.State,
	agent_index: int,
) -> (^Path, bool) {
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

// pathfinding_compute_path is the shared body of the async path methods: build a
// Path, compute it, and leave it on the stack for the caller to return.
pathfinding_compute_path :: proc(
	service: ^PathfindingService,
	L: ^vm.State,
	start: datatypes.Vector3,
	finish: datatypes.Vector3,
) -> (i32, bool) {
	path, ok := pathfinding_create_path(service, L, 0)
	if !ok {
		return vm.RaiseError(L, "failed to create Path"), true
	}

	path_ensure_signals(path)
	pathfinding_compute(path, start, finish)
	return 1, true
}

// pathfinding_push_waypoints writes a Path's waypoints as the array of tables
// Roblox callers expect: each entry carries a Position Vector3 and an Action
// enum item.
pathfinding_push_waypoints :: proc(
	L: ^vm.State,
	enum_registry: ^enums.Registry,
	path: ^Path,
) {
	vm.NewTable(L, len(path.waypoints), 0)

	index := 1
	for waypoint in path.waypoints {
		vm.NewTable(L, 0, 3)

		datatypes.Push_Vector3(L, waypoint.position)
		vm.SetField(L, -2, "Position")

		_ = enums.Push_Item_By_Value(
			L,
			enum_registry,
			"PathWaypointAction",
			i64(waypoint.action),
		)
		vm.SetField(L, -2, "Action")

		// Roblox exposes a Label on every waypoint. This engine has no modifier
		// data to carry, so it is always nil rather than a misleading string.
		vm.PushNil(L)
		vm.SetField(L, -2, "Label")

		vm.SetArrayValue(L, -2, index)
		index += 1
	}
}

// path_check_occlusion re-runs the query from a waypoint index and reports where
// the path first becomes unreachable. Roblox returns the 1-based index of the
// first blocked waypoint, or -1 when the path is still clear.
path_check_occlusion :: proc(path: ^Path, start_index: int) -> int {
	service := PathfindingService_For_Path(path)
	if service == nil || len(path.waypoints) == 0 {
		return -1
	}

	// A caller may only start from a waypoint that exists.
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

	// Walk from the requested waypoint onward and report the first one the
	// navigation mesh can no longer reach. Interpolated filler waypoints are
	// skipped because they sit between corners by design and are not expected to
	// be on the surface.
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
		) != kineffi.RCN_Error_None ||
		   poly == kineffi.RCN_POLYREF_INVALID {
			// The waypoint itself is unreachable, which is exactly the
			// occlusion the caller asked about.
			return index + 1
		}
	}

	return -1
}

// path_get serves the Path class's property reads.
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
		_ = enums.Push_Item_By_Value(
			L,
			enum_registry,
			"PathStatus",
			i64(path.status),
		)
	case "Blocked":
		signals.Push(L, path.blocked_signal)
	case "Unblocked":
		signals.Push(L, path.unblocked_signal)
	case "ComputeAsync",
	     "GetWaypoints",
	     "GetPointCoordinates",
	     "CheckOcclusionAsync":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}

	return true
}

// path_namecall serves the Path class's methods.
path_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (i32, bool) {
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
		// The deprecated form returns bare Vector3 positions rather than
		// waypoint tables, so each entry is unwrapped to just its Position.
		vm.NewTable(L, len(path.waypoints), 0)

		index := 1
		for waypoint in path.waypoints {
			datatypes.Push_Vector3(L, waypoint.position)
			vm.SetArrayValue(L, -2, index)
			index += 1
		}
		return 1, true

	case "CheckOcclusionAsync":
		// Roblox documents this as an int, but Luau passes 1 as a float, so the
		// argument is read as a number and truncated rather than raising.
		start_index := int(vm.ArgNumber(L, 2))
		blocked := path_check_occlusion(path, start_index)

		// The first occlusion report fires Blocked; a later check that clears
		// the path fires Unblocked, matching Roblox's one-shot event semantics.
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
				signals.Signal_Fire_Arguments(
					state,
					path.unblocked_signal,
					vm.StackTop(state),
					1,
				)
				vm.Pop(state, 1)
			}
		}

		// Roblox returns a number here, and this engine's integer subtype does
		// not compare equal to a float literal, so the result is pushed as a
		// plain number to keep `result == -1` working in scripts.
		vm.PushNumber(L, f64(blocked))
		return 1, true
	}

	return 0, false
}

// path_construct builds a bare Path. Scripts never construct one directly, so the
// only Paths that exist are the ones PathfindingService hands out.
path_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	path := new(Path)
	path.object = classes.Object_Init(&Path_Class, "Path")
	path.status = .NoPath
	path.blocked_index = -1
	return &path.object
}

path_destroy :: proc(
	object: ^classes.Object,
	renderer: ^classes.Renderer_Object,
) {
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

// pathfinding_service_construct builds the service.
pathfinding_service_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(PathfindingService)
	service.service = Service_Init(
		&PathfindingService_Class,
		"PathfindingService",
		data_model,
	)
	return &service.object
}

// pathfinding_service_get serves PathfindingService property reads.
pathfinding_service_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "EmptyCutoff":
		// Deprecated in Roblox and unused by the navigation grid. The documented
		// default of 0.16 is reported so legacy code reading it still works.
		vm.PushNumber(L, 0.16)
	case "CreatePath",
	     "FindPathAsync",
	     "ComputeRawPathAsync",
	     "ComputeSmoothPathAsync":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}

	return true
}

// pathfinding_service_namecall serves PathfindingService's methods.
pathfinding_service_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (i32, bool) {
	service := cast(^PathfindingService)object

	switch method {
	case "CreatePath":
		// The agent table is optional, so index 2 may legitimately be absent.
		path, ok := pathfinding_create_path(service, L, 2)
		if !ok {
			return vm.RaiseError(L, "PathfindingService:CreatePath failed"), true
		}

		path_ensure_signals(path)
		// Push_New left the new Path on the stack already.
		return 1, true

	case "FindPathAsync":
		start := datatypes.Arg_Vector3(L, 2)
		finish := datatypes.Arg_Vector3(L, 3)
		return pathfinding_compute_path(service, L, start, finish)

	case "ComputeRawPathAsync", "ComputeSmoothPathAsync":
		start := datatypes.Arg_Vector3(L, 2)
		finish := datatypes.Arg_Vector3(L, 3)
		max_distance := vm.ArgOptionalNumber(L, 4, 0.0)

		// Roblox raises past its documented 512-stud ceiling.
		if max_distance > PATHFINDING_MAX_DISTANCE_LIMIT {
			return vm.RaiseError(
				L,
				fmt.tprintf(
					"MaxDistance must be less than or equal to %.0f",
					PATHFINDING_MAX_DISTANCE_LIMIT,
				),
			), true
		}

		return pathfinding_compute_path(service, L, start, finish)
	}

	return 0, false
}

pathfinding_service_destroy :: proc(
	object: ^classes.Object,
	renderer: ^classes.Renderer_Object,
) {
	service := cast(^PathfindingService)object

	// Recast owns native memory, so every handle has to be released when the
	// service goes away or the process leaks a whole navmesh.
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
		methods = []string{
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
		methods = []string{
			"ComputeAsync",
			"GetWaypoints",
			"GetPointCoordinates",
			"CheckOcclusionAsync",
		},
		events = []string{"Blocked", "Unblocked"},
	)
}

