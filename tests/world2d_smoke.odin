package main

import kineffi "../src/engine/bindings"
import renderer "../src/engine/renderer"
import runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

run :: proc(v: ^vm.VM, script: string) {
	ok, err := vm.Run(v, script, "world2d_smoke")
	if !ok {fmt.eprintln(err); delete(err); panic("2D smoke failed")}
}
pixel :: proc(s: ^renderer.Skia_Surface, x, y: i32) -> [4]u8 {
	p: [4]u8
	kineffi.Kine_Skia_Surface_GetPixel(s, x, y, &p[0], &p[1], &p[2], &p[3])
	return p
}
main :: proc() {
	v := vm.New()
	r: renderer.RendererObject
	e: runtime.Environment
	runtime.Environment_Init(&e, &v, &r)
	s := kineffi.Kine_Skia_Surface_Create(320, 240)
	assert(s != nil)
	defer kineffi.Kine_Skia_Surface_Destroy(s)
	run(
		&v,
		`
workspace.Dimension = Enum.Dimension.D2
world = Instance.new("World2D", workspace)
local folder = Instance.new("Folder", world)
group = Instance.new("RigidBody2D", folder)
floor = Instance.new("Part2D", folder)
floor.Position = UDim2.fromOffset(0, 180)
floor.Size = UDim2.fromOffset(320, 30)
floor.BackgroundColor3 = Color3.new(0, 1, 0)
ball = Instance.new("Part2D", group)
ball.Position = UDim2.fromOffset(80, 30)
ball.Size = UDim2.fromOffset(24, 24)
ball.BackgroundColor3 = Color3.new(1, 0, 0)
ball.IsBall = true
ball.Anchored = false
ball.Elasticity = 0
ball.Friction = 0.4
ball.Density = 2
assert(ball.Velocity == Vector2.new(0, 0))
assert(group:GetPivot().Position.X == 92)
group:PivotTo(CFrame.new(112, 42, 0))
assert(ball.Position.X.Offset == 100)
ghost = Instance.new("Part2D", world)
ghost.Size = UDim2.fromOffset(16, 16)
ghost.Position = UDim2.fromOffset(150, 30)
ghost.Anchored = false
ghost.CanCollide = false
ghost.Velocity = Vector2.new(0, 5)
w2 = game:GetService("Workspace2D")
assert(w2.Gravity == Vector2.new(0, 130))
`,
	)
	kineffi.Kine_Skia_Surface_Clear(s, 0, 0, 0, 0)
	runtime.Environment_Render_2D(&e, &v, s, 320, 240, 0)
	kineffi.Kine_Skia_Surface_Flush(s)
	assert(!r.RenderFilament)
	assert(pixel(s, 112, 42) == [4]u8{255, 0, 0, 255})
	assert(pixel(s, 100, 30)[3] == 0)
	assert(pixel(s, 10, 190) == [4]u8{0, 255, 0, 255})
	for _ in 0 ..< 180 {runtime.Environment_Update_Step(&e, &v, 1.0 / 60)}
	run(
		&v,
		`
assert(w2.BodyCount == 3, tostring(w2.BodyCount))
assert(ball.Position.Y.Offset > 140 and ball.Position.Y.Offset < 165, tostring(ball.Position.Y.Offset))
assert(ghost.Position.Y.Offset > 190, tostring(ghost.Position.Y.Offset))
workspace.SimulatePhysics = false
oldY = ghost.Position.Y.Offset
ball.Position = UDim2.fromOffset(25, 40)
ball.Size = UDim2.fromOffset(32, 32)
ball.Anchored = true
`,
	)
	for _ in 0 ..< 30 {runtime.Environment_Update_Step(&e, &v, 1.0 / 60)}
	run(
		&v,
		`
assert(ghost.Position.Y.Offset == oldY)
assert(ball.Position.Y.Offset == 40)
ball:Destroy()
assert(w2.BodyCount == 2)
ghost.Parent = nil
`,
	)
	runtime.Environment_Update_Step(&e, &v, 1.0 / 60)
	run(&v, `
assert(w2.BodyCount == 1)
workspace.Dimension = Enum.Dimension.D3
`)
	runtime.Environment_Update_Step(&e, &v, 1.0 / 60)
	kineffi.Kine_Skia_Surface_Clear(s, 0, 0, 0, 0)
	runtime.Environment_Render_2D(&e, &v, s, 320, 240, 0)
	kineffi.Kine_Skia_Surface_Flush(s)
	assert(r.RenderFilament)
	assert(pixel(s, 10, 190)[3] == 0)
	run(&v, `
assert(w2.BodyCount == 0)
workspace.Dimension = Enum.Dimension.D2
`)
	runtime.Environment_Update_Step(&e, &v, 1.0 / 60)
	run(
		&v,
		`
assert(w2.BodyCount == 1)
local hit = w2:Raycast(Vector2.new(10, 100), Vector2.new(0, 150))
assert(hit and hit.Instance == floor)
assert(math.abs(hit.Distance - 80) < 0.2)
assert(hit.Normal.Y < -0.99)
assert(w2:Raycast(Vector2.new(10, 100), Vector2.new(0, 10)) == nil)
w2.Gravity = Vector2.new(0, 0)
group = Instance.new("RigidBody2D", world)
a = Instance.new("Part2D", group)
a.Size = UDim2.fromOffset(20, 20)
a.Position = UDim2.fromOffset(40, 60)
a.Anchored = false
b = Instance.new("Part2D", group)
b.Size = UDim2.fromOffset(20, 20)
b.Position = UDim2.fromOffset(80, 60)
b.Anchored = false
group:PivotTo(CFrame.new(70, 70, 0))
a:ApplyImpulse(Vector2.new(100, 0))
workspace.SimulatePhysics = true
`,
	)
	for _ in 0 ..< 30 {runtime.Environment_Update_Step(&e, &v, 1.0 / 60)}
	run(
		&v,
		`
assert(a.Position.X.Offset > 50, tostring(a.Position.X.Offset))
assert(b.Position.X.Offset > 90, tostring(b.Position.X.Offset))
assert(math.abs(b.Position.X.Offset - a.Position.X.Offset - 40) < 1)
assert(math.abs(b.Position.Y.Offset - a.Position.Y.Offset) < 1)
assert(group:GetPivot().Position.X > 80)
b.Anchored = true
`,
	)
	for _ in 0 ..< 30 {runtime.Environment_Update_Step(&e, &v, 1.0 / 60)}
	run(
		&v,
		`
assert(math.abs(a.Velocity.X) < 1)
group:Destroy()
assert(w2.BodyCount == 1)
world.Enabled = false
`,
	)
	runtime.Environment_Update_Step(&e, &v, 1.0 / 60)
	run(&v, `assert(w2.BodyCount == 0)`)
	kineffi.Kine_Skia_Surface_Clear(s, 0, 0, 0, 0)
	runtime.Environment_Render_2D(&e, &v, s, 320, 240, 0)
	kineffi.Kine_Skia_Surface_Flush(s)
	assert(pixel(s, 10, 190)[3] == 0)
	run(
		&v,
		`
world.Enabled = true
workspace.SimulatePhysics = false
scaled = Instance.new("Part2D", world)
scaled.AnchorPoint = Vector2.new(0.5, 0.5)
scaled.Position = UDim2.fromScale(0.5, 0.5)
scaled.Size = UDim2.fromOffset(20, 20)
`,
	)
	runtime.Environment_Update_Step(&e, &v, 1.0 / 60)
	run(
		&v,
		`
assert(w2.BodyCount == 2)
assert(w2.ViewportSize == Vector2.new(320, 240))
assert(scaled.AbsolutePosition == Vector2.new(150, 110), tostring(scaled.AbsolutePosition))
`,
	)

	run(
		&v,
		`
oversized = Instance.new("Part2D", world)
oversized.Anchored = false
oversized.Size = UDim2.fromOffset(1e25, 25)
`,
	)
	runtime.Environment_Update_Step(&e, &v, 1.0 / 60)
	run(
		&v,
		`
assert(w2.BodyCount == 2, "oversized collider entered physics")
oversized.Size = UDim2.fromOffset(20, 20)
oversized.Velocity = Vector2.new(1e25, 0)
`,
	)
	runtime.Environment_Update_Step(&e, &v, 1.0 / 60)
	run(
		&v,
		`
assert(w2.BodyCount == 2, "unbounded velocity entered physics")
oversized.Velocity = Vector2.zero
oversized.Density = 1e25
`,
	)
	runtime.Environment_Update_Step(&e, &v, 1.0 / 60)
	run(
		&v,
		`
assert(w2.BodyCount == 2, "unbounded density entered physics")
oversized.Density = 1
assert(not pcall(function() oversized:ApplyImpulse(Vector2.new(1e25, 0)) end))
assert(not pcall(function() oversized:ApplyAngularImpulse(1e25) end))
`,
	)
	runtime.Environment_Update_Step(&e, &v, 1.0 / 60)
	run(
		&v,
		`
assert(w2.BodyCount == 3, "corrected physical properties did not recover")
oversized:Destroy()
w2.Gravity = Vector2.new(0, 0)
outerGroup = Instance.new("RigidBody2D", world)
outerPart = Instance.new("Part2D", outerGroup)
outerPart.Size = UDim2.fromOffset(20, 20)
outerPart.Position = UDim2.fromOffset(60, -200)
outerPart.Anchored = false
outerPart.CanCollide = false
innerGroup = Instance.new("RigidBody2D", outerGroup)
innerPart = Instance.new("Part2D", innerGroup)
innerPart.Size = UDim2.fromOffset(20, 20)
innerPart.Position = UDim2.fromOffset(60, -1000)
innerPart.Anchored = false
innerPart.CanCollide = false
workspace.SimulatePhysics = true
outerPart:ApplyImpulse(Vector2.new(250, 0))
`,
	)
	for _ in 0 ..< 20 {runtime.Environment_Update_Step(&e, &v, 1.0 / 60)}
	run(
		&v,
		`
assert(w2.BodyCount == 4, tostring(w2.BodyCount))
assert(outerPart.Position.X.Offset > 61, "outer assembly did not move")
assert(math.abs(innerPart.Position.X.Offset - 60) < 0.1,
    "nested assembly was incorrectly welded to its parent")
outerGroup:Destroy()
`,
	)
	vm.Close(&v)
	runtime.Environment_Destroy(&e)
	fmt.println("WORLD2D_SMOKE_PASSED")
}
