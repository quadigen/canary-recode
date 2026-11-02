package main

import profiling "../src/engine/profiling"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("thread profiler smoke test failed")
	}
}

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)

	run_script(
		&script_vm,
		`
local profiler = game:GetService("ProfilerService")
assert(profiler.TrackingEnabled == true)

for i = 1, 8 do
	task.spawn(function()
		local acc = 0
		for n = 1, 200000 do
			acc = acc + n * 0.5
		end
		assert(acc > 0)
		task.wait(10)
	end)
end

-- Tasks that finish immediately: their records retire before the busy ones, so
-- they exercise the retained per-script fold.
for i = 1, 3 do
	task.spawn(function()
		local s = 0
		for n = 1, 1000 do s = s + n end
	end)
end
`,
		"thread_profiler_spawn",
	)

	for _ in 0 ..< 4 {
		engine_runtime.Environment_Update_Step(&environment, &script_vm, 1.0 / 60.0)
		engine_runtime.Environment_Render_Step(&environment, &script_vm, 1.0 / 60.0)
	}

	run_script(
		&script_vm,
		`
local profiler = game:GetService("ProfilerService")

local threads = profiler:GetThreads()
assert(type(threads) == "table")
assert(#threads >= 8, "expected at least the 8 spawned tasks, got " .. #threads)

local namedSpawn = false
local statuses = { Running = true, Suspended = true, Normal = true, Finished = true, Error = true, Dead = true }
for _, thread in ipairs(threads) do
	assert(type(thread.Id) == "number" and thread.Id > 0)
	assert(type(thread.Name) == "string" and #thread.Name > 0, "thread name must not be empty")
	assert(statuses[thread.Status] ~= nil, "unexpected status: " .. tostring(thread.Status))
	assert(type(thread.CpuMs) == "number" and thread.CpuMs >= 0)
	assert(type(thread.TotalCpuMs) == "number" and thread.TotalCpuMs >= 0)
	assert(type(thread.Resumes) == "number" and thread.Resumes >= 1)
	assert(type(thread.LiveBytes) == "number")
	assert(type(thread.AllocatedBytes) == "number")
	assert(type(thread.FrameCpuMs) == "number")
	if thread.Name:find("task", 1, true) then
		namedSpawn = true
	end
end
assert(namedSpawn, "spawned tasks should carry a task.* thread name")

local stats = profiler:GetThreadStats()
assert(type(stats) == "table")
assert(stats.threads >= 8)
assert(stats.deadThreads >= 0)
assert(type(stats.frameCpuMs) == "number")
assert(type(stats.totalCpuMs) == "number" and stats.totalCpuMs > 0)
assert(stats.frameResumes >= 0)
assert(type(stats.heapBytes) == "number" and stats.heapBytes > 0)
assert(stats.trackedLiveBytes >= 0)
assert(stats.trackingEnabled == true)
assert(stats.paused == false)

-- At least one of the last few frames must contain per-thread rows, because
-- the busy tasks ran inside them.
local foundRows = false
for index = 1, 4 do
	local history = profiler:GetThreadHistory(index)
	if history ~= nil then
		assert(history.index == index)
		assert(type(history.threads) == "table")
		for _, row in ipairs(history.threads) do
			assert(type(row.id) == "number" and row.id > 0)
			assert(type(row.name) == "string" and #row.name > 0)
			assert(type(row.cpuMs) == "number" and row.cpuMs >= 0)
			assert(type(row.resumes) == "number")
			foundRows = true
		end
	end
end
assert(foundRows, "expected per-thread rows in recent history")

assert(profiler:GetThreadHistory(0) == nil)
assert(profiler:GetThreadHistory(9999) == nil)

-- Retained per-script aggregate: every spawned task shares the "task.spawn"
-- identity, so they roll up into a single row.
local scripts = profiler:GetScripts()
assert(type(scripts) == "table")
assert(#scripts >= 1, "expected at least one script row")

local taskRow = nil
for _, row in ipairs(scripts) do
	assert(type(row.Name) == "string" and #row.Name > 0, "script name must not be empty")
	assert(type(row.CpuMs) == "number" and row.CpuMs >= 0)
	assert(type(row.TotalCpuMs) == "number" and row.TotalCpuMs >= 0)
	assert(type(row.Resumes) == "number" and row.Resumes >= 1)
	assert(type(row.AllocatedBytes) == "number")
	assert(type(row.FreedBytes) == "number")
	assert(type(row.LiveBytes) == "number")
	assert(type(row.Threads) == "number" and row.Threads >= 1)
	assert(type(row.AliveThreads) == "number" and row.AliveThreads >= 0)
	assert(row.AliveThreads <= row.Threads)
	if row.Name:find("task", 1, true) then
		taskRow = row
	end
end
assert(taskRow ~= nil, "spawned tasks should roll up under a task.* script row")
assert(taskRow.Threads >= 8, "expected the 8 busy tasks to roll into one row")

-- Tracking toggle: CPU counters keep working, memory attribution restarts.
profiler:SetTrackingEnabled(false)
assert(profiler.TrackingEnabled == false)
local offStats = profiler:GetThreadStats()
assert(offStats.trackingEnabled == false)
assert(offStats.trackedLiveBytes == 0)
assert(offStats.threads >= 8)

profiler:SetTrackingEnabled(true)
assert(profiler.TrackingEnabled == true)
assert(profiler:GetThreadStats().trackingEnabled == true)
`,
		"thread_profiler_verify",
	)

	records := profiling.all_thread_records()
	alive := 0
	for record in records {
		if record.alive {
			alive += 1
		}
	}
	assert(len(records) >= 8, "expected thread records to exist")
	assert(alive >= 8, "expected at least 8 live thread records")
	assert(profiling.is_tracking_enabled())


	root := profiling.caller_root(script_vm.L)
	synthetic := new(profiling.Thread_Record)
	synthetic.root = root
	synthetic.name = "synthetic_script"
	synthetic.script = "synthetic_script"
	synthetic.cpu_ns = 42_000_000
	synthetic.resumes = 3
	profiling.fold_into_script_totals(synthetic)
	free(synthetic)

	stats := profiling.script_stats(root)
	defer delete(stats)
	retained := false
	for stat in stats {
		if stat.name == "synthetic_script" {
			assert(stat.cpu_ns == 42_000_000, "retained CPU total must survive record teardown")
			assert(stat.resumes == 3)
			assert(stat.threads == 1)
			retained = true
		}
	}
	assert(retained, "retained script total must appear in script_stats")

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("THREAD_PROFILER_SMOKE_PASSED")
}
