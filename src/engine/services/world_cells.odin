package services

import classes "../classes"
import datatypes "../datatypes"

WORLD_CELL_LIMIT :: 1024
WORLD_CELL_MAX_NODES :: 512
WORLD_CELL_MAX_SNAPSHOT :: 1024 * 1024

World_Cell :: struct {
	name:            string,
	path:            string,
	model:           ^classes.Object,
	identity:        datatypes.UniqueId,
	center:          datatypes.Vector3,
	radius:          f64,
	estimated_bytes: i64,
	snapshot_bytes:  int,
	resident:        bool,
	failed:          bool,
}

World_Cell_Streaming :: struct {
	enabled:         bool,
	cell_size:       f64,
	load_radius:     f64,
	unload_radius:   f64,
	memory_budget:   i64,
	cache_budget:    i64,
	frame_budget_ms: f64,
	root:            string,
	cells:           [dynamic]World_Cell,
	worker:          rawptr,
	live_models:     map[^classes.Object]datatypes.UniqueId,
	focus_points:    [dynamic]datatypes.Vector3,
	explicit_focus:  bool,
	focus:           datatypes.Vector3,
	resident_bytes:  i64,
	cache_bytes:     i64,
	loads:           u64,
	unloads:         u64,
	cancelled:       u64,
	failures:        u64,
	bytes_read:      u64,
	bytes_written:   u64,
	last_step_ms:    f64,
	max_step_ms:     f64,
	budget_overruns: u64,
}
