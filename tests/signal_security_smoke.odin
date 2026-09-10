package main

import "core:fmt"
import engine_runtime "../src/engine/runtime"
import renderer "../src/engine/renderer"
import vm "../src/engine/vm"

run_user_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("signal security user-script test failed")
	}
}

run_internal_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.RunInternal(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("signal security internal-script test failed")
	}
}

main :: proc() {
	script_vm := vm.New()
	renderer_object: renderer.RendererObject
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm, &renderer_object)

	// Normal scripts have no internal capability and cannot mutate Signals.
	run_user_script(&script_vm, `
local current = SecurityCapabilities.fromCurrent()
assert(not current:Contains(Enum.SecurityCapability.RunClientScript))

signal = Signal.new()
normalCallbackRan = false
normalCallbackCouldFire = nil

local ok = pcall(function()
    signal:Fire("denied")
end)
assert(not ok)

local part = Instance.new("Part")
local setCapsOk = pcall(function()
    part.Capabilities = current
end)
assert(not setCapsOk)

signal:Connect(function()
    normalCallbackRan = true
    normalCallbackCouldFire = pcall(function()
        signal:Fire("escalated")
    end)
end)
`, "signal_security_user")

	// Internal execution gets the reserved engine capabilities.
	run_internal_script(&script_vm, `
local current = SecurityCapabilities.fromCurrent()
assert(current:Contains(Enum.SecurityCapability.RunClientScript))

local part = Instance.new("Part")
assert(pcall(function()
    part.Capabilities = current
end))

signal:Fire("allowed")
assert(normalCallbackRan)
assert(normalCallbackCouldFire == false)

-- Native Luau coroutine creation inherits the creating thread's security context.
local co = coroutine.create(function()
    local nested = Signal.new()
    local fired = pcall(function()
        nested:Fire()
    end)
    assert(fired)
end)
local resumed, resumeError = coroutine.resume(co)
assert(resumed, resumeError)
`, "signal_security_internal")

	// RunInternal restores the root thread's previous user-level context.
	run_user_script(&script_vm, `
assert(not SecurityCapabilities.fromCurrent():Contains(Enum.SecurityCapability.RunClientScript))
assert(not pcall(function()
    signal:Fire()
end))
`, "signal_security_restored")

	engine_runtime.Environment_Destroy(&environment)
	vm.Close(&script_vm)
	fmt.println("SIGNAL_SECURITY_SMOKE_PASSED")
}
