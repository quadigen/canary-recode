
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
capture_paused: bool
// Recording zone/thread history costs work every frame, so it only runs once
// something actually reads the history (the profiler overlay or ProfilerService).
collecting: bool

// FPS needs only the last few frame deltas, which is cheap enough to keep
// always on so reading ProfilerService.FPS never forces full history capture.
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


/// Starts recording per-frame history. Consumers call this before reading it.
set_collection_enabled :: proc(on: bool) {collecting = on}

is_collection_enabled :: proc() -> bool {return collecting}


@(deferred_out = End)
Begin :: proc(name: string, color: u32) -> Zone {
	return Zone{name, color, platform.GetTicksNS(), collecting && !capture_paused}
}

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
	}
	frame.zones = make([dynamic]Zone_Record, len(frame_zones))
	copy(frame.zones[:], frame_zones[:])
	if len(history) >= MAX_HISTORY {
		oldest := history[0]
		delete(oldest.zones)
		ordered_remove(&history, 0)
	}
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
