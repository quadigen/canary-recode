package main
import runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

run :: proc(state: ^vm.VM, source: string) {
	ok, err := vm.RunInternal(state, source, "imported_constraints")
	assert(ok, err)
}
main :: proc() {
	state := vm.New()
	env: runtime.Environment
	runtime.Environment_Init(&env, &state)
	run(
		&state,
		`
local function part(name,position,anchored)
    local p = Instance.new("Part",workspace)
    p.Name = name
    p.Size = Vector3.one
    p.Position = position
    p.Anchored = anchored
    return p
end
floor = part("Floor",Vector3.zero,true)
floor.Size = Vector3.new(60,1,60)
ghost = part("Ghost",Vector3.new(0,10,0),false)
solid = part("Solid",Vector3.new(5,10,0),false)
nc = Instance.new("NoCollisionConstraint",ghost)
nc.Part0,nc.Part1 = ghost,floor
local m = Instance.new("Model")
local a = part("CloneA",Vector3.new(0,30,0),true)
local b = part("CloneB",Vector3.new(0,32,0),true)
a.Parent,b.Parent = m,m
local c = Instance.new("NoCollisionConstraint",a)
c.Part0,c.Part1 = a,b
local copy = m:Clone()
assert(copy.CloneA.NoCollisionConstraint.Part1 == copy.CloneB)
m:Destroy()
copy:Destroy()
local function joint(kind,x)
    local a = part(kind.."A",Vector3.new(x,20,0),true)
    local b = part(kind.."B",Vector3.new(x,20,0),false)
    b.CanCollide = false
    b.Gravity = Vector3.zero
    local c = Instance.new(kind,b)
    c.Attachment0 = Instance.new("Attachment",a)
    c.Attachment1 = Instance.new("Attachment",b)
    return c,b
end
plane,planeBody = joint("PlaneConstraint",40)
universal,universalBody = joint("UniversalConstraint",45)
cylinder,cylinderBody = joint("CylindricalConstraint",50)
universal.LimitsEnabled = true
universal.MaxAngle = 30
planeBody.AssemblyLinearVelocity = Vector3.new(6,4,0)
cylinderBody.AssemblyLinearVelocity = Vector3.new(6,4,0)
mover = part("Mover",Vector3.new(60,30,0),false)
mover.Gravity = Vector3.zero
local lv = Instance.new("LinearVelocity",mover)
lv.Attachment0 = Instance.new("Attachment",mover)
lv.VectorVelocity = Vector3.new(5,0,0)
lv.ForceLimitsEnabled = false
alignBody = part("Align",Vector3.new(70,30,0),false)
alignBody.Gravity = Vector3.zero
local align = Instance.new("AlignOrientation",alignBody)
align.Attachment0 = Instance.new("Attachment",alignBody)
align.Mode = Enum.OrientationAlignmentMode.OneAttachment
align.CFrame = CFrame.Angles(0,math.rad(45),0)
align.MaxTorque = 100
`,
	)
	for i in 0 ..< 60 {runtime.Environment_Update_Step(&env, &state, 1.0 / 60.0)}
	run(
		&state,
		`
assert(nc.Active and not ghost:CanCollideWith(floor))
assert(ghost.Position.Y < -1,tostring(ghost.Position))
assert(solid.Position.Y > 0,tostring(solid.Position))
assert(plane.Active and universal.Active and cylinder.Active)
assert(math.abs(planeBody.Position.X-40) < 0.1,tostring(planeBody.Position))
assert(math.abs(cylinderBody.Position.Y-20) < 0.1,tostring(cylinderBody.Position))
assert(math.abs(mover.AssemblyLinearVelocity.X-5)<0.5,tostring(mover.AssemblyLinearVelocity))
assert(alignBody.AlignOrientation.Active)
assert(math.abs(alignBody.CFrame.LookVector.X)>0.1,tostring(alignBody.CFrame))
nc.Enabled = false
ghost.Position = Vector3.new(0,10,0)
ghost.AssemblyLinearVelocity = Vector3.zero
`,
	)
	for i in 0 ..< 60 {runtime.Environment_Update_Step(&env, &state, 1.0 / 60.0)}
	run(
		&state,
		`assert(not nc.Active and ghost:CanCollideWith(floor) and ghost.Position.Y > 0,tostring(ghost.Position))`,
	)
	vm.Close(&state)
	runtime.Environment_Destroy(&env)
	fmt.println("IMPORTED_CONSTRAINTS_SMOKE_PASSED")
}
