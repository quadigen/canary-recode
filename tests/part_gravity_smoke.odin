package main

import classes "../src/engine/classes"
import engine_runtime "../src/engine/runtime"
import serializer "../src/engine/serializer"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"

run :: proc(v: ^vm.VM, source: string) {
    ok, err := vm.Run(v, source, "part_gravity_smoke")
    assert(ok, err)
}

main :: proc() {
    v := vm.New()
    env: engine_runtime.Environment
    engine_runtime.Environment_Init(&env, &v)
    defer {vm.Close(&v); engine_runtime.Environment_Destroy(&env)}
    run(&v, `
local function make(name, x, g, material, parent)
    local p = Instance.new("Part", parent or workspace)
    p.Name = name
    p.Size = Vector3.one
    p.Position = Vector3.new(x, 100, 0)
    p.CanCollide = false
    p.Material = material or Enum.Material.Wood
    assert(math.abs(p.Gravity.Y + 196.2) < 0.001)
    if g then p.Gravity = g end
    p.Anchored = false
    return p
end
down = make("Down", 0)
up = make("Up", 20, Vector3.new(0, 60, 0))
side = make("Side", 40, Vector3.new(60, 0, 30))
heavy = make("Heavy", 60, side.Gravity, Enum.Material.Metal)
zero = make("Zero", 80, Vector3.zero)
local model = Instance.new("PhysicsModel", workspace)
model.GravityScale = 0.5
scaled = make("Scaled", 100, side.Gravity, nil, model)
fixed = make("Fixed", 120, side.Gravity)
fixed.Anchored = true
local mesh = Instance.new("MeshPart")
assert(math.abs(mesh.Gravity.Y + 196.2) < 0.001)
mesh.Gravity = side.Gravity
assert(mesh:Clone().Gravity == side.Gravity)
mesh:Destroy()
local clone = side:Clone()
assert(clone.Gravity == side.Gravity)
clone:Destroy()
assert(not pcall(function() side.Gravity = Vector3.new(math.huge, 0, 0) end))
assert(side.Gravity == Vector3.new(60, 0, 30))
assert(not pcall(function() side.Gravity = 123 end))
-- The non-part solver setting must not affect rigid part gravity.
game:GetService("Physics").Gravity = 0
`)
    physics := cast(^services.Physics)services.Ensure_Service(&env.services, "Physics")
    for _ in 0 ..< 30 {services.Physics_Step(physics, 1.0 / 60.0)}
    run(&v, `
assert(down.AssemblyLinearVelocity.Y < -90)
assert(up.AssemblyLinearVelocity.Y > 27)
assert(side.AssemblyLinearVelocity.X > 27 and side.AssemblyLinearVelocity.Z > 13)
assert(math.abs(side.AssemblyLinearVelocity.Y) < 0.001)
assert((side.AssemblyLinearVelocity - heavy.AssemblyLinearVelocity).Magnitude < 0.01)
assert(math.abs(scaled.AssemblyLinearVelocity.X - side.AssemblyLinearVelocity.X / 2) < 0.01)
assert(zero.AssemblyLinearVelocity.Magnitude < 0.001)
assert(fixed.Position == Vector3.new(120, 100, 0))
local previous = side.AssemblyLinearVelocity
side.Gravity = Vector3.new(-60, 0, 0)
assert(side.AssemblyLinearVelocity == previous)
game:GetService("Physics").Gravity = 100
`)
    for _ in 0 ..< 30 {services.Physics_Step(physics, 1.0 / 60.0)}
    run(&v, `
assert(math.abs(side.AssemblyLinearVelocity.X) < 2)
assert(up.AssemblyLinearVelocity.Y > 55)
assert(zero.AssemblyLinearVelocity.Magnitude < 0.001)
`)
    root := services.Ensure_Service(&env.services, "Workspace")
    side := classes.Find_First_Child(root, "Side")
    err := serializer.Serialize_To_File(&env.classes, v.L, side, "build/part-gravity-smoke.kine")
    assert(serializer.Error_Is_None(err))
    serializer.Error_Delete(&err)
    loaded, load_err := serializer.Deserialize_From_File(&env.classes, v.L, nil, "build/part-gravity-smoke.kine")
    assert(loaded != nil && serializer.Error_Is_None(load_err))
    serializer.Error_Delete(&load_err)
    assert((cast(^classes.Part)loaded).gravity.x == -60)
    classes.Destroy_Hierarchy(loaded)
    fmt.println("PART_GRAVITY_SMOKE_PASSED")
}
