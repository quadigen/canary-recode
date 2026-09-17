package main

import "core:fmt"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"

run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("Value family smoke test failed")
	}
}

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)

	run_script(&script_vm, `
local function v3close(a, b, tol)
	tol = tol or 0.001
	return math.abs(a.X - b.X) < tol and math.abs(a.Y - b.Y) < tol and math.abs(a.Z - b.Z) < tol
end

local function c3close(a, b, tol)
	tol = tol or 0.001
	return math.abs(a.R - b.R) < tol and math.abs(a.G - b.G) < tol and math.abs(a.B - b.B) < tol
end

-- ValueBase cannot be created directly.
assert(not pcall(function() Instance.new("ValueBase") end))

-- Each value is creatable and inherits ValueBase -> Instance.
local names = {
	"BoolValue", "NumberValue", "IntValue", "StringValue", "ObjectValue",
	"Vector3Value", "Vector2Value", "CFrameValue", "Color3Value",
	"BrickColorValue", "NumberSequenceValue", "NumberRangeValue",
	"RayValue", "ColorSequenceValue", "IntConstrainedValue", "DoubleConstrainedValue",
}

for _, name in ipairs(names) do
	local v = Instance.new(name)
	assert(v.ClassName == name)
	assert(v:IsA(name))
	assert(v:IsA("ValueBase"))
	assert(v:IsA("Instance"))
	assert(not v:IsA("Part"))
end

-- BoolValue
local bv = Instance.new("BoolValue")
bv.Value = true
assert(bv.Value == true)
bv.Value = false
assert(bv.Value == false)

-- NumberValue
local nv = Instance.new("NumberValue")
nv.Value = 42.5
assert(nv.Value == 42.5)

-- IntValue
local iv = Instance.new("IntValue")
iv.Value = 1234567
assert(iv.Value == 1234567)
iv.Value = -7
assert(iv.Value == -7)

-- StringValue
local sv = Instance.new("StringValue")
assert(sv.Value == "")
sv.Value = "hello value"
assert(sv.Value == "hello value")
sv.Value = ""
assert(sv.Value == "")

-- ObjectValue
local part = Instance.new("Part")
local ov = Instance.new("ObjectValue")
assert(ov.Value == nil)
ov.Value = part
assert(ov.Value == part)
assert(ov.Value.ClassName == "Part")
ov.Value = nil
assert(ov.Value == nil)
assert(not pcall(function() ov.Value = 42 end))

-- Vector3Value
local v3v = Instance.new("Vector3Value")
v3v.Value = Vector3.new(1.5, -0.25, 2.75)
assert(v3close(v3v.Value, Vector3.new(1.5, -0.25, 2.75)))

-- Vector2Value
local v2v = Instance.new("Vector2Value")
v2v.Value = Vector2.new(3.5, -1.25)
assert(math.abs(v2v.Value.X - 3.5) < 0.001)
assert(math.abs(v2v.Value.Y + 1.25) < 0.001)

-- CFrameValue
local cfv = Instance.new("CFrameValue")
cfv.Value = CFrame.new(10, 20, 30)
assert(v3close(cfv.Value.Position, Vector3.new(10, 20, 30)))

-- Color3Value
local c3v = Instance.new("Color3Value")
c3v.Value = Color3.fromRGB(255, 0, 128)
assert(c3close(c3v.Value, Color3.new(1, 0, 128/255)))

-- BrickColorValue
local bcv = Instance.new("BrickColorValue")
bcv.Value = BrickColor.new("Bright red")
assert(bcv.Value == BrickColor.new("Bright red"))
assert(bcv.Value.Name == "Bright red")

-- NumberSequenceValue
local nsv = Instance.new("NumberSequenceValue")
nsv.Value = NumberSequence.new(0.5, 1.5)
assert(nsv.Value == NumberSequence.new(0.5, 1.5))
assert(math.abs(nsv.Value.Keypoints[1].Value - 0.5) < 0.001)
assert(math.abs(nsv.Value.Keypoints[2].Value - 1.5) < 0.001)

-- NumberRangeValue
local nrv = Instance.new("NumberRangeValue")
nrv.Value = NumberRange.new(-5, 10)
assert(nrv.Value == NumberRange.new(-5, 10))
assert(nrv.Value.Min == -5)
assert(nrv.Value.Max == 10)

-- RayValue
local rv = Instance.new("RayValue")
rv.Value = Ray.new(Vector3.new(1, 2, 3), Vector3.new(0, 1, 0))
assert(rv.Value == Ray.new(Vector3.new(1, 2, 3), Vector3.new(0, 1, 0)))

-- ColorSequenceValue
local csv = Instance.new("ColorSequenceValue")
csv.Value = ColorSequence.new(Color3.new(1, 0, 0), Color3.new(0, 1, 0))
assert(csv.Value == ColorSequence.new(Color3.new(1, 0, 0), Color3.new(0, 1, 0)))
assert(c3close(csv.Value.Keypoints[1].Value, Color3.new(1, 0, 0)))
assert(c3close(csv.Value.Keypoints[2].Value, Color3.new(0, 1, 0)))

-- IntConstrainedValue
local icv = Instance.new("IntConstrainedValue")
icv.MinValue = 0
icv.MaxValue = 10
icv.Value = 5
assert(icv.Value == 5)
assert(icv.ConstrainedValue == 5)
icv.Value = 100
assert(icv.Value == 10)
assert(icv.ConstrainedValue == 10)
icv.Value = -100
assert(icv.Value == 0)
assert(icv.MinValue == 0)
assert(icv.MaxValue == 10)

-- DoubleConstrainedValue
local dcv = Instance.new("DoubleConstrainedValue")
dcv.MinValue = -1.5
dcv.MaxValue = 3.25
dcv.Value = 7.5
assert(dcv.Value == 3.25)
assert(dcv.ConstrainedValue == 3.25)
dcv.Value = -9
assert(dcv.Value == -1.5)

-- Cloning preserves value and class chain.
local clone_cases = {
	{ "NumberValue", 12.5 },
	{ "IntValue", 999 },
	{ "StringValue", "copied" },
	{ "Vector3Value", Vector3.new(4, 5, 6) },
}

for _, case in ipairs(clone_cases) do
	local original = Instance.new(case[1])
	original.Value = case[2]
	local cloned = original:Clone()
	assert(cloned ~= original)
	assert(cloned.ClassName == case[1])
	assert(cloned:IsA("ValueBase"))
	assert(cloned.Value == case[2])
end

local holder = Instance.new("Folder", workspace)
nv.Parent = holder
assert(nv:GetFullName() == "game.Workspace.Folder.NumberValue")
`, "value_family_properties")

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("VALUE_FAMILY_SMOKE_PASSED")
}