package main
import runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

run :: proc(v: ^vm.VM, source, label: string) {
	ok, err := vm.RunInternal(v, source, label)
	if !ok {fmt.println(label, err)}
	assert(ok, err)
}
step :: proc(env: ^runtime.Environment, v: ^vm.VM, count: int) {
	for _ in 0 ..< count {runtime.Environment_Update_Step(env, v, 1.0 / 60)}
}
main :: proc() {
	v := vm.New(); env: runtime.Environment
	runtime.Environment_Init(&env, &v)
	defer {vm.Close(&v); runtime.Environment_Destroy(&env)}
	run(
		&v,
		`
assembly=Instance.new("Model",workspace)
function part(name,pos,fixed)
    local p=Instance.new("Part",assembly)
    p.Name=name;p.Size=Vector3.one;p.Position=pos;p.Anchored=fixed
    p.Gravity=Vector3.zero
    p.CanCollide=false
    return p
end
function joint(kind,a,b,offsetA,offsetB)
    local j=Instance.new(kind,assembly)
    j.Attachment0=Instance.new("Attachment",a)
    j.Attachment1=Instance.new("Attachment",b)
    j.Attachment0.Position=offsetA or Vector3.zero
    j.Attachment1.Position=offsetB or Vector3.zero
    return j
end
rail=part("Rail",Vector3.new(0,30,0),true)
car=part("Car",Vector3.new(0,30,0),false)
payload=part("Payload",Vector3.new(0,30,2),false)
weld=Instance.new("WeldConstraint",car)
weld.Part0,weld.Part1=car,payload
cylinder=joint("CylindricalConstraint",rail,car)
cylinder.LimitsEnabled=true
cylinder.LowerLimit=-4
cylinder.UpperLimit=4
cylinder.AngularLimitsEnabled=true
cylinder.LowerAngle=-10
cylinder.UpperAngle=10
arm=part("Arm",Vector3.new(0,30,4),false)
universal=joint("UniversalConstraint",payload,arm,Vector3.new(0,0,1),Vector3.new(0,0,-1))
universal.LimitsEnabled=true
universal.MaxAngle=30
planeBase=part("PlaneBase",Vector3.new(30,30,0),true)
planePart=part("PlanePart",Vector3.new(30,30,0),false)
plane=joint("PlaneConstraint",planeBase,planePart)
planeDrive=Instance.new("LinearVelocity",planePart)
planeDrive.Attachment0=Instance.new("Attachment",planePart)
planeDrive.VelocityConstraintMode=Enum.VelocityConstraintMode.Plane
planeDrive.PrimaryTangentAxis=Vector3.yAxis
planeDrive.SecondaryTangentAxis=Vector3.zAxis
planeDrive.PlaneVelocity=Vector2.new(3,4)
planeDrive.ForceLimitsEnabled=false
drive=Instance.new("LinearVelocity",payload)
drive.Attachment0=Instance.new("Attachment",payload)
drive.VelocityConstraintMode=Enum.VelocityConstraintMode.Line
drive.LineDirection=Vector3.xAxis
drive.LineVelocity=3
drive.ForceLimitsEnabled=false
orient=Instance.new("AlignOrientation",car)
orient.Attachment0=Instance.new("Attachment",car)
orient.Mode=Enum.OrientationAlignmentMode.OneAttachment
orient.CFrame=CFrame.Angles(math.rad(8),0,0)
orient.MaxTorque=500
`,
		"build welded cylinder, universal and independently driven plane",
	)
	step(&env, &v, 120)
	run(
		&v,
		`
assert(cylinder.Active and universal.Active and plane.Active and drive.Active and orient.Active)
assert(car.Position.X>3.5 and car.Position.X<4.2,tostring(car.Position))
assert(math.abs(car.Position.Y-30)<0.15,tostring(car.Position))
assert((car.CFrame:PointToObjectSpace(payload.Position)-Vector3.new(0,0,2)).Magnitude<0.15)
local pivot0=payload.CFrame:PointToWorldSpace(universal.Attachment0.Position)
local pivot1=arm.CFrame:PointToWorldSpace(universal.Attachment1.Position)
assert((pivot0-pivot1).Magnitude<0.2,tostring((pivot0-pivot1).Magnitude))
assert(math.abs(planePart.Position.X-30)<0.08)
assert(math.abs(planePart.AssemblyLinearVelocity.Y-3)<0.3)
assert(math.abs(planePart.AssemblyLinearVelocity.Z-4)<0.3)
drive.LineVelocity=-3
`,
		"combined movement and joint limits",
	)
	step(&env, &v, 180)
	run(
		&v,
		`
assert(car.Position.X < -3.5 and car.Position.X > -4.2,tostring(car.Position))
assert((car.CFrame:PointToObjectSpace(payload.Position)-Vector3.new(0,0,2)).Magnitude<0.15)
cylinder.Enabled=false
universal.Parent=nil
plane.Enabled=false
drive.Enabled=false
orient.Enabled=false
planeDrive.Enabled=false
`,
		"reverse and disable",
	)
	step(&env, &v, 2)
	run(
		&v,
		`
assert(not cylinder.Active and not universal.Active and not plane.Active)
assert(not drive.Active and not orient.Active and not planeDrive.Active)
cylinder.Enabled=true
universal.Parent=assembly
plane.Enabled=true
drive.Enabled=true
orient.Enabled=true
planeDrive.Enabled=true
`,
		"rebuild",
	)
	step(&env, &v, 30)
	run(
		&v,
		`
assert(cylinder.Active and universal.Active and plane.Active)
payload:Destroy()
`,
		"destroy a welded endpoint",
	)
	step(&env, &v, 2)
	run(
		&v,
		`
assert(not universal.Active and universal.Attachment0==nil)
assert(cylinder.Active and plane.Active)
`,
		"endpoint cleanup",
	)
	fmt.println("IMPORTED_CONSTRAINT_ASSEMBLY_SMOKE_PASSED")
}
