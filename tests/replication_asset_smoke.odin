package main


import assetstore "../src/engine/assetstore"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"
import "core:slice"
import "core:time"

run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("replication asset smoke failed")
	}
}


bytes_of :: proc(text: string) -> [dynamic]u8 {
	out: [dynamic]u8
	for ch in text {
		append(&out, u8(ch))
	}
	return out
}


repeated_bytes :: proc(size: int, seed: u8) -> [dynamic]u8 {
	out := make([dynamic]u8, size)
	for index in 0 ..< size {out[index] = u8(index) + seed}
	return out
}

check_frame :: proc(label: string, condition: bool) {
	if !condition {
		panic(label)
	}
	fmt.printf("PASS  %s\n", label)
}

main :: proc() {


	{
		payload := bytes_of("PAYLOAD")
		defer delete(payload)
		encoded: [dynamic]u8
		defer delete(encoded)
		services.encode_asset_entry(
			&encoded,
			"0123456789abcdef",
			"meshes/hero.fbx",
			assetstore.Asset_Kind.Mesh,
			payload[:],
		)

		reader := services.Replication_Reader {
			data  = encoded[:],
			valid = true,
		}
		id, path, kind, data, accepted := services.decode_asset_entry(&reader)
		check_frame(
			"asset entry round trips",
			accepted &&
			id == "0123456789abcdef" &&
			path == "meshes/hero.fbx" &&
			kind == assetstore.Asset_Kind.Mesh &&
			string(data) == "PAYLOAD",
		)


		reader = services.Replication_Reader {
			data  = encoded[:len(encoded) - 1],
			valid = true,
		}
		_, _, _, _, accepted = services.decode_asset_entry(&reader)
		check_frame("asset entry rejects a truncated payload", !accepted)
		check_frame("truncation is reported as a reader fault", !reader.valid)


		not_an_entry: [dynamic]u8
		defer delete(not_an_entry)
		append(&not_an_entry, services.Replication_Asset_Subtype_End)
		reader = services.Replication_Reader {
			data  = not_an_entry[:],
			valid = true,
		}
		_, _, _, _, accepted = services.decode_asset_entry(&reader)
		check_frame("asset entry rejects a non-entry subtype", !accepted)
	}


	server_vm := vm.New()
	client_vm := vm.New()
	server: engine_runtime.Environment
	client: engine_runtime.Environment
	engine_runtime.Environment_Init(&server, &server_vm)
	engine_runtime.Environment_Init(&client, &client_vm)


	mesh_bytes := bytes_of("MESH-BYTES-FOR-TEST")
	mesh_id := assetstore.Register(mesh_bytes[:], "meshes/hero.fbx", .Mesh)
	defer delete(mesh_id)
	texture_bytes := bytes_of("TEXTURE-BYTES-FOR-TEST")
	texture_id := assetstore.Register(texture_bytes[:], "textures/hero.png", .Texture)
	defer delete(texture_id)


	BIG_ASSET_SIZE :: 1536 * 1024
	big_bytes := repeated_bytes(BIG_ASSET_SIZE, 7)
	big_id := assetstore.Register(big_bytes[:], "meshes/big.fbx", .Mesh)
	defer delete(big_id)

	check_frame(
		"fixtures published into the store",
		mesh_id != "" && texture_id != "" && big_id != "",
	)

	run_script(
		&server_vm,
		`
local r = game:GetService("ReplicatorService")
assert(r:RegisterSchema("Part", { "CanQuery" }))
assert(r:StartServer("127.0.0.1", 39471))
local floor = Instance.new("Part")
floor.Name = "Floor"
floor.Anchored = true
floor.Size = Vector3.new(4000, 1, 4000)
floor.CFrame = CFrame.new(0, -0.5, 0)
floor.Parent = game:GetService("Workspace")
`,
		"replication_asset_server_setup",
	)

	run_script(
		&client_vm,
		`
local r = game:GetService("ReplicatorService")
assert(r:RegisterSchema("Part", { "CanQuery" }))
assert(r:ConnectClient("127.0.0.1", 39471))
`,
		"replication_asset_client_setup",
	)


	server_service := cast(^services.ReplicatorService)services.Find_Service(&server.services, "ReplicatorService").object
	client_service := cast(^services.ReplicatorService)services.Find_Service(&client.services, "ReplicatorService").object

	settled := false
	for _ in 0 ..< 900 {
		engine_runtime.Environment_Render_Step(&server, &server_vm, 1.0 / 60.0)
		engine_runtime.Environment_Render_Step(&client, &client_vm, 1.0 / 60.0)


		time.sleep(15 * time.Millisecond)
		if client_service.asset_table_complete {
			settled = true
			break
		}
	}
	if !settled {


		fmt.eprintf(
			"server: handshake=%v sent=%d connected=%v\nclient: handshake=%v received=%d bytes=%d rejections=%d complete=%v connected=%v\n",
			server_service.peers != nil && len(server_service.peers) > 0,
			server_service.assets_sent,
			server_service.connected,
			client_service.handshake_complete,
			client_service.assets_received,
			client_service.asset_bytes_received,
			client_service.asset_rejections,
			client_service.asset_table_complete,
			client_service.connected,
		)
	}
	check_frame("the client's asset table arrived within the step budget", settled)

	check_frame("server handed the client a session", client_service.handshake_complete)
	check_frame(
		"server pushed every asset it holds",
		server_service.assets_sent == u64(assetstore.Count()),
	)
	check_frame(
		"client accepted the whole table",
		client_service.asset_table_complete &&
		client_service.assets_received == server_service.assets_sent,
	)
	check_frame("no asset was refused", client_service.asset_rejections == 0)
	expected_bytes := len("MESH-BYTES-FOR-TEST") + len("TEXTURE-BYTES-FOR-TEST") + BIG_ASSET_SIZE
	check_frame(
		"the bytes that arrived match what was sent",
		client_service.asset_bytes_received == u64(expected_bytes),
	)


	{
		client_service.assets_received = 0
		client_service.asset_table_complete = false
		before := client_service.asset_rejections

		frame: [dynamic]u8
		defer delete(frame)
		append(&frame, 'K', 'R', 'P', u8(services.Replication_Protocol_Version))
		append(&frame, services.Replication_Kind_Asset)
		append(&frame, services.Replication_Asset_Subtype_End)

		for byte in ([?]u8{5, 0, 0, 0}) {append(&frame, byte)}

		services.replication_receive(client_service, client_vm.L, client_service.remote, frame[:])

		check_frame(
			"a closing frame that overstates the table is refused",
			!client_service.asset_table_complete,
		)
		check_frame(
			"an overstated closing frame is counted as a rejection",
			client_service.asset_rejections == before + 1,
		)
	}


	{
		HUGE :: 700 * 1024
		source := repeated_bytes(HUGE, 3)
		defer delete(source)


		check_frame(
			"a full sized chunk still fits inside one frame",
			int(services.Replication_Asset_Max_Chunk) + 1 + 4 + 5 <=
			int(services.Replication_Max_Frame_Payload),
		)

		begin: [dynamic]u8
		defer delete(begin)
		services.encode_asset_begin(
			&begin,
			"0123456789abcdef",
			"meshes/huge.fbx",
			assetstore.Asset_Kind.Mesh,
			u32(HUGE),
		)


		reader := services.Replication_Reader {
			data  = begin[1:],
			valid = true,
		}
		id, path, kind, total, accepted := services.decode_asset_begin(&reader)
		check_frame(
			"a chunked asset announces its size and identity",
			accepted &&
			id == "0123456789abcdef" &&
			path == "meshes/huge.fbx" &&
			kind == assetstore.Asset_Kind.Mesh &&
			total == u32(HUGE),
		)


		overblown: [dynamic]u8
		defer delete(overblown)
		services.encode_asset_begin(
			&overblown,
			"0123456789abcdef",
			"meshes/huge.fbx",
			assetstore.Asset_Kind.Mesh,
			0xFFFFFFFF,
		)
		reader = services.Replication_Reader {
			data  = overblown[1:],
			valid = true,
		}
		_, _, _, _, accepted = services.decode_asset_begin(&reader)
		check_frame("an absurd announced total is refused", !accepted)
		check_frame("an absurd total is reported as a reader fault", !reader.valid)

		CHUNK :: 128 * 1024
		rebuilt: [dynamic]u8
		defer delete(rebuilt)
		in_order := true
		expected_index := 0
		for start := 0; start < HUGE; start += CHUNK {
			end := min(start + CHUNK, HUGE)
			frame: [dynamic]u8
			services.encode_asset_chunk(&frame, u32(expected_index), source[start:end])
			chunk_reader := services.Replication_Reader {
				data  = frame[1:],
				valid = true,
			}
			index, data, chunk_ok := services.decode_asset_chunk(&chunk_reader)
			if !chunk_ok || int(index) != expected_index {in_order = false}
			expected_index += 1
			append(&rebuilt, ..data)
			delete(frame)
		}
		check_frame("every chunk of a large asset is accepted", in_order)
		check_frame("a large asset is split across several chunks", expected_index > 1)
		check_frame(
			"a chunked asset reassembles byte for byte",
			len(rebuilt) == HUGE && slice.equal(rebuilt[:], source[:]),
		)


		oversized_body := repeated_bytes(int(services.Replication_Asset_Max_Chunk) + 1, 9)
		defer delete(oversized_body)
		oversized: [dynamic]u8
		defer delete(oversized)
		services.encode_asset_chunk(&oversized, 0, oversized_body[:])
		chunk_reader := services.Replication_Reader {
			data  = oversized[1:],
			valid = true,
		}
		_, _, accepted = services.decode_asset_chunk(&chunk_reader)
		check_frame("an oversized chunk is refused", !accepted)
	}

	fmt.println("ASSET_REPLICATION_PASSED")
}
