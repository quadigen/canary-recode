package main
import classes "../src/engine/classes"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:time"

run :: proc(v: ^vm.VM, source: string) {
	ok, err := vm.RunInternal(v, source, "cell_residency_smoke")
	if !ok {fmt.eprintln(err); delete(err); panic("world cell script failed")}
}
step :: proc(env: ^engine_runtime.Environment, v: ^vm.VM) {
	engine_runtime.Environment_Update_Step(env, v, 1.0 / 60.0)
	time.sleep(time.Millisecond)
}
main :: proc() {
	v := vm.New(); env: engine_runtime.Environment
	engine_runtime.Environment_Init(&env, &v)
	defer {vm.Close(&v); engine_runtime.Environment_Destroy(&env)}
	run(
		&v,
		`
 assert(not pcall(function() workspace:ConfigureCellStreaming({LoadRadius=20,UnloadRadius=10}) end))
 assert(workspace:ConfigureCellStreaming({CellSize=64,LoadRadius=30,UnloadRadius=60,MemoryBudgetBytes=1048576,FrameBudgetMs=2}))
 workspace:SetCellStreamingFocus(Vector3.zero)
 local dynamic=Instance.new("Model",workspace);dynamic.Name="Dynamic"
 local body=Instance.new("Part",dynamic);body.Anchored=false
 assert(not pcall(function() workspace:RegisterWorldCell(dynamic) end));dynamic:Destroy()
 local scripted=Instance.new("Model",workspace);scripted.Name="Scripted"
 Instance.new("Script",scripted)
 assert(not pcall(function() workspace:RegisterWorldCell(scripted) end));scripted:Destroy()
 for _,x in ipairs({0,256}) do
  local cell=Instance.new("Model",workspace);cell.Name="Cell"..x
  local p=Instance.new("Part",cell);p.Name="Stone";p.Anchored=true;p.Position=Vector3.new(x,0,0)
  cell:SetAttribute("Saved",x)
  assert(workspace:RegisterWorldCell(cell)>0)
 end
 assert(not pcall(function() workspace:RegisterWorldCell(workspace.Cell0) end))
 `,
	)
	ws := cast(^services.Workspace)services.Ensure_Service(&env.services, "Workspace")

	step(&env, &v)
	assert(ws.cell_streaming.worker != nil)
	run(
		&v,
		`workspace:SetCellStreamingFocus(Vector3.new(256,0,0));workspace.Cell256:SetAttribute("DuringWrite",42)`,
	)
	for _ in 0 ..< 50 {step(&env, &v); if ws.cell_streaming.cancelled > 0 {break}}
	assert(ws.cell_streaming.cancelled > 0, "focus/edit must invalidate an in-flight eviction")
	run(
		&v,
		`assert(workspace:FindFirstChild("Cell256")~=nil,"focus change must preserve the live cell")`,
	)
	run(&v, `workspace:SetCellStreamingFocus(Vector3.zero)`)
	for _ in 0 ..< 1000 {step(&env, &v); if ws.cell_streaming.unloads >= 1 && !ws.cell_streaming.cells[1].resident {break}}
	assert(!ws.cell_streaming.cells[1].resident, "far cell must unload")
	run(
		&v,
		`assert(workspace:FindFirstChild("Cell256")==nil);workspace:SetCellStreamingFocus(Vector3.new(256,0,0))`,
	)
	for _ in 0 ..< 1000 {step(&env, &v); if ws.cell_streaming.cells[1].resident && ws.cell_streaming.loads > 0 {break}}
	assert(ws.cell_streaming.cells[1].resident, "near cell must load asynchronously")
	run(
		&v,
		`
 assert(workspace.Cell256:GetAttribute("Saved")==256)
 assert(workspace.Cell256:GetAttribute("DuringWrite")==42)
 assert(workspace.Cell256.Stone.Anchored)
 workspace:SetCellStreamingFocus(Vector3.new(300,0,0))
 `,
	)
	for _ in 0 ..< 10 {step(&env, &v)}
	assert(
		ws.cell_streaming.cells[1].resident,
		"hysteresis must keep a loaded cell between load and unload radii",
	)

	run(&v, `workspace.Cell256:Destroy()`)
	step(&env, &v)
	assert(ws.cell_streaming.cells[1].failed)
	assert(ws.cell_streaming.bytes_read > 0 && ws.cell_streaming.bytes_written > 0)
	fmt.printf(
		"WORLD_CELL_RESIDENCY_SMOKE_PASSED loads=%d unloads=%d cancelled=%d read=%d written=%d max_step_ms=%.3f budget_overruns=%d\n",
		ws.cell_streaming.loads,
		ws.cell_streaming.unloads,
		ws.cell_streaming.cancelled,
		ws.cell_streaming.bytes_read,
		ws.cell_streaming.bytes_written,
		ws.cell_streaming.max_step_ms,
		ws.cell_streaming.budget_overruns,
	)
	if len(os.args) > 1 && os.args[1] == "--bench" {
		services.World_Cells_Destroy(ws)
		run(
			&v,
			`
   for _,child in ipairs(workspace:GetChildren()) do if child:IsA("Model") then child:Destroy() end end
   workspace:ConfigureCellStreaming({CellSize=64,LoadRadius=100000,UnloadRadius=100100,MemoryBudgetBytes=134217728,FrameBudgetMs=2})
   workspace:SetCellStreamingFocus(Vector3.zero)
   for i=1,1024 do
    local cell=Instance.new("Model",workspace);cell.Name="BenchmarkCell"..i
    local p=Instance.new("Part",cell);p.Anchored=true;p.Position=Vector3.new(i*4,0,0)
    workspace:RegisterWorldCell(cell)
   end
  `,
		)
		for _ in 0 ..< 30 {services.World_Cells_Step(ws, v.L)}
		samples: [300]f64
		for &sample in samples {services.World_Cells_Step(ws, v.L); sample = ws.cell_streaming.last_step_ms}
		slice.sort(samples[:])
		fmt.printf(
			"WORLD_CELL_RESIDENCY_BENCH cells=1024 p50_ms=%.4f p95_ms=%.4f p99_ms=%.4f max_ms=%.4f estimated_bytes=%d\n",
			samples[150],
			samples[285],
			samples[297],
			samples[299],
			ws.cell_streaming.resident_bytes,
		)
	}

}
