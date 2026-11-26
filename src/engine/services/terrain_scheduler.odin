package services

import classes "../classes"
import datatypes "../datatypes"
import "core:math"
import "core:sync"
import "core:time"

TERRAIN_DEFAULT_FRAME_BUDGET_MS :: 2.0
TERRAIN_PRIORITY_SCAN :: 256
TERRAIN_LOD_SCAN :: 64

Terrain_Frame_Work :: struct {
	budget_ms:      f64,
	started:        time.Tick,
	active:         bool,
	last_ms:        f64,
	mesh_cpu_ms:    f64,
	upload_bytes:   u64,
	cancelled_jobs: u64,
	priority_pops:  u64,
}

terrain_begin_frame :: proc(service: ^Terrain) {
	service.frame_work.started = time.tick_now()
	service.frame_work.active = true
}

terrain_end_frame :: proc(service: ^Terrain) {
	service.frame_work.last_ms =
		f64(time.tick_since(service.frame_work.started)) / f64(time.Millisecond)
	service.frame_work.active = false
}

terrain_frame_has_budget :: proc(service: ^Terrain) -> bool {
	if !service.frame_work.active {return true}
	budget := service.frame_work.budget_ms
	if budget <= 0 {budget = TERRAIN_DEFAULT_FRAME_BUDGET_MS}
	return f64(time.tick_since(service.frame_work.started)) / f64(time.Millisecond) < budget
}

terrain_camera :: proc(renderer: ^classes.Renderer_Object) -> ^classes.Camera {
	if renderer == nil || renderer.ActiveCamera == nil {return nil}
	return cast(^classes.Camera)renderer.ActiveCamera
}

terrain_chunk_distance :: proc(
	service: ^Terrain,
	key: Terrain_Chunk_Key,
	camera: ^classes.Camera,
) -> f64 {
	if camera == nil {return 0}
	span := f64(TERRAIN_CHUNK_SIZE) * f64(service.voxel_size)
	center := datatypes.Vec3_Add(
		terrain_chunk_world_origin(service, key),
		{span * 0.5, span * 0.5, span * 0.5},
	)
	delta := datatypes.Vec3_Subtract(center, datatypes.CFrame_Position(camera.CFrame))
	return datatypes.Vec3_Magnitude(delta)
}

terrain_chunk_priority :: proc(
	service: ^Terrain,
	key: Terrain_Chunk_Key,
	camera: ^classes.Camera,
) -> f64 {
	if camera == nil {return 0}
	span := f64(TERRAIN_CHUNK_SIZE) * f64(service.voxel_size)
	center := datatypes.Vec3_Add(
		terrain_chunk_world_origin(service, key),
		{span * 0.5, span * 0.5, span * 0.5},
	)
	delta := datatypes.Vec3_Subtract(center, datatypes.CFrame_Position(camera.CFrame))
	distance := datatypes.Vec3_Magnitude(delta)

	if distance < span * 2 {return distance}
	radius := span * math.sqrt(3.0) * 0.5
	depth := datatypes.Vec3_Dot(delta, datatypes.CFrame_LookVector(camera.CFrame))
	vertical := math.abs(datatypes.Vec3_Dot(delta, datatypes.CFrame_UpVector(camera.CFrame)))
	horizontal := math.abs(datatypes.Vec3_Dot(delta, datatypes.CFrame_RightVector(camera.CFrame)))
	aspect := f64(max(camera.viewport_width, 1) / max(camera.viewport_height, 1))
	tangent := math.tan(math.to_radians(f64(clamp(camera.field_of_view, 1, 179))) * 0.5)
	visible :=
		depth + radius > 0 &&
		vertical <= max(depth, 0) * tangent + radius * math.sqrt(1 + tangent * tangent) &&
		horizontal <=
			max(depth, 0) * tangent * aspect +
				radius * math.sqrt(1 + tangent * tangent * aspect * aspect)
	return distance if visible else distance + 1.0e12
}

terrain_pop_priority :: proc(
	service: ^Terrain,
	renderer: ^classes.Renderer_Object,
) -> (
	Terrain_Chunk_Key,
	bool,
) {
	if service.dirty_head >= len(service.dirty_queue) {return {}, false}
	best := service.dirty_head

	if service.frame_work.priority_pops % 16 != 15 {
		camera := terrain_camera(renderer)
		score := terrain_chunk_priority(service, service.dirty_queue[best], camera)
		for i in service.dirty_head + 1 ..< min(service.dirty_head + TERRAIN_PRIORITY_SCAN, len(service.dirty_queue)) {
			candidate := terrain_chunk_priority(service, service.dirty_queue[i], camera)
			if candidate < score {best, score = i, candidate}
		}
	}
	service.frame_work.priority_pops += 1
	key := service.dirty_queue[best]
	service.dirty_queue[best] = service.dirty_queue[service.dirty_head]
	service.dirty_head += 1
	delete_key(&service.dirty_lookup, key)
	return key, true
}

terrain_cancel_mesh_key :: proc(service: ^Terrain, key: Terrain_Chunk_Key) {
	batch := service.mesh_batch
	if batch == nil {return}
	for &job in batch.jobs[:batch.count] {
		if job.key == key {sync.atomic_store(&job.cancel, 1)}
	}
}

terrain_desired_lod :: proc(
	service: ^Terrain,
	chunk: ^Terrain_Chunk,
	camera: ^classes.Camera,
) -> u8 {
	if !service.mesh_lod_enabled ||
	   camera == nil ||
	   service.flat_shading ||
	   terrain_uses_raymarching(service) {return 0}
	distance := terrain_chunk_distance(service, chunk.key, camera)
	threshold := max(
		service.mesh_lod_distance,
		f64(TERRAIN_CHUNK_SIZE) * f64(service.voxel_size) * 3,
	)
	if chunk.mesh_lod == 0 {return 1 if distance > threshold * 1.15 else 0}
	return 0 if distance < threshold * 0.85 else 1
}

terrain_update_lods :: proc(service: ^Terrain, renderer: ^classes.Renderer_Object) {
	if len(service.lod_keys) == 0 {return}
	camera := terrain_camera(renderer)
	for _ in 0 ..< min(TERRAIN_LOD_SCAN, len(service.lod_keys)) {
		if !terrain_frame_has_budget(service) {break}
		service.lod_cursor %= len(service.lod_keys)
		key := service.lod_keys[service.lod_cursor]
		service.lod_cursor += 1
		chunk := service.chunks[key]
		if chunk == nil || chunk.dirty {continue}
		target := chunk.mesh_lod
		if batch := service.mesh_batch; batch != nil {
			for &job in batch.jobs[:batch.count] {
				if job.key == key && sync.atomic_load(&job.cancel) == 0 {target = job.lod; break}
			}
		}
		if terrain_desired_lod(service, chunk, camera) != target {
			chunk.dirty = true
			terrain_queue_chunk_dirty(service, key)
		}
	}
}

Terrain_LOD_Vertex_Key :: struct {
	x, y, z: i32,
}


terrain_simplify_lod :: proc(service: ^Terrain, job: ^Terrain_Mesh_Job) {
	if job.lod == 0 ||
	   len(job.indices) == 0 ||
	   service.flat_shading ||
	   terrain_uses_raymarching(service) {return}
	count := len(job.vertex_data) / 8
	mapping := make([]u16, count)
	defer delete(mapping)
	clusters := make(map[Terrain_LOD_Vertex_Key]u16)
	defer delete(clusters)
	vertices: [dynamic]f32
	weights: [dynamic]f32
	indices: [dynamic]u16
	span := f64(TERRAIN_CHUNK_SIZE) * f64(service.voxel_size)
	cell := f64(service.voxel_size) * 2
	margin := f64(service.voxel_size)
	for i in 0 ..< count {
		v := job.vertex_data[i * 8:][:8]
		x, y, z := f64(v[0]), f64(v[1]), f64(v[2])
		interior :=
			x > margin &&
			y > margin &&
			z > margin &&
			x < span - margin &&
			y < span - margin &&
			z < span - margin
		key := Terrain_LOD_Vertex_Key {
			i32(math.floor(x / cell)),
			i32(math.floor(y / cell)),
			i32(math.floor(z / cell)),
		}
		if interior {
			if existing, ok := clusters[key]; ok {mapping[i] = existing; continue}
		}
		index := u16(len(vertices) / 8)
		mapping[i] = index
		append(&vertices, ..v)
		append(&weights, ..job.material_weights[i * 8:][:8])
		if interior {clusters[key] = index}
	}
	for i := 0; i + 2 < len(job.indices); i += 3 {
		a, b, c :=
			mapping[job.indices[i]], mapping[job.indices[i + 1]], mapping[job.indices[i + 2]]
		if a != b && b != c && c != a {append(&indices, a, b, c)}
	}

	if len(indices) > 0 && len(indices) < len(job.indices) {
		delete(job.vertex_data); delete(job.material_weights); delete(job.indices)
		job.vertex_data, job.material_weights, job.indices = vertices, weights, indices
	} else {delete(vertices); delete(weights); delete(indices)}
}

Terrain_Process_Background :: proc(service: ^Terrain) {
	if service == nil || service.preparing {return}
	service.preparing = true
	defer service.preparing = false
	terrain_begin_frame(service)
	defer terrain_end_frame(service)
	_ = terrain_poll_generation(service)
	_ = terrain_poll_chunk_generation(service)
}
