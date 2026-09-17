package main

import "core:fmt"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)

	source := `
local function close(a, b, epsilon)
    return math.abs(a - b) <= (epsilon or 1e-5)
end

assert(typeof(Vector3.new()) == "vector")
local v = Vector3.new(3, 4, 0)
assert(v.X == 3 and v.Y == 4 and v.Z == 0)
assert(close(v.Magnitude, 5))
assert(close(v.Unit.X, 0.6) and close(v.Unit.Y, 0.8) and close(v.Unit.Z, 0))
assert(close(Vector3.new(0,0,0).Magnitude, 0))

assert(close(Vector3.one.X, 1) and close(Vector3.one.Y, 1) and close(Vector3.one.Z, 1))
assert(close(Vector3.zero.X, 0) and close(Vector3.zero.Y, 0) and close(Vector3.zero.Z, 0))
assert(close(Vector3.xAxis.X, 1) and close(Vector3.xAxis.Y, 0) and close(Vector3.xAxis.Z, 0))
assert(close(Vector3.yAxis.X, 0) and close(Vector3.yAxis.Y, 1) and close(Vector3.yAxis.Z, 0))
assert(close(Vector3.zAxis.X, 0) and close(Vector3.zAxis.Y, 0) and close(Vector3.zAxis.Z, 1))

local a = Vector3.new(1, 0, 0)
local b = Vector3.new(0, 1, 0)
assert(a:Dot(b) == 0)
local c = a:Cross(b)
assert(close(c.X, 0) and close(c.Y, 0) and close(c.Z, 1))
local d = b:Cross(a)
assert(close(d.X, 0) and close(d.Y, 0) and close(d.Z, -1))

assert(close(Vector3.new(1, 0, 0):Angle(Vector3.new(0, 1, 0)), math.pi / 2))
assert(close(Vector3.new(1, 0, 0):Angle(Vector3.new(1, 0, 0)), 0))

local lerped = Vector3.new(0, 0, 0):Lerp(Vector3.new(10, 20, 30), 0.5)
assert(close(lerped.X, 5) and close(lerped.Y, 10) and close(lerped.Z, 15))

local high = Vector3.new(5, 10, 15)
local low = Vector3.new(2, 20, 1)
local mx = low:Max(high)
local mn = high:Min(low)
assert(close(mx.X, 5) and close(mx.Y, 20) and close(mx.Z, 15))
assert(close(mn.X, 2) and close(mn.Y, 10) and close(mn.Z, 1))

local neg = Vector3.new(-1.2, -3.7, 0.5)
assert(close(neg:Abs().X, 1.2) and close(neg:Abs().Y, 3.7) and close(neg:Abs().Z, 0.5))
assert(close(neg:Ceil().X, -1) and close(neg:Ceil().Y, -3) and close(neg:Ceil().Z, 1))
assert(close(neg:Floor().X, -2) and close(neg:Floor().Y, -4) and close(neg:Floor().Z, 0))
assert(close(neg:Sign().X, -1) and close(neg:Sign().Y, -1) and close(neg:Sign().Z, 1))

local near = Vector3.new(1, 2, 3)
local exact = Vector3.new(1, 2, 3)
assert(near:FuzzyEq(exact))
assert(near:FuzzyEq(Vector3.new(1.000001, 2.000001, 3.000001)))
assert(not near:FuzzyEq(Vector3.new(1, 2, 4)))
assert(near:FuzzyEq(Vector3.new(1, 2, 4), 2))

local fromNormal = Vector3.FromNormalId(Enum.NormalId.Top)
assert(close(fromNormal.X, 0) and close(fromNormal.Y, 1) and close(fromNormal.Z, 0))
local fromRight = Vector3.FromNormalId(Enum.NormalId.Right)
assert(close(fromRight.X, 1) and close(fromRight.Y, 0) and close(fromRight.Z, 0))
local fromFront = Vector3.FromNormalId(Enum.NormalId.Front)
assert(close(fromFront.X, 0) and close(fromFront.Y, 0) and close(fromFront.Z, -1))
local fromBack = Vector3.FromNormalId(Enum.NormalId.Back)
assert(close(fromBack.X, 0) and close(fromBack.Y, 0) and close(fromBack.Z, 1))

local fromAxisX = Vector3.FromAxis(Enum.Axis.X)
assert(close(fromAxisX.X, 1) and close(fromAxisX.Y, 0) and close(fromAxisX.Z, 0))
local fromAxisY = Vector3.FromAxis(Enum.Axis.Y)
assert(close(fromAxisY.X, 0) and close(fromAxisY.Y, 1) and close(fromAxisY.Z, 0))
local fromAxisZ = Vector3.FromAxis(Enum.Axis.Z)
assert(close(fromAxisZ.X, 0) and close(fromAxisZ.Y, 0) and close(fromAxisZ.Z, 1))

local zero = Vector3.new()
assert(close(zero.X, 0) and close(zero.Y, 0) and close(zero.Z, 0))
local custom = Vector3.new(42.5, -7.25, 0)
assert(close(custom.X, 42.5) and close(custom.Y, -7.25) and close(custom.Z, 0))

assert(close(v.Unit.Magnitude, 1))
local big = Vector3.new(100, 200, 300)
assert(close(big.Magnitude, math.sqrt(100*100 + 200*200 + 300*300)))

local id1 = Vector3.new(1, 2, 3):Dot(Vector3.new(1, 2, 3))
assert(close(id1, 14))

assert(not pcall(function() Vector3.extra = true end))
`

	ok, err := vm.Run(&script_vm, source, "vector3_smoke")
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("Vector3 smoke test failed")
	}

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("VECTOR3_SMOKE_PASSED")
}
