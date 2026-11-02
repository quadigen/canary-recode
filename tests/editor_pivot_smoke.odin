package main

import classes "../src/engine/classes"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

run :: proc(v: ^vm.VM, source: string) {
	ok, err := vm.RunInternal(v, source, "editor_pivot_smoke")
	assert(ok, err)
}

step :: proc(
	server: ^engine_runtime.Environment,
	sv: ^vm.VM,
	client: ^engine_runtime.Environment,
	cv: ^vm.VM,
	frames: int,
) {
	for _ in 0 ..< frames {
		engine_runtime.Environment_Render_Step(server, sv, 1.0 / 60.0)
		engine_runtime.Environment_Render_Step(client, cv, 1.0 / 60.0)
	}
}

main :: proc() {
	sv, cv := vm.New(), vm.New()
	server, client: engine_runtime.Environment
	engine_runtime.Environment_Init(&server, &sv)
	engine_runtime.Environment_Init(&client, &cv)
	run(
		&sv,
		`
local luau = game:GetService("LuauService")
local function bad(source, line)
    local d = luau:Diagnose(source)
    assert(not d.Ok, "missing diagnostic: " .. source)
    assert(d.Line == line, d.Message .. " wrong line " .. tostring(d.Line))
end
local function good(source)
    local d = luau:Diagnose(source)
    assert(d.Ok, source .. ": " .. d.Message)
end
bad("nonexistent_function()", 1)
bad("\npcall(nonexistent_function)", 2)
bad("pcall(function()\n nonexistent_function()\nend)", 2)
bad("pcall()", 1)
bad("pcall(nil)", 1)
bad("math.nonexistent_function()", 1)
bad("missing_library.nonexistent_function()", 1)
bad("xpcall(function() end)", 1)
bad("local function broken(", 1)
good("local function f() end; pcall(f)")
good("function f() end; pcall(f)")
good("local f; f = function() end; f()")
good("local function f(pcall) pcall() end")
good("print(math.abs(-2))")
good("local t = setmetatable({}, {__call = function() end}); t()")
good("local function f(game) game:UnknownDynamicMethod() end")

local function close(a, b) return (a.Position-b.Position).Magnitude < 0.001 and a.LookVector:Dot(b.LookVector) > 0.9999 end
local model = Instance.new("Model", workspace)
local a = Instance.new("Part", model)
a.Anchored = true; a.CFrame = CFrame.new(-2, 3, 0)
local nested = Instance.new("Model", model)
local b = Instance.new("Part", nested)
b.Anchored = true; b.CFrame = CFrame.new(2, 3, 0)
local before = model:GetPivot()
local relative = before:Inverse() * b.CFrame
local target = CFrame.new(20, 8, -10) * CFrame.Angles(0, math.pi/2, 0)
local notified = false
local connection = a:GetPropertyChangedSignal("CFrame"):Connect(function()
    notified = true
    assert(close(model:GetPivot(), target), "notification saw stale pivot")
    assert(close(b.CFrame, target * relative), "notification saw a partial move")
end)
model:PivotTo(target)
assert(notified); connection:Disconnect()
assert(close(model:GetPivot(), target))
assert(close(b.CFrame, target * relative), "nested part lost its offset")
for i=1,10 do model:PivotTo(target) end
assert(close(b.CFrame, target * relative), "repeated pivot drifts")
local empty = Instance.new("Model")
empty:PivotTo(target); assert(close(empty:GetPivot(), target))
local clone = empty:Clone(); assert(close(clone:GetPivot(), target)); clone:Destroy(); empty:Destroy()
model:Destroy()

assert(game:GetService("ReplicatorService"):StartServer("127.0.0.1", 39493))
local floor = Instance.new("Part", workspace)
floor.Name = "Spawn"; floor.Anchored = true
floor.Size = Vector3.new(1000, 1, 1000); floor.CFrame = CFrame.new(0, 0, 0)
`,
	)
	run(&cv, `assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1",39493))`)
	step(&server, &sv, &client, &cv, 180)
	run(
		&sv,
		`
local char = game:GetService("Players"):GetPlayers()[1].Character
assert(char and char.RootPart)
char:PivotTo(CFrame.new(30, 6, 10) * CFrame.Angles(0, 1, 0))
assert(math.abs(char:GetPivot().Position.X-30) < 0.001)
`,
	)
	step(&server, &sv, &client, &cv, 90)
	run(
		&cv,
		`
local char = game:GetService("Players").LocalPlayer.Character
assert(math.abs(char.RootPart.Position.X-30) < 0.1, "server pivot was undone")
assert(math.abs(char.RootPart.Position.Z-10) < 0.1)
assert(math.abs(char:GetPivot().LookVector.X + math.sin(1)) < 0.01, "controller undid pivot rotation")
`,
	)

	run(
		&sv,
		`local c = game:GetService("Players"):GetPlayers()[1].Character; c:PivotTo(c:GetPivot() + Vector3.new(1,0,0))`,
	)
	step(&server, &sv, &client, &cv, 90)
	run(
		&cv,
		`assert(math.abs(game:GetService("Players").LocalPlayer.Character:GetPivot().Position.X-31) < 0.1)`,
	)
	run(
		&sv,
		`assert(math.abs(game:GetService("Players"):GetPlayers()[1].Character:GetPivot().Position.X-31) < 0.1)`,
	)

	effect := classes.DepthOfFieldEffect_Init()
	effect.near_intensity = 0; effect.far_intensity = 1
	options := classes.DepthOfFieldEffect_Render_Options(&effect)
	assert(options[4] == 1 && options[5] == 32)
	assert(options[2] == 0.01 && options[1] > 1)
	effect.in_focus_radius *= 2
	wider := classes.DepthOfFieldEffect_Render_Options(&effect)
	assert(wider[1] < options[1])
	run(&cv, `game:GetService("ReplicatorService"):Stop()`)
	run(&sv, `game:GetService("ReplicatorService"):Stop()`)
	vm.Close(&cv); vm.Close(&sv)
	engine_runtime.Environment_Destroy(&client); engine_runtime.Environment_Destroy(&server)
	fmt.println("EDITOR_PIVOT_SMOKE_PASSED")
}
