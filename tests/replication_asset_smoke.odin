package main

// Asset transfer over the replication wire.
//
// A network client never loads a map: main.odin only calls load_game_map for a
// server, a playtest or a standalone client, and the asset store is only ever
// filled as a side effect of deserializing a .kine stream. So without this the
// client's store is empty for its whole life, every `kineasset://` reference
// misses, and the mesh silently renders as a primitive box.
//
// Both ends of this test run in one process and the asset store is a package
// level global, so the store's contents cannot prove anything crossed the
// socket. The framing round trip below is checked directly, and the session
// assertions are on the sent / received counters, which only move if the bytes
// really went over the wire.

import "core:fmt"
import "core:slice"
import assetstore "../src/engine/assetstore"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"

run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("replication asset smoke failed")
	}
}

// bytes_of turns a string into a fresh byte slice. A string is a distinct type
// from []u8 in Odin and a literal is untyped, so neither can be transmuted in
// place; the fixtures are ASCII, so one byte per character is exact.
bytes_of :: proc(text: string) -> [dynamic]u8 {
	out: [dynamic]u8
	for ch in text {
		append(&out, u8(ch))
	}
	return out
}

// repeated_bytes builds `size` bytes whose value depends on the offset, so a
// reassembled asset can be compared byte for byte and not merely by length. A
// buffer of constant bytes would survive almost any chunking mistake.
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
	// -------------------------------------------------------------------------
	// Framing: an entry has to survive encode -> decode byte for byte, and a
	// payload longer than the bytes actually present must be refused rather than
	// trusted.
	// -------------------------------------------------------------------------
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

		reader := services.Replication_Reader{data = encoded[:], valid = true}
		id, path, kind, data, accepted := services.decode_asset_entry(&reader)
		check_frame(
			"asset entry round trips",
			accepted &&
			id == "0123456789abcdef" &&
			path == "meshes/hero.fbx" &&
			kind == assetstore.Asset_Kind.Mesh &&
			string(data) == "PAYLOAD",
		)

		// One byte short of the declared length. A parser that believes the
		// declared length instead of checking it walks off the end of its input.
		reader = services.Replication_Reader{data = encoded[:len(encoded) - 1], valid = true}
		_, _, _, _, accepted = services.decode_asset_entry(&reader)
		check_frame("asset entry rejects a truncated payload", !accepted)
		check_frame("truncation is reported as a reader fault", !reader.valid)

		// A frame that is not an entry at all.
		not_an_entry: [dynamic]u8
		defer delete(not_an_entry)
		append(&not_an_entry, services.Replication_Asset_Subtype_End)
		reader = services.Replication_Reader{data = not_an_entry[:], valid = true}
		_, _, _, _, accepted = services.decode_asset_entry(&reader)
		check_frame("asset entry rejects a non-entry subtype", !accepted)
	}

	// -------------------------------------------------------------------------
	// The real thing: a server holding assets, a client holding none.
	// -------------------------------------------------------------------------
	server_vm := vm.New()
	client_vm := vm.New()
	server: engine_runtime.Environment
	client: engine_runtime.Environment
	engine_runtime.Environment_Init(&server, &server_vm)
	engine_runtime.Environment_Init(&client, &client_vm)

	// Published the way a loaded map publishes them: under a content id the store
	// derived from the bytes. Register takes ownership of the buffer, so neither
	// slice is freed here; freeing one leaves the store holding a dangling pointer
	// and a later comparison against the same asset reads whatever is there now.
	mesh_bytes := bytes_of("MESH-BYTES-FOR-TEST")
	mesh_id := assetstore.Register(mesh_bytes[:], "meshes/hero.fbx", .Mesh)
	defer delete(mesh_id)
	texture_bytes := bytes_of("TEXTURE-BYTES-FOR-TEST")
	texture_id := assetstore.Register(texture_bytes[:], "textures/hero.png", .Texture)
	defer delete(texture_id)

	// Past the ceiling replication_send puts on a single frame. Meshes are
	// routinely this size -- a glTF mesh with baked textures runs to several
	// megabytes -- and one of them used to abort the whole table, leaving the
	// client unable to resolve any kineasset:// reference and rendering the
	// model as a primitive box.
	BIG_ASSET_SIZE :: 1536 * 1024
	big_bytes := repeated_bytes(BIG_ASSET_SIZE, 7)
	big_id := assetstore.Register(big_bytes[:], "meshes/big.fbx", .Mesh)
	defer delete(big_id)

	check_frame(
		"fixtures published into the store",
		mesh_id != "" && texture_id != "" && big_id != "",
	)

	run_script(&server_vm, `
local r = game:GetService("ReplicatorService")
assert(r:RegisterSchema("Part", { "CanQuery" }))
assert(r:StartServer("127.0.0.1", 39471))
local floor = Instance.new("Part")
floor.Name = "Floor"
floor.Anchored = true
floor.Size = Vector3.new(4000, 1, 4000)
floor.CFrame = CFrame.new(0, -0.5, 0)
floor.Parent = game:GetService("Workspace")
`, "replication_asset_server_setup")

	run_script(&client_vm, `
local r = game:GetService("ReplicatorService")
assert(r:RegisterSchema("Part", { "CanQuery" }))
assert(r:ConnectClient("127.0.0.1", 39471))
`, "replication_asset_client_setup")

	// Stepped until the transfer actually lands rather than for a fixed number of
	// frames. A frame budget is a guess at how fast a real socket drains, so it
	// passes on an idle machine and fails under load; the closing frame is the
	// signal that the table is whole, so wait on that. The bound is only there so
	// a broken transfer fails the test instead of hanging it.
	server_service := cast(^services.ReplicatorService)services.Find_Service(
		&server.services,
		"ReplicatorService",
	).object
	client_service := cast(^services.ReplicatorService)services.Find_Service(
		&client.services,
		"ReplicatorService",
	).object

	settled := false
	for _ in 0 ..< 900 {
		engine_runtime.Environment_Render_Step(&server, &server_vm, 1.0 / 60.0)
		engine_runtime.Environment_Render_Step(&client, &client_vm, 1.0 / 60.0)
		if client_service.asset_table_complete {
			settled = true
			break
		}
	}
	if !settled {
		// A failure here is otherwise invisible: the test would only say the
		// budget ran out. Report what each side actually did, because the useful
		// split is whether the server never sent, the client never received, or the
		// closing frame never arrived.
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

	// -------------------------------------------------------------------------
	// The closing frame is only worth having if its count is checked. Rewind the
	// client to "nothing has arrived yet" and feed it a closing frame that claims
	// otherwise, the way a truncated transfer or a peer that omits entries on
	// purpose would. A client that believed it would mark an incomplete table
	// complete, which is the one outcome the frame exists to prevent.
	// -------------------------------------------------------------------------
	{
		client_service.assets_received = 0
		client_service.asset_table_complete = false
		before := client_service.asset_rejections

		frame: [dynamic]u8
		defer delete(frame)
		append(&frame, 'K', 'R', 'P', u8(services.Replication_Protocol_Version))
		append(&frame, services.Replication_Kind_Asset)
		append(&frame, services.Replication_Asset_Subtype_End)
		// Little endian, so the frame claims a table of 5.
		for byte in ([?]u8{5, 0, 0, 0}) {append(&frame, byte)}

		services.replication_receive(
			client_service,
			client_vm.L,
			client_service.remote,
			frame[:],
		)

		check_frame(
			"a closing frame that overstates the table is refused",
			!client_service.asset_table_complete,
		)
		check_frame(
			"an overstated closing frame is counted as a rejection",
			client_service.asset_rejections == before + 1,
		)
	}

	// -------------------------------------------------------------------------
	// A mesh is routinely larger than one frame, so it travels as a Begin frame
	// followed by Chunks. Two things have to hold: every frame stays inside the
	// cap the sender enforces, and the reassembled bytes are identical to what
	// was sent. A length-only check would pass on a chunker that reordered or
	// dropped a slice, which is the failure that actually corrupts a model.
	// -------------------------------------------------------------------------
	{
		HUGE :: 700 * 1024
		source := repeated_bytes(HUGE, 3)
		defer delete(source)

		// subtype + index on the chunk, plus the 5 byte frame header that
		// replication_send adds. If this fails, a full sized chunk cannot fit a
		// frame and a chunked asset deadlocks against its own limit.
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
		// The subtype byte is consumed by the dispatcher, so the decoder is
		// handed the frame the way it is at runtime.
		reader := services.Replication_Reader{data = begin[1:], valid = true}
		id, path, kind, total, accepted := services.decode_asset_begin(&reader)
		check_frame(
			"a chunked asset announces its size and identity",
			accepted &&
			id == "0123456789abcdef" &&
			path == "meshes/huge.fbx" &&
			kind == assetstore.Asset_Kind.Mesh &&
			total == u32(HUGE),
		)

		// An announced total beyond what the store would ever accept is a claim
		// about memory this client is being asked to reserve, so it is refused
		// before any bytes are accepted.
		overblown: [dynamic]u8
		defer delete(overblown)
		services.encode_asset_begin(
			&overblown,
			"0123456789abcdef",
			"meshes/huge.fbx",
			assetstore.Asset_Kind.Mesh,
			0xFFFFFFFF,
		)
		reader = services.Replication_Reader{data = overblown[1:], valid = true}
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
			chunk_reader := services.Replication_Reader{data = frame[1:], valid = true}
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
			len(rebuilt) == HUGE &&
			slice.equal(rebuilt[:], source[:]),
		)

		// A chunk larger than the per frame ceiling is refused outright rather
		// than copied into a reassembly buffer.
		oversized_body := repeated_bytes(int(services.Replication_Asset_Max_Chunk) + 1, 9)
		defer delete(oversized_body)
		oversized: [dynamic]u8
		defer delete(oversized)
		services.encode_asset_chunk(&oversized, 0, oversized_body[:])
		chunk_reader := services.Replication_Reader{data = oversized[1:], valid = true}
		_, _, accepted = services.decode_asset_chunk(&chunk_reader)
		check_frame("an oversized chunk is refused", !accepted)
	}

	fmt.println("ASSET_REPLICATION_PASSED")
}