package main


import classes "../src/engine/classes"
import datatypes "../src/engine/datatypes"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"
import "core:math"
import "core:strings"

run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.RunInternal(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("replication unanchored smoke failed")
	}
}

step_pair :: proc(
	server: ^engine_runtime.Environment,
	server_vm: ^vm.VM,
	client: ^engine_runtime.Environment,
	client_vm: ^vm.VM,
	frames: int,
) {
	for _ in 0 ..< frames {
		engine_runtime.Environment_Update_Step(server, server_vm, 1.0 / 60.0)
		engine_runtime.Environment_Update_Step(client, client_vm, 1.0 / 60.0)
	}
}


client_part_pos :: proc(
	client: ^engine_runtime.Environment,
	name: string,
) -> (
	f64,
	f64,
	f64,
	bool,
) {
	descriptor := services.Find_Service(&client.services, "ReplicatorService")
	service := cast(^services.ReplicatorService)descriptor.object
	for entity in service.entity_list {
		if entity.object == nil || !classes.Is_A(entity.object, "Part") {continue}
		part := cast(^classes.Part)entity.object
		if part.name != name {continue}
		return f64(part.cframe.x), f64(part.cframe.y), f64(part.cframe.z), true
	}
	return 0, 0, 0, false
}


burst_part_counts :: proc(client: ^engine_runtime.Environment) -> (at_origin, total: int) {
	descriptor := services.Find_Service(&client.services, "ReplicatorService")
	service := cast(^services.ReplicatorService)descriptor.object
	for entity in service.entity_list {
		if entity.object == nil || !classes.Is_A(entity.object, "Part") {continue}
		part := cast(^classes.Part)entity.object
		if !strings.has_prefix(part.name, "Debris") {continue}
		total += 1
		if math.abs(part.cframe.x) < 0.5 &&
		   math.abs(part.cframe.y) < 0.5 &&
		   math.abs(part.cframe.z) < 0.5 {at_origin += 1}
	}
	return
}

burst_of_parts :: proc() {
	server_vm := vm.New()
	client_vm := vm.New()
	server: engine_runtime.Environment
	client: engine_runtime.Environment
	engine_runtime.Environment_Init(&server, &server_vm, nil, .Server)
	engine_runtime.Environment_Init(&client, &client_vm, nil, .Client)

	run_script(
		&server_vm,
		`
assert(game:GetService("ReplicatorService"):StartServer("127.0.0.1", 39391))
local floor = Instance.new("Part", workspace)
floor.Name = "Floor"
floor.Anchored = true
floor.Size = vector.create(4000, 1, 4000)
floor.CFrame = CFrame.new(0, -0.5, 0)
`,
		"burst_server_setup",
	)
	run_script(
		&client_vm,
		`assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39391))`,
		"burst_client_setup",
	)
	step_pair(&server, &server_vm, &client, &client_vm, 120)


	run_script(
		&server_vm,
		`
for index = 1, 700 do
    local part = Instance.new("Part", workspace)
    part.Name = "Debris" .. tostring(index)
    part.Anchored = false
    part.Size = vector.create(2, 2, 2)
    part.CFrame = CFrame.new(20 + (index % 20) * 6, 10, 20 + math.floor(index / 20) * 6)
end
`,
		"burst_create",
	)

	for frame in 0 ..< 6 {
		engine_runtime.Environment_Update_Step(&server, &server_vm, 1.0 / 60.0)
		engine_runtime.Environment_Update_Step(&client, &client_vm, 1.0 / 60.0)
		at_origin, total := burst_part_counts(&client)
		fmt.printf(
			"frame %2d  client debris total=%d  sitting at the world origin=%d\n",
			frame,
			total,
			at_origin,
		)
		run_script(&client_vm, `
for _, part in workspace:GetPartBoundsInRadius(Vector3.zero, 1) do
    assert(not string.match(part.Name, "^Debris"), "an uninitialized debris part was queryable at the origin")
end
`, "burst_no_ghost_overlap")
	}
	step_pair(&server, &server_vm, &client, &client_vm, 90)
	at_origin, total := burst_part_counts(&client)
	fmt.printf("settled  client debris total=%d  still at the origin=%d\n", total, at_origin)
	assert(total == 700 && at_origin == 0, "every debris part must receive its initial transform")
	run_script(&client_vm, `
local debris = workspace:FindFirstChild("Debris1")
assert(debris and table.find(workspace:GetPartBoundsInRadius(debris.Position, 0.25), debris))
`, "burst_transformed_debris_is_queryable")

	run_script(&server_vm, `game:GetService("ReplicatorService"):Stop()`, "burst_server_stop")
	run_script(&client_vm, `game:GetService("ReplicatorService"):Stop()`, "burst_client_stop")
	vm.Close(&server_vm)
	vm.Close(&client_vm)
	engine_runtime.Environment_Destroy(&server)
	engine_runtime.Environment_Destroy(&client)
}

moving_parts_case :: proc() {
	server_vm := vm.New()
	client_vm := vm.New()
	server: engine_runtime.Environment
	client: engine_runtime.Environment
	engine_runtime.Environment_Init(&server, &server_vm, nil, .Server)
	engine_runtime.Environment_Init(&client, &client_vm, nil, .Client)

	run_script(
		&server_vm,
		`
assert(game:GetService("ReplicatorService"):StartServer("127.0.0.1", 39390))

-- A floor so the client's character has a focus point inside the relevancy
-- sphere; without it the character free-falls and nothing is ever replicated.
local floor = Instance.new("Part", workspace)
floor.Name = "Floor"
floor.Anchored = true
floor.Size = vector.create(4000, 1, 4000)
floor.CFrame = CFrame.new(0, -0.5, 0)

-- The parts under test: unanchored, spread out, resting on the floor.
local spots = {
    { "Crate0",  10,  0,   0 },
    { "Crate1",  40,  0,  20 },
    { "Crate2",  70,  0,  40 },
    { "Crate3", 100,  0,  60 },
}
for _, spot in spots do
    local part = Instance.new("Part", workspace)
    part.Name = spot[1]
    part.Anchored = false
    part.Size = vector.create(4, 4, 4)
    part.CFrame = CFrame.new(spot[2], spot[3] + 2, spot[4])
end
`,
		"unanchored_server_setup",
	)

	run_script(
		&client_vm,
		`assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39390))`,
		"unanchored_client_setup",
	)


	step_pair(&server, &server_vm, &client, &client_vm, 120)

	run_script(
		&server_vm,
		`
local spots = {
    { "Crate0",  10,  0 },
    { "Crate1",  40, 20 },
    { "Crate2",  70, 40 },
    { "Crate3", 100, 60 },
}
for _, spot in spots do
    local part = Instance.new("Part", workspace)
    part.Name = spot[1]
    part.Anchored = false
    part.Size = vector.create(4, 4, 4)
    part.CFrame = CFrame.new(spot[2], spot[3] + 2, 0)
end
`,
		"unanchored_server_create_late",
	)


	names := []string{"Crate0", "Crate1", "Crate2", "Crate3"}
	for frame in 0 ..< 4 {
		engine_runtime.Environment_Update_Step(&server, &server_vm, 1.0 / 60.0)
		engine_runtime.Environment_Update_Step(&client, &client_vm, 1.0 / 60.0)
		for name in names {
			cx, cy, cz, cok := client_part_pos(&client, name)
			sx, sy, sz, _ := client_part_pos(&server, name)
			fmt.printf(
				"frame %2d  %-8s server=(%6.1f,%6.1f,%6.1f)  client=(%6.1f,%6.1f,%6.1f) spawned=%v\n",
				frame,
				name,
				sx,
				sy,
				sz,
				cx,
				cy,
				cz,
				cok,
			)
		}
	}


	run_script(
		&client_vm,
		`
print(
    "CLIENT physics: awake=" .. tostring(workspace:GetNumAwakeParts()) ..
    " bodies=" .. tostring(game:GetService("Physics").BodyCount) ..
    "  (a correct client simulates 0 of the server-authoritative crates)"
)
`,
		"unanchored_client_physics_probe",
	)


	run_script(
		&server_vm,
		`
local base = {
    { "Crate0",  10,  0 },
    { "Crate1",  40, 20 },
    { "Crate2",  70, 40 },
    { "Crate3", 100, 60 },
}
_G.t = 0
function drive()
    _G.t += 1
    for _, spot in base do
        local part = workspace:FindFirstChild(spot[1])
        part.CFrame = CFrame.new(spot[2] + _G.t * 0.5, spot[3] + 2, 0)
    end
end
`,
		"unanchored_server_drive_setup",
	)

	for _ in 0 ..< 120 {
		run_script(&server_vm, `drive()`, "unanchored_server_drive")
		engine_runtime.Environment_Update_Step(&server, &server_vm, 1.0 / 60.0)
		engine_runtime.Environment_Update_Step(&client, &client_vm, 1.0 / 60.0)
	}

	fmt.println("--- server vs client after the crates were driven along +X ---")
	for name in names {
		sx, sy, sz, sok := client_part_pos(&server, name)
		cx, cy, cz, cok := client_part_pos(&client, name)
		fmt.printf(
			"%-8s server=(%7.2f,%7.2f,%7.2f)%v  client=(%7.2f,%7.2f,%7.2f)%v\n",
			name,
			sx,
			sy,
			sz,
			sok,
			cx,
			cy,
			cz,
			cok,
		)
	}

	run_script(&server_vm, `game:GetService("ReplicatorService"):Stop()`, "unanchored_server_stop")
	run_script(&client_vm, `game:GetService("ReplicatorService"):Stop()`, "unanchored_client_stop")
	vm.Close(&server_vm)
	vm.Close(&client_vm)
	engine_runtime.Environment_Destroy(&server)
	engine_runtime.Environment_Destroy(&client)
}


dead_reckoning_first_pass :: proc() {
	server_vm := vm.New()
	client_vm := vm.New()
	server: engine_runtime.Environment
	client: engine_runtime.Environment
	engine_runtime.Environment_Init(&server, &server_vm, nil, .Server)
	engine_runtime.Environment_Init(&client, &client_vm, nil, .Client)

	run_script(
		&server_vm,
		`
assert(game:GetService("ReplicatorService"):StartServer("127.0.0.1", 39392))
local floor = Instance.new("Part", workspace)
floor.Name = "Floor"
floor.Anchored = true
floor.Size = vector.create(4000, 1, 4000)
floor.CFrame = CFrame.new(0, -0.5, 0)
`,
		"dr_server_setup",
	)
	run_script(
		&client_vm,
		`assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39392))`,
		"dr_client_setup",
	)
	step_pair(&server, &server_vm, &client, &client_vm, 120)


	client_service := service_of(&client)
	client_service.time_offset = 30.0
	client_service.time_offset_measured = true

	run_script(
		&server_vm,
		`
local part = Instance.new("Part", workspace)
part.Name = "Meteor"
part.Anchored = false
part.Size = vector.create(4, 4, 4)
part.CFrame = CFrame.new(300, 120, -250)
`,
		"dr_create",
	)

	for _ in 0 ..< 6 {
		engine_runtime.Environment_Update_Step(&server, &server_vm, 1.0 / 60.0)
		engine_runtime.Environment_Update_Step(&client, &client_vm, 1.0 / 60.0)
	}

	cx, cy, cz, found := client_part_pos(&client, "Meteor")
	assert(found, "the meteor never replicated to the client")
	assert(
		math.abs(cx - 300) < 40 && math.abs(cy - 120) < 40 && math.abs(cz + 250) < 40,
		fmt.tprintf(
			"a client that dead reckons before it has interpolated put the part at (%f,%f,%f) instead of near (300,120,-250)",
			cx,
			cy,
			cz,
		),
	)


	descriptor := services.Find_Service(&client.services, "ReplicatorService")
	service := cast(^services.ReplicatorService)descriptor.object
	for entity in service.entity_list {
		if entity.object == nil || !classes.Is_A(entity.object, "Part") {continue}
		part := cast(^classes.Part)entity.object
		if part.name != "Meteor" {continue}
		ROTATION_TOLERANCE: f64 = 0.01
		row0: f64 =
			f64(part.cframe.r00) * f64(part.cframe.r00) +
			f64(part.cframe.r01) * f64(part.cframe.r01) +
			f64(part.cframe.r02) * f64(part.cframe.r02)
		row1: f64 =
			f64(part.cframe.r10) * f64(part.cframe.r10) +
			f64(part.cframe.r11) * f64(part.cframe.r11) +
			f64(part.cframe.r12) * f64(part.cframe.r12)
		row2: f64 =
			f64(part.cframe.r20) * f64(part.cframe.r20) +
			f64(part.cframe.r21) * f64(part.cframe.r21) +
			f64(part.cframe.r22) * f64(part.cframe.r22)


		d0: f64 = row0 - f64(1.0)
		if d0 < f64(0) {d0 = -d0}
		d1: f64 = row1 - f64(1.0)
		if d1 < f64(0) {d1 = -d1}
		d2: f64 = row2 - f64(1.0)
		if d2 < f64(0) {d2 = -d2}
		assert(
			d0 < ROTATION_TOLERANCE,
			fmt.tprintf(
				"rotation basis row 0 length^2 is %f, not 1: transform is degenerate",
				row0,
			),
		)
		assert(
			d1 < ROTATION_TOLERANCE,
			fmt.tprintf(
				"rotation basis row 1 length^2 is %f, not 1: transform is degenerate",
				row1,
			),
		)
		assert(
			d2 < ROTATION_TOLERANCE,
			fmt.tprintf(
				"rotation basis row 2 length^2 is %f, not 1: transform is degenerate",
				row2,
			),
		)
	}

	run_script(&server_vm, `game:GetService("ReplicatorService"):Stop()`, "dr_server_stop")
	run_script(&client_vm, `game:GetService("ReplicatorService"):Stop()`, "dr_client_stop")
	vm.Close(&server_vm)
	vm.Close(&client_vm)
	engine_runtime.Environment_Destroy(&server)
	engine_runtime.Environment_Destroy(&client)
}


service_of :: proc(environment: ^engine_runtime.Environment) -> ^services.ReplicatorService {
	descriptor := services.Find_Service(&environment.services, "ReplicatorService")
	return cast(^services.ReplicatorService)descriptor.object
}


falling_lag :: proc() {
	server_vm := vm.New()
	client_vm := vm.New()
	server: engine_runtime.Environment
	client: engine_runtime.Environment
	engine_runtime.Environment_Init(&server, &server_vm, nil, .Server)
	engine_runtime.Environment_Init(&client, &client_vm, nil, .Client)

	run_script(
		&server_vm,
		`
assert(game:GetService("ReplicatorService"):StartServer("127.0.0.1", 39393))
local floor = Instance.new("Part", workspace)
floor.Name = "Floor"
floor.Anchored = true
floor.Size = vector.create(4000, 1, 4000)
floor.CFrame = CFrame.new(0, -0.5, 0)
`,
		"lag_server_setup",
	)
	run_script(
		&client_vm,
		`assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39393))`,
		"lag_client_setup",
	)
	step_pair(&server, &server_vm, &client, &client_vm, 120)


	run_script(
		&server_vm,
		`
local meteor = Instance.new("Part", workspace)
meteor.Name = "Meteor"
meteor.Shape = Enum.PartType.Ball
meteor.Size = vector.create(6, 6, 6)
meteor.Anchored = false
meteor.CanCollide = true
meteor.Position = vector.create(0, 250, 0)
`,
		"lag_create",
	)

	dt :: f64(1.0 / 60.0)
	previous_server_y: f64 = 0
	have_previous := false
	warmup :: 40
	lag_sum: f64 = 0
	lag_samples := 0
	worst: f64 = 0
	for frame in 0 ..< 240 {
		engine_runtime.Environment_Update_Step(&server, &server_vm, f32(dt))
		engine_runtime.Environment_Update_Step(&client, &client_vm, f32(dt))
		_, sy, _, found := client_part_pos(&server, "Meteor")
		_, cy, _, cfound := client_part_pos(&client, "Meteor")
		if !found || !cfound {continue}
		if have_previous {

			speed := (previous_server_y - sy) / dt
			if speed > 1.0 && frame > warmup {

				lag_ms := (cy - sy) / speed * 1000.0
				lag_sum += lag_ms
				lag_samples += 1
				if lag_ms > worst {worst = lag_ms}
			}
		}
		previous_server_y = sy
		have_previous = true
	}
	if lag_samples <= 0 {
		panic("falling_lag collected no samples; the meteor never replicated or never moved")
	}
	mean := lag_sum / f64(lag_samples)
	fmt.printf(
		"falling meteor render lag: mean %.1f ms, worst %.1f ms over %d samples\n",
		mean,
		worst,
		lag_samples,
	)


	BUDGET_MS :: f64(190.0)
	assert(
		mean < BUDGET_MS,
		fmt.tprintf(
			"a falling Part rendered %.1f ms behind the server on average, beyond the 67ms interpolation delay",
			mean,
		),
	)

	run_script(&server_vm, `game:GetService("ReplicatorService"):Stop()`, "lag_server_stop")
	run_script(&client_vm, `game:GetService("ReplicatorService"):Stop()`, "lag_client_stop")
	vm.Close(&server_vm)
	vm.Close(&client_vm)
	engine_runtime.Environment_Destroy(&server)
	engine_runtime.Environment_Destroy(&client)
}

smooth_prediction_recovery :: proc() {
	dt :: f32(1.0 / 30.0)
	part := classes.Part_Init()
	entity := services.Replication_Entity{object = &part.object}
	defer delete(entity.samples)
	client := services.ReplicatorService{
		mode = .Client,
		snapshot_rate = 30,
		time_offset_measured = true,
		teleport_threshold = 12,
		clock = 10 * dt,
	}
	defer delete(client.entity_list)
	append(&client.entity_list, &entity)
	append(&entity.samples,
		services.Replication_Sample{tick = 9, frame = datatypes.CFrame_Identity},
		services.Replication_Sample{tick = 10, frame = datatypes.CFrame_New_XYZ(1, 0, 0)},
	)
	services.replication_render_interpolated(&client, dt)
	for _ in 0 ..< 2 {
		client.clock += dt
		services.replication_render_interpolated(&client, dt)
	}
	assert(part.position.x > 2.9, "the remote part should predict movement during the gap")

	// The object stopped at X=1 while the client was predicting forward.
	append(&entity.samples, services.Replication_Sample{tick = 12, frame = datatypes.CFrame_New_XYZ(1, 0, 0)})
	services.replication_render_interpolated(&client, dt)
	first := part.position.x
	services.replication_render_interpolated(&client, dt)
	assert(part.position.x > 1.5 && part.position.x < first, "the second recovery frame must continue blending")
	for _ in 0 ..< 60 {
		services.replication_render_interpolated(&client, dt)
	}
	assert(abs(part.position.x - 1) < 0.01, "recovery must converge on the authoritative position")
}

main :: proc() {
	smooth_prediction_recovery()
	dead_reckoning_first_pass()
	falling_lag()
	moving_parts_case()
	burst_of_parts()
	fmt.println("REPLICATION_UNANCHORED_SMOKE_PASSED")
}
