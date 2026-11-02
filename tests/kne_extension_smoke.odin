package main

import classes "../src/engine/classes"
import extensions "../src/engine/extensions"
import engine_runtime "../src/engine/runtime"
import serializer "../src/engine/serializer"
import services "../src/engine/services"
import target "../src/engine/target"
import vm "../src/engine/vm"
import "core:fmt"

expect :: proc(ok: bool, message: string) {
	if !ok {
		panic(message)
	}
}

run :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.RunInternal(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		panic(name)
	}
}

main :: proc() {
	target.set_mode(.Editor)

	script_vm := vm.New()

	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm, nil, .Editor)

	loaded, discover_err := extensions.Discover(&environment.extensions, "build/kne-extensions")
	if discover_err != "" {
		fmt.eprintln(discover_err)
	}
	expect(discover_err == "", "extension discovery reported an error")
	expect(loaded == 1, "expected exactly one KNE extension to load")

	run(
		&script_vm,
		`
assert(KNE ~= nil, "KNE global missing")
assert(typeof(KNE.GetExtensions) == "function")

local list = KNE.GetExtensions()
assert(#list == 1, "extension count: " .. #list)
assert(list[1].Id == "kne.hello", "id: " .. tostring(list[1].Id))
assert(list[1].State == "running", "state: " .. tostring(list[1].State))

assert(HelloKNE ~= nil, "HelloKNE library missing")
assert(HelloKNE.Calculate(10, 20) == 30, "Calculate")
assert(HelloKNE.Greeting("world") == "hello world", "Greeting: " .. tostring(HelloKNE.Greeting("world")))

local counter = Instance.new("HelloCounter")
assert(counter ~= nil, "HelloCounter was not creatable")
assert(counter.ClassName == "HelloCounter")
assert(counter:IsA("Instance"))
assert(counter.Label == "counter", "default Label: " .. tostring(counter.Label))
counter.Label = "started"
assert(counter.Label == "started")
assert(counter.Updates == 0, "Updates: " .. tostring(counter.Updates) .. " type " .. typeof(counter.Updates) .. " eq " .. tostring(counter.Updates == 0))
assert(counter:Bump() == 1)
assert(counter.Updates == 1, "Updates after Bump: " .. tostring(counter.Updates))

local service = game:GetService("HelloService")
assert(service ~= nil, "HelloService missing")
assert(service:Ping() == 42, "Ping")

local tween = HelloKNE.Roundtrip(TweenInfo.new(2, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 3, true, 0.5))
assert(tween.Time == 2 and tween.EasingStyle == Enum.EasingStyle.Linear and tween.RepeatCount == 3 and tween.Reverses == true and tween.DelayTime == 0.5)
local waypoint = HelloKNE.Roundtrip(PathWaypoint.new(Vector3.new(1,2,3), Enum.PathWaypointAction.Jump, "marker"))
assert(waypoint.Position == Vector3.new(1,2,3) and waypoint.Action == Enum.PathWaypointAction.Jump and waypoint.Label == "marker")
local dock = HelloKNE.Roundtrip(DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false, true, 640, 480, 100, 80))
assert(dock.InitialDockState == Enum.InitialDockState.Float and dock.InitialEnabled == false and dock.FloatingXSize == 640 and dock.MinHeight == 80)
assert(HelloKNE.Roundtrip(Enum.EasingStyle.Linear) == Enum.EasingStyle.Linear)
local params = RaycastParams.new()
assert(HelloKNE.Roundtrip(params) == params, "stateful handle identity")
local v = HelloVector.new(3,4)
assert(typeof(v) == "HelloVector")
assert(v.X == 3 and v.Y == 4)
v.X = 6
local w = HelloKNE.NewVector(2,5)
assert(w.X == 2 and w.Y == 5)
local sum = v + w
assert(sum.X == 8 and sum.Y == 9)
assert(sum == HelloVector.new(8,9))
assert(sum:Sum() == 17)
local negative = -v
assert(negative.X == -6 and negative.Y == -4)
assert(tostring(v) == "HelloVector")
assert(HelloKNE.ApplyCallback(function(x) return x*3 end, 7) == 21)
assert(HelloKNE.ApplyCallback(function() error("expected") end, 7) == nil)
assert(HelloKNE.ApplyCallback(function(x) return {value=x} end, 9).value == 9)
assert(HelloKNE.ApplyCallback(function() return function() return 12 end end, 0)() == 12)
assert(HelloKNE.HasExport(workspace, "Raycast"))
assert(not HelloKNE.HasExport(workspace, "Destroy"))
assert(HelloKNE.ExportCount(workspace) >= 1)
local event = Instance.new("BindableEvent")
local received = 0
event.Event:Connect(function(x) received = x end)
HelloKNE.FireSignal(event.Event, 19)
assert(received == 19)
local calls = 0
assert(HelloKNE.Exercise(workspace, event.Event, function(x) calls += x end))
assert(calls == 7)
liveEvent = event
local saved = Instance.new("Folder")
saved.Name = "KNEPersistence"
saved:SetAttribute("CustomVector", v)
saved.Parent = workspace
liveVector = v
savedConstructor = HelloVector.new
counter:Destroy()
`,
		"kne_smoke",
	)

	workspace := services.Ensure_Service(&environment.services, "Workspace")
	saved := classes.Find_First_Child(workspace, "KNEPersistence")
	expect(saved != nil, "persistence fixture missing")
	bytes, save_error := serializer.Serialize(&environment.classes, script_vm.L, saved)
	serializer.Error_Print(save_error, "KNE save: ")
	expect(serializer.Error_Is_None(save_error), "extension datatype save failed")
	loaded_object, load_error := serializer.Deserialize(
		&environment.classes,
		script_vm.L,
		nil,
		bytes,
	)
	serializer.Error_Print(load_error, "KNE load: ")
	expect(serializer.Error_Is_None(load_error), "extension datatype load failed")
	classes.Push_Object(script_vm.L, loaded_object)
	vm.SetGlobalFromStack(&script_vm, "loadedKNE")
	run(
		&script_vm,
		`local v=loadedKNE:GetAttribute("CustomVector"); assert(v.X == 6 and v.Y == 4)`,
		"kne_persistence",
	)
	codec_version := environment.datatypes.extension_codecs[0].wire_version
	environment.datatypes.extension_codecs[0].wire_version += 1
	dropped, missing_error := serializer.Deserialize(&environment.classes, script_vm.L, nil, bytes)
	expect(
		serializer.Error_Is_None(missing_error) && dropped != nil,
		"missing codec should preserve the hierarchy",
	)
	classes.Push_Object(script_vm.L, dropped)
	vm.SetGlobalFromStack(&script_vm, "missingKNE")
	run(&script_vm, `assert(missingKNE:GetAttribute("CustomVector") == nil)`, "kne_missing_codec")
	environment.datatypes.extension_codecs[0].wire_version = codec_version
	serializer.Error_Delete(&missing_error)
	delete(bytes)
	serializer.Error_Delete(&save_error)
	serializer.Error_Delete(&load_error)

	vm.GetGlobal(script_vm.L, "liveVector")
	wire: [dynamic]u8
	expect(
		services.replication_encode_value(script_vm.L, -1, &wire, 0),
		"extension replication encode failed",
	)
	vm.Pop(script_vm.L)
	reader := services.Replication_Reader {
		data  = wire[:],
		valid = true,
	}
	services.replication_decode_value(script_vm.L, &reader, &environment.datatypes, 0)
	expect(reader.valid && reader.offset == len(wire), "extension replication decode failed")
	vm.SetGlobalFromStack(&script_vm, "replicatedKNE")
	run(&script_vm, `assert(replicatedKNE.X == 6 and replicatedKNE.Y == 4)`, "kne_replication")

	codec := environment.datatypes.extension_codecs[0]
	environment.datatypes.extension_codecs[0].wire_version += 1
	mismatch := services.Replication_Reader {
		data  = wire[:],
		valid = true,
	}
	services.replication_decode_value(script_vm.L, &mismatch, &environment.datatypes, 0)
	expect(mismatch.valid && vm.IsNil(script_vm.L, -1), "mismatched codec should drop the value")
	vm.Pop(script_vm.L)
	environment.datatypes.extension_codecs[0] = codec
	truncated := services.Replication_Reader {
		data  = wire[:len(wire) - 1],
		valid = true,
	}
	services.replication_decode_value(script_vm.L, &truncated, &environment.datatypes, 0)
	expect(!truncated.valid, "truncated extension payload was accepted")
	vm.Pop(script_vm.L)
	delete(wire)

	unload_error := extensions.Unload(&environment.extensions, "kne.hello")
	expect(unload_error == "", "unload failed")

	run(
		&script_vm,
		`
assert(KNE.IsLoaded("kne.hello") == false, "extension still loaded")
assert(HelloKNE == nil, "library table survived unload")
assert(HelloVector == nil)
assert(not pcall(function() return liveVector.X end))
assert(savedConstructor() == nil)
liveEvent:Fire(100)
liveEvent:Destroy()
assert(KNE.GetExtension("kne.hello") == nil)
`,
		"kne_smoke_unload",
	)

	run(
		&script_vm,
		`
local ok, load_err = KNE.Load("build/kne-extensions/hello_kne")
assert(ok == true, "KNE.Load failed: " .. tostring(load_err))
assert(HelloKNE.Calculate(1, 2) == 3)
assert(KNE.Reload("kne.hello") == true, "KNE.Reload failed")
assert(HelloKNE.Calculate(2, 2) == 4)
assert(KNE.Unload("kne.hello") == true, "KNE.Unload failed")
assert(KNE.IsLoaded("kne.hello") == false)
`,
		"kne_smoke_reload",
	)

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)

	fmt.println("KNE extension smoke PASSED")
}
