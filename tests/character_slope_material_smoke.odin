package main

// Exercises the character controller on otherwise identical walkable ramps whose
// surface materials -- and therefore Jolt friction values -- differ, so it is
// obvious whether the character holds or slides because of (missing) friction.
//
// The controller moves a kinematic capsule with shape casts, so friction must not
// change how it climbs or whether it holds still. The final section is a control:
// free dynamic boxes on the very same low- and high-friction materials, which must
// slide and hold respectively, proving Jolt really is applying the material
// friction and that the character's behaviour is friction-independent by design.

import "core:fmt"
import "core:strconv"
import "core:strings"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"

// One walkable ramp is built for each of these, in this order.
CHARACTER_SLOPE_MATERIALS :: [?]string {
	"SmoothPlastic",
	"Glass",
	"Wood",
	"Slate",
	"Concrete",
	"Sand",
}

slope_run :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("character slope material smoke failed")
	}
}

// Runs `body` as a chunk with `SLOPE` assigned to the 1-based ramp index first.
slope_run_index :: proc(script_vm: ^vm.VM, body: string, index: int, name: string) {
	number: [16]u8
	materials := CHARACTER_SLOPE_MATERIALS
	source := strings.concatenate({"SLOPE = ", strconv.write_int(number[:], i64(index), 10), "\n", body})
	defer delete(source)
	slope_run(script_vm, source, fmt.tprintf("%s[%s]", name, materials[index - 1]))
}

slope_step :: proc(
	server: ^engine_runtime.Environment,
	server_vm: ^vm.VM,
	client: ^engine_runtime.Environment,
	client_vm: ^vm.VM,
	frames: int,
) {
	for _ in 0..<frames {
		engine_runtime.Environment_Render_Step(server, server_vm, 1.0 / 60.0)
		engine_runtime.Environment_Render_Step(client, client_vm, 1.0 / 60.0)
	}
}

main :: proc() {
	server_vm := vm.New()
	client_vm := vm.New()
	server: engine_runtime.Environment
	client: engine_runtime.Environment
	engine_runtime.Environment_Init(&server, &server_vm)
	engine_runtime.Environment_Init(&client, &client_vm)

	// The floor has to exist before the character loads so it spawns on top of it.
	slope_run(&server_vm, `
assert(game:GetService("ReplicatorService"):StartServer("127.0.0.1", 39241))
local floor = Instance.new("Part", workspace)
floor.Name = "Spawn"
floor.Anchored = true
floor.Size = vector.create(500, 1, 500)
floor.CFrame = CFrame.new(0, 4, 0)

-- One 20 degree ramp per material. They share identical geometry and differ only
-- in Material, so any behavioural difference can only come from friction.
local function walk_ramp(index, z, material)
    local ramp = Instance.new("Part", workspace)
    ramp.Name = "Slope" .. index
    ramp.Anchored = true
    ramp.Size = vector.create(16, 1, 10)
    ramp.CFrame = CFrame.new(13, 4, z) * CFrame.Angles(0, 0, math.rad(20))
    ramp.Material = material
end
walk_ramp(1, 0, Enum.Material.SmoothPlastic)
walk_ramp(2, 14, Enum.Material.Glass)
walk_ramp(3, 28, Enum.Material.Wood)
walk_ramp(4, 42, Enum.Material.Slate)
walk_ramp(5, 56, Enum.Material.Concrete)
walk_ramp(6, 70, Enum.Material.Sand)
`, "slope_material_server_setup")

	slope_run(&client_vm, `
assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39241))
`, "slope_material_client_connect")

	slope_step(&server, &server_vm, &client, &client_vm, 180)

	// The client drives this character, so it owns the reference resting height.
	slope_run(&client_vm, `
local char = game:GetService("Players").LocalPlayer.Character
slope_rest_y = char.RootPart.CFrame.Position.Y
for _, c in ipairs(char:GetChildren()) do
    if c:IsA("CharacterController") then c.MaxSlopeAngle = 45 end
end
`, "slope_material_client_baseline")

	for index in 0..<len(CHARACTER_SLOPE_MATERIALS) {
		ramp := index + 1

		// Park on the floor in front of this ramp, then let the reset reach the
		// server before it starts measuring.
		slope_run_index(&client_vm, `
local char = game:GetService("Players").LocalPlayer.Character
assert(game:GetService("CharacterService"):SetMoveDirection(Vector3.new(0, 0, 0)))
for _, p in ipairs(char:GetChildren()) do
    if p:IsA("Part") then p.CFrame = CFrame.new(0, slope_rest_y, (SLOPE - 1) * 14) end
end
`, ramp, "slope_material_park")
		slope_step(&server, &server_vm, &client, &client_vm, 30)

		slope_run_index(&server_vm, `
local root = game:GetService("Players"):GetPlayers()[1].Character.RootPart
slope_result = {
    base = root.CFrame.Position.Y,
    peak = root.CFrame.Position.Y,
    x0 = root.CFrame.Position.X,
}
`, ramp, "slope_material_walk_base")

		slope_run(&client_vm, `
assert(game:GetService("CharacterService"):SetMoveDirection(Vector3.new(1, 0, 0)))
`, "slope_material_walk_start")

		for _ in 0..<48 {
			slope_step(&server, &server_vm, &client, &client_vm, 5)
			slope_run(&server_vm, `
local root = game:GetService("Players"):GetPlayers()[1].Character.RootPart
slope_result.peak = math.max(slope_result.peak, root.CFrame.Position.Y)
`, "slope_material_walk_sample")
		}

		slope_run_index(&server_vm, `
local name = workspace:FindFirstChild("Slope" .. SLOPE).Material.Name
local root = game:GetService("Players"):GetPlayers()[1].Character.RootPart
local rise = slope_result.peak - slope_result.base
local moved = root.CFrame.Position.X - slope_result.x0
print("slope climb  " .. name .. "  rise=" .. string.format("%.3f", rise) .. "  moved_x=" .. string.format("%.3f", moved))
assert(rise > 1.5, name .. " ramp was not climbed, rise=" .. tostring(rise))
assert(root.CFrame.Position.X > slope_result.x0 + 6, name .. " ramp stalled, x=" .. tostring(root.CFrame.Position.X))
`, ramp, "slope_material_walk_assert")

		// Stop, let the input velocity decay, then check the character holds its
		// ground on the ramp instead of sliding down it.
		slope_run(&client_vm, `
assert(game:GetService("CharacterService"):SetMoveDirection(Vector3.new(0, 0, 0)))
`, "slope_material_hold_release")
		slope_step(&server, &server_vm, &client, &client_vm, 40)
		slope_run(&server_vm, `
local root = game:GetService("Players"):GetPlayers()[1].Character.RootPart
slope_hold = root.CFrame.Position
`, "slope_material_hold_base")
		slope_step(&server, &server_vm, &client, &client_vm, 150)
		slope_run_index(&server_vm, `
local name = workspace:FindFirstChild("Slope" .. SLOPE).Material.Name
local root = game:GetService("Players"):GetPlayers()[1].Character.RootPart
local drift = (root.CFrame.Position - slope_hold).Magnitude
print("slope hold   " .. name .. "  drift=" .. string.format("%.4f", drift))
assert(drift < 0.3, name .. " character slid while idle, drift=" .. tostring(drift))
`, ramp, "slope_material_hold_assert")
	}

	// Control: free dynamic bodies on the same two materials. If friction never
	// reached Jolt, both boxes would hold and the character result above would be
	// meaningless. They are created here rather than up front so they have not
	// already slid to the bottom by the time they are measured.
	slope_run(&server_vm, `
local function control_ramp(name, z, material)
    local ramp = Instance.new("Part", workspace)
    ramp.Name = name
    ramp.Anchored = true
    ramp.Size = vector.create(24, 1, 10)
    ramp.CFrame = CFrame.new(13, 11, z) * CFrame.Angles(0, 0, math.rad(30))
    ramp.Material = material
    return ramp
end
local function control_box(name, ramp, along, material)
    local box = Instance.new("Part", workspace)
    box.Name = name
    box.Anchored = false
    box.Size = vector.create(2, 2, 2)
    box.Material = material
    -- Sit the box one half-height above the ramp surface, away along the slope.
    box.CFrame = CFrame.new(ramp.CFrame:VectorToWorldSpace(vector.create(along, 1.5, 0)) + ramp.CFrame.Position)
    return box
end
local slick = control_ramp("ControlSlide", 120, Enum.Material.Glass)
local grippy = control_ramp("ControlHold", 140, Enum.Material.Sand)
control_box("SlickBox", slick, 4, Enum.Material.Glass)
control_box("GrippyBox", grippy, 4, Enum.Material.Sand)
`, "slope_material_control_setup")
	slope_step(&server, &server_vm, &client, &client_vm, 2)
	slope_run(&server_vm, `
local slick = workspace:FindFirstChild("SlickBox")
local grippy = workspace:FindFirstChild("GrippyBox")
control_hold = { slick = slick.CFrame.Position, grippy = grippy.CFrame.Position }
print("control boxes  dynamic=" .. tostring(not slick.Anchored and not grippy.Anchored) .. "  bodies=" .. tostring(game:GetService("Physics").BodyCount))
`, "slope_material_control_base")
	slope_step(&server, &server_vm, &client, &client_vm, 180)
	slope_run(&server_vm, `
local slick_moved = (workspace:FindFirstChild("SlickBox").CFrame.Position - control_hold.slick).Magnitude
local grippy_moved = (workspace:FindFirstChild("GrippyBox").CFrame.Position - control_hold.grippy).Magnitude
print("control box  glass(friction .30) slide=" .. string.format("%.3f", slick_moved) .. "  sand(friction .90) slide=" .. string.format("%.3f", grippy_moved))
assert(slick_moved > 1.5, "low friction box should have slid, moved=" .. tostring(slick_moved))
assert(grippy_moved < 2.0, "high friction box should have held, moved=" .. tostring(grippy_moved))
`, "slope_material_control_assert")

	slope_run(&client_vm, `game:GetService("ReplicatorService"):Stop()`, "slope_material_client_stop")
	slope_step(&server, &server_vm, &client, &client_vm, 30)
	slope_run(&server_vm, `game:GetService("ReplicatorService"):Stop()`, "slope_material_server_stop")

	vm.Close(&client_vm)
	vm.Close(&server_vm)
	engine_runtime.Environment_Destroy(&client)
	engine_runtime.Environment_Destroy(&server)
	fmt.println("CHARACTER_SLOPE_MATERIAL_SMOKE_PASSED")
}
