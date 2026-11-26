
package profiling

import platform "../platform"
import "core:slice"

Zone_Record :: struct {
	name:     string,
	color:    u32,
	start_ns: u64,
	end_ns:   u64,
}

Zone_Accum :: struct {
	name:     string,
	color:    u32,
	count:    u64,
	total_ns: u64,
	last_ns:  u64,
	min_ns:   u64,
	max_ns:   u64,
}

Frame_Data :: struct {
	delta_ns: u64,
	zones:    [dynamic]Zone_Record,
	gc:       GC_Frame_Stats,
}

Zone :: struct {
	name:     string,
	color:    u32,
	start_ns: u64,
	active:   bool,
}

MAX_HISTORY :: 512

frame_zones: [dynamic]Zone_Record
accum: [dynamic]Zone_Accum
history: [dynamic]Frame_Data
frame_delta_ns: u64

latest_queue_frame_id: u64
latest_queue_frame_ns: u64
Queue_Stages :: struct {
	id, base_ns, render_ns: u64,
}
latest_queue_stages: Queue_Stages
Queue_Detail :: struct {
	id, filament_ns, overlay_ns: u64,
}
latest_queue_detail: Queue_Detail
record_queue_frame :: proc(id, ns: u64) {latest_queue_frame_id = id; latest_queue_frame_ns = ns}
latest_queue_frame :: proc() -> (u64, u64) {return latest_queue_frame_id, latest_queue_frame_ns}

Present_Metrics :: struct {
	completed:       u64,
	call_ns:         u64,
	drain_ns:        u64,
	prefetch_hits:   u64,
	prefetch_misses: u64,
	active:          bool,
	asynchronous:    bool,
}

latest_present_metrics: Present_Metrics

Render_Work_Metrics :: struct {
	world_frames:           u64,
	world_skips:            u64,
	viewport_handles:       u32,
	viewport_pages:         u32,
	viewport_renders:       u64,
	viewport_renders_frame: u64,
	viewport_reused:        u64,
	viewport_persistent:    u64,
}

latest_render_work: Render_Work_Metrics

record_render_work :: proc(
	world, eligible: bool,
	handles, pages: u32,
	renders, reused, persistent: u64,
) {
	if world {
		latest_render_work.world_frames += 1
	} else if eligible {
		latest_render_work.world_skips += 1
	}
	latest_render_work.viewport_handles = handles
	latest_render_work.viewport_pages = pages
	latest_render_work.viewport_renders_frame =
		renders - min(renders, latest_render_work.viewport_renders)
	latest_render_work.viewport_renders = renders
	latest_render_work.viewport_reused = reused
	latest_render_work.viewport_persistent = persistent
}

record_present_metrics :: proc(value: Present_Metrics) {latest_present_metrics = value}

latest_gpu_frame_id: u32
latest_gpu_frame_ns: u64
record_gpu_frame :: proc(id: u32, ns: u64) {latest_gpu_frame_id = id; latest_gpu_frame_ns = ns}
latest_gpu_frame :: proc() -> (u32, u64) {return latest_gpu_frame_id, latest_gpu_frame_ns}
reset_gpu_frame :: proc() {latest_gpu_frame_id = 0; latest_gpu_frame_ns = 0}

capture_paused: bool


collecting: bool


FPS_SAMPLES :: 64
fps_deltas: [FPS_SAMPLES]u64
fps_delta_count: int
fps_delta_index: int

average_frame_delta_ns :: proc(window: int) -> u64 {
	n := min(window, fps_delta_count)
	if n <= 0 {
		return 0
	}
	total: u64
	for i in 0 ..< n {
		index := (fps_delta_index + 2 * FPS_SAMPLES - 1 - i) % FPS_SAMPLES
		total += fps_deltas[index]
	}
	return total / u64(n)
}


set_collection_enabled :: proc(on: bool) {collecting = on}

is_collection_enabled :: proc() -> bool {return collecting}


Begin_Manual :: proc(name: string, color: u32) -> Zone {
	if !collecting || capture_paused {return {}}
	return Zone{name, color, platform.GetTicksNS(), true}
}

@(deferred_out = End)
Begin :: proc(name: string, color: u32) -> Zone {return Begin_Manual(name, color)}

End :: proc(zone: Zone) {
	if !zone.active {
		return
	}
	end_ns := platform.GetTicksNS()
	duration := end_ns - zone.start_ns

	append(&frame_zones, Zone_Record{zone.name, zone.color, zone.start_ns, end_ns})

	for &stat in accum {
		if stat.name == zone.name {
			stat.count += 1
			stat.total_ns += duration
			stat.last_ns = duration
			stat.min_ns = min(stat.min_ns, duration)
			stat.max_ns = max(stat.max_ns, duration)
			return
		}
	}
	append(
		&accum,
		Zone_Accum {
			name = zone.name,
			color = zone.color,
			count = 1,
			total_ns = duration,
			last_ns = duration,
			min_ns = duration,
			max_ns = duration,
		},
	)
}


frame_tick :: proc(delta_time: f32) {
	if capture_paused {
		return
	}
	gc_frame_tick()
	frame_delta_ns = u64(max(f32(delta_time), 0.0) * 1_000_000_000.0)
	fps_deltas[fps_delta_index] = frame_delta_ns
	fps_delta_index = (fps_delta_index + 1) % FPS_SAMPLES
	if fps_delta_count < FPS_SAMPLES {
		fps_delta_count += 1
	}
}

frame_flush :: proc() {
	if capture_paused || !collecting {
		clear(&frame_zones)
		thread_frame_discard()
		return
	}
	thread_frame_flush()
	frame := Frame_Data {
		delta_ns = frame_delta_ns,
		gc       = gc_last_frame,
	}
	if len(history) >= MAX_HISTORY {
		frame.zones = history[0].zones
		ordered_remove(&history, 0)
		resize(&frame.zones, len(frame_zones))
	} else {
		frame.zones = make([dynamic]Zone_Record, len(frame_zones))
	}
	copy(frame.zones[:], frame_zones[:])
	append(&history, frame)
	clear(&frame_zones)
	clear(&accum)
}


frame_zones_slice :: proc() -> []Zone_Record {return frame_zones[:]}

accumulated_zones :: proc() -> []Zone_Accum {return accum[:]}

history_frames :: proc() -> []Frame_Data {return history[:]}

last_frame_delta_ns :: proc() -> u64 {return frame_delta_ns}

set_capture_paused :: proc(on: bool) {capture_paused = on}
is_capture_paused :: proc() -> bool {return capture_paused}
frame_count :: proc() -> int {return len(history)}
