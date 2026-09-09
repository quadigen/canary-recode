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

assert(typeof(Color3.new()) == "Color3")
local orange = Color3.fromRGB(255, 128, 0)
assert(close(orange.R, 1) and close(orange.G, 128 / 255) and close(orange.B, 0))
assert(orange:ToHex() == "ff8000")
local r, g, b = orange:ToRGB()
assert(close(r, 255) and close(g, 128) and close(b, 0))
assert(Color3.fromHex("#fff") == Color3.white)
assert(Color3.black:Lerp(Color3.white, 0.5) == Color3.new(0.5, 0.5, 0.5))
assert((Color3.new(0.25, 0.5, 1) * 2) == Color3.new(0.5, 1, 2))

assert(typeof(Vector2.new()) == "Vector2")
local v = Vector2.new(3, 4)
assert(v.X == 3 and v.Y == 4 and v.Magnitude == 5)
assert(close(v.Unit.X, 0.6) and close(v.Unit.Y, 0.8))
assert(v:Dot(Vector2.one) == 7)
assert(v:Cross(Vector2.one) == -1)
assert(v + Vector2.new(1, 2) == Vector2.new(4, 6))
assert(2 * v == Vector2.new(6, 8))
assert(v:Lerp(Vector2.zero, 0.5) == Vector2.new(1.5, 2))

assert(typeof(UDim2.new()) == "UDim2")
local dim = UDim2.new(0.5, 10, 1, -5)
assert(dim.X.Scale == 0.5 and dim.X.Offset == 10)
assert(dim.Y.Scale == 1 and dim.Y.Offset == -5)
assert(dim.Width.Scale == dim.XScale and dim.Height.Offset == dim.YOffset)
assert(dim + UDim2.fromOffset(2, 3) == UDim2.new(0.5, 12, 1, -2))
assert(UDim2.zero:Lerp(UDim2.fromScale(1, 0.5), 0.5) == UDim2.fromScale(0.5, 0.25))

assert(typeof(CFrame.new()) == "CFrame")
assert(CFrame.new() == CFrame.identity)
local cf = CFrame.new(100000.5, 20.25, -30.75)
assert(cf.X == 100000.5 and cf.Y == 20.25 and cf.Z == -30.75)
assert(typeof(cf.Position) == "vector")
assert(cf.Position.X == 100000.5 and cf.Position.Y == 20.25 and cf.Position.Z == -30.75)
local movedPoint = cf * vector.create(1, 2, 3)
assert(movedPoint == vector.create(100001.5, 22.25, -27.75))
local localPoint = cf:PointToObjectSpace(movedPoint)
assert(localPoint == vector.create(1, 2, 3))
local rotation = CFrame.Angles(0, math.pi / 2, 0)
local composed = cf * rotation
assert(composed:ToObjectSpace(cf):Inverse():FuzzyEq(rotation, 1e-4))
local axisFrame = CFrame.fromAxisAngle(vector.create(0, 1, 0), math.pi / 4)
local axis, angle = axisFrame:ToAxisAngle()
assert(close(axis.Y, 1, 1e-4) and close(angle, math.pi / 4, 1e-4))
local x, y, z, r00, _, _, _, r11, _, _, _, r22 = cf:GetComponents()
assert(x == cf.X and y == cf.Y and z == cf.Z and r00 == 1 and r11 == 1 and r22 == 1)

local part = Instance.new("Part")
assert(typeof(part.CFrame) == "CFrame" and typeof(part.Color) == "Color3")
part.CFrame = composed
part.Color = orange
assert(part.CFrame == composed and part.Color == orange)
local invalidPartValue = pcall(function()
    part.CFrame = Vector2.zero
end)
assert(not invalidPartValue)

local writableValue = pcall(function()
    v.X = 9
end)
assert(not writableValue)
local writableLibrary = pcall(function()
    Color3.extra = true
end)
assert(not writableLibrary)
`

	ok, err := vm.Run(&script_vm, source, "datatype_smoke")
	if !ok {
		fmt.eprintln(err)
		vm.Close(&script_vm)
		engine_runtime.Environment_Destroy(&environment)
		panic("datatype smoke test failed")
	}

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("DATATYPE_SMOKE_PASSED")
}
