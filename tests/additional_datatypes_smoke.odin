package main

import "core:fmt"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)

	source := `
local fixed = NumberRange.new(4)
local range = NumberRange.new(-2, 8)
assert(typeof(range) == "NumberRange")
assert(fixed.Min == 4 and fixed.Max == 4)
assert(range.Min == -2 and range.Max == 8)
assert(range == NumberRange.new(-2, 8))
assert(not pcall(function() NumberRange.new(5, 1) end))

local empty = Rect.new()
local vectors = Rect.new(Vector2.new(1, 2), Vector2.new(11, 22))
local numbers = Rect.new(1, 2, 11, 22)
assert(typeof(vectors) == "Rect")
assert(empty.Width == 0 and empty.Height == 0)
assert(vectors == numbers)
assert(vectors.Min == Vector2.new(1, 2) and vectors.Max == Vector2.new(11, 22))
assert(vectors.Width == 10 and vectors.Height == 20)

local ray = Ray.new(vector.create(1, 2, 3), vector.create(0, 0, 10))
assert(typeof(ray) == "Ray")
assert(ray.Origin == vector.create(1, 2, 3))
assert(ray.Direction == vector.create(0, 0, 10))
assert(ray.Unit.Direction == vector.create(0, 0, 1))
assert(ray:ClosestPoint(vector.create(4, 6, 8)) == vector.create(1, 2, 8))
assert(ray:Distance(vector.create(4, 6, 8)) == 5)
assert(ray:ClosestPoint(vector.create(1, 2, -10)) == ray.Origin)

for _, library in {NumberRange, Rect, Ray, UniqueId, SecurityCapabilities} do
    assert(not pcall(function() library.extra = true end))
end
`

	ok, err := vm.Run(&script_vm, source, "additional_datatypes_smoke")
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("additional datatype smoke test failed")
	}

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("ADDITIONAL_DATATYPES_SMOKE_PASSED")
}
