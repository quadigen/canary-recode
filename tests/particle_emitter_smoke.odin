package main

import classes "../src/engine/classes"
import renderer "../src/engine/renderer"
import runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"
import "core:os"

run :: proc(script_vm: ^vm.VM, script: string) {
	ok, err := vm.RunInternal(script_vm, script, "particle_emitter_smoke")
	assert(ok, err)
}

main :: proc() {
	script_vm := vm.New()
	environment: runtime.Environment
	renderer_object: renderer.RendererObject
	runtime.Environment_Init(&environment, &script_vm, &renderer_object, .Editor)
	defer runtime.Environment_Destroy(&environment)
	defer vm.Close(&script_vm)

	run(
		&script_vm,
		`
local part = Instance.new("Part", workspace)
part.CFrame = CFrame.new(3, 4, 5)
local attachment = Instance.new("Attachment", part)
attachment.Position = Vector3.new(1, 0, 0)
emitter = Instance.new("ParticleEmitter", attachment)
emitter.Enabled = false
emitter.EmissionDirection = Enum.NormalId.Front
emitter.Speed = NumberRange.new(2)
emitter.Lifetime = NumberRange.new(0.25)
emitter.Color = ColorSequence.new(Color3.new(0, 1, 0))
emitter.Size = NumberSequence.new(2, 1)
emitter.Transparency = NumberSequence.new(0, 1)
emitter.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid2x2
emitter.FlipbookMode = Enum.ParticleFlipbookMode.OneShot

local clone = emitter:Clone()
assert(clone:IsA("ParticleEmitter"))
assert(clone.Speed.Min == 2 and clone.Size.Keypoints[1].Value == 2)
clone.Size = NumberSequence.new(9)
assert(emitter.Size.Keypoints[1].Value == 2)
clone:Destroy()

emitter.Orientation = Enum.ParticleOrientation.VelocityParallel
emitter.Shape = Enum.ParticleEmitterShape.Box
emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
emitter.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
assert(emitter.Orientation == Enum.ParticleOrientation.VelocityParallel)
assert(emitter.Shape == Enum.ParticleEmitterShape.Box)
local other = emitter:Clone()
assert(other.Orientation == emitter.Orientation and other.ShapeStyle == emitter.ShapeStyle)
other:Destroy()
emitter:Emit(3)
`,
	)
	vm.GetGlobal(script_vm.L, "emitter")
	emitter := cast(^classes.ParticleEmitter)classes.Object_From_Argument(script_vm.L, -1)
	vm.Pop(script_vm.L)
	assert(emitter != nil && len(emitter.particles) == 3)
	assert(emitter.particles[0].position == {4, 4, 5})
	assert(emitter.particles[0].velocity == {0, 0, -2})
	classes.ParticleEmitter_Step(&environment.classes, 0.1, {})
	assert(len(emitter.particles) == 3 && abs(emitter.particles[0].position.z - 4.8) < 0.001)
	for _ in 0 ..< 2 {classes.ParticleEmitter_Step(&environment.classes, 0.1, {})}
	assert(len(emitter.particles) == 0)

	run(&script_vm, `
emitter.Rate = 20
emitter.Enabled = true
`)
	classes.ParticleEmitter_Step(&environment.classes, 0.1, {})
	assert(len(emitter.particles) == 2)
	run(&script_vm, `emitter:Clear()`)
	assert(len(emitter.particles) == 0)

	run(
		&script_vm,
		`
local source = Instance.new("Part", workspace)
source.Position = Vector3.new(0, 20, 0)
source.Size = Vector3.new(2, 2, 2)
local attachment = Instance.new("Attachment", source)
colliding = Instance.new("ParticleEmitter", attachment)
assert(not colliding.CollisionEnabled)
assert(math.abs(colliding.CollisionRadius - 0.1) < 0.001)
colliding.Enabled = false
colliding.CollisionEnabled = true
colliding.CollisionRadius = 0.2
colliding.CollisionRestitution = 0.5
colliding.CollisionFriction = 0.25
colliding.Lifetime = NumberRange.new(5)
colliding.Speed = NumberRange.new(100)
colliding.EmissionDirection = Enum.NormalId.Bottom
local clone = colliding:Clone()
assert(clone.CollisionEnabled and math.abs(clone.CollisionRadius - 0.2) < 0.001)
assert(clone.CollisionRestitution == 0.5 and clone.CollisionFriction == 0.25)
clone:Destroy()
local floor = Instance.new("Part", workspace)
floor.Position = Vector3.new(0, 15, 0)
floor.Size = Vector3.new(20, 0.1, 20)
local sensor = Instance.new("Part", workspace)
sensor.Position = Vector3.new(0, 18, 0)
sensor.Size = Vector3.new(20, 0.1, 20)
sensor.CanCollide = false
colliding:Emit(1)
`,
	)
	vm.GetGlobal(script_vm.L, "colliding")
	collider := cast(^classes.ParticleEmitter)classes.Object_From_Argument(script_vm.L, -1)
	vm.Pop(script_vm.L)
	assert(collider != nil && len(collider.particles) == 1)
	collider.particles[0].velocity.x = 4
	services.ParticleEmitter_Physics_Step(&environment.services, 0.1)
	p := collider.particles[0]
	assert(abs(p.velocity.y - 50) < 0.1, "high-speed bounce or sensor/source exclusion failed")
	assert(abs(p.velocity.x - 3) < 0.1, "collision friction failed")
	assert(p.position.y > 15.25 && p.position.y < 19, "sphere sweep did not hit thin floor")


	collider.particles[0].position = {0, 15.1, 0}
	collider.particles[0].velocity = {0, -0.1, 0}
	services.ParticleEmitter_Physics_Step(&environment.services, 0.1)
	assert(collider.particles[0].position.y >= 15.249, "penetration recovery failed")
	assert(abs(collider.particles[0].velocity.y) < 0.001, "resting contact bounced")
	run(&script_vm, `colliding.CollisionEnabled = false; colliding:Clear(); colliding:Emit(1)`)
	services.ParticleEmitter_Physics_Step(&environment.services, 0.1)
	assert(
		abs(collider.particles[0].position.y - 10) < 0.001,
		"disabled collisions affected motion",
	)
	run(&script_vm, `colliding.Parent.Parent:Destroy()`)

	run(
		&script_vm,
		`
local debris = game:GetService("Debris")
local attachment = emitter.Parent
expired = 0
emitter.Destroying:Connect(function() expired += 1 end)
debris:AddItem(emitter, 0.5)
debris:AddItem(emitter, 1)
local cancelled = Instance.new("ParticleEmitter", attachment)
debris:AddItem(cancelled, 0.5)
cancelled:Destroy()
assert(emitter.Parent == attachment)
`,
	)
	classes.Step(&environment.classes, script_vm.L, 0.25, phase = .Update)
	run(&script_vm, `assert(emitter.Parent and expired == 0)`)
	classes.Step(&environment.classes, script_vm.L, 0.25, phase = .Update)
	classes.Step(&environment.classes, script_vm.L, 0.5, phase = .Update)
	run(&script_vm, `assert(emitter.Parent == nil and expired == 1)`)

	if len(os.args) > 1 {
		assert(runtime.Load_Map(&environment, &script_vm, os.args[1]))
		run(
			&script_vm,
			`
local templates = game.ReplicatedStorage.Shared.Libraries.ParticleEngine.ParticleInstances
assert(require(templates.Wind.particle):IsA("ParticleEmitter"))
assert(require(templates.Force.particle):FindFirstChildOfClass("ParticleEmitter"))
assert(require(templates.Temperature.particle):IsA("ParticleEmitter"))
`,
		)
	}

	fmt.println("PARTICLE_EMITTER_SMOKE_PASSED")
}
