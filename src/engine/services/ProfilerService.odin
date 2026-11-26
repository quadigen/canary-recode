package services


import kineffi "../bindings"
import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import profiling "../profiling"
import vm "../vm"


ProfilerService_Class := classes.Class_Info {
	name   = "ProfilerService",
	parent = &Service_Class,
}

ProfilerService :: struct {
	using service: Service,
}

profiler_service_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(ProfilerService)
	service.service = Service_Init(&ProfilerService_Class, "ProfilerService", data_model)
	return &service.object
}

profiler_service_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	classes.Object_Destroy(object)
	free(cast(^ProfilerService)object)
}

PROFILER_FPS_WINDOW :: 30
PROFILER_HISTORY_POINTS :: 60
PROFILER_DEFAULT_COUNT :: 120

profiler_ns_ms :: #force_inline proc(ns: u64) -> f64 {
	return f64(ns) * 1e-6
}

profiler_frame_ms :: proc() -> f64 {
	return profiler_ns_ms(profiling.last_frame_delta_ns())
}

profiler_fps :: proc() -> f64 {
	avg_ns := profiling.average_frame_delta_ns(PROFILER_FPS_WINDOW)
	if avg_ns == 0 {
		return 0
	}
	return 1_000_000_000.0 / f64(avg_ns)
}


profiler_count_arg :: proc(
	L: ^vm.State,
	arg: int,
	fallback: i64 = PROFILER_DEFAULT_COUNT,
) -> int {if vm.StackTop(L) < arg {
		return int(fallback)
	}
	value := vm.ArgNumber(L, arg)
	if value != value {
		return int(fallback)
	}
	value = max(1.0, min(value, f64(profiling.MAX_HISTORY)))
	return int(value)
}

profiler_index_arg :: proc(L: ^vm.State, arg: int) -> i64 {
	if vm.StackTop(L) < arg {
		return 1
	}
	value := vm.ArgNumber(L, arg)
	if value != value || value < 1.0 || value > f64(profiling.MAX_HISTORY) {
		return 0
	}
	return i64(value)
}

profiler_push_number :: proc(L: ^vm.State, key: string, value: f64) {
	vm.PushNumber(L, value)
	vm.SetField(L, -2, key)
}

profiler_push_bool :: proc(L: ^vm.State, key: string, value: bool) {
	vm.PushBoolean(L, value)
	vm.SetField(L, -2, key)
}

profiler_push_string :: proc(L: ^vm.State, key: string, value: string) {
	vm.PushString(L, value)
	vm.SetField(L, -2, key)
}

profiler_zones_base_ns :: proc(zones: []profiling.Zone_Record) -> u64 {
	if len(zones) == 0 {
		return 0
	}
	base := zones[0].start_ns
	for zone in zones {
		base = min(base, zone.start_ns)
	}
	return base
}


profiler_push_zone :: proc(L: ^vm.State, zone: profiling.Zone_Record, base_ns: u64) {
	vm.NewTable(L, 0, 4)
	profiler_push_string(L, "name", zone.name)
	profiler_push_number(L, "color", f64(zone.color))
	duration_ns: u64 = 0
	if zone.end_ns >= zone.start_ns {
		duration_ns = zone.end_ns - zone.start_ns
	}
	profiler_push_number(L, "ms", profiler_ns_ms(duration_ns))
	offset_ns: u64 = 0
	if zone.start_ns >= base_ns {
		offset_ns = zone.start_ns - base_ns
	}
	profiler_push_number(L, "startMs", profiler_ns_ms(offset_ns))
}

profiler_push_zones :: proc(L: ^vm.State, zones: []profiling.Zone_Record) {
	vm.NewTable(L, 0, len(zones))
	base_ns := profiler_zones_base_ns(zones)
	for zone, i in zones {
		profiler_push_zone(L, zone, base_ns)
		vm.RawSetIndex(L, -2, i + 1)
	}
}

profiler_push_frame :: proc(L: ^vm.State, frame: profiling.Frame_Data, index: i64) {
	frame_ms := profiler_ns_ms(frame.delta_ns)
	vm.NewTable(L, 0, 5)
	profiler_push_number(L, "index", f64(index))
	profiler_push_number(L, "frameMs", frame_ms)
	fps := 0.0
	if frame_ms > 0 {
		fps = 1000.0 / frame_ms
	}
	profiler_push_number(L, "fps", fps)
	profiler_push_number(L, "gcMs", profiler_ns_ms(frame.gc.total_ns))
	profiler_push_number(L, "gcMaxStepMs", profiler_ns_ms(frame.gc.max_ns))
	profiler_push_number(L, "gcSteps", f64(frame.gc.steps))
	profiler_push_zones(L, frame.zones[:])
	vm.SetField(L, -2, "zones")
}

profiler_push_frame_record :: proc(L: ^vm.State, index: i64) {
	frames := profiling.history_frames()
	total := i64(len(frames))
	if index < 1 || index > total {
		vm.PushNil(L)
		return
	}
	profiler_push_frame(L, frames[int(total - index)], index)
}


profiler_push_frame_stats :: proc(
	L: ^vm.State,
	display_refresh_hz: f32 = 0,
	batch_stats: ^kineffi.KineFilamentBatchStats = nil,
	render_scale: f32 = 1,
	shadow_map_size: u32 = 0,
	include_history := true,
	pass_stats: ^kineffi.KineFilamentPassStats = nil,
) {
	frames := profiling.history_frames()
	vm.NewTable(L, 0, 8)
	profiler_push_bool(L, "enabled", profiling.is_enabled())
	profiler_push_bool(L, "paused", profiling.is_capture_paused())
	profiler_push_bool(L, "collectionEnabled", profiling.is_collection_enabled())
	profiler_push_number(L, "frameCount", f64(len(frames)))
	profiler_push_number(L, "frameMs", profiler_frame_ms())
	profiler_push_number(L, "fps", profiler_fps())
	gpu_id, gpu_ns := profiling.latest_gpu_frame()
	profiler_push_bool(L, "gpuFrameValid", gpu_ns > 0)
	profiler_push_number(L, "gpuFrameMs", profiler_ns_ms(gpu_ns))
	profiler_push_number(L, "gpuFrameId", f64(gpu_id))
	queue_id, queue_ns := profiling.latest_queue_frame()
	profiler_push_number(L, "queueFrameId", f64(queue_id))
	profiler_push_number(L, "queueFrameMs", profiler_ns_ms(queue_ns))
	profiler_push_bool(L, "queueFrameValid", queue_id != 0 && queue_ns != 0)
	stages := profiling.latest_queue_stages
	profiler_push_bool(L, "queueStagesValid", stages.id != 0 && stages.id == queue_id)
	profiler_push_number(L, "queueBaseMs", profiler_ns_ms(stages.base_ns))
	profiler_push_number(L, "queueRenderMs", profiler_ns_ms(stages.render_ns))
	detail := profiling.latest_queue_detail
	profiler_push_bool(L, "queueDetailValid", detail.id != 0 && detail.id == queue_id)
	profiler_push_number(L, "queueFilamentMs", profiler_ns_ms(detail.filament_ns))
	profiler_push_number(L, "queueOverlayMs", profiler_ns_ms(detail.overlay_ns))
	present := profiling.latest_present_metrics
	profiler_push_bool(L, "odinPresentActive", present.active)
	profiler_push_bool(L, "odinPresentAsync", present.asynchronous)
	profiler_push_number(L, "odinPresentFrameId", f64(present.completed))
	profiler_push_number(L, "odinPresentCallMs", profiler_ns_ms(present.call_ns))
	profiler_push_number(L, "odinPresentDrainMs", profiler_ns_ms(present.drain_ns))
	profiler_push_number(L, "odinPrefetchHits", f64(present.prefetch_hits))
	profiler_push_number(L, "odinPrefetchMisses", f64(present.prefetch_misses))
	work := profiling.latest_render_work
	profiler_push_number(L, "worldRenderFrames", f64(work.world_frames))
	profiler_push_number(L, "worldSkippedFrames", f64(work.world_skips))
	profiler_push_number(L, "viewportHandles", f64(work.viewport_handles))
	profiler_push_number(L, "viewportAtlasPages", f64(work.viewport_pages))
	profiler_push_number(L, "viewportRenders", f64(work.viewport_renders))
	profiler_push_number(L, "viewportRendersFrame", f64(work.viewport_renders_frame))
	profiler_push_number(L, "viewportReused", f64(work.viewport_reused))
	profiler_push_number(L, "viewportPersistent", f64(work.viewport_persistent))
	dirty := classes.Render_3D_Dirty_Counts()
	profiler_push_number(L, "worldDirtyCamera", f64(dirty[.Camera]))
	profiler_push_number(L, "worldDirtyPart", f64(dirty[.Part]))
	profiler_push_number(L, "worldDirtyHierarchy", f64(dirty[.Hierarchy]))
	profiler_push_number(L, "worldDirtyOther", f64(dirty[.Object] + dirty[.Other]))
	profiler_push_number(L, "displayRefreshHz", f64(display_refresh_hz))
	profiler_push_number(L, "renderScale", f64(render_scale))
	profiler_push_number(L, "effectiveShadowMapSize", f64(shadow_map_size))
	if pass_stats != nil {
		vm.NewTable(L, 0, 15)
		profiler_push_number(L, "world", f64(pass_stats.world))
		profiler_push_number(L, "clouds", f64(pass_stats.clouds))
		profiler_push_number(L, "waterDepth", f64(pass_stats.waterDepth))
		profiler_push_number(L, "sharedDepth", f64(pass_stats.sharedDepth))
		profiler_push_number(L, "customDepth", f64(pass_stats.customDepth))
		profiler_push_number(L, "screenEffects", f64(pass_stats.screenEffects))
		profiler_push_number(L, "customPost", f64(pass_stats.customPost))
		profiler_push_number(L, "outlineMask", f64(pass_stats.outlineMask))
		profiler_push_number(L, "outlineComposite", f64(pass_stats.outlineComposite))
		profiler_push_number(L, "reflectionFaces", f64(pass_stats.reflectionFaces))
		profiler_push_number(L, "viewportScene", f64(pass_stats.viewportScene))
		profiler_push_number(L, "viewportClear", f64(pass_stats.viewportClear))
		profiler_push_number(L, "viewportCopy", f64(pass_stats.viewportCopy))
		profiler_push_number(L, "viewportShadow", f64(pass_stats.viewportShadow))
		profiler_push_number(L, "viewportPresent", f64(pass_stats.viewportPresent))
		vm.SetField(L, -2, "renderPasses")
	}
	if batch_stats != nil {
		vm.NewTable(L, 0, 10)
		profiler_push_number(L, "activeBatches", f64(batch_stats.activeBatches))
		profiler_push_number(L, "activeChunks", f64(batch_stats.activeChunks))
		profiler_push_number(L, "retainedChunks", f64(batch_stats.retainedChunks))
		profiler_push_number(L, "createdChunks", f64(batch_stats.createdChunks))
		profiler_push_number(L, "destroyedChunks", f64(batch_stats.destroyedChunks))
		profiler_push_number(L, "unchangedBatches", f64(batch_stats.unchangedBatches))
		profiler_push_number(L, "transformUploads", f64(batch_stats.transformUploads))
		profiler_push_number(L, "colorUploads", f64(batch_stats.colorUploads))
		profiler_push_number(L, "uvUploads", f64(batch_stats.uvUploads))
		profiler_push_number(L, "boundsUpdates", f64(batch_stats.boundsUpdates))
		vm.SetField(L, -2, "renderBatches")
	}

	if !include_history {return}
	n := min(PROFILER_HISTORY_POINTS, len(frames))
	vm.NewTable(L, 0, n)
	for i in 0 ..< n {
		frame := frames[len(frames) - 1 - i]
		vm.PushNumber(L, profiler_ns_ms(frame.delta_ns))
		vm.RawSetIndex(L, -2, i + 1)
	}
	vm.SetField(L, -2, "history")

	if len(frames) > 0 {
		last := frames[len(frames) - 1]
		profiler_push_zones(L, last.zones[:])
	} else {
		vm.NewTable(L, 0, 0)
	}
	vm.SetField(L, -2, "zones")
}


profiler_push_frame_times :: proc(L: ^vm.State, wanted: int) {
	frames := profiling.history_frames()
	n := min(wanted, len(frames))
	vm.NewTable(L, 0, n)
	first := len(frames) - n
	for i in 0 ..< n {
		vm.PushNumber(L, profiler_ns_ms(frames[first + i].delta_ns))
		vm.RawSetIndex(L, -2, i + 1)
	}
}


profiler_push_zone_history :: proc(L: ^vm.State, name: string, wanted: int) {
	frames := profiling.history_frames()
	n := min(wanted, len(frames))
	first := len(frames) - n
	vm.NewTable(L, 0, n)
	for i in 0 ..< n {
		total_ns: u64
		for zone in frames[first + i].zones {
			if zone.name == name && zone.end_ns >= zone.start_ns {
				total_ns += zone.end_ns - zone.start_ns
			}
		}
		vm.PushNumber(L, profiler_ns_ms(total_ns))
		vm.RawSetIndex(L, -2, i + 1)
	}
}


profiler_push_zone_stats :: proc(L: ^vm.State, name: string) {
	frames := profiling.history_frames()
	count: u64
	total_ns: u64
	min_ns: u64
	max_ns: u64
	last_ns: u64
	touched_frames: u64
	for frame in frames {
		touched := false
		for zone in frame.zones {
			if zone.name != name || zone.end_ns < zone.start_ns {
				continue
			}
			duration := zone.end_ns - zone.start_ns
			if count == 0 {
				min_ns = duration
			} else {
				min_ns = min(min_ns, duration)
			}
			max_ns = max(max_ns, duration)
			total_ns += duration
			last_ns = duration
			count += 1
			touched = true
		}
		if touched {
			touched_frames += 1
		}
	}
	vm.NewTable(L, 0, 8)
	profiler_push_string(L, "name", name)
	profiler_push_number(L, "count", f64(count))
	profiler_push_number(L, "frames", f64(touched_frames))
	profiler_push_number(L, "totalMs", profiler_ns_ms(total_ns))
	profiler_push_number(L, "lastMs", profiler_ns_ms(last_ns))
	profiler_push_number(L, "minMs", profiler_ns_ms(min_ns))
	profiler_push_number(L, "maxMs", profiler_ns_ms(max_ns))
	avg := 0.0
	if count > 0 {
		avg = profiler_ns_ms(total_ns) / f64(count)
	}
	profiler_push_number(L, "avgMs", avg)
}

profiler_thread_status :: proc(L: ^vm.State, record: ^profiling.Thread_Record) -> string {
	if !record.alive || record.L == nil {
		return "Dead"
	}
	switch vm.ThreadStatus(L, record.L) {
	case .Running:
		return "Running"
	case .Suspended:
		return "Suspended"
	case .Normal:
		return "Normal"
	case .Finished:
		return "Finished"
	case .Error:
		return "Error"
	}
	return "Unknown"
}


profiler_push_thread_record :: proc(L: ^vm.State, record: ^profiling.Thread_Record) {
	vm.NewTable(L, 0, 13)
	profiler_push_number(L, "Id", f64(record.id))
	profiler_push_string(L, "Name", profiling.thread_display_name(record))
	profiler_push_string(L, "Status", profiler_thread_status(L, record))
	profiler_push_number(L, "CpuMs", profiler_ns_ms(record.cpu_ns))
	profiler_push_number(L, "TotalCpuMs", profiler_ns_ms(record.total_cpu_ns))
	profiler_push_number(L, "Resumes", f64(record.resumes))
	profiler_push_number(L, "AllocatedBytes", f64(record.alloc_bytes))
	profiler_push_number(L, "FreedBytes", f64(record.free_bytes))
	profiler_push_number(L, "LiveBytes", f64(record.live_bytes))
	profiler_push_number(L, "FrameCpuMs", profiler_ns_ms(record.frame_cpu_ns))
	profiler_push_number(L, "FrameTotalCpuMs", profiler_ns_ms(record.frame_total_cpu_ns))
	profiler_push_number(L, "FrameAllocatedBytes", f64(record.frame_alloc_bytes))
	profiler_push_number(L, "FrameResumes", f64(record.frame_resumes))
}

profiler_push_threads :: proc(L: ^vm.State) {
	records := profiling.all_thread_records()
	root := profiling.caller_root(L)
	count := 0
	for record in records {
		if record.alive && record.root == root {
			count += 1
		}
	}
	vm.NewTable(L, 0, count)
	next_index := 1
	for record in records {
		if !record.alive || record.root != root {
			continue
		}
		profiler_push_thread_record(L, record)
		vm.RawSetIndex(L, -2, next_index)
		next_index += 1
	}
}

profiler_push_thread_stats :: proc(L: ^vm.State) {
	records := profiling.all_thread_records()
	root := profiling.caller_root(L)
	alive := 0
	dead := 0
	frame_cpu_ns: u64
	frame_total_cpu_ns: u64
	frame_alloc_bytes: u64
	frame_free_bytes: u64
	frame_resumes: u64
	total_cpu_ns: u64
	tracked_live_bytes: i64

	for record in records {
		if record.root != root {
			continue
		}
		if record.alive {
			alive += 1
		} else {
			dead += 1
		}
		frame_cpu_ns += record.frame_cpu_ns
		frame_total_cpu_ns += record.frame_total_cpu_ns
		frame_alloc_bytes += record.frame_alloc_bytes
		frame_free_bytes += record.frame_free_bytes
		frame_resumes += record.frame_resumes
		total_cpu_ns += record.cpu_ns
		tracked_live_bytes += record.live_bytes
	}

	vm.NewTable(L, 0, 13)
	profiler_push_number(L, "threads", f64(alive))
	profiler_push_number(L, "deadThreads", f64(dead))
	profiler_push_number(L, "frameCpuMs", profiler_ns_ms(frame_cpu_ns))
	profiler_push_number(L, "frameTotalCpuMs", profiler_ns_ms(frame_total_cpu_ns))
	profiler_push_number(L, "totalCpuMs", profiler_ns_ms(total_cpu_ns))
	profiler_push_number(L, "frameAllocatedBytes", f64(frame_alloc_bytes))
	profiler_push_number(L, "frameFreedBytes", f64(frame_free_bytes))
	profiler_push_number(L, "frameResumes", f64(frame_resumes))
	profiler_push_number(L, "trackedLiveBytes", f64(tracked_live_bytes))
	profiler_push_number(L, "heapBytes", f64(profiling.heap_bytes(L)))
	profiler_push_number(
		L,
		"allocationRateBytesPerSecond",
		profiling.allocation_rate_bytes_per_sec(),
	)
	profiler_push_bool(L, "trackingEnabled", profiling.is_tracking_enabled())
	profiler_push_bool(L, "paused", profiling.is_capture_paused())
}

profiler_push_scripts :: proc(L: ^vm.State) {
	root := profiling.caller_root(L)
	stats := profiling.script_stats(root)
	defer delete(stats)

	vm.NewTable(L, 0, len(stats))
	for stat, i in stats {
		vm.NewTable(L, 0, 9)
		profiler_push_string(L, "Name", stat.name)
		profiler_push_number(L, "CpuMs", profiler_ns_ms(stat.cpu_ns))
		profiler_push_number(L, "TotalCpuMs", profiler_ns_ms(stat.total_cpu_ns))
		profiler_push_number(L, "Resumes", f64(stat.resumes))
		profiler_push_number(L, "AllocatedBytes", f64(stat.alloc_bytes))
		profiler_push_number(L, "FreedBytes", f64(stat.free_bytes))
		profiler_push_number(L, "LiveBytes", f64(stat.live_bytes))
		profiler_push_number(L, "Threads", f64(stat.threads))
		profiler_push_number(L, "AliveThreads", f64(stat.alive_threads))
		vm.RawSetIndex(L, -2, i + 1)
	}
}


profiler_push_thread_history :: proc(L: ^vm.State, index: i64) {
	frames := profiling.thread_history_frames()
	total := i64(len(frames))
	if index < 1 || index > total {
		vm.PushNil(L)
		return
	}
	frame := frames[int(total - index)]
	root := profiling.caller_root(L)
	vm.NewTable(L, 0, 2)
	profiler_push_number(L, "index", f64(index))
	vm.NewTable(L, 0, len(frame.rows))
	i := 1
	for row in frame.rows {
		record := profiling.find_thread_record(row.id)
		if record == nil || record.root != root {
			continue
		}
		vm.NewTable(L, 0, 7)
		profiler_push_number(L, "id", f64(row.id))
		profiler_push_string(L, "name", profiling.thread_display_name(record))
		profiler_push_number(L, "cpuMs", profiler_ns_ms(row.cpu_ns))
		profiler_push_number(L, "totalCpuMs", profiler_ns_ms(row.total_cpu_ns))
		profiler_push_number(L, "resumes", f64(row.resumes))
		profiler_push_number(L, "allocatedBytes", f64(row.alloc_bytes))
		profiler_push_number(L, "freedBytes", f64(row.free_bytes))
		vm.RawSetIndex(L, -2, i)
		i += 1
	}
	vm.SetField(L, -2, "threads")
}

profiler_service_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "Enabled":
		vm.PushBoolean(L, profiling.is_enabled())
	case "Paused":
		vm.PushBoolean(L, profiling.is_capture_paused())
	case "CollectionEnabled":
		vm.PushBoolean(L, profiling.is_collection_enabled())
	case "TrackingEnabled":
		vm.PushBoolean(L, profiling.is_tracking_enabled())
	case "FrameCount":
		vm.PushNumber(L, f64(profiling.frame_count()))
	case "FrameTime":
		vm.PushNumber(L, profiler_frame_ms())
	case "FPS":
		vm.PushNumber(L, profiler_fps())
	case "SetEnabled", "SetCollectionEnabled":
		if !vm.ThreadHasSecurityCapability(L, PROJECT_INTERNALS_CAPABILITY) {
			return false
		}
		vm.PushUserdataMethod(L, key)
	case "GetService",
	     "FindService",
	     "GetFrameStats",
	     "GetObjectStats",
	     "GetGCStats",
	     "SetGCProfilingEnabled",
	     "GetFrameTimes",
	     "GetFrameRecord",
	     "GetZoneHistory",
	     "GetZoneStats",
	     "Pause",
	     "Resume",
	     "SetPaused",
	     "GetThreads",
	     "GetThreadStats",
	     "GetThreadHistory",
	     "GetScripts",
	     "SetTrackingEnabled":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}
	return true
}

profiler_push_object_stats :: proc(L: ^vm.State, registry: ^classes.Registry) {
	vm.NewTable(L, 0, 2)
	total := 0
	vm.NewTable(L, 0, 0)
	if registry != nil {
		index := 1
		for descriptor in registry.classes {
			if descriptor == nil || descriptor.info == nil {continue}
			count := len(descriptor.instances)
			if count == 0 {continue}
			total += count
			vm.NewTable(L, 0, 2)
			profiler_push_string(L, "name", descriptor.info.name)
			profiler_push_number(L, "count", f64(count))
			vm.RawSetIndex(L, -2, index)
			index += 1
		}
	}
	vm.SetField(L, -2, "classes")
	profiler_push_number(L, "total", f64(total))
}

profiler_service_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	service := cast(^ProfilerService)object
	switch method {
	case "GetService", "FindService":
		classes.Push_Object(L, Service_Get_Service(&service.service, vm.ArgString(L, 2)))
		return 1, true

	case "GetGCStats":
		gc := profiling.last_gc_stats()
		vm.NewTable(L, 0, 4)
		profiler_push_bool(L, "enabled", profiling.gc_profiling_enabled(L))
		profiler_push_number(L, "totalMs", profiler_ns_ms(gc.total_ns))
		profiler_push_number(L, "maxStepMs", profiler_ns_ms(gc.max_ns))
		profiler_push_number(L, "steps", f64(gc.steps))
		return 1, true
	case "SetGCProfilingEnabled":
		vm.PushBoolean(L, profiling.set_gc_profiling(L, vm.ArgBoolean(L, 2)))
		return 1, true
	case "GetObjectStats":
		profiler_push_object_stats(L, object.signal_registry)
		return 1, true
	case "GetFrameStats":
		include_history := vm.StackTop(L) < 2 || vm.IsNil(L, 2) || vm.ArgBoolean(L, 2)
		if include_history {profiling.set_collection_enabled(true)}
		hz: f32
		render_scale: f32 = 1
		shadow_map_size: u32
		batch_stats: kineffi.KineFilamentBatchStats
		batch_stats_ptr: ^kineffi.KineFilamentBatchStats
		pass_stats: kineffi.KineFilamentPassStats
		pass_stats_ptr: ^kineffi.KineFilamentPassStats
		when ODIN_OS != .JS {
			if registry := object.signal_registry;
			   registry != nil && registry.renderer != nil && registry.renderer.Filament != nil {
				hz = kineffi.Kine_Filament_GetDisplayRefreshRate(registry.renderer.Filament)
				render_scale = kineffi.Kine_Filament_GetResolutionScale(registry.renderer.Filament)
				shadow_map_size = kineffi.Kine_Filament_GetEffectiveShadowMapSize(
					registry.renderer.Filament,
				)
				kineffi.Kine_Filament_GetBatchStats(registry.renderer.Filament, &batch_stats)
				batch_stats_ptr = &batch_stats
				kineffi.Kine_Filament_GetPassStats(registry.renderer.Filament, &pass_stats)
				pass_stats_ptr = &pass_stats
			}
		}
		profiler_push_frame_stats(
			L,
			hz,
			batch_stats_ptr,
			render_scale,
			shadow_map_size,
			include_history,
			pass_stats_ptr,
		)
		return 1, true
	case "GetFrameTimes":
		profiling.set_collection_enabled(true)
		profiler_push_frame_times(L, profiler_count_arg(L, 2))
		return 1, true
	case "GetFrameRecord":
		profiling.set_collection_enabled(true)
		profiler_push_frame_record(L, profiler_index_arg(L, 2))
		return 1, true
	case "GetZoneHistory":
		profiling.set_collection_enabled(true)
		name := vm.ArgString(L, 2)
		profiler_push_zone_history(L, name, profiler_count_arg(L, 3))
		return 1, true
	case "GetZoneStats":
		profiling.set_collection_enabled(true)
		profiler_push_zone_stats(L, vm.ArgString(L, 2))
		return 1, true

	case "GetThreads":
		profiler_push_threads(L)
		return 1, true
	case "GetThreadStats":
		profiler_push_thread_stats(L)
		return 1, true
	case "GetThreadHistory":
		profiling.set_collection_enabled(true)
		profiler_push_thread_history(L, profiler_index_arg(L, 2))
		return 1, true
	case "GetScripts":
		profiler_push_scripts(L)
		return 1, true

	case "SetEnabled":
		if !vm.ThreadHasSecurityCapability(L, PROJECT_INTERNALS_CAPABILITY) {
			return 0, false
		}
		profiling.set_enabled(vm.ArgBoolean(L, 2))
		return 0, true
	case "SetCollectionEnabled":
		if !vm.ThreadHasSecurityCapability(L, PROJECT_INTERNALS_CAPABILITY) {
			return 0, false
		}

		on := vm.ArgBoolean(L, 2)
		profiling.set_collection_enabled(on || profiling.is_enabled())
		return 0, true
	case "SetPaused":
		profiling.set_capture_paused(vm.ArgBoolean(L, 2))
		return 0, true
	case "Pause":
		profiling.set_capture_paused(true)
		return 0, true
	case "Resume":
		profiling.set_capture_paused(false)
		return 0, true
	case "SetTrackingEnabled":
		profiling.set_tracking_enabled(vm.ArgBoolean(L, 2))
		return 0, true
	}
	return 0, false
}

Register_ProfilerService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&ProfilerService_Class,
		profiler_service_construct,
		profiler_service_destroy,
		creatable = false,
		get = profiler_service_get,
		namecall = profiler_service_namecall,
	)
}

PROFILER_OVERLAY_SOURCE :: `local profiler = game:GetService("ProfilerService")
local coreGui = game:GetService("CoreGui")
local white = Color3.new(1, 1, 1)
local dim = Color3.new(0.72, 0.72, 0.72)
local green = Color3.new(0.4, 0.92, 0.58)
local blue = Color3.new(0.46, 0.75, 1)
local amber = Color3.new(1, 0.72, 0.34)
local points = 60

local function make(class, name, parent)
	local object = Instance.new(class)
	object.Name = name
	object.Archivable = false
	object.CanReplicate = false
	object.Parent = parent
	return object
end

local screen = make("ScreenGui", "ProfilerOverlay", coreGui)
screen.Enabled = false
screen.RenderOnTop = true
screen.IgnoreGuiInset = true
screen.ResetOnSpawn = false
screen.DisplayOrder = 10000

local panel = make("Frame", "Panel", screen)
panel.Position = UDim2.fromOffset(10, 10)
panel.Size = UDim2.fromOffset(460, 430)
panel.BackgroundColor3 = Color3.new(0, 0, 0)
panel.BackgroundTransparency = 0.5
panel.BorderSizePixel = 0
panel.Active = false

local backdrop = make("UIBackdrop", "Blur", panel)

local function label(name, parent, text, size, color)
	local l = make("TextLabel", name, parent)
	l.BackgroundTransparency = 1
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextColor3 = color
	l.TextSize = size
	l.Text = text
	return l
end
local function place(object, x, y, w, h)
	object.Position = UDim2.fromOffset(x, y)
	object.Size = UDim2.fromOffset(w, h)
	return object
end
local headline = place(label("Headline", panel, "-- FPS", 21, white), 10, 4, 180, 30)
local frameLabel = label("FrameTime", panel, "-- ms", 17, white)
frameLabel.Position = UDim2.new(1, -150, 0, 4)
frameLabel.Size = UDim2.fromOffset(140, 30)
frameLabel.TextXAlignment = Enum.TextXAlignment.Right

local tabs = {"Frame", "CPU", "Luau", "GPU", "Net", "Objects"}
local current = "Frame"
local elapsed = 0
local selected = 1
local tabButtons = {}
local function button(name, text, parent)
	local b = make("TextButton", name, parent)
	b.BackgroundTransparency = 1
	b.TextColor3 = dim
	b.TextSize = 12
	b.Text = text
	return b
end
for i, tab in ipairs(tabs) do
	local b = button(tab .. "Tab", tab, panel)
	b.Position = UDim2.new((i - 1) / #tabs, 0, 0, 36)
	b.Size = UDim2.new(1 / #tabs, 0, 0, 24)
	tabButtons[tab] = b
end
local historyTitle = label("HistoryTitle", panel, "Frame time", 12, dim)
historyTitle.Position = UDim2.fromOffset(10, 64)
historyTitle.Size = UDim2.new(1, -20, 0, 16)
local graph = make("Frame", "FrameGraph", panel)
graph.Position = UDim2.fromOffset(10, 84)
graph.Size = UDim2.new(1, -20, 0, 52)
graph.BackgroundTransparency = 1
graph.BorderSizePixel = 0
local bars = {}
for i = 1, points do
	local bar = make("Frame", "Sample" .. i, graph)
	bar.AnchorPoint = Vector2.new(0, 1)
	bar.Position = UDim2.new((i - 1) / points, 0, 1, 0)
	bar.Size = UDim2.new(1 / points, -1, 0, 0)
	bar.BorderSizePixel = 0
	bar.Visible = false
	bars[i] = bar
end

local body = make("ScrollingFrame", "Metrics", panel)
body.BackgroundTransparency = 1
body.BorderSizePixel = 0
body.ScrollBarThickness = 4
body.ScrollingDirection = Enum.ScrollingDirection.Y
body.CanvasSize = UDim2.fromOffset(0, 0)
local rows = {}
local rowHeight = 20
local metricData = {}
local renderedStart = -1
local function makeRow(i)
	local row = make("Frame", "Row" .. i, body)
	row.Position = UDim2.fromOffset(0, (i - 1) * rowHeight)
	row.Size = UDim2.new(1, -8, 0, rowHeight)
	row.BackgroundTransparency = 1
	local bar = make("Frame", "Bar", row)
	bar.Size = UDim2.new(0, 0, 1, -2)
	bar.BackgroundColor3 = green
	bar.BackgroundTransparency = 0.8
	bar.BorderSizePixel = 0
	local name = label("Name", row, "", 12, dim)
	name.Position = UDim2.fromOffset(2, 0)
	name.Size = UDim2.new(0.66, -4, 1, 0)
	local value = label("Value", row, "", 12, white)
	value.Position = UDim2.new(0.66, 0, 0, 0)
	value.Size = UDim2.new(0.34, -2, 1, 0)
	value.TextXAlignment = Enum.TextXAlignment.Right
	return {row = row, bar = bar, name = name, value = value}
end
local footer = label("Footer", panel, "F2 hide", 11, dim)
footer.Position = UDim2.new(0, 10, 1, -24)
footer.Size = UDim2.new(1, -170, 0, 20)
local pause = button("PauseButton", "Pause", panel)
pause.Position = UDim2.new(1, -66, 1, -24)
pause.Size = UDim2.fromOffset(56, 20)
local older = button("Older", "<", panel)
older.Position = UDim2.new(1, -116, 1, -24)
older.Size = UDim2.fromOffset(24, 20)
local newer = button("Newer", ">", panel)
newer.Position = UDim2.new(1, -92, 1, -24)
newer.Size = UDim2.fromOffset(24, 20)
older.Visible = false
newer.Visible = false

for tab, b in pairs(tabButtons) do
	b.MouseButton1Click:Connect(function()
		current = tab
		body.CanvasPosition = Vector2.new(0, 0)
		elapsed = 0.2
	end)
end
pause.MouseButton1Click:Connect(function()
	if profiler.Paused then profiler:Resume() else profiler:Pause() end
	selected = 1
	elapsed = 0.2
end)
older.MouseButton1Click:Connect(function()
	selected = math.min(selected + 1, math.max(profiler.FrameCount, 1))
	elapsed = 0.2
end)
newer.MouseButton1Click:Connect(function()
	selected = math.max(selected - 1, 1)
	elapsed = 0.2
end)

local function number(value, suffix, decimals)
	if type(value) ~= "number" then return "--" end
	return string.format("%." .. (decimals or 0) .. "f%s", value, suffix or "")
end
local function ms(value)
	return number(value, " ms", 2)
end
local function memory(value)
	if type(value) ~= "number" then return "--" end
	if math.abs(value) >= 1048576 then return number(value / 1048576, " MiB", 2) end
	if math.abs(value) >= 1024 then return number(value / 1024, " KiB", 1) end
	return number(value, " B")
end
local function fields(data, values, add)
	for _, field in ipairs(values) do
		local value = data[field[2]]
		if type(value) == "boolean" then
			value = value and "Yes" or "No"
		elseif field[3] then
			value = field[3](value)
		else
			value = number(value)
		end
		add(field[1], value)
	end
end

local function renderRows(force)
	local first = math.max(1, math.floor(body.CanvasPosition.Y / rowHeight) + 1)
	if not force and first == renderedStart then return end
	renderedStart = first
	for i = 1, 24 do
		local index = first + i - 1
		local entry = metricData[index]
		local row = rows[i]
		if entry then
			if not row then
				row = makeRow(i)
				rows[i] = row
			end
			row.row.Position = UDim2.fromOffset(0, (index - 1) * rowHeight)
			row.row.Visible = true
			row.name.Text = entry[1]
			row.name.TextColor3 = entry[2] == "" and blue or dim
			row.value.Text = entry[2]
			row.bar.Size = UDim2.new(math.clamp(entry[3], 0, 1), 0, 1, -2)
			row.bar.BackgroundColor3 = entry[4]
		elseif row then
			row.row.Visible = false
		end
	end
end

local function update()
	local stats = profiler:GetFrameStats()
	local history = stats.history or {}
	local zones = stats.zones or {}
	local frameMs = stats.frameMs or 0
	local fps = stats.fps or 0
	local paused = profiler.Paused
	local record
	if paused then
		selected = math.clamp(selected, 1, math.max(profiler.FrameCount, 1))
		record = profiler:GetFrameRecord(selected)
		if record then
			frameMs = record.frameMs or 0
			fps = record.fps or 0
			zones = record.zones or {}
		end
	else
		selected = 1
	end
	headline.Text = number(fps, " FPS", 1)
	frameLabel.Text = ms(frameMs)
	for tab, b in pairs(tabButtons) do
		b.TextColor3 = tab == current and white or dim
	end
	local width = math.min(460, math.max(180, screen.AbsoluteSize.X - 20))
	local height = math.min(430, math.max(150, screen.AbsoluteSize.Y - 20))
	if screen.AbsoluteSize.X > 0 and screen.AbsoluteSize.Y > 0 then
		panel.Size = UDim2.fromOffset(width, height)
	end
	local showGraph = current == "Frame"
	graph.Visible = showGraph
	historyTitle.Visible = showGraph
	local bodyY = showGraph and 142 or 64
	body.Position = UDim2.fromOffset(10, bodyY)
	body.Size = UDim2.new(1, -20, 1, -(bodyY + 28))
	local data = {}
	local function add(name, value, fraction, color)
		data[#data + 1] = {name, tostring(value or "--"), fraction or 0, color or green}
	end
	local function heading(name)
		add(name, "", 0, blue)
	end
	if current == "Frame" then
		local peak, minimum, total = 0, math.huge, 0
		for _, t in ipairs(history) do
			peak = math.max(peak, t)
			minimum = math.min(minimum, t)
			total += t
		end
		local average = #history > 0 and total / #history or nil
		historyTitle.Text = "Frame time history    " .. tostring(#history) .. " samples"
		for i, bar in ipairs(bars) do
			local t = history[points - i + 1]
			bar.Visible = t ~= nil and t > 0
			if t and t > 0 then
				bar.Size = UDim2.new(1 / points, -1, math.clamp(t / math.max(peak, 16.67), 0, 1), 0)
				bar.BackgroundColor3 = t > 16.67 and amber or green
			end
		end
		heading("FRAME STATISTICS")
		add("Average", ms(average))
		add("Minimum", ms(#history > 0 and minimum or nil))
		add("Maximum", ms(#history > 0 and peak or nil))
		add("Frame budget (display)", stats.displayRefreshHz > 0 and ms(1000 / stats.displayRefreshHz) or "--")
		add("Display refresh", stats.displayRefreshHz > 0 and number(stats.displayRefreshHz, " Hz", 1) or "--")
		add("GPU frame (live)", stats.gpuFrameValid and ms(stats.gpuFrameMs) or "--")
		add("GPU queue (live)", stats.queueFrameValid and ms(stats.queueFrameMs) or "--")
		add("Captured frames", number(stats.frameCount))
		add("Capture", paused and "Paused" or "Live")
		add("History collection", stats.collectionEnabled and "On" or "Off")
		add("CPU zones", number(#zones))
	elseif current == "CPU" then
		heading("CPU ZONES (INCLUSIVE)")
		local byName = {}
		for _, zone in ipairs(zones) do
			local item = byName[zone.name]
			if not item then
				item = {name = zone.name, ms = 0, count = 0}
				byName[zone.name] = item
			end
			item.ms += zone.ms
			item.count += 1
		end
		local sorted = {}
		for _, item in pairs(byName) do sorted[#sorted + 1] = item end
		table.sort(sorted, function(a, b) return a.ms > b.ms or (a.ms == b.ms and a.name < b.name) end)
		for _, zone in ipairs(sorted) do
			add(zone.name .. " (" .. zone.count .. ")", ms(zone.ms), zone.ms / math.max(frameMs, 0.001))
		end
		if #sorted == 0 then add("No captured zones", "--") end
	elseif current == "Luau" then
		heading("LUAU VM (LIVE)")
		local threads = profiler:GetThreadStats()
		fields(threads, {
			{"Heap", "heapBytes", memory}, {"Tracked live allocations", "trackedLiveBytes", memory},
			{"Allocation rate", "allocationRateBytesPerSecond", function(v) return memory(v) .. "/s" end},
			{"Allocated this frame", "frameAllocatedBytes", memory}, {"Freed this frame", "frameFreedBytes", memory},
			{"Active threads", "threads"}, {"Retired threads", "deadThreads"},
			{"Frame CPU", "frameCpuMs", ms}, {"Inclusive frame CPU", "frameTotalCpuMs", ms},
			{"Total CPU", "totalCpuMs", ms}, {"Frame resumes", "frameResumes"}, {"Tracking", "trackingEnabled"},
		}, add)
		heading("GARBAGE COLLECTION")
		local gc = profiler:GetGCStats()
		add("GC timing", gc.enabled and "On" or "Off")
		add("Total", ms(record and record.gcMs or gc.totalMs))
		add("Longest step", ms(record and record.gcMaxStepMs or gc.maxStepMs))
		add("Steps", number(record and record.gcSteps or gc.steps))
		heading("SCRIPTS (LIVE TOTAL CPU)")
		local scripts = profiler:GetScripts()
		table.sort(scripts, function(a, b) return a.CpuMs > b.CpuMs or (a.CpuMs == b.CpuMs and a.Name < b.Name) end)
		for _, item in ipairs(scripts) do
			add(item.Name, ms(item.CpuMs))
			add("   Allocated / live", memory(item.AllocatedBytes) .. " / " .. memory(item.LiveBytes))
			add("   Threads / resumes", number(item.AliveThreads) .. " / " .. number(item.Resumes))
		end
		heading(paused and "THREADS (SELECTED FRAME)" or "THREADS (LIVE FRAME CPU)")
		local threadHistory = paused and profiler:GetThreadHistory(selected) or nil
		local list = paused and (threadHistory and threadHistory.threads or {}) or profiler:GetThreads()
		table.sort(list, function(a, b) return (a.FrameCpuMs or a.cpuMs or 0) > (b.FrameCpuMs or b.cpuMs or 0) end)
		for _, item in ipairs(list) do
			add(item.Name or item.name or "Thread", ms(item.FrameCpuMs or item.cpuMs))
			add("   " .. (item.Status or "Captured") .. " / allocated", memory(item.FrameAllocatedBytes or item.allocatedBytes))
		end
	elseif current == "GPU" then
		heading("RENDERER (LIVE)")
		add("GPU frame", stats.gpuFrameValid and ms(stats.gpuFrameMs) or "--")
		add("GPU queue", stats.queueFrameValid and ms(stats.queueFrameMs) or "--")
		add("GPU frame ID", stats.gpuFrameValid and number(stats.gpuFrameId) or "--")
		add("Queue frame ID", stats.queueFrameValid and number(stats.queueFrameId) or "--")
		add("Queue base / Skia", stats.queueStagesValid and ms(stats.queueBaseMs) or "--")
		add("Queue 3D + overlay", stats.queueStagesValid and ms(stats.queueRenderMs) or "--")
		if stats.queueDetailValid then
			add("Queue Filament", ms(stats.queueFilamentMs))
			add("Queue overlay", ms(stats.queueOverlayMs))
		end
		if stats.odinPresentActive then
			heading("ODIN PRESENTATION")
			add("Mode", stats.odinPresentAsync and "Asynchronous" or "Synchronous")
			add("WSI call (completed)", stats.odinPresentFrameId > 0 and ms(stats.odinPresentCallMs) or "--")
			add("Main thread drain", ms(stats.odinPresentDrainMs))
			add("Present frame ID", number(stats.odinPresentFrameId))
			add("Prefetch hits", number(stats.odinPrefetchHits))
			add("Prefetch misses", number(stats.odinPrefetchMisses))
		end
		add("Resolution scale", stats.renderBatches and number(stats.renderScale * 100, "%", 1) or "--")
		add("Shadow map", stats.effectiveShadowMapSize > 0 and number(stats.effectiveShadowMapSize, " px") or "--")
		heading("WORLD AND VIEWPORTS")
		add("World rendered", number(stats.worldRenderFrames))
		add("World skipped", number(stats.worldSkippedFrames))
		add("Viewport renders / frame", number(stats.viewportRendersFrame))
		add("Viewport renders total", number(stats.viewportRenders))
		add("Viewport renders reused", number(stats.viewportReused))
		add("Viewport cross-frame reuse", number(stats.viewportPersistent))
		add("Dirty camera", number(stats.worldDirtyCamera))
		add("Dirty part", number(stats.worldDirtyPart))
		add("Dirty hierarchy", number(stats.worldDirtyHierarchy))
		add("Dirty other", number(stats.worldDirtyOther))
		add("Viewport handles", number(stats.viewportHandles))
		add("Viewport atlas pages", number(stats.viewportAtlasPages))
		heading("LAST FILAMENT FRAME / VIEW SUBMISSIONS")
		fields(stats.renderPasses or {}, {
			{"World views", "world"}, {"Cloud offscreen", "clouds"}, {"Water contact depth", "waterDepth"},
			{"Shared depth", "sharedDepth"}, {"Custom depth", "customDepth"}, {"Screen effects", "screenEffects"},
			{"Custom post", "customPost"}, {"Outline mask", "outlineMask"}, {"Outline composite", "outlineComposite"},
			{"Reflection faces", "reflectionFaces"}, {"Preview scenes", "viewportScene"}, {"Preview clears", "viewportClear"},
			{"Preview atlas copies", "viewportCopy"}, {"Shadowed previews", "viewportShadow"}, {"Preview present", "viewportPresent"},
		}, add)
		heading("RENDER BATCHES")
		fields(stats.renderBatches or {}, {
			{"Active batches", "activeBatches"}, {"Active chunks", "activeChunks"},
			{"Retained chunks", "retainedChunks"}, {"Created chunks", "createdChunks"},
			{"Destroyed chunks", "destroyedChunks"}, {"Unchanged batches", "unchangedBatches"},
			{"Transform uploads", "transformUploads"}, {"Color uploads", "colorUploads"},
			{"UV uploads", "uvUploads"}, {"Bounds updates", "boundsUpdates"},
		}, add)
	elseif current == "Net" then
		heading("REPLICATION (LIVE)")
		local ok, network = pcall(function() return game:GetService("ReplicatorService"):GetStats() end)
		if ok and type(network) == "table" then
			local keys = {}
			for key in pairs(network) do keys[#keys + 1] = key end
			table.sort(keys)
			for _, key in ipairs(keys) do
				local value = network[key]
				if type(value) == "boolean" then value = value and "Yes" or "No"
				elseif key == "bytesSent" or key == "bytesReceived" then value = memory(value)
				elseif type(value) == "number" then value = number(value, "", value % 1 == 0 and 0 or 3) end
				local caption = key:gsub("(%l)(%u)", "%1 %2")
				add(caption:sub(1, 1):upper() .. caption:sub(2), value)
			end
		else
			add("Replication metrics unavailable", "--")
		end
	elseif current == "Objects" then
		heading("ENGINE OBJECTS (LIVE)")
		local objects = profiler:GetObjectStats()
		table.sort(objects.classes, function(a, b) return a.count > b.count or (a.count == b.count and a.name < b.name) end)
		add("Registered instances", number(objects.total))
		local ok, awake = pcall(function() return game:GetService("Workspace"):GetNumAwakeParts() end)
		add("Awake physics parts", ok and number(awake) or "--")
		heading("INSTANCES BY CLASS")
		for _, item in ipairs(objects.classes) do add(item.name, number(item.count)) end
	end
	metricData = data
	body.CanvasSize = UDim2.fromOffset(0, #metricData * rowHeight)
	renderRows(true)
	pause.Text = paused and "Resume" or "Pause"
	older.Visible = paused
	newer.Visible = paused
	footer.Text = paused and string.format("Frame %d/%d     F2 hide", selected, profiler.FrameCount) or "F2 hide"
end

while true do
	local enabled = profiler.Enabled
	if screen.Enabled ~= enabled then
		screen.Enabled = enabled
		elapsed = 0.2
	end
	if enabled and elapsed >= 0.2 then
		update()
		elapsed = 0
	elseif enabled then
		renderRows(false)
	end
	elapsed += task.wait()
end
`

Register_ProfilerOverlay :: proc(registry: ^Registry, vm_state: ^vm.VM) {
	if registry.classes.renderer == nil || registry.mode == .Server {return}
	script_object, script_ok := classes.Push_New(registry.classes, vm_state, "Script", false)
	assert(script_ok && script_object != nil)
	defer vm.Pop(vm_state.L)

	classes.Set_Name(script_object, "ProfilerOverlay")
	script_object.archivable = false
	classes.Set_Can_Replicate(script_object, false)
	script := cast(^classes.Script)script_object
	script.run_as_plugin = true
	script.run_context = .Client
	classes.Script_Set_Source(script, PROFILER_OVERLAY_SOURCE)
	classes.Set_Parent(script_object, &registry.data_model.object)
}
