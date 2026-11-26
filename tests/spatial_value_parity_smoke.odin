package main

import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)

	source := `
local function check(name, first, second)
    local value = Instance.new(name)
    local seen, last = 0, nil
    local conn = value.Changed:Connect(function(newValue)
        seen += 1
        last = newValue
    end)
    value.Value = first
    assert(seen == 1 and last == first, name .. ": Changed first value")
    value.Value = first
    assert(seen == 1, name .. ": duplicate Changed for unchanged value")
    value.Value = second
    assert(seen == 2 and last == second, name .. ": Changed second value")
    conn:Disconnect()
    value.Value = first
    assert(seen == 2, name .. ": disconnected listener fired")
    local clone = value:Clone()
    assert(clone.Value == value.Value, name .. ": clone lost Value")
end

check("Vector2Value", Vector2.new(10, 20), Vector2.new(-2, 5))
check("Vector3Value", Vector3.new(1, 2, 3), Vector3.new(4, -8, 16))
check("Color3Value", Color3.fromRGB(255, 0, 0), Color3.fromRGB(0, 255, 0))
check("CFrameValue", CFrame.new(2, 4, 8), CFrame.new(-3, 7, 5))

local part = Instance.new("Part")
local ov = Instance.new("ObjectValue")
assert(ov.Value == nil)
local seen, last = 0, false
ov.Changed:Connect(function(newValue)
    seen += 1
    last = newValue
end)
ov.Value = part
assert(seen == 1 and last == part)
ov.Value = part
assert(seen == 1)
ov.Value = nil
assert(seen == 2 and last == nil)
ov.Value = nil
assert(seen == 2)
assert(not pcall(function() ov.Value = 22 end))
`

	ok, err := vm.Run(&script_vm, source, "spatial_value_parity_smoke")
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("spatial value parity smoke failed")
	}

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("SPATIAL_VALUE_PARITY_SMOKE_PASSED")
}
