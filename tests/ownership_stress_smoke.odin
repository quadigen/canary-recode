package main

import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

CLIENT_COUNT :: 5
OWNERSHIP_STRESS_PORT :: 39238

run_stress :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("ownership stress smoke failed")
	}
}

stress_step :: proc(
	server: ^engine_runtime.Environment,
	server_vm: ^vm.VM,
	clients: []engine_runtime.Environment,
	client_vms: []vm.VM,
	frames: int,
) {
	for _ in 0 ..< frames {
		engine_runtime.Environment_Render_Step(server, server_vm, 1.0 / 60.0)
		for i in 0 ..< len(clients) {
			engine_runtime.Environment_Render_Step(&clients[i], &client_vms[i], 1.0 / 60.0)
		}
	}
}

main :: proc() {
	server_vm := vm.New()
	client_vms: [CLIENT_COUNT]vm.VM
	server: engine_runtime.Environment
	clients: [CLIENT_COUNT]engine_runtime.Environment
	engine_runtime.Environment_Init(&server, &server_vm)
	for i in 0 ..< CLIENT_COUNT {
		client_vms[i] = vm.New()
		engine_runtime.Environment_Init(&clients[i], &client_vms[i])
	}

	run_stress(
		&server_vm,
		`
local r = game:GetService("ReplicatorService")
assert(r:StartServer("127.0.0.1", 39238))
local floor = Instance.new("Part", workspace)
floor.Name = "Floor"
floor.Anchored = true
floor.Size = vector.create(300, 1, 300)
local folder = Instance.new("Folder", workspace)
folder.Name = "FallenCrumbs"
`,
		"own_stress_server_setup",
	)

	for i in 0 ..< CLIENT_COUNT {
		run_stress(
			&client_vms[i],
			`
assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39238))
`,
			fmt.tprintf("own_stress_connect_%d", i),
		)

		stress_step(&server, &server_vm, clients[:], client_vms[:], 15)
	}


	stress_step(&server, &server_vm, clients[:], client_vms[:], 120)

	run_stress(
		&server_vm,
		`
local r = game:GetService("ReplicatorService")
local folder = workspace:FindFirstChild("FallenCrumbs")
local rng = Random.new()
local function jitter() return (rng:NextNumber() * 2 - 1) end
local seeded = 0
for i = 1, 300 do
	local crumb = Instance.new("Part", folder)
	crumb.Name = "Crumb" .. i
	crumb.Anchored = false
	local s = 1 + rng:NextNumber() * 2
	crumb.Size = vector.create(s, s, s)
	crumb.CFrame = CFrame.new(jitter() * 25, 12, jitter() * 25)
	seeded += 1
end
assert(seeded == 300, "drop loop should create 300 crumbs")
accepted_before = r:GetStats().ownedStatesAccepted or 0
`,
		"own_stress_drop",
	)


	stress_step(&server, &server_vm, clients[:], client_vms[:], 360)

	run_stress(
		&server_vm,
		`
local folder = workspace:FindFirstChild("FallenCrumbs")
local owned_now = 0
for _, crumb in ipairs(folder:GetChildren()) do
	if crumb:GetNetworkOwner() ~= nil then owned_now += 1 end
end
assert(owned_now >= 50, "parts should be client-owned during the drop, got " .. tostring(owned_now))
`,
		"own_stress_drop_owned",
	)

	for i in 0 ..< CLIENT_COUNT {
		run_stress(
			&client_vms[i],
			`
local id = game.Players.LocalPlayer.UserId
local dirs = {
	[1] = Vector3.new(1, 0, 0),
	[2] = Vector3.new(-1, 0, 0),
	[3] = Vector3.new(0, 0, 1),
	[4] = Vector3.new(0, 0, -1),
	[5] = Vector3.new(1, 0, 1),
}
assert(dirs[id] ~= nil, "unexpected LocalPlayer id " .. tostring(id))
game:GetService("CharacterService"):SetMoveDirection(dirs[id])
`,
			fmt.tprintf("own_stress_walk_%d", i),
		)
	}


	stress_step(&server, &server_vm, clients[:], client_vms[:], 240)

	for i in 0 ..< CLIENT_COUNT {
		run_stress(
			&client_vms[i],
			`
game:GetService("CharacterService"):SetMoveDirection(Vector3.new(0, 0, 0))
`,
			fmt.tprintf("own_stress_stop_%d", i),
		)
	}

	stress_step(&server, &server_vm, clients[:], client_vms[:], 120)

	run_stress(
		&server_vm,
		`
local r = game:GetService("ReplicatorService")
local folder = workspace:FindFirstChild("FallenCrumbs")
assert(#game.Players:GetPlayers() == 5, "five players should be connected")
local roots = {}
for _, p in ipairs(game.Players:GetPlayers()) do
	local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
	if root then roots[#roots + 1] = root.Position end
end
local client_count = 0
local misplaced = 0
local frozen = 0
for _, crumb in ipairs(folder:GetChildren()) do
	local owner = crumb:GetNetworkOwner()
	local pos = crumb.Position
	if owner ~= nil then
		client_count += 1
		local nearest_sq = math.huge
		for _, root in ipairs(roots) do
			local dx, dy, dz = pos.X - root.X, pos.Y - root.Y, pos.Z - root.Z
			local d = dx * dx + dy * dy + dz * dz
			if d < nearest_sq then nearest_sq = d end
		end
		if nearest_sq > 100 * 100 then misplaced += 1 end
	end
	-- A crumb may rest on the floor, near a player, or on another crumb.
	-- Anything else that is still airborne is a frozen/leaked part.
	local held = pos.Y <= 2.0
	for _, root in ipairs(roots) do
		local dx, dy, dz = pos.X - root.X, pos.Y - root.Y, pos.Z - root.Z
		if dx * dx + dy * dy + dz * dz <= 6 * 6 then held = true break end
	end
	if not held then
		for _, other in ipairs(folder:GetChildren()) do
			if other ~= crumb then
				local dx, dz = pos.X - other.Position.X, pos.Z - other.Position.Z
				local dy = pos.Y - other.Position.Y
				if dy > 0 and dy <= 3.5 and dx * dx + dz * dz <= 3.5 * 3.5 then held = true break end
			end
		end
	end
	if not held and pos.Y > 3.5 then frozen += 1 end
end
assert(misplaced == 0, "airborne or far owner should have been released, got " .. tostring(misplaced))
assert(frozen == 0, "no part should freeze in mid-air, got " .. tostring(frozen))
assert(client_count >= 1, "stress should end with parts in client hands, got " .. tostring(client_count))
assert(r:GetStats().ownedStatesAccepted > accepted_before, "stress run should accept owned states")
`,
		"own_stress_final",
	)

	for i in 0 ..< CLIENT_COUNT {
		run_stress(
			&client_vms[i],
			`game:GetService("ReplicatorService"):Stop()`,
			fmt.tprintf("own_stress_client_stop_%d", i),
		)
	}
	run_stress(&server_vm, `game:GetService("ReplicatorService"):Stop()`, "own_stress_server_stop")
	for i in 0 ..< CLIENT_COUNT {
		vm.Close(&client_vms[i])
		engine_runtime.Environment_Destroy(&clients[i])
	}
	vm.Close(&server_vm)
	engine_runtime.Environment_Destroy(&server)
	fmt.println("OWNERSHIP_STRESS_SMOKE_PASSED")
}
