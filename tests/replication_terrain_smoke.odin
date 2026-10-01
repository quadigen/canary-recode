package main

import "core:fmt"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"

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

	server_terrain := cast(^services.Terrain)services.Find_Service(
		&server.services,
		"Terrain",
	).object
	{
		header: [dynamic]u8
		defer delete(header)
		services.encode_terrain_header(&header, server_terrain)

		reader := services.Replication_Reader{data = header[:], valid = true}
		// The dispatch site consumes the subtype byte before it knows which
		// reader to call, so the header decoder starts after it.
		reader.offset = 1
		voxel_size, iso_level, draw_version, declared, ok := services.decode_terrain_header(&reader)
		check_frame(
			"terrain header round trips",
			ok &&
			abs(voxel_size - server_terrain.voxel_size) < 0.0001 &&
			abs(iso_level - server_terrain.iso_level) < 0.0001 &&
			draw_version == u32(server_terrain.draw_version),
		)

		// A header claiming a zero voxel size is the cheapest way to turn a
		// received map into garbage coordinates. voxel_size is the fifth through
		// eighth bytes: the subtype, then the four-byte cell count.
		bad: [dynamic]u8
		defer delete(bad)
		services.encode_terrain_header(&bad, server_terrain)
		bad[5] = 0
		bad[6] = 0
		bad[7] = 0
		bad[8] = 0
		reader = services.Replication_Reader{data = bad[:], valid = true}
		reader.offset = 1
		_, _, _, _, ok = services.decode_terrain_header(&reader)
		check_frame("terrain header rejects a zero voxel size", !ok)
	}

	// -------------------------------------------------------------------------
	// A batch has to survive encode -> decode with its material and its two
	// fractional fields intact. Occupancy and water are 16-bit fixed point, so
	// the tolerance is one quantization step rather than exact equality.
	// -------------------------------------------------------------------------
	{
		cells: [dynamic]services.Terrain_Cell_Record
		defer delete(cells)
		append(&cells, services.Terrain_Cell_Record{x = -7, y = 3, z = 11, occupancy = 1, water = 0, material = .Grass})
		append(&cells, services.Terrain_Cell_Record{x = 0, y = 0, z = 0, occupancy = 0, water = 0.75, material = .Water})
		append(&cells, services.Terrain_Cell_Record{x = 4096, y = -4096, z = 0, occupancy = 0, water = 0.5, material = .Glass})
		append(&cells, services.Terrain_Cell_Record{x = 1, y = 2, z = 3, occupancy = 1, water = 0, material = .Neon})

		payload: [dynamic]u8
		defer delete(payload)
		services.encode_terrain_batch(&payload, cells[:])

		reader := services.Replication_Reader{data = payload[:], valid = true}
		// Skip the subtype byte, exactly as the transport does before dispatching.
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

		// Truncated by one byte. A parser that trusts the declared count walks off
		// the end of its input.
		reader = services.Replication_Reader{data = payload[:len(payload) - 1], valid = true}
		reader.offset = 1
		truncated, accepted := services.decode_terrain_batch(&reader)
		defer delete(truncated)
		check_frame("terrain batch rejects a truncated payload", !accepted)

		// A declared count far larger than the bytes present must be refused
		// before it drives an allocation loop.
		hostile := make([]u8, 8)
		defer delete(hostile)
		hostile[0] = services.Replication_Terrain_Subtype_Batch
		hostile[1] = 0xFF
		hostile[2] = 0xFF
		hostile[3] = 0xFF
		hostile[4] = 0xFF
		reader = services.Replication_Reader{data = hostile, valid = true}
		reader.offset = 1
		refused, hostile_ok := services.decode_terrain_batch(&reader)
		defer delete(refused)
		check_frame("terrain batch refuses a hostile cell count", !hostile_ok)
		check_frame("a hostile cell count is reported as a reader fault", !reader.valid)
	}

	// -------------------------------------------------------------------------
	// The real thing: a server holding terrain, a client holding none.
	// -------------------------------------------------------------------------
	run_script(&server_vm, `
local r = game:GetService("ReplicatorService")
assert(r:RegisterSchema("Part", { "CanQuery" }))
assert(r:StartServer("127.0.0.1", 39472))
local terrain = game:GetService("Terrain")
terrain:SetCell(0, 0, 0, Enum.Material.Grass)
terrain:SetCell(1, 0, 0, Enum.Material.Grass)
terrain:SetCell(2, 0, 0, Enum.Material.Neon)
terrain:SetCell(3, 0, 0, Enum.Material.Slate)
terrain:SetWaterCell(4, 0, 0)
`, "replication_terrain_server_setup")

	run_script(&client_vm, `
local r = game:GetService("ReplicatorService")
assert(r:RegisterSchema("Part", { "CanQuery" }))
assert(r:ConnectClient("127.0.0.1", 39472))
`, "replication_terrain_client_setup")

	client_service := cast(^services.ReplicatorService)services.Find_Service(
		&client.services,
		"ReplicatorService",
	).object

	// Stepped until the transfer lands rather than for a fixed number of frames.
	// A frame budget is a guess at how fast a real socket drains, so it passes
	// on an idle machine and fails under load; the closing frame is the signal
	// that the table is whole. The bound only exists so a broken transfer fails
	// the test instead of hanging it.
	server_service := cast(^services.ReplicatorService)services.Find_Service(
		&server.services,
		"ReplicatorService",
	).object
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
		// Otherwise the test would only say the budget ran out. The useful split
		// is whether the header never arrived, the batches stalled, or the closing
		// frame never landed.
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

	// The counters only prove frames moved. Reading the client's own Terrain
	// service back through the scripting API is what proves the voxels actually
	// landed in its map, materials and water included.
	run_script(&client_vm, `
local terrain = game:GetService("Terrain")
local material, occupancy = terrain:GetCell(0, 0, 0)
assert(material == Enum.Material.Grass, "cell 0 material")
assert(occupancy > 0.5, "cell 0 occupancy")
material, occupancy = terrain:GetCell(2, 0, 0)
assert(material == Enum.Material.Neon, "cell 2 material")
assert(occupancy > 0.5, "cell 2 occupancy")
material, occupancy = terrain:GetCell(3, 0, 0)
assert(material == Enum.Material.Slate, "cell 3 material")
local water_material, depth = terrain:GetWaterCell(4, 0, 0)
assert(depth > 0.5, "cell 4 water depth")
`, "replication_terrain_client_verify")

	// -------------------------------------------------------------------------
	// A connect-time snapshot only covers the map as it was when the client
	// joined. Without deltas a server that edits terrain afterwards leaves the
	// client standing on a world that no longer exists, which is exactly the
	// desync this is here to prevent.
	// -------------------------------------------------------------------------
	{
		baseline := client_service.terrain_cells_received
		run_script(&server_vm, `
local terrain = game:GetService("Terrain")
terrain:SetCell(10, 0, 0, Enum.Material.Concrete)
terrain:SetCell(0, 0, 0, Enum.Material.Brick)
terrain:SetVoxel(3, 0, 0, 0, Enum.Material.Air)
`, "replication_terrain_server_edit")

		// Waited on the client's own cell counter rather than a frame count, for
		// the same reason the snapshot wait is: the delta is paced by the
		// snapshot clock, and a fixed budget would be a guess at socket latency.
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

		// An edit, a new voxel and a removal, checked through the client's own
		// Terrain service. A removal has to travel as an empty record, so this is
		// also the only thing here that proves deletions are not silently
		// dropped.
		run_script(&client_vm, `
local terrain = game:GetService("Terrain")
local material, occupancy = terrain:GetCell(10, 0, 0)
assert(material == Enum.Material.Concrete, "new voxel material")
assert(occupancy > 0.5, "new voxel occupancy")
material, occupancy = terrain:GetCell(0, 0, 0)
assert(material == Enum.Material.Brick, "edited voxel material")
material, occupancy = terrain:GetCell(3, 0, 0)
assert(material == Enum.Material.Air, "removed voxel material")
assert(occupancy < 0.5, "removed voxel occupancy")
`, "replication_terrain_client_verify_delta")
	}

	// -------------------------------------------------------------------------
	// Two clients, staggered.
	//
	// The pending-change map is shared by every peer, so anything that resets it
	// on connect discards changes still owed to a client that joined earlier.
	// That client cannot be told about them afterwards, because its cursor has
	// already moved past them, so it stays stale for the rest of the session.
	// This is the only shape that catches it: a single client never has a peer
	// whose delivery depends on state the second connect would reset.
	// -------------------------------------------------------------------------
	{
		late_vm := vm.New()
		late: engine_runtime.Environment
		engine_runtime.Environment_Init(&late, &late_vm)
		late_service := cast(^services.ReplicatorService)services.Find_Service(
			&late.services,
			"ReplicatorService",
		).object

		// The edit and the second connect are both issued before any stepping.
		// The window this needs is the one where A is still owed a change that has
		// not been delivered, and B is about to connect. Letting A catch up first
		// would make the test pass whether or not the implementation is correct.
		caught_up := client_service.terrain_cells_received
		run_script(&server_vm, `
local terrain = game:GetService("Terrain")
terrain:SetCell(20, 0, 0, Enum.Material.Grass)
`, "replication_terrain_server_edit_before_second_client")

		run_script(&late_vm, `
local r = game:GetService("ReplicatorService")
assert(r:RegisterSchema("Part", { "CanQuery" }))
assert(r:ConnectClient("127.0.0.1", 39472))
`, "replication_terrain_late_client_setup")

		for _ in 0 ..< 900 {
			engine_runtime.Environment_Render_Step(&server, &server_vm, 1.0 / 60.0)
			engine_runtime.Environment_Render_Step(&client, &client_vm, 1.0 / 60.0)
			engine_runtime.Environment_Render_Step(&late, &late_vm, 1.0 / 60.0)
			if late_service.terrain_table_complete &&
			   client_service.terrain_cells_received > caught_up {
				break
			}
		}
		check_frame("a second client also received the terrain", late_service.terrain_table_complete)
		check_frame(
			"the earlier client was not charged for the second client connecting",
			client_service.terrain_cells_received > caught_up,
		)

		// Now edit again, after both clients are connected, and require both to
		// converge on it.
		before_first := client_service.terrain_cells_received
		before_late := late_service.terrain_cells_received
		run_script(&server_vm, `
local terrain = game:GetService("Terrain")
terrain:SetCell(30, 0, 0, Enum.Material.Glass)
`, "replication_terrain_server_edit_after_second_client")

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

		// The earlier client is the one that matters: it is the peer whose
		// delivery depended on state the second connect could have reset.
		run_script(&client_vm, `
local terrain = game:GetService("Terrain")
local material, occupancy = terrain:GetCell(30, 0, 0)
assert(material == Enum.Material.Glass, "earlier client sees the newest edit")
local earlier, earlier_occupancy = terrain:GetCell(20, 0, 0)
assert(earlier == Enum.Material.Grass, "earlier client kept an edit from before the second connect")
`, "replication_terrain_client_verify_staggered")
	}

	// -------------------------------------------------------------------------
	// The closing frame is only worth having if its count is checked. Rewind the
	// client to "nothing has arrived" and feed it a closing frame that claims
	// otherwise, the way a truncated transfer or a peer that omits batches on
	// purpose would. A client that believed it would mark an incomplete terrain
	// complete, which is the one outcome the frame exists to prevent.
	// -------------------------------------------------------------------------
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

		services.replication_receive(
			client_service,
			client_vm.L,
			client_service.remote,
			frame[:],
		)

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
