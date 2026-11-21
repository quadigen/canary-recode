package main

import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

run :: proc(v: ^vm.VM, code: string) {
	ok, err := vm.RunInternal(v, code, "parallel_luau_smoke")
	if !ok {fmt.eprintln(err); delete(err); panic("parallel Luau smoke failed")}
}

main :: proc() {
	v := vm.New()
	env: engine_runtime.Environment
	engine_runtime.Environment_Init(&env, &v, nil, .Server)
	defer {
		vm.Close(&v)
		engine_runtime.Environment_Destroy(&env)
	}
	run(
		&v,
		`
local target = Instance.new("Part", workspace)
target.Name = "ParallelTarget"
target.Anchored = true
target.Size = Vector3.new(4, 4, 4)
target.Position = Vector3.new(100, 0, 0)
local probe = Instance.new("Part", workspace)
probe.Name = "ParallelProbe"
probe.Anchored = true
probe.Size = Vector3.new(1, 1, 1)
probe.Position = Vector3.new(101, 0, 0)
probe.CanQuery = false
target:AddTag("ParallelTargetTag")
workspace.Terrain:SetVoxel(60, 1, 60, 1, Enum.Material.Grass)

local model = Instance.new("Model", workspace)
model.Name = "ParallelModel"
local item = Instance.new("MeshPart", model)
item.Anchored = true
item.Position = Vector3.new(500, 0, 0)
item.Size = Vector3.new(4, 4, 4)
local attachment = Instance.new("Attachment", item)
attachment.Position = Vector3.new(1, 0, 0)
local number = Instance.new("NumberValue", model)
number.Value = 42
local locale = game:GetService("LocalizationService")
locale:LoadTranslations("en-us", '{"Hello":"Hi"}')
locale:SetLocale("en-us")
local actor = Instance.new("Actor", workspace)
actor.Name = "Worker"
assert(actor:IsA("Model"))
local scriptObject = Instance.new("Script", actor)
assert(scriptObject:GetActor() == actor)
assert(workspace:GetActor() == nil)
assert(not pcall(task.desynchronize))
scriptObject.Source = [[
 local actor = script:GetActor()
 local example = game:GetService("ExampleService")
 local collection = game:GetService("CollectionService")
 local runService = game:GetService("RunService")
 local terrain = workspace.Terrain
 local target = workspace.ParallelTarget
 local probe = workspace.ParallelProbe
 local rayParams = RaycastParams.new()
 rayParams.IncludeInstances = { target }
 local overlap = OverlapParams.new()
 overlap.IncludeInstances = { target }
 actor:BindToMessage("serial", function(n)
  actor:SetAttribute("Serial", n)
 end)
 actor:BindToMessageParallel("compute", function(n)
  assert(not pcall(function() actor.Name = "Illegal" end))
  assert(not pcall(function() actor:SetAttribute("Illegal", true) end))
  assert(not pcall(function() Instance.new("Part") end))
  assert(typeof(actor) == "Instance" or actor:IsA("Actor"))
  assert(example:Add(2, 3) == 5)
  local http = game:GetService("HttpService")
  local encoding = game:FindService("EncodingService")
  assert(game.HttpService == http)
  assert(game:FindService("NotARealService") == nil)
  assert(not pcall(function() game:GetService("NotARealService") end))
  assert(workspace.Terrain == terrain)
  local json = http:JSONEncode({ answer = 42 })
  assert(http:JSONDecode(json).answer == 42)
  assert(http:UrlDecode(http:UrlEncode("a b&c")) == "a b&c")
  assert(encoding:EncodeBase64("hello") == "aGVsbG8=")
  assert(encoding:DecodeBase64("aGVsbG8=") == "hello")
  local tween = game:GetService("TweenService")
  assert(math.abs(tween:GetValue(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.In) - 0.5) < 0.001)
  local smooth, velocity = tween:SmoothDamp(0, 1, 0, 0.2, 100, 0.016)
  assert(smooth > 0 and velocity > 0)
  local groups = game:GetService("PhysicsService")
  assert(groups:IsCollisionGroupRegistered("Default"))
  assert(#groups:GetRegisteredCollisionGroups() >= 1)
  local players = game:GetService("Players")
  assert(type(players:GetPlayers()) == "table")
  local localization = game:GetService("LocalizationService")
  assert(localization:Translate("Hello") == "Hi")
  local model = workspace.ParallelModel
  assert(model.NumberValue.Value == 42)
  assert(model.MeshPart.Position.X == 500)
  assert(model.MeshPart:GetPivot().Position.X == 500)
  assert(model.MeshPart.Attachment.WorldPosition.X == 501)
  local center, size = model:GetBoundingBox()
  assert(center.Position.X == 500 and size.X == 4)
  local camera = workspace.CurrentCamera
  assert(typeof(camera:GetRenderCFrame()) == "CFrame")
  assert(typeof(camera:ViewportPointToRay(0, 0)) == "Ray")
  assert(not pcall(function() http:GetAsync("https://example.com") end))
  assert(not pcall(function() groups:RegisterCollisionGroup("Illegal") end))
  assert(not pcall(function() model.NumberValue.Value = 1 end))
  assert(not pcall(function() localization:SetLocale("fr") end))
  local hit = workspace:Raycast(Vector3.new(100, 0, -10), Vector3.new(0, 0, 20), rayParams)
  assert(hit and hit.Instance == target, "parallel raycast")
  assert(math.abs(hit.Distance - 8) < 0.01)
  assert(workspace:Raycast(Vector3.new(100, 0, -10), Vector3.new(0, 0, -20), rayParams) == nil)
  assert(target.Position.X == 100)
  local query = workspace.GetPartBoundsInBox
  assert(query(workspace, CFrame.new(100, 0, 0), Vector3.new(8, 8, 8), overlap)[1] == target)
  assert(workspace:GetPartBoundsInRadius(Vector3.new(100, 0, 0), 3, overlap)[1] == target)
  assert(workspace:GetPartsInPart(probe, overlap)[1] == target)
  assert(collection:HasTag(target, "ParallelTargetTag"))
  assert(collection:GetTagged("ParallelTargetTag")[1] == target)
  assert(runService:IsServer())
  assert(terrain:GetVoxel(60, 1, 60).material == Enum.Material.Grass)
  assert(terrain.VoxelSize > 0)
  assert(not pcall(function() target.Position = Vector3.zero end))
  assert(not pcall(function() collection:RemoveTag(target, "ParallelTargetTag") end))
  assert(not pcall(function() terrain:SetVoxel(60, 1, 60, 0) end))
  assert(not pcall(function() terrain:GenerateChunk(0, 0, 0) end))
  assert(not pcall(function() workspace:Disable3D() end))
  local echo = example.Echo
  assert(echo(example, "hello") == "hello")
  assert(example.CallCount >= 2)
  example.ParallelValue = 123
  assert(example.ParallelValue == 123)
  assert(not pcall(function() example:MakeColor(1, 0, 0) end))
  assert(not pcall(function() example.CallCount = 0 end))
  assert(not pcall(function() return example.MakeColor end))
  task.wait()
  assert(not pcall(function() actor.Name = "Illegal" end))
  task.synchronize()
  actor:SetAttribute("Result", n * n)
 end)
 local signal = Instance.new("BindableEvent", actor)
 signal.Name = "TestSignal"
 signal.Event:ConnectParallel(function(n)
  assert(not pcall(function() actor.Name = "Illegal" end))
  task.synchronize()
  actor:SetAttribute("SignalResult", n)
 end)
 actor:SetAttribute("Ready", true)
 task.desynchronize()
 assert(not pcall(function() actor.Name = "Illegal" end))
 task.synchronize()
 actor:SetAttribute("Transition", true)
]]
`,
	)
	for _ in 0 ..< 8 {
		engine_runtime.Environment_Update_Step(&env, &v, 1.0 / 60.0)
		engine_runtime.Environment_Render_Step(&env, &v, 1.0 / 60.0)
	}
	run(
		&v,
		`
local a = workspace.Worker
assert(a:GetAttribute("Ready") and a:GetAttribute("Transition"))
a:SendMessage("compute", 7)
a:SendMessage("serial", 9)
a.TestSignal:Fire(11)
assert(a:GetAttribute("Serial") == nil)
`,
	)
	for _ in 0 ..< 8 {
		engine_runtime.Environment_Update_Step(&env, &v, 1.0 / 60.0)
		engine_runtime.Environment_Render_Step(&env, &v, 1.0 / 60.0)
	}
	run(
		&v,
		`
local a = workspace.Worker
assert(a:GetAttribute("Result") == 49)
assert(a:GetAttribute("Serial") == 9)
assert(a:GetAttribute("SignalResult") == 11)
assert(a:GetAttribute("Illegal") == nil)
assert(game:GetService("ExampleService").ParallelValue == 123)
assert(typeof(a.TestSignal.Event) == "KinemiumScriptSignal")
a:Destroy()
workspace.ParallelTarget:Destroy()
workspace.ParallelProbe:Destroy()
workspace.ParallelModel:Destroy()
`,
	)
	fmt.println("PASSED: parallel Luau compatibility smoke")
}
