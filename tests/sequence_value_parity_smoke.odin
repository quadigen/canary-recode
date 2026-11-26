package main

import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)
	source := `
local function check(name, a, sameA, b)
    local v = Instance.new(name)
    local seen, latest = 0, nil
    v.Changed:Connect(function(newValue)
        seen += 1
        latest = newValue
    end)
    v.Value = a
    assert(seen == 1 and latest == a, name .. ": first Changed(newValue)")
    v.Value = sameA
    assert(seen == 1 and v.Value == a, name .. ": duplicate keypoints fired Changed")
    v.Value = v.Value
    assert(seen == 1 and v.Value == a, name .. ": self-assignment modified the value")
    v.Value = b
    assert(seen == 2 and latest == b, name .. ": second Changed(newValue)")
    local cloned = v:Clone()
    assert(cloned.Value == b, name .. ": clone lost keypoints")
    cloned.Value = a
    assert(v.Value == b, name .. ": clone mutation affected original")
end

local a = NumberSequence.new(0.5, 1.5)
check("NumberSequenceValue", a, NumberSequence.new(0.5, 1.5), NumberSequence.new(-2, 10))

local red = Color3.fromRGB(255, 0, 0)
local blue = Color3.fromRGB(0, 0, 255)
local green = Color3.fromRGB(0, 255, 0)
local c = ColorSequence.new(red, blue)
check("ColorSequenceValue", c, ColorSequence.new(red, blue), ColorSequence.new(green, red))
`
	ok, err := vm.Run(&script_vm, source, "sequence_value_parity_smoke")
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("sequence value parity smoke failed")
	}
	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("SEQUENCE_VALUE_PARITY_SMOKE_PASSED")
}
