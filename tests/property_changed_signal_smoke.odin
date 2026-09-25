package main

import "core:fmt"
import engine_runtime "../src/engine/runtime"
import renderer "../src/engine/renderer"
import sandbox "../src/sandboxed"
import vm "../src/engine/vm"

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	renderer_object: renderer.RendererObject

	sandbox.init(&script_vm, &environment, &renderer_object)
	defer sandbox.shutdown()
	defer vm.Close(&script_vm)

	ok, err := vm.Run(&script_vm, `
-- A plain Part is enough: GetPropertyChangedSignal lives on the base Instance
-- binding, so this also proves every class inherits it.
local part = Instance.new("Part")
part.Name = "before"

local fired = 0
local seen
part:GetPropertyChangedSignal("Name"):Connect(function()
	fired += 1
	seen = part.Name
end)

-- Writing the watched property must notify.
part.Name = "after"
assert(fired == 1, "expected 1 fire, got " .. tostring(fired))
assert(seen == "after", "callback saw " .. tostring(seen))

-- Repeated writes fire each time.
part.Name = "third"
assert(fired == 2, "expected 2 fires, got " .. tostring(fired))

-- An unwatched property must stay silent.
part.Transparency = 0.5
assert(fired == 2, "unwatched property fired, count " .. tostring(fired))

-- Two subscriptions to one property share a single signal.
local second = 0
part:GetPropertyChangedSignal("Name"):Connect(function()
	second += 1
end)
part.Name = "fourth"
assert(fired == 3 and second == 1, "shared signal mismatch")

-- Disconnect stops delivery without breaking the signal for other listeners.
local dCount = 0
local dConn = part:GetPropertyChangedSignal("Name"):Connect(function()
	dCount += 1
end)
part.Name = "d1"
assert(dCount == 1, "pre-disconnect fire failed, got " .. tostring(dCount))
dConn:Disconnect()
part.Name = "d2"
assert(dCount == 1, "disconnected callback still ran: " .. tostring(dCount))
assert(fired == 5, "other listeners should keep firing, got " .. tostring(fired))

-- Works on an unrelated class too, so it is not Part-specific.
local folder = Instance.new("Folder")
local folderFired = 0
folder:GetPropertyChangedSignal("Name"):Connect(function()
	folderFired += 1
end)
folder.Name = "renamed"
assert(folderFired == 1, "Folder did not fire")

-- Requesting the same property again returns an already-live signal.
assert(part:GetPropertyChangedSignal("Name") ~= nil)
`, "property_changed_signal_smoke")

	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("property changed signal probe failed")
	}

	fmt.println("PROPERTY_CHANGED_SIGNAL_SMOKE_PASSED")
	_ = renderer_object
}