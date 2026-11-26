package main

import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("aerodynamics service smoke test failed")
	}
}

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)

	run_script(
		&script_vm,
		`
local aero = game:GetService("Aerodynamics")
assert(aero:IsA("Service"))
assert(aero.Name == "Aerodynamics")
assert(aero.Enabled == false)
assert(aero.MaxSpeed == 0 and math.abs(aero.WaveDrag - 0.15) < 1e-5)
assert(workspace.FluidForces == false)

aero.Enabled = true
assert(aero.Enabled)
assert(workspace.FluidForces)
workspace.FluidForces = false
assert(aero.Enabled == false)

assert(aero.Atmosphere == Enum.AerodynamicsAtmosphere.Standard)
assert(aero.Mode == Enum.AerodynamicsMode.Auto)
assert(aero.NormalAxis == Enum.AerodynamicsNormalAxis.Auto)

aero.Atmosphere = Enum.AerodynamicsAtmosphere.Legacy
aero.Mode = Enum.AerodynamicsMode.Wing
aero.NormalAxis = Enum.AerodynamicsNormalAxis.Z
assert(aero.Atmosphere == Enum.AerodynamicsAtmosphere.Legacy)
assert(aero.Mode == Enum.AerodynamicsMode.Wing)
assert(aero.NormalAxis == Enum.AerodynamicsNormalAxis.Z)

aero.Density = 0.8
aero.MetersPerUnit = 2
aero.ReferenceHeight = 10
aero.DensityScaleHeight = 500
aero.Wind = vector.create(1, 2, 3)
aero.WindShear = vector.create(0.1, 0, 0)
aero.Gust = vector.create(2, 0, 0)
aero.GustFrequency = 0.5
aero.GustWavelength = 20
aero.MinSpeed = 0.1
aero.MaxSpeed = 150
aero.ThinRatio = 0.3
aero.MinimumDimension = 0.002
aero.MaxForce = 1000
aero.MaxTorque = 500
aero.DragCoefficient = 1.2
aero.ProfileDrag = 0.03
aero.LiftMultiplier = 1.1
aero.StallAngle = 16
aero.Efficiency = 0.85
aero.MaxLift = 1.4
aero.AreaMultiplier = 1.2
aero.DirectionalDrag = vector.create(1, 2, 3)
aero.PressureOffset = vector.create(0, 0.1, 0)
aero.IncidenceAngle = 2
aero.WaveDrag = 0.1
aero.SoundSpeed = 340
aero.WakeSleeping = false

assert(math.abs(aero.Density - 0.8) < 1e-5)
assert(math.abs(aero.MetersPerUnit - 2) < 1e-5)
assert(math.abs(aero.ReferenceHeight - 10) < 1e-5)
assert(math.abs(aero.Wind.X - 1) < 1e-5)
assert(math.abs(aero.WindShear.X - 0.1) < 1e-5)
assert(math.abs(aero.Gust.X - 2) < 1e-5)
assert(math.abs(aero.GustFrequency - 0.5) < 1e-5)
assert(math.abs(aero.GustWavelength - 20) < 1e-5)
assert(math.abs(aero.MinSpeed - 0.1) < 1e-5)
assert(math.abs(aero.MaxSpeed - 150) < 1e-5)
assert(math.abs(aero.ThinRatio - 0.3) < 1e-5)
assert(math.abs(aero.MinimumDimension - 0.002) < 1e-5)
assert(math.abs(aero.MaxForce - 1000) < 1e-5)
assert(math.abs(aero.MaxTorque - 500) < 1e-5)
assert(math.abs(aero.DragCoefficient - 1.2) < 1e-5)
assert(math.abs(aero.ProfileDrag - 0.03) < 1e-5)
assert(math.abs(aero.LiftMultiplier - 1.1) < 1e-5)
assert(math.abs(aero.StallAngle - 16) < 1e-5)
assert(math.abs(aero.Efficiency - 0.85) < 1e-5)
assert(math.abs(aero.MaxLift - 1.4) < 1e-5)
assert(math.abs(aero.AreaMultiplier - 1.2) < 1e-5)
assert(math.abs(aero.DirectionalDrag.Y - 2) < 1e-5)
assert(math.abs(aero.PressureOffset.Y - 0.1) < 1e-5)
assert(math.abs(aero.IncidenceAngle - 2) < 1e-5)
assert(math.abs(aero.WaveDrag - 0.1) < 1e-5)
assert(math.abs(aero.SoundSpeed - 340) < 1e-5)
assert(aero.WakeSleeping == false)

aero.Density = -5
aero.MetersPerUnit = 0
assert(aero.Density == 0)
assert(aero.MetersPerUnit > 0)

aero:ResetToDefaults()
assert(aero.Enabled == false)
assert(math.abs(aero.Density - 1.225) < 1e-5)
assert(aero.Mode == Enum.AerodynamicsMode.Auto)
assert(aero.Atmosphere == Enum.AerodynamicsAtmosphere.Standard)
assert(aero.Wind.X == 0 and aero.Wind.Y == 0 and aero.Wind.Z == 0)
`,
		"aerodynamics_service",
	)

	run_script(
		&script_vm,
		`
local aero = game:GetService("Aerodynamics")
aero.Enabled = true
aero.Wind = vector.create(0, 0, 10)

local part = Instance.new("Part", workspace)
part.Anchored = false
part.Size = vector.create(4, 4, 4)
part.Position = vector.create(0, 100, 0)
`,
		"aerodynamics_step_setup",
	)
	engine_runtime.Environment_Update_Step(&environment, &script_vm, 1.0 / 60.0)
	run_script(
		&script_vm,
		`
assert(game:GetService("Physics").BodyCount >= 1)
`,
		"aerodynamics_step",
	)

	run_script(
		&script_vm,
		`
local aero = game:GetService("Aerodynamics")
aero.Enabled = false
local aircraft = Instance.new("PhysicsModel", workspace)
aircraft.Name = "FastAircraft"
aircraft.GravityScale = 0
aircraft.MaxLinearVelocity = 1800
local hull = Instance.new("Part", aircraft)
hull.Name = "Hull"
hull.Size = Vector3.new(4, 2, 2)
hull.Position = Vector3.new(0, 1000, 0)
hull.Anchored = false
`,
		"high_speed_setup",
	)
	engine_runtime.Environment_Update_Step(&environment, &script_vm, 1.0 / 60.0)
	run_script(
		&script_vm,
		`
local p = workspace.FastAircraft.Hull
p.AssemblyLinearVelocity = Vector3.new(1200, 0, 0)
assert(p.AssemblyLinearVelocity.X > 1000, tostring(p.AssemblyLinearVelocity))
`,
		"high_speed_velocity",
	)
	engine_runtime.Environment_Update_Step(&environment, &script_vm, 1.0 / 60.0)
	run_script(
		&script_vm,
		`
local model = workspace.FastAircraft
assert(model.Hull.AssemblyLinearVelocity.X > 1000)
model.MaxLinearVelocity = 700
model.Hull.AssemblyLinearVelocity = Vector3.new(1200, 0, 0)
assert(model.Hull.AssemblyLinearVelocity.X <= 701)
`,
		"high_speed_live_limit",
	)
	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("AERODYNAMICS_SERVICE_SMOKE_PASSED")
}
