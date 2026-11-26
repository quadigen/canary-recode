#+build !js
package services

import classes "../classes"
import datatypes "../datatypes"
import serializer "../serializer"
import vm "../vm"
import "core:bytes"
import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"
import "core:thread"
import "core:time"

World_Cell_IO :: struct {
	index:   int,
	reading: bool,
	path:    string,
	payload: []u8,
	ok:      bool,
}

world_cell_io_run :: proc(worker: ^thread.Thread) {
	job := cast(^World_Cell_IO)worker.data
	if !job.reading {
		staged := strings.concatenate({job.path, ".staged"})
		defer delete(staged)
		if os.write_entire_file(staged, job.payload) != nil {return}
		job.ok = os.rename(staged, job.path) == nil
		if !job.ok {_ = os.remove(staged)}
		return
	}
	file, err := os.open(job.path)
	if err != nil {return}
	defer os.close(file)
	info, stat_err := os.fstat(file, context.allocator)
	if stat_err != nil {return}
	defer os.file_info_delete(info, context.allocator)
	if info.type != .Regular || info.size <= 0 || info.size > WORLD_CELL_MAX_SNAPSHOT {return}
	job.payload = make([]u8, int(info.size))
	offset := 0
	for offset < len(job.payload) {
		count, read_err := os.read(file, job.payload[offset:])
		if count <= 0 || read_err != nil {return}
		offset += count
	}
	probe: [1]u8
	n, probe_err := os.read(file, probe[:])
	job.ok = n == 0 && (probe_err == nil || probe_err == .EOF)
}

world_cell_begin_io :: proc(
	state: ^World_Cell_Streaming,
	index: int,
	reading: bool,
	payload: []u8 = nil,
) -> bool {
	if state.worker != nil {return false}
	job := new(World_Cell_IO)
	job^ = {
		index   = index,
		reading = reading,
		path    = strings.clone(state.cells[index].path),
		payload = payload,
	}
	worker := thread.create(world_cell_io_run)
	if worker == nil {delete(job.path); free(job); return false}
	worker.data = job
	state.worker = worker
	thread.start(worker)
	return true
}

world_cell_model :: proc(workspace: ^Workspace, cell: ^World_Cell) -> ^classes.Object {

	if id, ok := workspace.cell_streaming.live_models[cell.model];
	   ok && id == cell.identity {return cell.model}
	return nil
}

world_cell_snapshot :: proc(workspace: ^Workspace, L: ^vm.State, model: ^classes.Object) -> []u8 {
	count := 0
	if !world_cell_static_tree(model, &count) {return nil}
	data, err := serializer.Serialize(workspace.signal_registry, L, model)
	if !serializer.Error_Is_None(err) {serializer.Error_Delete(&err); delete(data); return nil}
	if len(data) == 0 || len(data) > WORLD_CELL_MAX_SNAPSHOT {delete(data); return nil}
	return data
}

world_cell_static_tree :: proc(object: ^classes.Object, count: ^int) -> bool {
	if object == nil || object.destroyed {return false}
	count^ += 1
	if count^ > WORLD_CELL_MAX_NODES {return false}

	if classes.Is_A(object, "BaseScript") ||
	   classes.Is_A(object, "Humanoid") ||
	   classes.Is_A(object, "Player") ||
	   classes.Is_A(object, "Constraint") ||
	   classes.Is_A(object, "ObjectValue") ||
	   classes.Is_A(object, "WorldObject2D") ||
	   classes.Is_A(object, "Sound") {return false}
	if classes.Is_A(object, "Part") && !(cast(^classes.Part)object).anchored {return false}
	for child in object.children {if !world_cell_static_tree(child, count) {return false}}
	return true
}

world_cell_focus_points :: proc(workspace: ^Workspace, points: ^[dynamic]datatypes.Vector3) {
	state := &workspace.cell_streaming
	if state.explicit_focus {append(points, state.focus)}
	descriptor := workspace_existing_service(workspace, "ReplicatorService")
	if descriptor != nil {
		service := cast(^ReplicatorService)descriptor
		for &peer in service.peers {
			if !peer.handshake_complete {continue}
			x, y, z, ok := replication_focus(service, &peer)
			if ok {append(points, datatypes.Vector3{x, y, z})}
		}
	}
	if len(points^) == 0 &&
	   workspace.current_camera != nil &&
	   !workspace.current_camera.destroyed {
		frame := workspace.current_camera.CFrame
		append(points, datatypes.Vector3{frame.x, frame.y, frame.z})
	}
}

world_cell_distance :: proc(cell: ^World_Cell, points: []datatypes.Vector3) -> f64 {
	nearest := f64(1e30)
	for p in points {
		dx, dy, dz := cell.center.x - p.x, cell.center.y - p.y, cell.center.z - p.z
		nearest = min(nearest, max(0, math.sqrt(dx * dx + dy * dy + dz * dz) - cell.radius))
	}
	return nearest
}

world_cell_should_evict :: proc(
	workspace: ^Workspace,
	cell: ^World_Cell,
	points: []datatypes.Vector3,
) -> bool {
	state := &workspace.cell_streaming
	if !state.enabled || len(points) == 0 {return false}
	distance := world_cell_distance(cell, points)
	if distance > state.unload_radius || state.resident_bytes > state.memory_budget {return true}
	for &other in state.cells {
		if other.resident || other.failed || other.estimated_bytes > state.memory_budget {continue}
		d := world_cell_distance(&other, points)
		if d <= state.load_radius &&
		   d + (state.unload_radius - state.load_radius) * 0.25 < distance &&
		   state.resident_bytes + other.estimated_bytes > state.memory_budget {return true}
	}
	return false
}

World_Cells_Destroy :: proc(workspace: ^Workspace) {
	state := &workspace.cell_streaming
	if state.worker != nil {
		worker := cast(^thread.Thread)state.worker
		thread.join(worker)
		job := cast(^World_Cell_IO)worker.data
		delete(job.path); delete(job.payload); free(job); thread.destroy(worker)
	}
	for cell in state.cells {delete(cell.name); delete(cell.path)}
	delete(state.cells)
	delete(state.live_models)
	delete(state.focus_points)
	if state.root != "" {_ = os.remove_all(state.root); delete(state.root)}
	state^ = {}
}

World_Cells_Step :: proc(workspace: ^Workspace, L: ^vm.State) {
	state := &workspace.cell_streaming
	if L == nil ||
	   workspace.signal_registry == nil ||
	   workspace.signal_registry.mode == .Client ||
	   (!state.enabled && state.worker == nil) {return}
	start := time.now()
	clear(&state.live_models)
	for child in workspace.children {
		if child != nil && !child.destroyed {state.live_models[child] = child.unique_id}
	}
	defer {
		state.last_step_ms = f64(time.since(start)) / f64(time.Millisecond)
		state.max_step_ms = max(state.max_step_ms, state.last_step_ms)
		if state.enabled && state.last_step_ms > state.frame_budget_ms {state.budget_overruns += 1}
	}
	clear(&state.focus_points)
	world_cell_focus_points(workspace, &state.focus_points)
	points := state.focus_points
	if state.worker != nil {
		worker := cast(^thread.Thread)state.worker
		if !thread.is_done(worker) {return}
		thread.join(worker)
		job := cast(^World_Cell_IO)worker.data
		defer {delete(job.path); delete(job.payload); free(job); thread.destroy(worker)
			state.worker = nil}
		if job.index < 0 || job.index >= len(state.cells) {return}
		cell := &state.cells[job.index]
		if !job.ok {state.failures += 1; cell.failed = true; return}
		if job.reading {
			state.bytes_read += u64(len(job.payload))
			if !state.enabled ||
			   world_cell_distance(cell, points[:]) > state.load_radius ||
			   state.resident_bytes + cell.estimated_bytes > state.memory_budget {
				state.cancelled += 1; return
			}
			for child in workspace.children {if child.name == cell.name {state.failures += 1; cell.failed = true; return}}
			model, err := serializer.Deserialize(
				workspace.signal_registry,
				L,
				nil,
				job.payload,
				fresh_unique_ids = true,
			)
			if !serializer.Error_Is_None(
				err,
			) {serializer.Error_Delete(&err); state.failures += 1; cell.failed = true; return}
			count := 0
			if model == nil ||
			   !classes.Is_A(model, "Model") ||
			   !world_cell_static_tree(model, &count) {
				if model != nil {classes.Destroy_Hierarchy(model)}
				state.failures += 1; cell.failed = true; return
			}
			classes.Set_Parent(model, &workspace.object)
			cell.model = model; cell.identity = model.unique_id; cell.resident = true
			state.resident_bytes += cell.estimated_bytes; state.loads += 1
		} else {
			state.bytes_written += u64(len(job.payload))
			state.cache_bytes += i64(len(job.payload) - cell.snapshot_bytes)
			cell.snapshot_bytes = len(job.payload)
			model := world_cell_model(workspace, cell)
			if model ==
			   nil {cell.model = nil; cell.resident = false; cell.failed = true; state.failures += 1; state.resident_bytes -= cell.estimated_bytes; return}

			fresh := world_cell_snapshot(workspace, L, model)
			defer delete(fresh)
			if !bytes.equal(fresh, job.payload) {state.cancelled += 1; return}
			if !world_cell_should_evict(workspace, cell, points[:]) {state.cancelled += 1; return}
			classes.Destroy_Hierarchy(model)
			cell.model = nil; cell.resident = false
			state.resident_bytes -= cell.estimated_bytes; state.unloads += 1
		}
		return
	}
	if !state.enabled || len(points) == 0 {return}

	if f64(time.since(start)) / f64(time.Millisecond) >= state.frame_budget_ms {return}
	farthest := -1; far_distance := f64(-1)
	nearest := -1; near_distance := f64(1e30)
	for &cell, i in state.cells {
		if cell.failed {continue}
		d := world_cell_distance(&cell, points[:])
		if cell.resident {
			if world_cell_model(workspace, &cell) ==
			   nil {cell.resident = false; cell.model = nil; cell.failed = true; state.resident_bytes -= cell.estimated_bytes; continue}
			if (d > state.unload_radius || state.resident_bytes > state.memory_budget) &&
			   d > far_distance {farthest = i; far_distance = d}
		} else if d <= state.load_radius && d < near_distance {nearest = i; near_distance = d}
	}
	if farthest < 0 &&
	   nearest >= 0 &&
	   state.resident_bytes + state.cells[nearest].estimated_bytes > state.memory_budget {
		for &cell, i in state.cells {
			if !cell.resident || cell.failed {continue}
			d := world_cell_distance(&cell, points[:])
			if d > near_distance + (state.unload_radius - state.load_radius) * 0.25 &&
			   d > far_distance {farthest = i; far_distance = d}
		}
	}
	if farthest >= 0 {
		cell := &state.cells[farthest]
		data := world_cell_snapshot(workspace, L, world_cell_model(workspace, cell))
		if data == nil {cell.failed = true; state.failures += 1; return}
		if state.cache_bytes + i64(len(data) - cell.snapshot_bytes) >
		   state.cache_budget {delete(data); state.failures += 1; return}
		if !world_cell_begin_io(state, farthest, false, data) {delete(data); state.failures += 1}
	} else if nearest >= 0 {
		cell := &state.cells[nearest]
		if state.resident_bytes + cell.estimated_bytes > state.memory_budget {return}
		if !world_cell_begin_io(state, nearest, true) {state.failures += 1}
	}
}

world_cell_number :: proc(L: ^vm.State, key: string, fallback: f64) -> (f64, bool) {
	kind := vm.GetField(L, 2, key)
	defer vm.Pop(L, 1)
	if kind == .Nil {return fallback, true}
	if kind != .Number {return 0, false}
	n := vm.ArgNumber(L, -1)
	return n, n == n && abs(n) < 1e15
}

World_Cells_Namecall :: proc(
	workspace: ^Workspace,
	L: ^vm.State,
	d: ^datatypes.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	switch method {
	case "ConfigureCellStreaming",
	     "RegisterWorldCell",
	     "SetCellStreamingFocus",
	     "GetCellStreamingStats",
	     "GetWorldCells",
	     "RetryWorldCell",
	     "UnregisterWorldCell":
	case:
		return 0, false
	}
	if vm.ThreadIsParallel(L) ||
	   workspace.signal_registry == nil ||
	   workspace.signal_registry.mode ==
		   .Client {return vm.RaiseError(L, "world cell residency requires the authoritative main thread"), true}
	state := &workspace.cell_streaming
	switch method {
	case "ConfigureCellStreaming":
		if !vm.IsTable(
			L,
			2,
		) {return vm.RaiseError(L, "ConfigureCellStreaming expects a configuration table"), true}
		size, a := world_cell_number(L, "CellSize", 256)
		load, b := world_cell_number(L, "LoadRadius", 512)
		unload, c := world_cell_number(L, "UnloadRadius", 640)
		memory, e := world_cell_number(L, "MemoryBudgetBytes", 256 * 1024 * 1024)
		budget, f := world_cell_number(L, "FrameBudgetMs", 2)
		cache, g := world_cell_number(L, "CacheBudgetBytes", 512 * 1024 * 1024)
		if !a ||
		   !b ||
		   !c ||
		   !e ||
		   !f ||
		   !g ||
		   size < 1 ||
		   size > 65536 ||
		   load < 0 ||
		   unload <= load ||
		   unload > 1e7 ||
		   memory < 1 ||
		   memory > 1024 * 1024 * 1024 ||
		   budget < 0.05 ||
		   budget > 50 ||
		   cache < 1 ||
		   cache > 2 * 1024 * 1024 * 1024 {
			return vm.RaiseError(L, "invalid cell streaming configuration or hysteresis"), true
		}
		if len(state.cells) > 0 &&
		   size !=
			   state.cell_size {return vm.RaiseError(L, "CellSize cannot change while cells are registered"), true}
		kind := vm.GetField(L, 2, "Enabled")
		enabled := true
		if kind !=
		   .Nil {if kind != .Boolean {vm.Pop(L, 1); return vm.RaiseError(L, "Enabled must be boolean"), true}
			enabled = vm.ArgBoolean(L, -1)}
		vm.Pop(L, 1)
		if state.root == "" {
			directory, err := os.make_directory_temp(
				"",
				"kinemium-world-cells-*",
				context.allocator,
			)
			if err !=
			   nil {return vm.RaiseError(L, "could not create private world cell cache"), true}
			state.root = directory
		}
		state.cell_size = size
		state.load_radius = load
		state.unload_radius = unload
		state.memory_budget = i64(memory)
		state.cache_budget = i64(cache)
		state.frame_budget_ms = budget
		state.enabled = enabled
		vm.PushBoolean(L, true)
		return 1, true
	case "RegisterWorldCell":
		if state.root ==
		   "" {return vm.RaiseError(L, "configure cell streaming before registering cells"), true}
		model := classes.Object_From_Argument(L, 2)
		if model == nil ||
		   model.destroyed ||
		   !classes.Is_A(model, "Model") ||
		   model.parent != &workspace.object ||
		   model.name ==
			   "" {return vm.RaiseError(L, "cell must be a named direct-child Model"), true}
		if len(state.cells) >=
		   WORLD_CELL_LIMIT {return vm.RaiseError(L, "world cell limit exceeded"), true}
		for cell in state.cells {if cell.name == model.name {return vm.RaiseError(L, "cell names must be unique"), true}}
		count := 0
		if !world_cell_static_tree(
			model,
			&count,
		) {return vm.RaiseError(L, "cells require <=512 static nodes; scripts, constraints and simulated bodies must remain resident"), true}
		data := world_cell_snapshot(workspace, L, model)
		if data == nil {return vm.RaiseError(L, "cell exceeds the 1 MiB snapshot limit"), true}
		defer delete(data)
		estimate := i64(count) * i64(size_of(classes.Part)) + i64(len(data)) * 2
		if !vm.IsNoneOrNil(L, 3) {
			n := vm.ArgNumber(L, 3)
			if n != n ||
			   n < f64(estimate) ||
			   n >
				   1024 *
					   1024 *
					   1024 {return vm.RaiseError(L, "cell memory estimate is below object/snapshot accounting or exceeds 1 GiB"), true}
			estimate = i64(n)
		}
		if estimate >
		   state.memory_budget {return vm.RaiseError(L, "cell exceeds configured resident memory budget"), true}
		frame, size := classes.Model_Get_Bounding_Box(cast(^classes.Model)model)
		center := datatypes.Vector3{frame.x, frame.y, frame.z}
		if center.x != center.x ||
		   center.y != center.y ||
		   center.z != center.z ||
		   abs(center.x) > 1e9 ||
		   abs(center.y) > 1e9 ||
		   abs(center.z) > 1e9 {return vm.RaiseError(L, "cell bounds must be finite"), true}

		radius := math.sqrt(size.x * size.x + size.y * size.y + size.z * size.z) * 0.5
		if radius != radius ||
		   radius >
			   state.cell_size {return vm.RaiseError(L, "cell bounds exceed CellSize; split the Model"), true}
		path := fmt.aprintf("%s/%s.kine", state.root, datatypes.UniqueId_ToString(model.unique_id))
		append(
			&state.cells,
			World_Cell {
				name = strings.clone(model.name),
				path = path,
				model = model,
				identity = model.unique_id,
				center = center,
				radius = radius,
				estimated_bytes = estimate,
				resident = true,
			},
		)
		state.resident_bytes += estimate
		vm.PushNumber(L, f64(len(state.cells)))
		return 1, true
	case "UnregisterWorldCell":
		if state.worker !=
		   nil {return vm.RaiseError(L, "wait for pending cell I/O before unregistering"), true}
		name := vm.ArgString(L, 2)
		for &cell, i in state.cells {
			if cell.name != name {continue}
			if !cell.resident {return vm.RaiseError(L, "load a cell before unregistering to preserve its content"), true}
			state.resident_bytes -=
				cell.estimated_bytes; state.cache_bytes -= i64(cell.snapshot_bytes)
			_ = os.remove(cell.path); delete(cell.path); delete(cell.name)
			ordered_remove(&state.cells, i)
			vm.PushBoolean(L, true); return 1, true
		}
		return vm.RaiseError(L, "unknown world cell"), true
	case "RetryWorldCell":
		name := vm.ArgString(L, 2)
		for &cell in state.cells {if cell.name == name {cell.failed = false; vm.PushBoolean(L, true); return 1, true}}
		return vm.RaiseError(L, "unknown world cell"), true
	case "SetCellStreamingFocus":
		if vm.IsNoneOrNil(L, 2) {state.explicit_focus = false} else {
			x, y, z := vm.ArgVector3(L, 2)
			if x != x ||
			   y != y ||
			   z != z ||
			   abs(x) > 1e9 ||
			   abs(y) > 1e9 ||
			   abs(z) > 1e9 {return vm.RaiseError(L, "streaming focus must be finite"), true}
			state.focus = {f64(x), f64(y), f64(z)}; state.explicit_focus = true
		}
		return 0, true
	case "GetCellStreamingStats":
		vm.NewTable(L, 0)
		values := [?]f64 {
			f64(len(state.cells)),
			f64(state.resident_bytes),
			f64(state.cache_bytes),
			f64(state.loads),
			f64(state.unloads),
			f64(state.cancelled),
			f64(state.failures),
			f64(state.bytes_read),
			f64(state.bytes_written),
			state.last_step_ms,
			state.max_step_ms,
			f64(state.budget_overruns),
		}
		for value, i in values {
			names := [?]string {
				"Cells",
				"EstimatedResidentBytes",
				"CacheBytes",
				"Loads",
				"Unloads",
				"Cancelled",
				"Failures",
				"BytesRead",
				"BytesWritten",
				"LastStepMs",
				"MaxStepMs",
				"BudgetOverruns",
			}
			vm.PushNumber(L, value); vm.SetField(L, -2, names[i])
		}
		vm.PushBoolean(L, state.worker != nil); vm.SetField(L, -2, "IOPending")
		return 1, true
	case "GetWorldCells":
		vm.NewTable(L, len(state.cells))
		for cell, i in state.cells {
			vm.NewTable(L, 0); vm.PushString(L, cell.name); vm.SetField(L, -2, "Name")
			vm.PushBoolean(L, cell.resident); vm.SetField(L, -2, "Resident")
			vm.PushBoolean(L, cell.failed); vm.SetField(L, -2, "Failed")
			vm.PushNumber(
				L,
				math.floor(cell.center.x / state.cell_size),
			); vm.SetField(L, -2, "CellX")
			vm.PushNumber(
				L,
				math.floor(cell.center.y / state.cell_size),
			); vm.SetField(L, -2, "CellY")
			vm.PushNumber(
				L,
				math.floor(cell.center.z / state.cell_size),
			); vm.SetField(L, -2, "CellZ")
			vm.SetArrayValue(L, -2, i + 1)
		}
		return 1, true
	}
	return 0, false
}
