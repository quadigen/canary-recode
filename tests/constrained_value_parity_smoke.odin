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
    local v = Instance.new(name)
    local seen, last = 0, nil
    local connection = v.Changed:Connect(function(value)
        seen += 1
        last = value
    end)
    v.Value = first
    assert(seen == 1 and last == first, name .. ": first Changed(value)")
    v.Value = first
    assert(seen == 1, name .. ": unchanged value fired Changed")
    v.Value = second
    assert(seen == 2 and last == second, name .. ": second Changed(value)")
    connection:Disconnect()
    v.Value = first
    assert(seen == 2)
    local copied = v:Clone()
    assert(copied.Value == first)
end

check("BrickColorValue", BrickColor.new("Bright red"), BrickColor.new("Bright green"))
check("RayValue", Ray.new(Vector3.new(1, 0, 0), Vector3.new(0, 1, 0)), Ray.new(Vector3.new(2, 2, 2), Vector3.new(0, 0, 3)))
check("NumberRangeValue", NumberRange.new(-4, 6), NumberRange.new(5, 10))

local intValue = Instance.new("IntConstrainedValue")
intValue.MinValue = 0
intValue.MaxValue = 10
local intCount, intSeen = 0, 0
intValue.Changed:Connect(function(value)
    intCount += 1
    intSeen = value
end)
intValue.Value = 100
assert(intValue.Value == 10 and intCount == 1 and intSeen == 10)
intValue.Value = 500
assert(intCount == 1, "clamp-equivalent integer Value should not fire")
intValue.Value = -100
assert(intValue.Value == 0 and intCount == 2 and intSeen == 0)

local doubleValue = Instance.new("DoubleConstrainedValue")
doubleValue.MinValue = -1
doubleValue.MaxValue = 1
local doubleCount, doubleSeen = 0, 0
doubleValue.Changed:Connect(function(value)
    doubleCount += 1
    doubleSeen = value
end)
doubleValue.Value = 100
assert(doubleValue.Value == 1 and doubleCount == 1 and doubleSeen == 1)
doubleValue.Value = 200
assert(doubleCount == 1, "clamp-equivalent double Value should not fire")
doubleValue.Value = -50
assert(doubleValue.Value == -1 and doubleCount == 2 and doubleSeen == -1)
`
	ok, err := vm.Run(&script_vm, source, "constrained_value_parity_smoke")
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("constrained value parity smoke failed")
	}
	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("CONSTRAINED_VALUE_PARITY_SMOKE_PASSED")
}
