package main

import renderer "../src/engine/renderer"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import sandbox "../src/sandboxed"
import "core:fmt"

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	renderer_object: renderer.RendererObject

	sandbox.init(&script_vm, &environment, &renderer_object)
	defer sandbox.shutdown()
	defer vm.Close(&script_vm)

	ok, err := vm.Run(
		&script_vm,
		`
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

-- The general Instance.Changed event reports the property that changed.
local changedName
local changedCount = 0
part.Changed:Connect(function(property)
	changedCount += 1
	changedName = property
end)
part.Name = "changed-general"
assert(changedCount == 1, "Changed should fire once, got " .. tostring(changedCount))
assert(changedName == "Name", "Changed reported " .. tostring(changedName))
part.Transparency = 0.25
assert(changedCount == 2 and changedName == "Transparency", "Changed missed Transparency")

-- ValueBase subclasses use the same base event.
local toggle = Instance.new("BoolValue")
local toggleCount = 0
toggle.Changed:Connect(function()
	toggleCount += 1
end)
toggle.Value = false
assert(toggleCount == 1, "BoolValue.Changed should fire")
toggle.Value = true
assert(toggleCount == 2, "BoolValue.Changed should fire on every write")

-- A callback resumes on a new coroutine, but it still shares the firing
-- coroutine's native stack budget.
local recursive = Instance.new("Folder")
local depth = 0
recursive:GetPropertyChangedSignal("Name"):Connect(function()
	depth += 1
	if depth < 2000 then
		recursive.Name = tostring(depth)
	end
end)
recursive.Name = "start"
assert(depth > 1 and depth < 2000, "nested notifications must be bounded by Luau")
`,
		"property_changed_signal_smoke",
	)

	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("property changed signal probe failed")
	}

	fmt.println("PROPERTY_CHANGED_SIGNAL_SMOKE_PASSED")
	_ = renderer_object
}
