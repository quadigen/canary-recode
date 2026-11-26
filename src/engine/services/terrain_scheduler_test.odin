#+build !js
package services

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import "core:fmt"
import "core:math"
import "core:sync"
import "core:testing"
import "core:time"

terrain_test_service :: proc() -> Terrain {
	return Terrain {
		chunks = make(map[Terrain_Chunk_Key]^Terrain_Chunk),
		dirty_lookup = make(map[Terrain_Chunk_Key]bool),
		dirty_tracking = false,
		voxel_size = 4,
		iso_level = 0.5,
		mesh_lod_distance = 512,
	}
}

terrain_test_release :: proc(service: ^Terrain) {
	terrain_clear(service, nil)
	delete(service.chunks)
	delete(service.dirty_queue)
	delete(service.dirty_lookup)
	delete(service.draw_items)
	delete(service.lod_keys)
	delete(service.replication_dirty)
}

@(test)
terrain_service_layout_preserves_object_pointer :: proc(t: ^testing.T) {
	service := terrain_test_service()
	defer terrain_test_release(&service)
	testing.expect(
		t,
		cast(uintptr)&service == cast(uintptr)&service.service.object,
		"Terrain embedded Object must remain at offset zero for service pointer casts",
	)
}

@(test)
terrain_scheduler_visible_priority_and_fifo_progress :: proc(t: ^testing.T) {
	service := terrain_test_service()
	defer terrain_test_release(&service)
	camera := classes.Camera_Init()
	camera.CFrame = datatypes.CFrame_New_XYZ(32, 32, 32)
	camera.viewport_width, camera.viewport_height = 1920, 1080
	renderer := classes.Renderer_Object {
		ActiveCamera = &camera,
	}
	behind := Terrain_Chunk_Key{0, 0, 4}
	visible := Terrain_Chunk_Key{0, 0, -8}
	terrain_mark_chunk_dirty(&service, behind)
	terrain_mark_chunk_dirty(&service, visible)
	key, ok := terrain_pop_priority(&service, &renderer)
	testing.expect(t, ok && key == visible, "visible chunk precedes closer offscreen chunk")
	service.frame_work.priority_pops = 15
	key, ok = terrain_pop_priority(&service, &renderer)
	testing.expect(t, ok && key == behind, "FIFO reservation gives offscreen terrain progress")
}

@(test)
terrain_scheduler_budget_defers_generation_commit :: proc(t: ^testing.T) {
	service := terrain_test_service()
	defer terrain_test_release(&service)
	job := new(Terrain_Generation)
	for x in 0 ..< 100 {append(&job.cells, Terrain_Generated_Cell{x = i32(x), occupancy = 1, material = .Rock})}
	service.generation = job
	service.frame_work.budget_ms = 0.1
	terrain_begin_frame(&service)
	time.sleep(time.Millisecond)
	testing.expect(t, !terrain_frame_has_budget(&service), "expired frame budget is exhausted")
	_ = terrain_poll_generation(&service)
	testing.expect(
		t,
		service.generation_cursor == 0 && len(service.chunks) == 0,
		"no new generation commit after budget expires",
	)
	terrain_end_frame(&service)
	_ = terrain_poll_generation(&service)
	testing.expect(
		t,
		service.generation == nil && len(service.chunks) > 0,
		"deferred generation resumes rather than losing work",
	)
}

@(test)
terrain_scheduler_obsolete_jobs_cancel_without_publishing :: proc(t: ^testing.T) {
	service := terrain_test_service()
	defer terrain_test_release(&service)
	key := Terrain_Chunk_Key{}
	terrain_mark_chunk_dirty(&service, key)
	batch := new(Terrain_Mesh_Batch)
	batch.count = 1
	batch.jobs[0].key = key
	service.mesh_batch = batch
	terrain_queue_chunk_dirty(&service, key)
	testing.expect(
		t,
		sync.atomic_load(&batch.jobs[0].cancel) == 1,
		"edited chunk cancels in-flight mesh",
	)
	terrain_build_job(&service, &batch.jobs[0])
	testing.expect(t, len(batch.jobs[0].vertex_data) == 0, "cancelled mesh does not build")
	generation := Terrain_Generation {
		width  = 1000,
		height = 1000,
	}
	sync.atomic_store(&generation.cancel, 1)
	terrain_generate_cells(&generation, &generation.cells)
	testing.expect(t, len(generation.cells) == 0, "cancelled generation does not allocate cells")

	terrain_clear(&service, nil)
	testing.expect(
		t,
		service.mesh_batch == nil && len(service.chunks) == 0,
		"clear releases stale batch",
	)
}

@(test)
terrain_scheduler_lod_hysteresis_and_pending_transition :: proc(t: ^testing.T) {
	service := terrain_test_service()
	defer terrain_test_release(&service)
	service.mesh_lod_enabled = true
	key := Terrain_Chunk_Key{0, 0, -16}
	chunk := terrain_get_or_create_chunk(&service, key)
	chunk.dirty = false
	camera := classes.Camera_Init()
	camera.CFrame = datatypes.CFrame_New_XYZ(32, 32, 32)
	renderer := classes.Renderer_Object {
		ActiveCamera = &camera,
	}
	testing.expect(
		t,
		terrain_desired_lod(&service, chunk, &camera) == 1,
		"distant chunk requests coarse render mesh",
	)
	batch := new(Terrain_Mesh_Batch)
	batch.count = 1
	batch.jobs[0].key, batch.jobs[0].lod = key, 1
	service.mesh_batch = batch
	terrain_update_lods(&service, &renderer)
	testing.expect(
		t,
		!chunk.dirty && sync.atomic_load(&batch.jobs[0].cancel) == 0,
		"pending desired LOD is not cancelled each frame",
	)
	chunk.mesh_lod = 1
	camera.CFrame = datatypes.CFrame_New_XYZ(32, 32, -500)
	testing.expect(
		t,
		terrain_desired_lod(&service, chunk, &camera) == 1,
		"hysteresis keeps coarse mesh in transition band",
	)
	camera.CFrame = datatypes.CFrame_New_XYZ(32, 32, -700)
	testing.expect(
		t,
		terrain_desired_lod(&service, chunk, &camera) == 0,
		"approaching camera restores full mesh",
	)
	service.raymarching = true
	testing.expect(
		t,
		terrain_desired_lod(&service, chunk, &camera) == 0,
		"raymarched field is never clustered",
	)
}

terrain_test_plane :: proc() -> Terrain_Mesh_Job {
	job := Terrain_Mesh_Job {
		lod = 1,
	}
	for x in 0 ..= 16 {
		for z in 0 ..= 16 {
			append(&job.vertex_data, f32(x * 4), 32, f32(z * 4), 0, 1, 0, 0, 0)
			append(&job.material_weights, 1, 0, 0, 0, 0, 0, 0, 0)
		}
	}
	for x in 0 ..< 16 {
		for z in 0 ..< 16 {
			a := u16(x * 17 + z)
			append(&job.indices, a, a + 1, a + 17, a + 1, a + 18, a + 17)
		}
	}
	return job
}

@(test)
terrain_scheduler_render_lod_preserves_borders_and_collision_data :: proc(t: ^testing.T) {
	service := terrain_test_service()
	defer terrain_test_release(&service)
	chunk := terrain_get_or_create_chunk(&service, {})
	chunk.data = new(Terrain_Chunk_Data)
	chunk.data.occupancy[0], chunk.data.present, chunk.data.solid = 1, 1, 1
	job := terrain_test_plane()
	defer delete(job.vertex_data)
	defer delete(job.material_weights)
	defer delete(job.indices)
	before := len(job.indices)
	terrain_simplify_lod(&service, &job)
	testing.expect(
		t,
		len(job.indices) < before && len(job.indices) > 0,
		"coarse mesh reduces triangle indices",
	)
	for i in job.indices {testing.expect(t, int(i) < len(job.vertex_data) / 8, "indices remain valid")}
	for x in 0 ..= 16 {
		found := false
		for i := 0; i < len(job.vertex_data); i += 8 {
			if job.vertex_data[i] == f32(x * 4) &&
			   job.vertex_data[i + 2] == 0 {found = true; break}
		}
		testing.expect(t, found, "every boundary vertex remains exact")
	}
	testing.expect(
		t,
		chunk.data.occupancy[0] == 1 && chunk.data.present == 1 && chunk.collision_dirty,
		"render LOD leaves authoritative voxel and collision state unchanged",
	)
}

@(test)
terrain_scheduler_benchmark :: proc(t: ^testing.T) {
	service := terrain_test_service()
	defer terrain_test_release(&service)
	camera := classes.Camera_Init()
	renderer := classes.Renderer_Object {
		ActiveCamera = &camera,
	}
	for x in 0 ..< 32 {for z in -16 ..< 16 {terrain_mark_chunk_dirty(&service, {x, 0, z})}}
	started := time.tick_now()
	for service.dirty_head <
	    len(service.dirty_queue) {_, _ = terrain_pop_priority(&service, &renderer)}
	elapsed := f64(time.tick_since(started)) / f64(time.Millisecond)
	testing.expect(
		t,
		service.frame_work.priority_pops == 1024,
		"all queue entries processed exactly once",
	)
	fmt.printfln(
		"TERRAIN_PRIORITY_BENCH chunks=1024 window=%d elapsed_ms=%.3f per_pop_us=%.3f",
		TERRAIN_PRIORITY_SCAN,
		elapsed,
		elapsed * 1000 / 1024,
	)
}

@(test)
terrain_scheduler_replacing_generation_stops_obsolete_worker :: proc(t: ^testing.T) {
	service := terrain_test_service()
	defer terrain_test_release(&service)
	options := Terrain_Fill_Options {
		terrain_type = .Flat,
		noise_scale  = 1,
	}
	terrain_start_generation(&service, 1000000, 0, 1000000, 64, 64, options)
	time.sleep(time.Millisecond)
	started := time.tick_now()
	terrain_start_generation(&service, 0, 0, 0, 1, 1, options)
	cancel_ms := f64(time.tick_since(started)) / f64(time.Millisecond)
	for service.generation != nil {
		_ = terrain_poll_generation(&service)
		time.sleep(time.Microsecond * 100)
	}
	testing.expect(t, len(service.chunks) > 0, "replacement generation commits")
	for key, _ in service.chunks {testing.expect(t, math.abs(key.x) < 10 && math.abs(key.z) < 10, "obsolete generated cells are not applied")}
	fmt.printfln("TERRAIN_GENERATION_CANCEL replacement_ms=%.3f", cancel_ms)
}

@(test)
terrain_scheduler_failed_upload_keeps_previous_lod :: proc(t: ^testing.T) {
	service := terrain_test_service()
	defer terrain_test_release(&service)
	chunk := terrain_get_or_create_chunk(&service, {})
	append(&chunk.meshes, nil)
	chunk.mesh_lod = 0
	job := Terrain_Mesh_Job {
		key         = {},
		lod         = 1,
		has_surface = true,
	}
	terrain_commit_job(&service, &job, nil)
	testing.expect(
		t,
		len(chunk.meshes) == 1 && chunk.mesh_lod == 0,
		"failed replacement retains previous mesh and LOD",
	)
	testing.expect(t, chunk.dirty && service.dirty_lookup[{}], "failed replacement is requeued")
	testing.expect(
		t,
		service.frame_work.upload_bytes == 0,
		"failed upload is not counted as transferred data",
	)
}
