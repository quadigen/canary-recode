package main

import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"

run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("replication terrain smoke failed")
	}
}

check_frame :: proc(label: string, condition: bool) {
	if !condition {
		panic(label)
	}
	fmt.printf("PASS  %s\n", label)
}

main :: proc() {
	server_vm := vm.New()
	client_vm := vm.New()
	server: engine_runtime.Environment
	client: engine_runtime.Environment
	engine_runtime.Environment_Init(&server, &server_vm)
	engine_runtime.Environment_Init(&client, &client_vm)

	server_terrain := cast(^services.Terrain)services.Find_Service(&server.services, "Terrain").object
	{
		header: [dynamic]u8
		defer delete(header)
		services.encode_terrain_header(&header, server_terrain)

		reader := services.Replication_Reader {
			data  = header[:],
			valid = true,
		}


		reader.offset = 1
		voxel_size, iso_level, draw_version, declared, ok := services.decode_terrain_header(
			&reader,
		)
		check_frame(
			"terrain header round trips",
			ok &&
			abs(voxel_size - server_terrain.voxel_size) < 0.0001 &&
			abs(iso_level - server_terrain.iso_level) < 0.0001 &&
			draw_version == u32(server_terrain.draw_version),
		)


		bad: [dynamic]u8
		defer delete(bad)
		services.encode_terrain_header(&bad, server_terrain)
		bad[5] = 0
		bad[6] = 0
		bad[7] = 0
		bad[8] = 0
		reader = services.Replication_Reader {
			data  = bad[:],
			valid = true,
		}
		reader.offset = 1
		_, _, _, _, ok = services.decode_terrain_header(&reader)
		check_frame("terrain header rejects a zero voxel size", !ok)
	}


	{
		cells: [dynamic]services.Terrain_Cell_Record
		defer delete(cells)
		append(
			&cells,
			services.Terrain_Cell_Record {
				x = -7,
				y = 3,
				z = 11,
				occupancy = 1,
				water = 0,
				material = .Grass,
			},
		)
		append(
			&cells,
			services.Terrain_Cell_Record {
				x = 0,
				y = 0,
				z = 0,
				occupancy = 0,
				water = 0.75,
				material = .Water,
			},
		)
		append(
			&cells,
			services.Terrain_Cell_Record {
				x = 4096,
				y = -4096,
				z = 0,
				occupancy = 0,
				water = 0.5,
				material = .Glass,
			},
		)
		append(
			&cells,
			services.Terrain_Cell_Record {
				x = 1,
				y = 2,
				z = 3,
				occupancy = 1,
				water = 0,
				material = .Neon,
			},
		)

		payload: [dynamic]u8
		defer delete(payload)
		services.encode_terrain_batch(&payload, cells[:])

		reader := services.Replication_Reader {
			data  = payload[:],
			valid = true,
		}

		reader.offset = 1
		decoded, ok := services.decode_terrain_batch(&reader)
		defer delete(decoded)

		tolerance := f32(1.0 / 65535.0)
		check_frame(
			"terrain batch round trips",
			ok &&
			len(decoded) == 4 &&
			decoded[0].x == -7 &&
			decoded[0].y == 3 &&
			decoded[0].z == 11 &&
			decoded[0].material == .Grass &&
			abs(decoded[0].occupancy - 1.0) <= tolerance &&
			decoded[1].material == .Water &&
			abs(decoded[1].water - 0.75) <= tolerance &&
			decoded[2].x == 4096 &&
			decoded[2].y == -4096 &&
			decoded[2].material == .Glass &&
			decoded[3].material == .Neon,
		)


		reader = services.Replication_Reader {
			data  = payload[:len(payload) - 1],
			valid = true,
		}
		reader.offset = 1
		truncated, accepted := services.decode_terrain_batch(&reader)
		defer delete(truncated)
		check_frame("terrain batch rejects a truncated payload", !accepted)


		hostile := make([]u8, 8)
		defer delete(hostile)
		hostile[0] = services.Replication_Terrain_Subtype_Batch
		hostile[1] = 0xFF
		hostile[2] = 0xFF
		hostile[3] = 0xFF
		hostile[4] = 0xFF
		reader = services.Replication_Reader {
			data  = hostile,
			valid = true,
		}
		reader.offset = 1
		refused, hostile_ok := services.decode_terrain_batch(&reader)
		defer delete(refused)
		check_frame("terrain batch refuses a hostile cell count", !hostile_ok)
		check_frame("a hostile cell count is reported as a reader fault", !reader.valid)
	}


	run_script(
		&server_vm,
		`
local r = game:GetService("ReplicatorService")
assert(r:RegisterSchema("Part", { "CanQuery" }))
assert(r:StartServer("127.0.0.1", 39472))
local diamond = Instance.new("Part",workspace)
diamond.Name = "DiamondPlateProbe"; diamond.Material = Enum.Material.DiamondPlate
local rubber = Instance.new("Part",workspace)
rubber.Name = "RubberProbe"; rubber.Material = Enum.Material.Rubber
local terrain = game:GetService("Terrain")
terrain:SetCell(0, 0, 0, Enum.Material.Grass)
terrain:SetCell(1, 0, 0, Enum.Material.Grass)
terrain:SetCell(2, 0, 0, Enum.Material.Neon)
terrain:SetCell(3, 0, 0, Enum.Material.Basalt)
terrain:SetWaterCell(4, 0, 0)
`,
		"replication_terrain_server_setup",
	)

	run_script(
		&client_vm,
		`
local r = game:GetService("ReplicatorService")
assert(r:RegisterSchema("Part", { "CanQuery" }))
assert(r:ConnectClient("127.0.0.1", 39472))
`,
		"replication_terrain_client_setup",
	)

	client_service := cast(^services.ReplicatorService)services.Find_Service(&client.services, "ReplicatorService").object


	server_service := cast(^services.ReplicatorService)services.Find_Service(&server.services, "ReplicatorService").object
	settled := false
	for _ in 0 ..< 900 {
		engine_runtime.Environment_Render_Step(&server, &server_vm, 1.0 / 60.0)
		engine_runtime.Environment_Render_Step(&client, &client_vm, 1.0 / 60.0)
		if client_service.terrain_table_complete {
			settled = true
			break
		}
	}
	if !settled {


		fmt.eprintf(
			"client: handshake=%v header=%v batches=%d cells=%d declared=%d rejections=%d connected=%v\n",
			client_service.handshake_complete,
			client_service.terrain_header_seen,
			client_service.terrain_batches_received,
			client_service.terrain_cells_received,
			client_service.terrain_cells_declared,
			client_service.terrain_rejections,
			client_service.connected,
		)
	}
	check_frame("the client's terrain arrived within the step budget", settled)
	check_frame("client completed the handshake", client_service.handshake_complete)
	check_frame("the client saw a terrain header", client_service.terrain_header_seen)
	check_frame("no terrain batch was refused", client_service.terrain_rejections == 0)
	check_frame(
		"the client's cell count matches the server's declaration",
		u32(client_service.terrain_cells_received) == client_service.terrain_cells_declared &&
		client_service.terrain_cells_received == 5,
	)


	run_script(
		&client_vm,
		`
local terrain = game:GetService("Terrain")
local material, occupancy = terrain:GetCell(0, 0, 0)
assert(material == Enum.Material.Grass, "cell 0 material")
assert(occupancy > 0.5, "cell 0 occupancy")
material, occupancy = terrain:GetCell(2, 0, 0)
assert(material == Enum.Material.Neon, "cell 2 material")
assert(occupancy > 0.5, "cell 2 occupancy")
material, occupancy = terrain:GetCell(3, 0, 0)
assert(material == Enum.Material.Basalt, "cell 3 material")
local water_material, depth = terrain:GetWaterCell(4, 0, 0)
assert(depth > 0.5, "cell 4 water depth")
`,
		"replication_terrain_client_verify",
	)


	{
		baseline := client_service.terrain_cells_received
		run_script(
			&server_vm,
			`
local terrain = game:GetService("Terrain")
terrain:SetCell(10, 0, 0, Enum.Material.Concrete)
terrain:SetCell(0, 0, 0, Enum.Material.Brick)
terrain:SetVoxel(3, 0, 0, 0, Enum.Material.Air)
`,
			"replication_terrain_server_edit",
		)


		delivered := false
		for _ in 0 ..< 900 {
			engine_runtime.Environment_Render_Step(&server, &server_vm, 1.0 / 60.0)
			engine_runtime.Environment_Render_Step(&client, &client_vm, 1.0 / 60.0)
			if client_service.terrain_cells_received > baseline {
				delivered = true
				break
			}
		}
		check_frame("terrain edits after connect reached the client", delivered)

		deltas := u64(0)
		if len(server_service.peers) > 0 {
			deltas = server_service.peers[0].terrain_deltas_sent
		}
		check_frame("the server counted the delta cells it sent", deltas >= 3)


		run_script(
			&client_vm,
			`
local terrain = game:GetService("Terrain")
local material, occupancy = terrain:GetCell(10, 0, 0)
assert(material == Enum.Material.Concrete, "new voxel material")
assert(occupancy > 0.5, "new voxel occupancy")
material, occupancy = terrain:GetCell(0, 0, 0)
assert(material == Enum.Material.Brick, "edited voxel material")
material, occupancy = terrain:GetCell(3, 0, 0)
assert(material == Enum.Material.Air, "removed voxel material")
assert(occupancy < 0.5, "removed voxel occupancy")
`,
			"replication_terrain_client_verify_delta",
		)
	}


	{
		late_vm := vm.New()
		late: engine_runtime.Environment
		engine_runtime.Environment_Init(&late, &late_vm)
		late_service := cast(^services.ReplicatorService)services.Find_Service(&late.services, "ReplicatorService").object


		caught_up := client_service.terrain_cells_received
		run_script(
			&server_vm,
			`
local terrain = game:GetService("Terrain")
terrain:SetCell(20, 0, 0, Enum.Material.Grass)
`,
			"replication_terrain_server_edit_before_second_client",
		)

		run_script(
			&late_vm,
			`
local r = game:GetService("ReplicatorService")
assert(r:RegisterSchema("Part", { "CanQuery" }))
assert(r:ConnectClient("127.0.0.1", 39472))
`,
			"replication_terrain_late_client_setup",
		)

		for _ in 0 ..< 900 {
			engine_runtime.Environment_Render_Step(&server, &server_vm, 1.0 / 60.0)
			engine_runtime.Environment_Render_Step(&client, &client_vm, 1.0 / 60.0)
			engine_runtime.Environment_Render_Step(&late, &late_vm, 1.0 / 60.0)
			if late_service.terrain_table_complete &&
			   client_service.terrain_cells_received > caught_up {
				break
			}
		}
		check_frame(
			"a second client also received the terrain",
			late_service.terrain_table_complete,
		)
		check_frame(
			"the earlier client was not charged for the second client connecting",
			client_service.terrain_cells_received > caught_up,
		)


		before_first := client_service.terrain_cells_received
		before_late := late_service.terrain_cells_received
		run_script(
			&server_vm,
			`
local terrain = game:GetService("Terrain")
terrain:SetCell(30, 0, 0, Enum.Material.Glass)
`,
			"replication_terrain_server_edit_after_second_client",
		)

		both := false
		for _ in 0 ..< 900 {
			engine_runtime.Environment_Render_Step(&server, &server_vm, 1.0 / 60.0)
			engine_runtime.Environment_Render_Step(&client, &client_vm, 1.0 / 60.0)
			engine_runtime.Environment_Render_Step(&late, &late_vm, 1.0 / 60.0)
			if client_service.terrain_cells_received > before_first &&
			   late_service.terrain_cells_received > before_late {
				both = true
				break
			}
		}
		check_frame("an edit after both connects reached the earlier client", both)


		run_script(
			&client_vm,
			`
local terrain = game:GetService("Terrain")
local material, occupancy = terrain:GetCell(30, 0, 0)
assert(material == Enum.Material.Glass, "earlier client sees the newest edit")
local earlier, earlier_occupancy = terrain:GetCell(20, 0, 0)
assert(earlier == Enum.Material.Grass, "earlier client kept an edit from before the second connect")
`,
			"replication_terrain_client_verify_staggered",
		)
	}


	services.replication_trim_terrain_history(server_service)
	check_frame(
		"terrain history is released after every peer received the edits",
		len(server_terrain.replication_dirty) == 0,
	)
	run_script(
		&client_vm,
		`
assert(workspace:FindFirstChild("DiamondPlateProbe").Material == Enum.Material.DiamondPlate,"part replication lost DiamondPlate")
assert(workspace:FindFirstChild("RubberProbe").Material == Enum.Material.Rubber,"part replication lost the last material")
`,
		"replication_new_part_materials",
	)


	{
		terrain := cast(^services.Terrain)services.Find_Service(&client.services, "Terrain").object
		before_count := services.Terrain_Cell_Count(terrain)
		header: [dynamic]u8
		defer delete(header)
		append(&header, services.Replication_Terrain_Subtype_Header)
		services.replication_put_u32(&header, 1)
		services.replication_put_f32(&header, terrain.voxel_size)
		services.replication_put_f32(&header, terrain.iso_level)
		services.replication_put_u32(&header, 1)
		reader := services.Replication_Reader {
			data  = header[:],
			valid = true,
		}
		services.replication_receive_terrain(client_service, client_service.remote, &reader)
		check_frame(
			"a resync header preserves the live terrain",
			services.Terrain_Cell_Count(terrain) == before_count,
		)
		check_frame(
			"a resync resets its counters",
			client_service.terrain_cells_received == 0 &&
			client_service.terrain_batches_received == 0,
		)
		payload: [dynamic]u8
		defer delete(payload)
		services.encode_terrain_batch(
			&payload,
			[]services.Terrain_Cell_Record {
				{x = 100, y = 0, z = 0, occupancy = 1, material = .Brick},
			},
		)
		reader = services.Replication_Reader {
			data  = payload[:],
			valid = true,
		}
		services.replication_receive_terrain(client_service, client_service.remote, &reader)
		check_frame(
			"a partial replacement preserves the live terrain",
			services.Terrain_Cell_Count(terrain) == before_count,
		)
		footer: [dynamic]u8
		defer delete(footer)
		append(&footer, services.Replication_Terrain_Subtype_End)
		services.replication_put_u32(&footer, 1)
		services.replication_put_u32(&footer, 1)
		reader = services.Replication_Reader {
			data  = footer[:],
			valid = true,
		}
		services.replication_receive_terrain(client_service, client_service.remote, &reader)
		cell, exists := services.Terrain_Get_Cell(terrain, 100, 0, 0)
		check_frame(
			"a complete replacement commits and removes obsolete cells",
			services.Terrain_Cell_Count(terrain) == 1 && exists && cell.material == .Brick,
		)

		draw_version := terrain.draw_version
		reader = services.Replication_Reader {
			data  = header[:],
			valid = true,
		}
		services.replication_receive_terrain(client_service, client_service.remote, &reader)
		reader = services.Replication_Reader {
			data  = payload[:],
			valid = true,
		}
		services.replication_receive_terrain(client_service, client_service.remote, &reader)
		reader = services.Replication_Reader {
			data  = footer[:],
			valid = true,
		}
		services.replication_receive_terrain(client_service, client_service.remote, &reader)
		check_frame(
			"an identical replacement preserves terrain draw state",
			terrain.draw_version == draw_version,
		)
	}


	{
		client_service.terrain_batches_received = 0
		client_service.terrain_cells_received = 0
		client_service.terrain_table_complete = false
		before := client_service.terrain_rejections

		frame: [dynamic]u8
		defer delete(frame)
		append(&frame, 'K', 'R', 'P', u8(services.Replication_Protocol_Version))
		append(&frame, services.Replication_Kind_Terrain)
		append(&frame, services.Replication_Terrain_Subtype_End)
		for byte in ([?]u8{5, 0, 0, 0}) {append(&frame, byte)}
		append(&frame, 244, 1, 0, 0)

		services.replication_receive(client_service, client_vm.L, client_service.remote, frame[:])

		check_frame(
			"a closing frame that overstates the terrain is refused",
			!client_service.terrain_table_complete,
		)
		check_frame(
			"an overstated terrain closing frame is counted as a rejection",
			client_service.terrain_rejections == before + 1,
		)
	}

	fmt.println("TERRAIN_REPLICATION_PASSED")
}
