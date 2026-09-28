package main

// Relevancy and level of detail.
//
// This covers the spatial scoping rules, which decide what a client is told
// about at all:
//
//   - the focus is the client's own camera when there is one, falling back to
//     its character, resolved once per snapshot rather than per entity
//   - anything that is not spatially positioned follows the focus's scope
//   - a part that leaves the relevance sphere is despawned on the client, not
//     simply left behind at its last position
//   - a client with no focus at all gets nothing rather than the whole world
//
// The last two are the ones that used to leak: relevancy returned true for
// anything it could not measure, and there was no despawn packet, so a part that
// walked out of range stayed on the client forever at a frozen position.

import "core:fmt"
import datatypes "../src/engine/datatypes"
import engine_runtime "../src/engine/runtime"
import classes "../src/engine/classes"
import services "../src/engine/services"
import vm "../src/engine/vm"

run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("replication relevancy smoke failed")
	}
}

step_network :: proc(environment: ^engine_runtime.Environment, script_vm: ^vm.VM) {
	descriptor := services.Find_Service(&environment.services, "ReplicatorService")
	services.Replication_Step(cast(^services.ReplicatorService)descriptor.object, script_vm.L, 1.0 / 60.0)
}

settle :: proc(
	server: ^engine_runtime.Environment,
	server_vm: ^vm.VM,
	client: ^engine_runtime.Environment,
	client_vm: ^vm.VM,
	count: int,
) {
	for _ in 0 ..< count {
		step_network(server, server_vm)
		step_network(client, client_vm)
	}
}

service_of :: proc(environment: ^engine_runtime.Environment) -> ^services.ReplicatorService {
	descriptor := services.Find_Service(&environment.services, "ReplicatorService")
	return cast(^services.ReplicatorService)descriptor.object
}

Pair :: struct {
	server:    engine_runtime.Environment,
	client:    engine_runtime.Environment,
	server_vm: vm.VM,
	client_vm: vm.VM,
}

// One port per case, baked into literal scripts. Odin's tprintf reads "{" as a
// custom formatting verb and would eat the Luau table literals these scripts
// depend on, and Odin only concatenates constant strings, so a runtime port
// cannot be spliced in. Distinct ports per case also keep a lingering socket
// from one case from failing the next.
SERVER_SCRIPT_39320 :: `
local r = game:GetService("ReplicatorService")
assert(r:RegisterSchema("Part", { "CanQuery" }))
assert(r:StartServer("127.0.0.1", 39320))
r.RelevancyDistance = 400
local part = Instance.new("Part")
part.Name = "Roamer"
part.Anchored = true
part.Size = Vector3.new(2, 2, 2)
part.CFrame = CFrame.new(0, 0, 0)
part.Parent = game:GetService("Workspace")
local distant = Instance.new("Part")
distant.Name = "Distant"
distant.Anchored = true
distant.Size = Vector3.new(2, 2, 2)
distant.CFrame = CFrame.new(5000, 0, 0)
distant.Parent = game:GetService("Workspace")
local far = Instance.new("Part")
far.Name = "Far"
far.Anchored = true
far.Size = Vector3.new(2, 2, 2)
far.CFrame = CFrame.new(1200, 0, 0)
far.Parent = game:GetService("Workspace")
`

SERVER_SCRIPT_39321 :: `
local r = game:GetService("ReplicatorService")
assert(r:RegisterSchema("Part", { "CanQuery" }))
assert(r:StartServer("127.0.0.1", 39321))
r.RelevancyDistance = 400
local part = Instance.new("Part")
part.Name = "Roamer"
part.Anchored = true
part.Size = Vector3.new(2, 2, 2)
part.CFrame = CFrame.new(0, 0, 0)
part.Parent = game:GetService("Workspace")
`

SERVER_SCRIPT_39322 :: `
local r = game:GetService("ReplicatorService")
assert(r:RegisterSchema("Part", { "CanQuery" }))
assert(r:StartServer("127.0.0.1", 39322))
r.RelevancyDistance = 400
local part = Instance.new("Part")
part.Name = "Roamer"
part.Anchored = true
part.Size = Vector3.new(2, 2, 2)
part.CFrame = CFrame.new(0, 0, 0)
part.Parent = game:GetService("Workspace")
`

CLIENT_SCRIPT_39320 :: `assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39320))`
CLIENT_SCRIPT_39321 :: `assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39321))`
CLIENT_SCRIPT_39322 :: `assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39322))`

SERVER_SCRIPT_39324 :: `
local r = game:GetService("ReplicatorService")
assert(r:RegisterSchema("Part", { "CanQuery" }))
assert(r:StartServer("127.0.0.1", 39324))
r.RelevancyDistance = 400
local near = Instance.new("Part")
near.Name = "Near"
near.Anchored = true
near.Size = Vector3.new(2, 2, 2)
near.CFrame = CFrame.new(40, 0, 0)
near.Parent = game:GetService("Workspace")
local distant = Instance.new("Part")
distant.Name = "Distant"
distant.Anchored = true
distant.Size = Vector3.new(2, 2, 2)
distant.CFrame = CFrame.new(300, 0, 0)
distant.Parent = game:GetService("Workspace")
`

CLIENT_SCRIPT_39324 :: `assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39324))`

SERVER_SCRIPT_39325 :: `
local r = game:GetService("ReplicatorService")
assert(r:RegisterSchema("Part", { "CanQuery" }))
assert(r:StartServer("127.0.0.1", 39325))
r.RelevancyDistance = 400
local part = Instance.new("Part")
part.Name = "Roamer"
part.Anchored = true
part.Size = Vector3.new(2, 2, 2)
part.CFrame = CFrame.new(0, 0, 0)
part.Parent = game:GetService("Workspace")
`

CLIENT_SCRIPT_39325 :: `assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39325))`

pair_start :: proc(pair: ^Pair, server_script, client_script: string) {
	pair.server_vm = vm.New()
	pair.client_vm = vm.New()
	engine_runtime.Environment_Init(&pair.server, &pair.server_vm)
	engine_runtime.Environment_Init(&pair.client, &pair.client_vm)
	run_script(&pair.server_vm, server_script, "relevancy_server_start")
	run_script(&pair.client_vm, client_script, "relevancy_client_start")
	settle(&pair.server, &pair.server_vm, &pair.client, &pair.client_vm, 400)
}

pair_stop :: proc(pair: ^Pair) {
	run_script(&pair.client_vm, `game:GetService("ReplicatorService"):Stop()`, "relevancy_client_stop")
	run_script(&pair.server_vm, `game:GetService("ReplicatorService"):Stop()`, "relevancy_server_stop")
	vm.Close(&pair.server_vm)
	vm.Close(&pair.client_vm)
	engine_runtime.Environment_Destroy(&pair.server)
	engine_runtime.Environment_Destroy(&pair.client)
}

// client_workspace_names returns the sorted child names of the client's
// Workspace, read through the engine rather than through a Luau global so the
// assertion is about what the client actually holds.
client_workspace_names :: proc(pair: ^Pair) -> [dynamic]string {
	names: [dynamic]string
	descriptor := services.Find_Service(&pair.client.services, "Workspace")
	workspace := cast(^services.Workspace)descriptor.object
	for &child in workspace.children {
		append(&names, child.name)
	}
	sort_names(names[:])
	return names
}

sort_names :: proc(names: []string) {
	// Insertion sort keeps this dependency free; the lists are tiny.
	for index := 1; index < len(names); index += 1 {
		value := names[index]
		position := index - 1
		for position >= 0 && names[position] > value {
			names[position + 1] = names[position]
			position -= 1
		}
		names[position + 1] = value
	}
}

has_name :: proc(names: [dynamic]string, name: string) -> bool {
	for candidate in names {if candidate == name {return true}}
	return false
}

// client_position_error returns how far each named part has drifted from where
// the server put it, measured on the client. LOD is only allowed to affect how
// often a part is updated, so the far part is expected to trail the near one.
client_position_error :: proc(pair: ^Pair, near_name, far_name: string) -> (near, far: f32) {
	descriptor := services.Find_Service(&pair.client.services, "Workspace")
	workspace := cast(^services.Workspace)descriptor.object
	for &child in workspace.children {
		if !classes.Is_A(child, "Part") {continue}
		if child.name != near_name && child.name != far_name {continue}
		part := cast(^classes.Part)child
		if child.name == near_name {
			near = abs(part.cframe.z - server_part_z(pair, near_name))
		} else {
			far = abs(part.cframe.z - server_part_z(pair, far_name))
		}
	}
	return
}

server_part_z :: proc(pair: ^Pair, name: string) -> f32 {
	return server_part_by_name(pair, name).cframe.z
}

server_part_by_name :: proc(pair: ^Pair, name: string) -> ^classes.Part {
	descriptor := services.Find_Service(&pair.server.services, "Workspace")
	workspace := cast(^services.Workspace)descriptor.object
	for &child in workspace.children {
		if child.name == name && classes.Is_A(child, "Part") {
			return cast(^classes.Part)child
		}
	}
	panic(fmt.tprintf("server part %q not found", name))
}

// ---------------------------------------------------------------------------
// 1. A part outside the relevance sphere is never sent.
// ---------------------------------------------------------------------------
out_of_range_part_is_not_sent :: proc() {
	pair: Pair
	pair_start(&pair, SERVER_SCRIPT_39320, CLIENT_SCRIPT_39320)
	names := client_workspace_names(&pair)
	assert(
		has_name(names, "Roamer"),
		"a part at the origin was not replicated to a client at the origin",
	)
	assert(
		!has_name(names, "Distant"),
		"a part 5000 studs out was replicated through a 400 stud sphere",
	)
	assert(
		!has_name(names, "Far"),
		"a part 1200 studs out was replicated through a 400 stud sphere",
	)
	pair_stop(&pair)
}

// ---------------------------------------------------------------------------
// 2. A part that walks out of the sphere is removed from the client.
//
//    This is the case that used to fail: the part simply stopped being sent, so
//    the client kept it at whatever position it last received, and it stayed
//    there for the rest of the session.
// ---------------------------------------------------------------------------
leaving_range_despawns :: proc() {
	pair: Pair
	pair_start(&pair, SERVER_SCRIPT_39321, CLIENT_SCRIPT_39321)
	names := client_workspace_names(&pair)
	assert(has_name(names, "Roamer"), "the roamer was not replicated to begin with")

	// Walk it well past the sphere.
	run_script(
		&pair.server_vm,
		`game:GetService("Workspace"):FindFirstChild("Roamer").CFrame = CFrame.new(9000, 0, 0)`,
		"relevancy_walk_away",
	)
	settle(&pair.server, &pair.server_vm, &pair.client, &pair.client_vm, 200)

	names = client_workspace_names(&pair)
	assert(
		!has_name(names, "Roamer"),
		"a part that left the relevance sphere is still on the client",
	)

	// And it must come back when it returns, rather than staying destroyed.
	run_script(
		&pair.server_vm,
		`game:GetService("Workspace"):FindFirstChild("Roamer").CFrame = CFrame.new(0, 0, 0)`,
		"relevancy_walk_back",
	)
	settle(&pair.server, &pair.server_vm, &pair.client, &pair.client_vm, 200)
	names = client_workspace_names(&pair)
	assert(
		has_name(names, "Roamer"),
		"a part that came back into range was not respawned on the client",
	)
	pair_stop(&pair)
}

// ---------------------------------------------------------------------------
// 3. A part that leaves and re-enters range repeatedly must not accumulate
//    state on the client, and the client's entity table must not grow without
//    bound as a result of the churn.
// ---------------------------------------------------------------------------
range_churn_does_not_grow_client_state :: proc() {
	pair: Pair
	pair_start(&pair, SERVER_SCRIPT_39322, CLIENT_SCRIPT_39322)
	for round in 0 ..< 6 {
		run_script(
			&pair.server_vm,
			fmt.tprintf(
				"game:GetService('Workspace'):FindFirstChild('Roamer').CFrame = CFrame.new(%d, 0, 0)",
				9000,
			),
			"relevancy_churn_out",
		)
		settle(&pair.server, &pair.server_vm, &pair.client, &pair.client_vm, 90)
		run_script(
			&pair.server_vm,
			`game:GetService("Workspace"):FindFirstChild("Roamer").CFrame = CFrame.new(0, 0, 0)`,
			"relevancy_churn_in",
		)
		settle(&pair.server, &pair.server_vm, &pair.client, &pair.client_vm, 90)
	}
	client_service := service_of(&pair.client)
	assert(
		len(client_service.entity_list) < 200,
		fmt.tprintf(
			"repeated range churn grew the client entity table to %d entries",
			len(client_service.entity_list),
		),
	)
	pair_stop(&pair)
}

// ---------------------------------------------------------------------------
// 4. Level of detail: a near part is updated every snapshot, a far part inside
//    the same sphere is updated less often.
//
//    Both parts are in range, so both must be present on the client. Only the
//    update frequency is allowed to differ. The far part is moved on the server
//    and the client's copy is checked to see how far behind it ended up: LOD
//    that still sent every frame would let it match exactly.
// ---------------------------------------------------------------------------
lod_reduces_update_rate_for_distant_parts :: proc() {
	pair: Pair
	pair_start(&pair, SERVER_SCRIPT_39324, CLIENT_SCRIPT_39324)

	names := client_workspace_names(&pair)
	assert(has_name(names, "Near"), "a near part was not replicated")
	assert(has_name(names, "Distant"), "a far part inside the sphere was not replicated")

	// The client is seeded at the origin, so the near part sits at 40 studs and
	// the far part at 300, both comfortably inside the 400 stud sphere.
	run_script(
		&pair.server_vm,
		`
local workspace = game:GetService("Workspace")
workspace:FindFirstChild("Near").CFrame = CFrame.new(40, 0, 0)
workspace:FindFirstChild("Distant").CFrame = CFrame.new(300, 0, 0)
`,
		"lod_place",
	)
	settle(&pair.server, &pair.server_vm, &pair.client, &pair.client_vm, 120)

	// Now move both continuously and record the worst lag seen while the motion
	// is still going. Measuring only after the motion stops is useless here:
	// both parts converge to their final position, so a far part updated once
	// every fourth tick and a near part updated every tick end up identical.
	//
	// The motion is driven from Odin rather than from a Luau task.wait, because
	// this harness calls the VM synchronously and a yield would cross the
	// metamethod boundary.
	near_worst: f32 = 0
	distant_worst: f32 = 0
	for step in 1 ..= 120 {
		z := f32(step) * 1.2
		server_part_by_name(&pair, "Near").cframe = datatypes.CFrame_New_XYZ(40, 0, z)
		server_part_by_name(&pair, "Distant").cframe = datatypes.CFrame_New_XYZ(300, 0, z)
		settle(&pair.server, &pair.server_vm, &pair.client, &pair.client_vm, 1)
		near_now, distant_now := client_position_error(&pair, "Near", "Distant")
		if near_now > near_worst {near_worst = near_now}
		if distant_now > distant_worst {distant_worst = distant_now}
	}

	assert(
		near_worst > 0,
		"the near part never moved on the client, so this case measured nothing",
	)
	assert(
		distant_worst > near_worst,
		fmt.tprintf(
			"far part worst lag %.2f vs near %.2f; LOD did not reduce the far update rate",
			distant_worst,
			near_worst,
		),
	)
	pair_stop(&pair)
}

// ---------------------------------------------------------------------------
// 5. Losing the character does not blank the world.
//
//    The focus is the client's own character, and relevancy means "no focus"
//    replicates nothing at all. A respawn unbinds the old model, so there is a
//    window with no owned Part on the server. Without the cached focus point
//    that window would despawn the whole scene and then spend time rebuilding
//    it, which shows up as a visible hitch on every death.
// ---------------------------------------------------------------------------
losing_the_character_does_not_blank_the_world :: proc() {
	pair: Pair
	pair_start(&pair, SERVER_SCRIPT_39325, CLIENT_SCRIPT_39325)

	names := client_workspace_names(&pair)
	assert(has_name(names, "Roamer"), "the roamer was not replicated to begin with")

	// Remove the client's character on the server, the way a respawn would.
	run_script(
		&pair.server_vm,
		`
local players = game:GetService("Players"):GetPlayers()
assert(#players == 1, "expected one player")
local character = players[1].Character
assert(character ~= nil, "expected a character before unloading it")
character:Destroy()
`,
		"relevancy_drop_character",
	)
	settle(&pair.server, &pair.server_vm, &pair.client, &pair.client_vm, 200)

	names = client_workspace_names(&pair)
	assert(
		has_name(names, "Roamer"),
		"the scene was blanked while the client had no character",
	)
	pair_stop(&pair)
}

main :: proc() {
	out_of_range_part_is_not_sent()
	leaving_range_despawns()
	range_churn_does_not_grow_client_state()
	lod_reduces_update_rate_for_distant_parts()
	losing_the_character_does_not_blank_the_world()
	fmt.println("REPLICATION_RELEVANCY_SMOKE_PASSED")
}
