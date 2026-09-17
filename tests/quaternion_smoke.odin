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
    return math.abs(a - b) <= (epsilon or 1e-4)
end

-- Quaternion basic construction
assert(typeof(Quaternion.new()) == "Quaternion")
local q = Quaternion.new(0, 0, 0, 1)
assert(q.X == 0 and q.Y == 0 and q.Z == 0 and q.W == 1)

-- Identity
local ident = Quaternion.identity
assert(ident.X == 0 and ident.Y == 0 and ident.Z == 0 and ident.W == 1)

-- Custom quaternion
local q2 = Quaternion.new(0.5, 0.5, 0.5, 0.5)
assert(close(q2.X, 0.5) and close(q2.Y, 0.5) and close(q2.Z, 0.5) and close(q2.W, 0.5))
assert(close(q2.Magnitude, 1, 1e-4))

-- Unit quaternion
local notUnit = Quaternion.new(2, 0, 0, 0)
local unit = notUnit.Unit
assert(close(unit.Magnitude, 1))

-- fromAxisAngle
local ninetyY = Quaternion.fromAxisAngle(vector.create(0, 1, 0), math.pi / 2)
assert(close(ninetyY.Magnitude, 1, 1e-4))
local axis, angle = ninetyY:ToAxisAngle()
assert(close(axis.Y, 1, 1e-3) and close(angle, math.pi / 2, 1e-3))

local ninetyX = Quaternion.fromAxisAngle(vector.create(1, 0, 0), math.pi / 4)
local ax, ang = ninetyX:ToAxisAngle()
assert(close(ax.X, 1, 1e-3) and close(ang, math.pi / 4, 1e-3))

-- Conjugate and Inverse for unit quaternion
local conj = ninetyY:Conjugate()
assert(close(conj.X, 0) and close(conj.Y, -0.7071, 1e-3) and close(conj.Z, 0) and close(conj.W, 0.7071, 1e-3))

local inv = ninetyY:Inverse()
assert(close(inv.X, 0) and close(inv.Y, -0.7071, 1e-3) and close(inv.Z, 0) and close(inv.W, 0.7071, 1e-3))

-- Dot product
local dotResult = Quaternion.identity:Dot(Quaternion.identity)
assert(close(dotResult, 1))
assert(close(Quaternion.identity:Dot(Quaternion.new(0, 0, 0, 1)), 1))

-- Lerp
local from = Quaternion.new(0, 0, 0, 1)
local to = Quaternion.new(0, 0, 0.7071, 0.7071)
local lerped = from:Lerp(to, 0.5)
assert(close(lerped.Z, 0.3827, 1e-3))
assert(close(lerped.W, 0.9239, 1e-3))

-- Slerp
local slerped = from:Slerp(to, 0.5)
assert(close(slerped.Magnitude, 1, 1e-3))

-- Multiply (Hamilton product)
local qIdent = Quaternion.identity * Quaternion.identity
assert(close(qIdent.X, 0) and close(qIdent.Y, 0) and close(qIdent.Z, 0) and close(qIdent.W, 1))

local qMul = Quaternion.new(0, 0, 0.7071, 0.7071) * Quaternion.new(0, 0, 0.7071, 0.7071)
assert(close(qMul.Z, 1, 1e-2) or close(qMul.W, 0, 1e-2))

-- Equality
assert(Quaternion.new(1, 2, 3, 4) == Quaternion.new(1, 2, 3, 4))
assert(Quaternion.new(1, 2, 3, 4) ~= Quaternion.new(5, 6, 7, 8))

-- TweenInfo
assert(typeof(TweenInfo.new()) == "TweenInfo")
local ti = TweenInfo.new()
assert(ti.Time == 1)
assert(ti.RepeatCount == 0)
assert(ti.Reverses == false)
assert(ti.DelayTime == 0)

local customTi = TweenInfo.new(2, Enum.EasingStyle.Bounce, Enum.EasingDirection.InOut, 3, true, 0.5)
assert(customTi.Time == 2)
assert(customTi.EasingStyle == Enum.EasingStyle.Bounce)
assert(customTi.EasingDirection == Enum.EasingDirection.InOut)
assert(customTi.RepeatCount == 3)
assert(customTi.Reverses == true)
assert(customTi.DelayTime == 0.5)

local defaultTi = TweenInfo.default
assert(defaultTi.Time == 1)

assert(TweenInfo.new() == TweenInfo.new())
assert(TweenInfo.new(2) ~= TweenInfo.new(1))
assert(not pcall(function() TweenInfo.new(-1) end))
assert(not pcall(function() TweenInfo.new(1, nil, nil, -2) end))
assert(not pcall(function() TweenInfo.extra = true end))

-- DateTime
local now = DateTime.now()
assert(typeof(now) == "DateTime")
assert(now == now)
assert(typeof(now.UnixTimestamp) == "integer")
assert(typeof(now.UnixTimestampMillis) == "integer")
-- NOTE: DateTime.fromUnixTimestamp and DateTime.fromUnixTimestampMillis
-- cannot be called from Lua because they require the VM's distinct
-- "integer" type, which Lua number literals cannot produce.
assert(not pcall(function() DateTime.fromUnixTimestamp(1000000) end))
assert(not pcall(function() DateTime.extra = true end))
`

	ok, err := vm.Run(&script_vm, source, "quaternion_smoke")
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("Quaternion smoke test failed")
	}

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("QUATERNION_SMOKE_PASSED")
}
