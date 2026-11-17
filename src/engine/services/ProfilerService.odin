package services

// wire:service

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import profiling "../profiling"
import vm "../vm"

// ProfilerService exposes Kinemium's native profiler to Luau.
//
// Frame records are indexed newest-first: 1 = most recently captured frame.
// GetFrameTimes and GetZoneHistory return their arrays oldest-first.
// Time values are milliseconds, allocation values are bytes.
//
// Lua numbers are doubles in this VM. Always use ArgNumber, not ArgInteger,
// for numeric Luau arguments. This fixes GetFrameRecord's argument #2 error.

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

// Reads a Luau floating-point number as a bounded count, defaulting if absent.
// The bounds are applied BEFORE the conversion to an integer.
profiler_count_arg :: proc(
	L: ^vm.State,
	arg: int,
	fallback: i64 = PROFILER_DEFAULT_COUNT,
) -> int {if vm.StackTop(L) < arg {
		return int(fallback)
	}
	value := vm.ArgNumber(L, arg)
	if value != value { 	// NaN
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

// Zone record shape: {name, color, ms, startMs}.
// startMs is relative to the earliest zone in that frame, not the frame boundary.
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

// Returns a single snapshot including a short, newest-first history.
profiler_push_frame_stats :: proc(L: ^vm.State) {
	frames := profiling.history_frames()
	vm.NewTable(L, 0, 8)
	profiler_push_bool(L, "enabled", profiling.is_enabled())
	profiler_push_bool(L, "paused", profiling.is_capture_paused())
	profiler_push_bool(L, "collectionEnabled", profiling.is_collection_enabled())
	profiler_push_number(L, "frameCount", f64(len(frames)))
	profiler_push_number(L, "frameMs", profiler_frame_ms())
	profiler_push_number(L, "fps", profiler_fps())

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

// Oldest-to-newest frame durations.
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

// Oldest-to-newest total duration of all matching zones in each frame.
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

// Optional convenience API for per-zone summaries of the current capture ring.
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

// Cumulative + current-frame fields, keeping the exact names the UI expects.
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

// Unlike GetThreads, historical rows represent per-frame counters.
// History may contain retired threads; only retained IDs in the current VM
// can be resolved to names by the native tracking backend.
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

	case "GetFrameStats":
		profiling.set_collection_enabled(true)
		profiler_push_frame_stats(L)
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
		// Do not turn off the fullscreen F2 profiler's active capture.
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

// Existing F2 fullscreen profiler overlay, kept for compatibility.

PROFILER_OVERLAY_SOURCE :: `local profiler = game:GetService("ProfilerService")

local ROW_H = 18

local MAX_ROWS = 16

local GRAPH_POINTS = 60

local PANEL_BG = Color3.new(0.055, 0.07, 0.10)

local GRAPH_BG = Color3.new(0.09, 0.11, 0.14)

local ROW_BG = Color3.new(0.13, 0.145, 0.18)

local TEXT = Color3.new(0.82, 0.86, 0.92)

local DIM = Color3.new(0.45, 0.50, 0.58)

local ACCENT = Color3.new(0.337, 0.714, 0.761)

local function colorFromRGB(c)

    return Color3.new(

        math.floor(c / 65536) / 255,

        math.floor((c % 65536) / 256) / 255,

        (c % 256) / 255

    )

end

local function makeLabel(parent, text, size, color)

    local l = Instance.new("TextLabel")

    l.Parent = parent

    l.Text = text or ""

    l.TextSize = size or 12

    l.TextColor3 = color or TEXT

    l.BackgroundTransparency = 1

    return l

end

local screenGui = Instance.new("ScreenGui")

screenGui.Name = "ProfilerOverlay"

screenGui.RenderOnTop = true

screenGui.IgnoreGuiInset = true

screenGui.Enabled = profiler.Enabled

-- Panel fills the whole screen.

local panel = Instance.new("Frame")

panel.Name = "Panel"

panel.Parent = screenGui

panel.Position = UDim2.new(0, 0, 0, 0)

panel.Size = UDim2.new(1, 0, 1, 0)

panel.BackgroundColor3 = PANEL_BG

panel.BackgroundTransparency = 0.06

panel.ZIndex = 1

-- Header --------------------------------

local headerBg = Instance.new("Frame")

headerBg.Parent = panel

headerBg.Position = UDim2.new(0, 0, 0, 0)

headerBg.Size = UDim2.new(1, 0, 0, 34)

headerBg.BackgroundColor3 = Color3.new(0.02, 0.025, 0.04)

headerBg.ZIndex = 2

local title = makeLabel(headerBg, "PROFILER", 15, ACCENT)

title.Position = UDim2.new(0, 12, 0, 7)

title.Size = UDim2.new(0, 120, 0, 20)

title.ZIndex = 3

local header = makeLabel(headerBg, "FPS --", 13, TEXT)

header.Position = UDim2.new(0, 140, 0, 8)

header.Size = UDim2.new(0, 260, 0, 20)

header.ZIndex = 3

-- Pause / resume button.

local pauseBtn = Instance.new("TextButton")

pauseBtn.Name = "PauseButton"

pauseBtn.Parent = headerBg

pauseBtn.Position = UDim2.new(1, -110, 0, 5)

pauseBtn.Size = UDim2.new(0, 100, 0, 24)

pauseBtn.BackgroundColor3 = ACCENT

pauseBtn.BackgroundTransparency = 0.15

pauseBtn.Text = "Pause"

pauseBtn.TextSize = 13

pauseBtn.TextColor3 = Color3.new(1, 1, 1)

pauseBtn.ZIndex = 3

-- Frame navigation (visible while paused).

local nav = Instance.new("Frame")

nav.Parent = headerBg

nav.Position = UDim2.new(1, -360, 0, 5)

nav.Size = UDim2.new(0, 240, 0, 24)

nav.BackgroundTransparency = 1

nav.ZIndex = 3

nav.Visible = profiler.Paused

local frameLabel = makeLabel(nav, "frame --/--", 13, TEXT)

frameLabel.Position = UDim2.new(0, 0, 0, 2)

frameLabel.Size = UDim2.new(0, 160, 0, 20)

frameLabel.ZIndex = 4

local prevBtn = Instance.new("TextButton")

prevBtn.Parent = nav

prevBtn.Position = UDim2.new(0, 165, 0, 0)

prevBtn.Size = UDim2.new(0, 34, 0, 22)

prevBtn.BackgroundColor3 = Color3.new(0.2, 0.25, 0.32)

prevBtn.Text = "<"

prevBtn.TextSize = 14

prevBtn.TextColor3 = TEXT

prevBtn.ZIndex = 4

local nextBtn = Instance.new("TextButton")

nextBtn.Parent = nav

nextBtn.Position = UDim2.new(0, 204, 0, 0)

nextBtn.Size = UDim2.new(0, 34, 0, 22)

nextBtn.BackgroundColor3 = Color3.new(0.2, 0.25, 0.32)

nextBtn.Text = ">"

nextBtn.TextSize = 14

nextBtn.TextColor3 = TEXT

nextBtn.ZIndex = 4

-- Body layout ----------------------------

local BODY_Y = 44

local GRAPH_H = 92

-- Frame time graph.

local graph = Instance.new("Frame")

graph.Name = "FrameGraph"

graph.Parent = panel

graph.Position = UDim2.new(0, 12, 0, BODY_Y)

graph.Size = UDim2.new(1, -24, 0, GRAPH_H)

graph.BackgroundColor3 = GRAPH_BG

graph.BackgroundTransparency = 0.25

graph.ZIndex = 2

local graphTitle = makeLabel(graph, "frame time (ms)", 11, DIM)

graphTitle.Position = UDim2.new(0, 8, 0, 4)

graphTitle.Size = UDim2.new(0, 180, 0, 16)

graphTitle.ZIndex = 3

local graphBars = {}

local barWidth = math.max(math.floor((1280 - 24) / GRAPH_POINTS), 1)

for i = 1, GRAPH_POINTS do

    local bar = Instance.new("Frame")

    bar.Parent = graph

    bar.Name = "Bar"

    bar.Size = UDim2.new(0, barWidth - 1, 0, 0)

    bar.ZIndex = 3

    graphBars[i] = bar

end

-- Bottom split: zone rows (left) + stats panel (right).

local rowArea = Instance.new("Frame")

rowArea.Parent = panel

rowArea.Position = UDim2.new(0, 12, 0, BODY_Y + GRAPH_H + 8)

rowArea.Size = UDim2.new(1, -340, 1, -(BODY_Y + GRAPH_H + 20))

rowArea.BackgroundColor3 = GRAPH_BG

rowArea.BackgroundTransparency = 0.25

rowArea.ZIndex = 2

local rowTitle = makeLabel(rowArea, "zones", 11, DIM)

rowTitle.Position = UDim2.new(0, 8, 0, 4)

rowTitle.Size = UDim2.new(0, 120, 0, 16)

rowTitle.ZIndex = 3

-- Stats panel (right column).

local statsPanel = Instance.new("Frame")

statsPanel.Name = "StatsPanel"

statsPanel.Parent = panel

statsPanel.Position = UDim2.new(1, -316, 0, BODY_Y + GRAPH_H + 8)

statsPanel.Size = UDim2.new(0, 296, 1, -(BODY_Y + GRAPH_H + 20))

statsPanel.BackgroundColor3 = GRAPH_BG

statsPanel.BackgroundTransparency = 0.25

statsPanel.ZIndex = 2

local statLabels = {}

local function addStat(name)

    local cap = makeLabel(statsPanel, name, 11, DIM)

    cap.Position = UDim2.new(0, 10, 0, 8 + #statLabels * 22)

    cap.Size = UDim2.new(0, 140, 0, 16)

    cap.ZIndex = 3

    local val = makeLabel(statsPanel, "--", 12, TEXT)

    val.Position = UDim2.new(0, 150, 0, 8 + #statLabels * 22)

    val.Size = UDim2.new(0, 136, 0, 16)

    val.ZIndex = 3

    statLabels[#statLabels + 1] = { cap = cap, val = val }

    return val

end

local statFrame = addStat("frame")

local statNumZones = addStat("zones")

local statLast = addStat("last")

local statMin = addStat("min")

local statMax = addStat("max")

local statAvg = addStat("avg")

-- Zone rows.

local rowObjs = {}

for i = 1, MAX_ROWS do

    local row = Instance.new("Frame")

    row.Parent = rowArea

    row.Position = UDim2.new(0, 8, 0, 26 + (i - 1) * ROW_H)

    row.Size = UDim2.new(1, -16, 0, ROW_H - 2)

    row.BackgroundColor3 = ROW_BG

    row.BackgroundTransparency = 0.2

    row.ZIndex = 3

    local bar = Instance.new("Frame")

    bar.Parent = row

    bar.Size = UDim2.new(0, 0, 1, 0)

    bar.BackgroundColor3 = Color3.new(0.3, 0.6, 0.3)

    bar.BackgroundTransparency = 0.1

    bar.ZIndex = 4

    local name = makeLabel(row, "", 12, TEXT)

    name.Position = UDim2.new(0, 6, 0, 0)

    name.Size = UDim2.new(1, -110, 1, 0)

    name.TextXAlignment = Enum.TextXAlignment.Left

    name.ZIndex = 4

    local time = makeLabel(row, "", 12, DIM)

    time.Position = UDim2.new(1, -76, 0, 0)

    time.Size = UDim2.new(0, 70, 1, 0)

    time.TextXAlignment = Enum.TextXAlignment.Right

    time.ZIndex = 4

    rowObjs[i] = { bar = bar, name = name, time = time }

end

-- Pause / navigation logic ---------------

local selected = 1

local function pauseSet(on)

    if on then

        profiler:Pause()

    else

        profiler:Resume()

    end

    nav.Visible = on

    pauseBtn.Text = on and "Resume" or "Pause"

end

pauseBtn.MouseButton1Click:Connect(function()

    pauseSet(not profiler.Paused)

end)

prevBtn.MouseButton1Click:Connect(function()

    -- Previous = older frame = larger index (1 = newest).

    if selected < profiler.FrameCount then

        selected = selected + 1

    end

end)

nextBtn.MouseButton1Click:Connect(function()

    -- Next = newer frame = smaller index.

    if selected > 1 then

        selected = selected - 1

    end

end)

local function update()

    local enabled = profiler.Enabled

    if screenGui.Enabled ~= enabled then

        screenGui.Enabled = enabled

    end

    if not enabled then

        return

    end

    local stats = profiler:GetFrameStats()

    local paused = profiler.Paused

    pauseBtn.Text = paused and "Resume" or "Pause"

    nav.Visible = paused

    -- Selected frame data. When live, use the newest frame; when paused,

    -- drop down to the recorded frame and make it the newest selection.

    local frameMs = stats.frameMs

    local fps = stats.fps

    local zones = stats.zones

    if paused then

        local count = profiler.FrameCount

        if selected < 1 then

            selected = 1

        end

        if selected > math.max(count, 1) then

            selected = math.max(count, 1)

        end

        local rec = profiler:GetFrameRecord(selected)

        if rec then

            frameMs = rec.frameMs

            fps = rec.fps

            zones = rec.zones

        end

        frameLabel.Text = string.format("frame %d/%d", selected, count)

    else

        selected = 1

        frameLabel.Text = "frame --/--"

    end

    -- Header / fps line.

    if frameMs > 0 then

        header.Text = string.format("FPS %.1f   frame %.3f ms", fps, frameMs)

        statFrame.Text = string.format("%.2f ms / %.1f fps", frameMs, fps)

    else

        header.Text = "FPS --   frame --"

        statFrame.Text = "--"

    end

    local zoneCount = 0

    if zones then

        for _ in ipairs(zones) do

            zoneCount = zoneCount + 1

        end

    end

    statNumZones.Text = tostring(zoneCount)

    -- Graph of frame times.

    local graphMax = 1

    for _, ms in ipairs(stats.history) do

        if ms > graphMax then

            graphMax = ms

        end

    end

    barWidth = math.max(math.floor((graph.AbsoluteSize.X - 16) / GRAPH_POINTS), 1)

    for i = 1, GRAPH_POINTS do

        local ms = stats.history[i]

        local h = 0

        if ms and ms > 0 then

            h = math.floor(math.min(ms / graphMax, 1) * (GRAPH_H - 28))

            if h < 1 then

                h = 1

            end

        end

        graphBars[i].Position = UDim2.new(0, 8 + (i - 1) * barWidth, 0, GRAPH_H - 8)

        graphBars[i].AnchorPoint = Vector2.new(0, 1)

        graphBars[i].BackgroundColor3 = ACCENT

        graphBars[i].Size = UDim2.new(0, math.max(barWidth - 1, 1), 0, h)

    end

    -- Min/max/avg of the history window.

    if stats.history and #stats.history > 0 then

        local mn, mx, sum, n = math.huge, 0, 0, 0

        for _, ms in ipairs(stats.history) do

            if ms > 0 then

                if ms < mn then mn = ms end

                if ms > mx then mx = ms end

                sum = sum + ms

                n = n + 1

            end

        end

        if n > 0 then

            statMin.Text = string.format("%.3f ms", mn)

            statMax.Text = string.format("%.3f ms", mx)

            statAvg.Text = string.format("%.3f ms", sum / n)

            statLast.Text = string.format("%.3f ms", stats.history[1])

        else

            statMin.Text = "--"

            statMax.Text = "--"

            statAvg.Text = "--"

            statLast.Text = "--"

        end

    end

    -- Zones sorted by time, rendered as bars.

    table.sort(zones or {}, function(a, b)

        return a.ms > b.ms

    end)

    for i = 1, MAX_ROWS do

        local row = rowObjs[i]

        local zone = zones and zones[i]

        if zone then

            row.name.Text = zone.name

            row.time.Text = string.format("%.3f ms", zone.ms)

            row.bar.Size = UDim2.new(0, math.floor(math.min(zone.ms / math.max(frameMs, 0.001), 1) * 280), 1, 0)

            row.bar.BackgroundColor3 = colorFromRGB(zone.color)

            row.Visible = true

        else

            row.name.Text = ""

            row.time.Text = ""

            row.bar.Size = UDim2.new(0, 0, 1, 0)

            row.Visible = false

        end

    end

end

while true do

    task.wait()

    update()

end

`

Register_ProfilerOverlay :: proc(registry: ^Registry, vm_state: ^vm.VM) {

	script_object, script_ok := classes.Push_New(registry.classes, vm_state, "Script", false)

	assert(script_ok && script_object != nil)

	defer vm.Pop(vm_state.L)

	classes.Set_Name(script_object, "ProfilerOverlay")

	classes.Script_Set_Source(cast(^classes.Script)script_object, PROFILER_OVERLAY_SOURCE)

	classes.Set_Parent(script_object, &registry.data_model.object)

}
