package main

import "core:fmt"
import datatypes "../src/engine/datatypes"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"

main :: proc() {
	red := datatypes.Color3{1, 0, 0}
	blue := datatypes.Color3{0, 0, 1}
	native, valid := datatypes.ColorSequence_FromKeypoints([]datatypes.ColorSequenceKeypoint{
		{0, red},
		{0.5, datatypes.Color3{0, 1, 0}},
		{1, blue},
	})
	assert(valid)
	assert(datatypes.ColorSequence_At(native, 0.25) == datatypes.Color3{0.5, 0.5, 0})
	datatypes.ColorSequence_Destroy(native)

	_, valid = datatypes.ColorSequence_FromKeypoints([]datatypes.ColorSequenceKeypoint{
		{0, red},
		{1, blue},
		{0.5, red},
	})
	assert(!valid)

	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)

	source := `
local red = Color3.fromRGB(255, 0, 0)
local green = Color3.fromRGB(0, 255, 0)
local blue = Color3.fromRGB(0, 0, 255)

assert(typeof(ColorSequenceKeypoint) == "table")
assert(typeof(ColorSequence) == "table")

local first = ColorSequenceKeypoint.new(0, red)
local middle = ColorSequenceKeypoint.new(0.5, green)
local last = ColorSequenceKeypoint.new(1, blue)
assert(typeof(first) == "ColorSequenceKeypoint")
assert(first.Time == 0 and first.Value == red)
assert(first == ColorSequenceKeypoint.new(0, red))

local solid = ColorSequence.new(red)
assert(typeof(solid) == "ColorSequence")
assert(#solid.Keypoints == 2)
assert(solid.Keypoints[1] == first)
assert(solid.Keypoints[2] == ColorSequenceKeypoint.new(1, red))

local gradient = ColorSequence.new(red, blue)
assert(gradient.Keypoints[1].Value == red)
assert(gradient.Keypoints[2].Value == blue)

local keyed = ColorSequence.new({first, middle, last})
assert(#keyed.Keypoints == 3)
assert(keyed.Keypoints[2] == middle)
assert(keyed == ColorSequence.new({first, middle, last}))

assert(not pcall(function()
    ColorSequenceKeypoint.new(-0.1, red)
end))
assert(not pcall(function()
    ColorSequence.new({first})
end))
assert(not pcall(function()
    ColorSequence.new({first, last, middle})
end))
assert(not pcall(function()
    ColorSequence.new({first, ColorSequenceKeypoint.new(0, green), last})
end))
assert(not pcall(function()
    keyed.Keypoints[1] = last
end))
assert(not pcall(function()
    ColorSequence.extra = true
end))
`

	ok, err := vm.Run(&script_vm, source, "color_sequence_smoke")
	if !ok {
		fmt.eprintln(err)
		vm.Close(&script_vm)
		engine_runtime.Environment_Destroy(&environment)
		panic("ColorSequence smoke test failed")
	}

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("COLOR_SEQUENCE_SMOKE_PASSED")
}
