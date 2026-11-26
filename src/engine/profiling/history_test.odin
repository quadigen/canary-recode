package profiling

import "core:testing"

@(test)
recycled_history_test :: proc(t: ^testing.T) {
	set_collection_enabled(true)
	defer {
		for frame in history {delete(frame.zones)}
		delete(history)
		history = nil
		reset_thread_state()
		delete(thread_history)
		thread_history = nil
		delete(frame_dirty_records)
		frame_dirty_records = nil
		delete(frame_zones)
		frame_zones = nil
		set_collection_enabled(false)
	}
	record := Thread_Record {
		id    = 42,
		alive = true,
	}
	for i in 1 ..< MAX_HISTORY + 101 {
		frame_tick(f32(i) / 100000.0)
		append(&frame_zones, Zone_Record{name = "sample", start_ns = u64(i), end_ns = u64(i + 1)})
		record.frame_cpu_ns = u64(i)
		record.frame_resumes = 1
		thread_record_touch(&record)
		frame_flush()
	}
	testing.expect_value(t, len(history), MAX_HISTORY)
	testing.expect_value(t, len(thread_history), MAX_HISTORY)
	for i in 0 ..< MAX_HISTORY {
		testing.expect_value(t, len(history[i].zones), 1)
		testing.expect_value(t, history[i].zones[0].start_ns, u64(i + 101))
		testing.expect_value(t, thread_history[i].serial, u64(i + 101))
		testing.expect_value(t, len(thread_history[i].rows), 1)
		testing.expect_value(t, thread_history[i].rows[0].cpu_ns, u64(i + 101))
		testing.expect_value(t, thread_history[i].rows[0].id, u64(42))
	}
}
