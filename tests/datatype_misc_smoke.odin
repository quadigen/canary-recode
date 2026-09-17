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

-- UDim
assert(typeof(UDim.new()) == "UDim")
local udim = UDim.new(0.5, 10)
assert(udim.Scale == 0.5 and udim.Offset == 10)
assert(UDim.zero.Scale == 0 and UDim.zero.Offset == 0)
local lerped = UDim.new(0, 10):Lerp(UDim.new(1, 20), 0.5)
assert(close(lerped.Scale, 0.5) and close(lerped.Offset, 15))
assert(UDim.new(0.5, 10) == UDim.new(0.5, 10))
assert(UDim.new(0.5, 10) ~= UDim.new(0.3, 5))
assert((UDim.new(0, 10) + UDim.new(0.5, 5)) == UDim.new(0.5, 15))
assert((UDim.new(1, 20) - UDim.new(0.5, 5)) == UDim.new(0.5, 15))
local fe = UDim.new(0.5, 10)
assert(fe:FuzzyEq(UDim.new(0.5, 10)))
assert(not fe:FuzzyEq(UDim.new(0.9, 10)))
assert(not pcall(function() UDim.extra = true end))

-- BrickColor
assert(typeof(BrickColor.new("White")) == "BrickColor")
local white = BrickColor.new("White")
assert(white.Name == "White")
assert(white.Number == BrickColor.White.Number)
local black = BrickColor.new("Black")
assert(black.Name == "Black")
assert(black.Number == BrickColor.Black.Number)
local red = BrickColor.new(21)
assert(red.Name == "Bright red")
assert(red.Number == BrickColor["Bright red"].Number)
local byCopy = BrickColor.new(white)
assert(byCopy.Number == white.Number)
assert(BrickColor.White.Number == white.Number)
assert(BrickColor.Black.Number ~= white.Number)
assert(BrickColor["Bright red"].Number == red.Number)
assert(BrickColor["Bright blue"].Number ~= white.Number)
assert(BrickColor["Bright green"].Number ~= white.Number)
assert(BrickColor["Medium stone grey"].Number ~= white.Number)
assert(not pcall(function() BrickColor.extra = true end))

-- Faces
assert(typeof(Faces.none) == "Faces")
local none = Faces.none
assert(not none.Top and not none.Bottom and not none.Left and not none.Right and not none.Front and not none.Back)
local all = Faces.all
assert(all.Top and all.Bottom and all.Left and all.Right and all.Front and all.Back)
local customFaces = Faces.new(Enum.NormalId.Top, Enum.NormalId.Front)
assert(customFaces.Top and customFaces.Front and not customFaces.Bottom)
assert(Faces.new(Enum.NormalId.Left, Enum.NormalId.Right, Enum.NormalId.Back) == 
      Faces.new(Enum.NormalId.Right, Enum.NormalId.Left, Enum.NormalId.Back))
assert(not pcall(function() Faces.extra = true end))

-- Axes
assert(typeof(Axes.none) == "Axes")
local axesNone = Axes.none
assert(not axesNone.X and not axesNone.Y and not axesNone.Z)
local axesAll = Axes.all
assert(axesAll.X and axesAll.Y and axesAll.Z)
local axesCustom = Axes.new(Enum.Axis.X, Enum.Axis.Z)
assert(axesCustom.X and axesCustom.Z and not axesCustom.Y)
assert(Axes.new(Enum.Axis.Y) == Axes.new(Enum.Axis.Y))
assert(not pcall(function() Axes.extra = true end))

-- Vector3int16
assert(typeof(Vector3int16.new()) == "Vector3int16")
local vi = Vector3int16.new(10, -20, 30)
assert(vi.X == 10 and vi.Y == -20 and vi.Z == 30)
assert(Vector3int16.zero.X == 0 and Vector3int16.zero.Y == 0 and Vector3int16.zero.Z == 0)
assert(Vector3int16.new(1, 2, 3) == Vector3int16.new(1, 2, 3))
assert(Vector3int16.new(1, 2, 3) ~= Vector3int16.new(4, 5, 6))
local sum = Vector3int16.new(1, 2, 3) + Vector3int16.new(10, 20, 30)
assert(sum.X == 11 and sum.Y == 22 and sum.Z == 33)
local diff = Vector3int16.new(10, 20, 30) - Vector3int16.new(1, 2, 3)
assert(diff.X == 9 and diff.Y == 18 and diff.Z == 27)
assert(not pcall(function() Vector3int16.new(40000, 0, 0) end))

-- NumberSequence
assert(typeof(NumberSequence.new(0.75)) == "NumberSequence")
assert(typeof(NumberSequenceKeypoint.new(0.25, 0.5)) == "NumberSequenceKeypoint")
local ks = NumberSequenceKeypoint.new(0.25, 0.5)
assert(typeof(ks) == "NumberSequenceKeypoint")
assert(ks.Time == 0.25 and ks.Value == 0.5 and ks.Envelope == 0)
local ksEnv = NumberSequenceKeypoint.new(0.5, 1.0, 0.1)
assert(ksEnv.Time == 0.5 and ksEnv.Value == 1.0 and close(ksEnv.Envelope, 0.1))
assert(NumberSequenceKeypoint.new(0, 1) == NumberSequenceKeypoint.new(0, 1))
local solid = NumberSequence.new(0.75)
assert(#solid.Keypoints == 2)
assert(solid.Keypoints[1].Time == 0 and solid.Keypoints[1].Value == 0.75)
assert(solid.Keypoints[2].Time == 1 and solid.Keypoints[2].Value == 0.75)
local gradient = NumberSequence.new(0, 1)
assert(gradient.Keypoints[1].Value == 0 and gradient.Keypoints[2].Value == 1)
local keyed = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 0),
    NumberSequenceKeypoint.new(0.5, 0.8),
    NumberSequenceKeypoint.new(1, 1),
})
assert(#keyed.Keypoints == 3)
assert(close(keyed.Keypoints[2].Value, 0.8))
assert(not pcall(function() NumberSequence.new({NumberSequenceKeypoint.new(0, 0)}) end))
assert(not pcall(function() NumberSequenceKeypoint.new(-0.1, 0) end))
assert(not pcall(function() NumberSequenceKeypoint.new(1.1, 0) end))
assert(not pcall(function() NumberSequenceKeypoint.new(0.5, 0, -1) end))
assert(not pcall(function() NumberSequence.extra = true end))
assert(not pcall(function() NumberSequenceKeypoint.extra = true end))

-- Region3
assert(typeof(Region3.new(vector.create(0,0,0), vector.create(10,10,10))) == "Region3")
local r = Region3.new(vector.create(-5, -5, -5), vector.create(5, 5, 5))
assert(r.Min == vector.create(-5, -5, -5))
assert(r.Max == vector.create(5, 5, 5))
assert(r.Size == vector.create(10, 10, 10))
assert(r.CFrame.Position == vector.create(0, 0, 0))
local expanded = r:ExpandToGrid(1)
assert(expanded.Min == vector.create(-5, -5, -5))
assert(expanded.Max == vector.create(5, 5, 5))
assert(not pcall(function() Region3.new(vector.create(0,0,0), vector.create(1,1,1)):ExpandToGrid(0) end))
`

	ok, err := vm.Run(&script_vm, source, "datatype_misc_smoke")
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("Datatype misc smoke test failed")
	}

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("DATATYPE_MISC_SMOKE_PASSED")
}
