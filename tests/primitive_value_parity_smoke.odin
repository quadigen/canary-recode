package main

import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)

	source := `
local function check(className, defaultValue, firstValue, secondValue)
    local value = Instance.new(className)
    assert(value.Value == defaultValue, className .. ": wrong default Value")
    local changed = {}
    local propertyChanges = 0
    local conn = value.Changed:Connect(function(newValue)
        table.insert(changed, newValue)
    end)
    value:GetPropertyChangedSignal("Value"):Connect(function()
        propertyChanges += 1
    end)
    value.Value = firstValue
    assert(#changed == 1 and changed[1] == firstValue, className .. ": Changed must fire the new Value")
    value.Value = firstValue
    assert(#changed == 1, className .. ": unchanged assignment must not fire Changed")
    value.Value = secondValue
    assert(#changed == 2 and changed[2] == secondValue, className .. ": second Changed argument incorrect")
    assert(propertyChanges >= 2, className .. ": property changed notification missing")
    conn:Disconnect()
    value.Value = firstValue
    assert(#changed == 2, className .. ": disconnected listener fired")
    local cloned = value:Clone()
    assert(cloned.Value == value.Value and cloned.ClassName == value.ClassName)
    cloned.Value = secondValue
    assert(value.Value == firstValue, className .. ": clone mutated original")
end

check("BoolValue", false, true, false)
check("NumberValue", 0, 12.25, -18.5)
check("IntValue", 0, 64, -12)
check("StringValue", "", "first", "second")

local value = Instance.new("NumberValue")
local count = 0
value.Changed:Connect(function(v)
    count += 1
    assert(v == 5)
end)
value.Value = 5
assert(count == 1)
`

	ok, err := vm.Run(&script_vm, source, "primitive_value_parity_smoke")
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("primitive value parity smoke failed")
	}

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("PRIMITIVE_VALUE_PARITY_SMOKE_PASSED")
}
