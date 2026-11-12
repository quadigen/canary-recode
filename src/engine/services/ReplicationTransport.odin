package services

import assetstore "../assetstore"
import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import signals "../signals"
import tracy "../util/odin-tracy"
import vm "../vm"
import "core:fmt"
import "core:slice"
import "core:sort"
import "core:strings"


Replication_Protocol_Version: u32 = 11


Replication_Max_Frame_Payload: u32 = 1048576


Replication_Minimum_Framing_Version: u32 = 5

Replication_Capability_Ack_Tokens: u32 = 1 << 0
Replication_Capability_Batch_Properties: u32 = 1 << 1
Replication_Capability_Time_Sync: u32 = 1 << 2


Replication_Capability_Asset_Transfer: u32 = 1 << 3


Replication_Capability_Terrain: u32 = 1 << 4


Replication_Capability_Scene_Ready: u32 = 1 << 5


Replication_Capability_Finished_Replicating: u32 = 1 << 6
Replication_Capability_Model_Pivot: u32 = 1 << 7
Replication_Capability_Group_Ownership :: u32(1 << 8)
Replication_Capability_World_Gravity :: u32(1 << 9)
Replication_Capability_Snapshot_Clock :: u32(1 << 10)
Replication_Capability_Owned_Correction :: u32(1 << 11)
Replication_Capability_Player_Gui :: u32(1 << 12)
Replication_Capability_Script_Source :: u32(1 << 13)
Replication_Capability_Metadata :: u32(1 << 14)
Replication_Capability_Player_Reference :: u32(1 << 15)
Replication_Capability_Buffer :: u32(1 << 16)
Replication_Capability_Join_Batch :: u32(1 << 17)
REPLICATION_SNAPSHOT_CLOCK_RATE :: 120


Replication_Local_Capabilities: u32 =
	Replication_Capability_Ack_Tokens |
	Replication_Capability_Batch_Properties |
	Replication_Capability_Time_Sync |
	Replication_Capability_Asset_Transfer |
	Replication_Capability_Terrain |
	Replication_Capability_Scene_Ready |
	Replication_Capability_Finished_Replicating |
	Replication_Capability_Model_Pivot |
	Replication_Capability_Group_Ownership |
	Replication_Capability_World_Gravity |
	Replication_Capability_Snapshot_Clock |
	Replication_Capability_Owned_Correction |
	Replication_Capability_Player_Gui |
	Replication_Capability_Script_Source |
	Replication_Capability_Metadata |
	Replication_Capability_Player_Reference |
	Replication_Capability_Buffer |
	Replication_Capability_Join_Batch

Replication_Handshake_Ok: u8 = 0
Replication_Handshake_Version_Mismatch: u8 = 1
Replication_Handshake_Auth_Rejected: u8 = 2
Replication_Handshake_Malformed: u8 = 3
Replication_Handshake_Already_Complete: u8 = 4
Replication_Handshake_Schema_Mismatch: u8 = 5


Replication_Kind_Owned_State :: u8(11)
Replication_Kind_Owned_Correction :: u8(15)
Replication_Kind_Asset :: u8(21)
Replication_Kind_Terrain :: u8(22)


Replication_Kind_Scene_Ready :: u8(23)


Replication_Kind_Finished_Replicating :: u8(24)
Replication_Kind_Model_Pivot :: u8(25)
Replication_Kind_Group_Ownership :: u8(26)
Replication_Kind_World_Gravity :: u8(27)
Replication_Kind_Deformable :: u8(28)
Replication_Kind_Script_Source :: u8(29)
Replication_Kind_Metadata :: u8(30)
Replication_Kind_Join_Batch :: u8(31)

Replication_Deformable_Cloth :: u8(0)
Replication_Deformable_SoftBody :: u8(1)
Replication_Deformable_Max_Vertices :: u32(8192)

replication_string_compare :: proc(a, b: string) -> int {
	if a < b {return -1}
	if a > b {return 1}
	return 0
}

replication_u64_compare :: proc(a, b: u64) -> int {
	if a < b {return -1}
	if a > b {return 1}
	return 0
}


replication_voxel_key_compare :: proc(a, b: Terrain_Voxel_Key) -> int {
	if a.y != b.y {return a.y < b.y ? -1 : 1}
	if a.z != b.z {return a.z < b.z ? -1 : 1}
	if a.x != b.x {return a.x < b.x ? -1 : 1}
	return 0
}


replication_cell_entry_compare :: proc(a, b: Terrain_Cell_Entry) -> int {
	if a.y != b.y {return a.y < b.y ? -1 : 1}
	if a.z != b.z {return a.z < b.z ? -1 : 1}
	if a.x != b.x {return a.x < b.x ? -1 : 1}
	return 0
}


replication_schema_hash :: proc(service: ^ReplicatorService) -> u64 {
	FNV_OFFSET: u64 = 14695981039346656037
	FNV_PRIME: u64 = 1099511628211
	hash: u64 = FNV_OFFSET
	if service == nil ||
	   service.data_model == nil ||
	   service.data_model.registry == nil ||
	   service.data_model.registry.classes == nil {return hash}
	registry := service.data_model.registry.classes


	class_digests: [dynamic]u64
	defer delete(class_digests)
	for descriptor in registry.classes {
		if descriptor == nil || descriptor.info == nil {continue}
		if replication_builtin_class(descriptor.info.name) {continue}
		properties := classes.Class_Property_List(
			registry,
			descriptor.info.name,
			include_imported = false,
		)


		filtered: [dynamic]string
		defer delete(filtered)
		for property in properties {
			switch property {
			case "Parent",
			     "Name",
			     "ReplicationMode",
			     "ReplicationGroup",
			     "AbsolutePosition",
			     "AbsoluteSize",
			     "TextBounds",
			     "SelectedText",
			     "LineCount",
			     "AbsoluteCellCount",
			     "AbsoluteCellSize",
			     "AbsoluteContentSize",
			     "PositionCallback",
			     "ClassName",
			     "NetworkId",
			     "UniqueId",
			     "Capabilities",
			     "IsInSandbox":
				continue
			}
			append(&filtered, property)
		}
		delete(properties)
		if len(filtered) == 0 {continue}


		sort.quick_sort_proc(filtered[:], replication_string_compare)
		digest: u64 = FNV_OFFSET
		for byte in transmute([]u8)descriptor.info.name {
			digest = (digest ~ u64(byte)) * FNV_PRIME
		}
		digest = (digest ~ 0xFF) * FNV_PRIME
		for property in filtered {
			for byte in transmute([]u8)property {digest = (digest ~ u64(byte)) * FNV_PRIME}

			digest = (digest ~ u64(len(property))) * FNV_PRIME
		}
		append(&class_digests, digest)
	}
	sort.quick_sort_proc(class_digests[:], replication_u64_compare)
	for digest in class_digests {hash = (hash ~ digest) * FNV_PRIME}
	return hash
}

Replication_Handshake_Timeout: f32 = 10
Replication_Time_Sync_Interval: f32 = 1


replication_tokens_equal :: proc(a: string, b: string) -> bool {
	if len(a) != len(b) {return false}
	difference: u8
	for index in 0 ..< len(a) {
		difference |= u8(a[index]) ~ u8(b[index])
	}
	return difference == 0
}


replication_make_nonce :: proc(service: ^ReplicatorService) -> u32 {
	value := transmute(u32)service.clock * 2654435761
	value ~= service.next_user_id * 40503
	value ~= service.tick * 2246822519
	return value | 1
}

replication_send_hello :: proc(service: ^ReplicatorService) {
	if service.mode != .Client || service.remote == nil {return}
	bytes: [dynamic]u8
	defer delete(bytes)
	replication_put_u32(&bytes, Replication_Protocol_Version)
	replication_put_u32(&bytes, service.client_capabilities)


	replication_put_u64(&bytes, replication_schema_hash(service))
	replication_put_string(&bytes, service.join_token)
	replication_put_string(&bytes, service.username)
	_ = replication_send(service, service.remote, 1, bytes[:], true)
}

replication_send_welcome :: proc(
	service: ^ReplicatorService,
	peer: ^Replication_Transport_Peer,
	status: u8,
	user_id: u32,
	name: string,
	capabilities: u32,
	nonce: u32,
	schema_hash: u64,
) {
	bytes: [dynamic]u8
	defer delete(bytes)
	append(&bytes, status)
	replication_put_u32(&bytes, Replication_Protocol_Version)
	replication_put_u32(&bytes, capabilities)


	replication_put_u64(&bytes, schema_hash)
	replication_put_u32(&bytes, user_id)
	replication_put_string(&bytes, name)
	replication_put_u32(&bytes, nonce)
	if status == Replication_Handshake_Ok &&
	   (capabilities & Replication_Capability_Snapshot_Clock) != 0 {
		replication_put_f32(&bytes, service.snapshot_rate)
	} else {
		replication_put_u32(&bytes, u32(service.snapshot_rate))
	}
	_ = replication_send(service, peer, 3, bytes[:], true)
}

replication_peer_of :: proc(
	service: ^ReplicatorService,
	peer: ^Replication_Transport_Peer,
) -> ^Replication_Peer {
	if service == nil || peer == nil {return nil}
	for &connection in service.peers {
		if connection.peer == peer {return &connection}
	}
	return nil
}

replication_receive_hello :: proc(
	service: ^ReplicatorService,
	L: ^vm.State,
	peer: ^Replication_Transport_Peer,
	reader: ^Replication_Reader,
) {
	if service.mode != .Server {reader.valid = false; return}
	version := replication_read_u32(reader)
	capabilities := replication_read_u32(reader)
	schema_hash := replication_read_u64(reader)
	token := replication_read_string(reader)
	if !reader.valid || len(token) > 256 {reader.valid = false; return}


	username := ""
	if reader.offset < len(reader.data) {
		username = replication_read_string(reader)
		if !reader.valid || len(username) > 32 {reader.valid = false; return}
	}
	connection: ^Replication_Peer
	for &candidate in service.peers {if candidate.peer == peer {connection = &candidate; break}}
	if connection == nil {reader.valid = false; return}
	if connection.handshake_complete {


		replication_send_welcome(
			service,
			peer,
			Replication_Handshake_Already_Complete,
			0,
			"",
			service.server_capabilities,
			0,
			0,
		)
		return
	}
	if version != Replication_Protocol_Version {
		service.version_mismatches += 1
		service.handshake_rejections += 1
		fmt.eprintf(
			"[Replication] refused a client speaking protocol %d (this server speaks %d)\n",
			version,
			Replication_Protocol_Version,
		)
		replication_send_welcome(
			service,
			peer,
			Replication_Handshake_Version_Mismatch,
			0,
			"",
			service.server_capabilities,
			0,
			0,
		)
		transport_peer_disconnect_now(peer)
		return
	}


	local_schema := replication_schema_hash(service)
	if schema_hash != local_schema {
		service.schema_mismatches += 1
		service.handshake_rejections += 1
		fmt.eprintf(
			"[Replication] refused a client whose replicated class surface differs (client %016x, server %016x)\n",
			schema_hash,
			local_schema,
		)
		replication_send_welcome(
			service,
			peer,
			Replication_Handshake_Schema_Mismatch,
			0,
			"",
			service.server_capabilities,
			0,
			local_schema,
		)
		transport_peer_disconnect_now(peer)
		return
	}


	if len(service.join_token) > 0 && !replication_tokens_equal(token, service.join_token) {
		service.auth_failures += 1
		service.handshake_rejections += 1
		fmt.eprintln("[Replication] refused a client with an invalid join token")
		replication_send_welcome(
			service,
			peer,
			Replication_Handshake_Auth_Rejected,
			0,
			"",
			service.server_capabilities,
			0,
			0,
		)
		transport_peer_disconnect_now(peer)
		return
	}

	id := service.next_user_id
	service.next_user_id += 1
	name := username
	if name == "" {
		name = fmt.tprintf("Player%d", id)
	}
	players := cast(^Players)DataModel_Get_Service(service.data_model, "Players")
	player := Players_Add(players, L, id, name)
	character_service := cast(^CharacterService)Ensure_Service(
		service.data_model.registry,
		"CharacterService",
	)
	if character_service != nil && player != nil {CharacterService_Load(character_service, player)}
	connection.player = player
	connection.client_capabilities = capabilities
	welcome_capabilities := service.server_capabilities
	if (capabilities & Replication_Capability_Snapshot_Clock) == 0 {
		welcome_capabilities &= ~Replication_Capability_Snapshot_Clock
	}
	connection.snapshot_clock_rate = f32(u32(service.snapshot_rate))
	if (welcome_capabilities & Replication_Capability_Snapshot_Clock) != 0 {
		connection.snapshot_clock_rate = REPLICATION_SNAPSHOT_CLOCK_RATE
	}
	connection.handshake_complete = true
	connection.server_nonce = replication_make_nonce(service)
	replication_send_welcome(
		service,
		peer,
		Replication_Handshake_Ok,
		id,
		name,
		welcome_capabilities,
		connection.server_nonce,
		local_schema,
	)
	service.connected = true
	fmt.printf("Network server accepted %s (user %d)\n", name, id)


	replication_send_asset_table(service, connection)
	replication_send_terrain(service, connection)
}

replication_receive_welcome :: proc(
	service: ^ReplicatorService,
	L: ^vm.State,
	peer: ^Replication_Transport_Peer,
	reader: ^Replication_Reader,
) {
	if service.mode != .Client || peer != service.remote {return}
	if reader.offset >= len(reader.data) {reader.valid = false; return}
	status := reader.data[reader.offset]
	reader.offset += 1
	server_version := replication_read_u32(reader)
	capabilities := replication_read_u32(reader)
	server_schema := replication_read_u64(reader)
	user_id := replication_read_u32(reader)
	name := replication_read_string(reader)
	nonce := replication_read_u32(reader)
	snapshot_rate_bits := replication_read_u32(reader)
	if !reader.valid {return}
	service.server_capabilities = capabilities
	if status != Replication_Handshake_Ok {
		service.handshake_status = status
		service.handshake_rejections += 1
		switch status {
		case Replication_Handshake_Version_Mismatch:
			fmt.eprintf(
				"[Replication] server speaks protocol %d but this client speaks %d\n",
				server_version,
				Replication_Protocol_Version,
			)
		case Replication_Handshake_Auth_Rejected:
			fmt.eprintln("[Replication] the server rejected this client's join token")
		case Replication_Handshake_Schema_Mismatch:
			service.schema_mismatches += 1
			fmt.eprintf(
				"[Replication] this client replicates a different class surface than the server (client %016x, server %016x)\n",
				replication_schema_hash(service),
				server_schema,
			)
		case:
			fmt.eprintf("[Replication] the server refused the connection (status %d)\n", status)
		}
		return
	}
	if server_version != Replication_Protocol_Version {
		service.version_mismatches += 1
		service.handshake_status = Replication_Handshake_Version_Mismatch
		fmt.eprintf(
			"[Replication] server speaks protocol %d but this client speaks %d\n",
			server_version,
			Replication_Protocol_Version,
		)
		return
	}


	local_schema := replication_schema_hash(service)
	if server_schema != local_schema {
		service.schema_mismatches += 1
		service.handshake_status = Replication_Handshake_Schema_Mismatch
		fmt.eprintf(
			"[Replication] server replicates a different class surface than this client (client %016x, server %016x)\n",
			local_schema,
			server_schema,
		)
		return
	}
	if user_id == 0 ||
	   len(name) == 0 ||
	   len(name) > 64 {service.handshake_status = Replication_Handshake_Malformed; return}
	service.server_nonce = nonce
	service.handshake_status = Replication_Handshake_Ok
	service.handshake_complete = true
	service.connected = true


	snapshot_rate := f32(snapshot_rate_bits)
	fixed_clock :=
		(capabilities & service.client_capabilities & Replication_Capability_Snapshot_Clock) != 0
	if fixed_clock {
		snapshot_rate = transmute(f32)snapshot_rate_bits
	}
	if snapshot_rate >= 1 && snapshot_rate <= 120 {service.snapshot_rate = snapshot_rate}
	service.snapshot_clock_rate =
		REPLICATION_SNAPSHOT_CLOCK_RATE if fixed_clock else service.snapshot_rate
	players := cast(^Players)DataModel_Get_Service(service.data_model, "Players")
	if players != nil &&
	   players.local_player == nil {players.local_player = Players_Add(players, L, user_id, name)}
	fmt.printf("Network client connected as %s (user %d)\n", name, user_id)
}

replication_send_time_sync :: proc(service: ^ReplicatorService) {
	if service.mode != .Client || service.remote == nil || !service.handshake_complete {return}
	service.time_sync_sequence += 1
	bytes: [dynamic]u8
	defer delete(bytes)
	replication_put_u32(&bytes, u32(service.clock * 1000))
	replication_put_u32(&bytes, service.time_sync_sequence)


	replication_put_u32(&bytes, service.server_nonce)
	_ = replication_send(service, service.remote, 19, bytes[:], false)
}

replication_receive_time_sync :: proc(
	service: ^ReplicatorService,
	peer: ^Replication_Transport_Peer,
	reader: ^Replication_Reader,
) {
	if service.mode != .Server {reader.valid = false; return}
	client_ms := replication_read_u32(reader)
	sequence := replication_read_u32(reader)
	nonce := replication_read_u32(reader)
	if !reader.valid {return}
	connection := replication_peer_of(service, peer)
	if connection == nil || !connection.handshake_complete {return}
	if nonce != connection.server_nonce {


		return
	}
	bytes: [dynamic]u8
	defer delete(bytes)
	replication_put_u32(&bytes, client_ms)
	replication_put_u32(&bytes, u32(service.clock * 1000))
	replication_put_u32(&bytes, sequence)
	replication_put_u32(&bytes, connection.server_nonce)
	if (connection.client_capabilities &
		   service.server_capabilities &
		   Replication_Capability_Snapshot_Clock) !=
	   0 {
		replication_put_f32(&bytes, service.snapshot_rate)
	}
	_ = replication_send(service, peer, 20, bytes[:], false)
}

replication_receive_time_sync_reply :: proc(
	service: ^ReplicatorService,
	peer: ^Replication_Transport_Peer,
	reader: ^Replication_Reader,
) {
	if service.mode != .Client || peer != service.remote {return}
	client_ms := replication_read_u32(reader)
	server_ms := replication_read_u32(reader)
	sequence := replication_read_u32(reader)
	nonce := replication_read_u32(reader)
	rate := service.snapshot_rate
	if (service.server_capabilities &
			   service.client_capabilities &
			   Replication_Capability_Snapshot_Clock) !=
		   0 &&
	   reader.offset < len(reader.data) {
		rate = replication_read_f32(reader)
	}
	if !reader.valid {return}
	if sequence == 0 || service.server_nonce != nonce {return}
	now_ms := u32(service.clock * 1000)


	elapsed: u32 = 0
	if now_ms > client_ms {elapsed = now_ms - client_ms}
	if elapsed > 2000 {return}
	if rate >= 1 && rate <= 120 {service.snapshot_rate = rate}
	local_midpoint := f64(client_ms) + f64(elapsed) / 2
	offset := (f64(server_ms) - local_midpoint) / 1000
	if !service.time_offset_measured {


		service.time_offset = f32(offset)
		service.time_offset_measured = true
		return
	}


	service.time_offset = service.time_offset + f32((offset - f64(service.time_offset)) * 0.25)
}

replication_start :: proc(
	service: ^ReplicatorService,
	address: string,
	port: u16,
	mode: Replication_Mode,
	username: string = "",
) -> bool {
	replication_stop(service)
	if mode == .Client && (address == "" || address == "0.0.0.0") {
		fmt.eprintln(
			"Network client needs a reachable server address; use 127.0.0.1 for a server on this computer",
		)
		return false
	}
	if !transport_init() {
		fmt.eprintln("Could not initialize ENet")
		return false
	}
	service.transport_initialized = true
	if mode == .Server {
		service.host = transport_host_create_server(address, port, 32, 2)
	} else {
		service.host = transport_host_create_client()
		if service.host != nil {
			service.remote = transport_host_connect(service.host, address, port, 2)
		}
	}
	if service.host == nil || (mode == .Client && service.remote == nil) {
		if service.host == nil {
			fmt.eprintf(
				"Could not create the %s network host\n",
				mode == .Server ? "server" : "client",
			)
		} else {
			fmt.eprintf("Could not begin the connection to %s:%d\n", address, port)
		}
		replication_stop(service)
		return false
	}
	service.mode = mode
	if service.data_model != nil &&
	   service.data_model.registry != nil &&
	   service.data_model.registry.vm_state != nil &&
	   service.data_model.registry.vm_state.L != nil {
		vm.AddGlobal_Boolean(service.data_model.registry.vm_state, "IsServer", mode == .Server)
		vm.AddGlobal_Boolean(service.data_model.registry.vm_state, "IsClient", mode == .Client)
	}
	return true
}


replication_budgeted :: proc(service: ^ReplicatorService, kind: u8) -> bool {
	if service == nil || service.mode != .Server {return false}


	return(
		kind != 1 &&
		kind != 2 &&
		kind != 3 &&
		kind != 7 &&
		kind != 8 &&
		kind != 10 &&
		kind != 20 &&
		kind != Replication_Kind_Asset &&
		kind != Replication_Kind_Terrain &&
		kind != Replication_Kind_Model_Pivot &&
		kind != Replication_Kind_Group_Ownership &&
		kind != Replication_Kind_World_Gravity &&
		kind != Replication_Kind_Scene_Ready \
	)
}

REPLICATION_DEFAULT_JOIN_BUDGET :: 192 * 1024

replication_initial_snapshot_pending :: proc(connection: ^Replication_Peer) -> bool {
	return(
		(connection.client_capabilities & Replication_Capability_Finished_Replicating) != 0 &&
		!connection.finished_replicating_sent \
	)
}

replication_peer_bandwidth_budget :: proc(
	service: ^ReplicatorService,
	connection: ^Replication_Peer,
) -> u32 {
	// A join is a queued snapshot. Deferring part of it to the next tick is expected.
	if replication_initial_snapshot_pending(connection) {
		if service.bandwidth_budget_configured {return service.base_bandwidth_budget}
		return REPLICATION_DEFAULT_JOIN_BUDGET
	}
	return service.bandwidth_budget
}

replication_send :: proc(
	service: ^ReplicatorService,
	peer: ^Replication_Transport_Peer,
	kind: u8,
	payload: []u8,
	reliable: bool = true,
) -> bool {
	if peer == nil ||
	   service.host == nil ||
	   len(payload) > int(Replication_Max_Frame_Payload) {return false}
	if int(kind) < len(service.diag_kind_counts) {
		service.diag_kind_counts[int(kind)] += 1
		service.diag_kind_bytes[int(kind)] += u64(len(payload))


		if len(payload) > 0 && int(payload[0]) < 16 {
			service.diag_subtype_counts[int(payload[0])][int(kind)] += 1
		}
	}
	connection: ^Replication_Peer
	if service.mode == .Server {
		for &candidate in service.peers {
			if candidate.peer == peer {connection = &candidate; break}
		}
	}
	wire_size := len(payload) + 5
	budgeted := connection != nil && replication_budgeted(service, kind)
	if budgeted &&
	   u64(connection.bytes_this_tick) + u64(wire_size) >
		   u64(replication_peer_bandwidth_budget(service, connection)) {
		service.bandwidth_drops += 1
		if !replication_initial_snapshot_pending(connection) {service.drops_window += 1}
		return false
	}

	if connection != nil {
		batch := &connection.join_batch
		if connection.join_batch_enabled &&
		   reliable &&
		   replication_join_batch_kind(kind) &&
		   wire_size + 4 <= REPLICATION_JOIN_BATCH_MAX {
			if len(batch^) + wire_size + 4 > REPLICATION_JOIN_BATCH_MAX &&
			   !replication_flush_join_batch(service, connection) {return false}
			replication_put_u32(batch, u32(wire_size))
			append(batch, 'K', 'R', 'P', u8(Replication_Protocol_Version), kind)
			append(batch, ..payload)
			if budgeted {connection.bytes_this_tick += u32(wire_size)}
			return true
		}
		if !replication_flush_join_batch(service, connection) {return false}
	}

	bytes := make([dynamic]u8, 0, wire_size)
	defer delete(bytes)
	append(&bytes, 'K', 'R', 'P', u8(Replication_Protocol_Version), kind)
	append(&bytes, ..payload)
	channel :=
		reliable ? Replication_Transport_Channel_Reliable : Replication_Transport_Channel_Unreliable
	if !transport_peer_send(peer, channel, bytes[:], reliable) {return false}
	service.packets_sent += 1
	service.bytes_sent += u64(len(bytes))
	if budgeted {connection.bytes_this_tick += u32(wire_size)}
	return true
}

replication_send_gravity_updates :: proc(service: ^ReplicatorService) {
	physics := cast(^Physics)DataModel_Get_Service(service.data_model, "Physics")
	if physics == nil || !physics_finite_f32(physics.gravity) {return}

	payload: [dynamic]u8
	defer delete(payload)
	for &peer in service.peers {
		if !peer.handshake_complete ||
		   (peer.client_capabilities & Replication_Capability_World_Gravity) == 0 ||
		   (peer.gravity_sent && peer.last_gravity == physics.gravity) {continue}
		if len(payload) == 0 {replication_put_f32(&payload, physics.gravity)}
		if replication_send(service, peer.peer, Replication_Kind_World_Gravity, payload[:]) {
			peer.gravity_sent = true
			peer.last_gravity = physics.gravity
		}
	}
}

replication_send_owned_correction :: proc(
	service: ^ReplicatorService,
	connection: ^Replication_Peer,
	id: u32,
	frame: datatypes.CFrame,
) {
	payload: [dynamic]u8
	defer delete(payload)
	replication_put_u32(&payload, id)
	if (connection.client_capabilities & Replication_Capability_Owned_Correction) != 0 {
		replication_put_cframe(&payload, frame)
	}
	_ = replication_send(service, connection.peer, Replication_Kind_Owned_Correction, payload[:])
}

replication_apply_property :: proc "c" (L: ^vm.State) -> i32 {
	context = tracy.DefaultContext()
	name := vm.ArgString(L, int(vm.UpvalueIndex(1)))
	vm.SetField(L, -2, name)
	return 0
}


replication_send_asset_entry :: proc(
	service: ^ReplicatorService,
	peer: ^Replication_Transport_Peer,
	entry: ^assetstore.Asset,
) -> bool {


	entry_overhead :=
		1 + 4 + int(Replication_Asset_Max_Id_Length) + 4 + int(Replication_Asset_Max_Path) + 1 + 4
	body := int(Replication_Max_Frame_Payload) - entry_overhead

	if len(entry.bytes) <= body {
		payload: [dynamic]u8
		encode_asset_entry(&payload, entry.id, entry.path, entry.kind, entry.bytes)
		sent_ok := replication_send(service, peer, Replication_Kind_Asset, payload[:], true)


		delete(payload)
		return sent_ok
	}

	header: [dynamic]u8
	encode_asset_begin(&header, entry.id, entry.path, entry.kind, u32(len(entry.bytes)))
	sent_ok := replication_send(service, peer, Replication_Kind_Asset, header[:], true)
	delete(header)
	if !sent_ok {return false}


	chunk_size := min(int(Replication_Asset_Max_Chunk), body - 5)
	if chunk_size <= 0 {return false}

	for start := 0; start < len(entry.bytes); {
		end := min(start + chunk_size, len(entry.bytes))
		frame: [dynamic]u8
		encode_asset_chunk(&frame, u32(start / chunk_size), entry.bytes[start:end])
		sent_ok = replication_send(service, peer, Replication_Kind_Asset, frame[:], true)
		delete(frame)
		if !sent_ok {return false}
		start = end
	}
	return true
}


replication_send_asset_table :: proc(service: ^ReplicatorService, connection: ^Replication_Peer) {
	if (connection.client_capabilities & Replication_Capability_Asset_Transfer) == 0 {return}
	peer := connection.peer
	total := assetstore.Count()

	sent := 0
	for index := 0; index < total; index += 1 {


		entry, ok := assetstore.At(index)
		if !ok || entry == nil {continue}
		if entry.kind == .Path_File &&
		   strings.has_prefix(entry.path, assetstore.PROJECT_ASSET_SCHEME) &&
		   !strings.has_prefix(entry.path, "project://assets/replicated/") {continue}
		if !replication_send_asset_entry(service, peer, entry) {return}
		if entry.kind == .Mesh {connection.mesh_assets[strings.clone(entry.id)] = true}
		sent += 1
	}


	footer: [dynamic]u8
	append(&footer, Replication_Asset_Subtype_End)
	replication_put_u32(&footer, u32(sent))
	replication_send(service, peer, Replication_Kind_Asset, footer[:], true)
	delete(footer)

	service.assets_sent += u64(sent)
	fmt.printf("Sent %d embedded assets to a client\n", sent)
}


replication_send_operation_mesh :: proc(
	service: ^ReplicatorService,
	connection: ^Replication_Peer,
	object: ^classes.Object,
) -> bool {
	if !classes.Is_A_Class(object, &classes.PartOperation_Class) ||
	   (connection.client_capabilities & Replication_Capability_Asset_Transfer) == 0 {
		return true
	}
	uri := classes.MeshPart_Source_Path(cast(^classes.MeshPart)object)
	id, embedded := assetstore.Parse_Uri(uri)
	if !embedded || connection.mesh_assets[id] {return true}
	entry, found := assetstore.Find(id)
	if !found || !replication_send_asset_entry(service, connection.peer, entry) {return false}
	connection.mesh_assets[strings.clone(id)] = true
	service.assets_sent += 1
	return true
}

replication_send_terrain :: proc(service: ^ReplicatorService, connection: ^Replication_Peer) {
	client_capabilities := connection.client_capabilities
	if (client_capabilities & Replication_Capability_Terrain) == 0 {return}

	terrain_object := DataModel_Get_Service(service.data_model, "Terrain")
	if terrain_object == nil {return}
	terrain := cast(^Terrain)terrain_object
	if terrain == nil {return}

	header: [dynamic]u8
	encode_terrain_header(&header, terrain)
	sent_ok := replication_send(
		service,
		connection.peer,
		Replication_Kind_Terrain,
		header[:],
		true,
	)
	delete(header)
	if !sent_ok {return}


	terrain.dirty_tracking = true


	cells: [dynamic]Terrain_Cell_Record
	entries := Terrain_Collect_Cells(terrain)
	defer delete(entries)
	sort.quick_sort_proc(entries[:], replication_cell_entry_compare)
	reserve := min(len(entries), int(Replication_Terrain_Max_Cells))
	cells = make([dynamic]Terrain_Cell_Record, 0, reserve)

	batches := 0
	sent_cells := 0
	for entry in entries {
		append(
			&cells,
			Terrain_Cell_Record {
				x = i32(entry.x),
				y = i32(entry.y),
				z = i32(entry.z),
				occupancy = entry.cell.occupancy,
				water = entry.cell.water,
				material = entry.cell.material,
			},
		)
		if len(cells) < int(Replication_Terrain_Max_Cells) {continue}

		payload: [dynamic]u8
		encode_terrain_batch(&payload, cells[:])
		batch_cells := len(cells)
		ok := replication_send(
			service,
			connection.peer,
			Replication_Kind_Terrain,
			payload[:],
			true,
		)
		delete(payload)
		clear(&cells)
		if !ok {
			delete(cells)
			return
		}
		batches += 1
		sent_cells += batch_cells
	}

	if len(cells) > 0 {
		payload: [dynamic]u8
		encode_terrain_batch(&payload, cells[:])
		batch_cells := len(cells)
		ok := replication_send(
			service,
			connection.peer,
			Replication_Kind_Terrain,
			payload[:],
			true,
		)
		delete(payload)
		if !ok {
			delete(cells)
			return
		}
		batches += 1
		sent_cells += batch_cells
	}

	footer: [dynamic]u8
	append(&footer, Replication_Terrain_Subtype_End)
	replication_put_u32(&footer, u32(batches))
	replication_put_u32(&footer, u32(sent_cells))
	footer_ok := replication_send(
		service,
		connection.peer,
		Replication_Kind_Terrain,
		footer[:],
		true,
	)
	delete(footer)

	delete(cells)
	if !footer_ok {return}


	connection.terrain_initial_sent = true
	connection.terrain_cursor = terrain.change_serial
	connection.terrain_epoch = terrain.dirty_epoch
	fmt.printf("Sent %d terrain cells in %d batches to a client\n", sent_cells, batches)
}


replication_receive_deformable :: proc(
	service: ^ReplicatorService,
	peer: ^Replication_Transport_Peer,
	reader: ^Replication_Reader,
) {
	if service.mode != .Client || peer != service.remote {return}
	id := replication_read_u32(reader)
	kind := replication_read_u8(reader)
	if !reader.valid || id == 0 {reader.valid = false; return}
	entity := replication_entity_by_id(service, id)
	if entity == nil || entity.object == nil || entity.object.destroyed {return}
	object := entity.object
	switch kind {
	case Replication_Deformable_Cloth:
		if !classes.Is_A(object, "Cloth") {reader.valid = false; return}
		cloth := cast(^classes.Cloth)object
		for &particle in cloth.particles {
			particle.position.x = replication_read_f32(reader)
			particle.position.y = replication_read_f32(reader)
			particle.position.z = replication_read_f32(reader)
			particle.velocity = {}
		}
		if !reader.valid {return}
		cloth.force = {}
		cloth.width = cloth.size.X
		if workspace := DataModel_Get_Service(service.data_model, "Workspace"); workspace != nil {
			_, pin_count := classes.Cloth_Anchors(cloth, workspace)
			if pin_count == 2 {
				cloth.width = classes.Cloth_Width(
					cloth,
					cloth.particles[classes.CLOTH_SEGMENTS].position - cloth.particles[0].position,
				)
			}
		}
		cloth.pose_source = .Replication
		cloth.initialized = true
		cloth.revision += 1
	case Replication_Deformable_SoftBody:
		if !classes.Is_A(object, "SoftBody") {reader.valid = false; return}
		body := cast(^classes.SoftBody)object
		frame := replication_read_cframe(reader)
		count := replication_read_u32(reader)
		if !reader.valid ||
		   count > Replication_Deformable_Max_Vertices {reader.valid = false; return}
		if int(count) > len(body.positions) {reader.valid = false; return}
		for index in 0 ..< int(count) {
			body.positions[index].x = replication_read_f32(reader)
			body.positions[index].y = replication_read_f32(reader)
			body.positions[index].z = replication_read_f32(reader)
		}
		if !reader.valid {return}
		body.cframe = frame
		body.simulation_cframe = frame
		body.pose_dirty = false
		body.revision += 1
	case:
		reader.valid = false
	}
}

replication_receive_terrain :: proc(
	service: ^ReplicatorService,
	peer: ^Replication_Transport_Peer,
	reader: ^Replication_Reader,
) {
	if service.mode != .Client || peer != service.remote {return}
	if reader.offset >= len(reader.data) {reader.valid = false; return}
	subtype := reader.data[reader.offset]
	reader.offset += 1

	terrain_object := DataModel_Get_Service(service.data_model, "Terrain")
	if terrain_object == nil {reader.valid = false; return}
	terrain := cast(^Terrain)terrain_object
	if terrain == nil {reader.valid = false; return}

	if subtype == Replication_Terrain_Subtype_Header {
		voxel_size, iso_level, draw_version, declared, ok := decode_terrain_header(reader)
		if !ok {return}


		delete(service.terrain_pending)
		service.terrain_pending = make(map[Terrain_Voxel_Key]Terrain_Cell_Record)
		service.terrain_pending_voxel_size = voxel_size
		service.terrain_pending_iso_level = iso_level
		service.terrain_receiving = true
		service.terrain_batches_received = 0
		service.terrain_cells_received = 0
		service.terrain_header_seen = true
		service.terrain_cells_declared = declared
		service.terrain_draw_version = draw_version
		return
	}

	if subtype == Replication_Terrain_Subtype_End {
		batches := replication_read_u32(reader)
		cells := replication_read_u32(reader)
		if !reader.valid {return}
		if !service.terrain_receiving ||
		   u32(service.terrain_batches_received) != batches ||
		   u32(service.terrain_cells_received) != cells ||
		   cells != service.terrain_cells_declared ||
		   len(service.terrain_pending) != int(cells) {
			fmt.eprintf(
				"[Replication] terrain transfer is incomplete: server closed after %d batches / %d cells, received %d / %d\n",
				batches,
				cells,
				service.terrain_batches_received,
				service.terrain_cells_received,
			)
			service.terrain_rejections += 1
			return
		}
		if terrain.voxel_size != service.terrain_pending_voxel_size ||
		   terrain.iso_level != service.terrain_pending_iso_level {
			terrain_clear(terrain, terrain.renderer)
			terrain.voxel_size = service.terrain_pending_voxel_size
			terrain.iso_level = service.terrain_pending_iso_level
		} else {
			old := Terrain_Collect_Cells(terrain)
			for entry in old {
				if _, exists :=
					   service.terrain_pending[Terrain_Voxel_Key{entry.x, entry.y, entry.z}];
				   !exists {
					terrain_set_cell(terrain, entry.x, entry.y, entry.z, 0, 0, .Air)
				}
			}
			delete(old)
		}
		for key, cell in service.terrain_pending {
			previous, exists := Terrain_Get_Cell(terrain, key.x, key.y, key.z)
			if exists &&
			   previous.material == cell.material &&
			   abs(previous.occupancy - cell.occupancy) < 0.00002 &&
			   abs(previous.water - cell.water) < 0.00002 {continue}
			terrain_set_cell(
				terrain,
				key.x,
				key.y,
				key.z,
				cell.occupancy,
				cell.water,
				cell.material,
			)
		}
		delete(service.terrain_pending)
		service.terrain_pending = nil
		service.terrain_receiving = false
		service.terrain_table_complete = true
		fmt.printf("Received %d terrain cells from the server\n", cells)
		return
	}

	if subtype != Replication_Terrain_Subtype_Batch {reader.valid = false; return}
	if !service.terrain_header_seen {reader.valid = false; return}

	cells, ok := decode_terrain_batch(reader)


	defer delete(cells)
	if !ok {
		service.terrain_rejections += 1
		return
	}

	for cell in cells {
		if service.terrain_receiving {
			service.terrain_pending[Terrain_Voxel_Key{int(cell.x), int(cell.y), int(cell.z)}] =
				cell
			continue
		}
		terrain_set_cell(
			terrain,
			int(cell.x),
			int(cell.y),
			int(cell.z),
			cell.occupancy,
			cell.water,
			cell.material,
		)
	}

	service.terrain_batches_received += 1
	service.terrain_cells_received += len(cells)
}


replication_trim_terrain_history :: proc(service: ^ReplicatorService) {
	terrain := cast(^Terrain)DataModel_Get_Service(service.data_model, "Terrain")
	if terrain == nil {return}
	cursor := terrain.change_serial
	for peer in service.peers {
		if !peer.handshake_complete ||
		   !peer.terrain_initial_sent ||
		   peer.terrain_epoch != terrain.dirty_epoch ||
		   (peer.client_capabilities & Replication_Capability_Terrain) == 0 {continue}
		cursor = min(cursor, peer.terrain_cursor)
	}


	for key, dirty in terrain.replication_dirty {
		if dirty.serial <= cursor {delete_key(&terrain.replication_dirty, key)}
	}
}


replication_send_terrain_delta :: proc(
	service: ^ReplicatorService,
	connection: ^Replication_Peer,
) {
	if (connection.client_capabilities & Replication_Capability_Terrain) == 0 {return}

	terrain_object := DataModel_Get_Service(service.data_model, "Terrain")
	if terrain_object == nil {return}
	terrain := cast(^Terrain)terrain_object
	if terrain == nil {return}

	if !connection.terrain_initial_sent {
		replication_send_terrain(service, connection)
		return
	}


	if connection.terrain_epoch != terrain.dirty_epoch {
		replication_send_terrain(service, connection)
		return
	}

	if terrain.change_serial <= connection.terrain_cursor {return}

	cells: [dynamic]Terrain_Cell_Record
	defer delete(cells)
	for key, dirty in terrain.replication_dirty {
		if dirty.serial <= connection.terrain_cursor {continue}
		append(&cells, dirty.record)
	}
	if len(cells) == 0 {


		connection.terrain_cursor = terrain.change_serial
		return
	}


	sort.quick_sort_proc(cells[:], replication_terrain_record_compare)

	sent := 0
	for start := 0; start < len(cells); {
		end := min(start + int(Replication_Terrain_Max_Cells), len(cells))
		payload: [dynamic]u8
		encode_terrain_batch(&payload, cells[start:end])
		ok := replication_send(
			service,
			connection.peer,
			Replication_Kind_Terrain,
			payload[:],
			true,
		)
		delete(payload)
		if !ok {return}
		sent += end - start
		start = end
	}

	connection.terrain_cursor = terrain.change_serial
	connection.terrain_deltas_sent += u64(sent)
}

replication_terrain_record_compare :: proc(a, b: Terrain_Cell_Record) -> int {
	if a.y != b.y {return a.y < b.y ? -1 : 1}
	if a.z != b.z {return a.z < b.z ? -1 : 1}
	if a.x != b.x {return a.x < b.x ? -1 : 1}
	return 0
}


replication_asset_pending_reset :: proc(service: ^ReplicatorService) {
	delete(service.asset_pending_bytes)
	service.asset_pending_bytes = nil


	delete(service.asset_pending_id)
	delete(service.asset_pending_path)
	service.asset_pending_id = ""
	service.asset_pending_path = ""
	service.asset_pending_total = 0
	service.asset_pending_next = 0
}


replication_asset_commit :: proc(
	service: ^ReplicatorService,
	id: string,
	path: string,
	kind: assetstore.Asset_Kind,
	data: []u8,
) -> bool {


	if service.assets_received >= u64(assetstore.MAX_ASSET_COUNT) {
		fmt.eprintln("[Replication] refused an asset past the asset count limit")
		service.asset_rejections += 1
		return false
	}
	if service.asset_bytes_received + u64(len(data)) > u64(assetstore.MAX_ASSET_TOTAL_BYTES) {
		fmt.eprintln("[Replication] refused an asset past the total size limit")
		service.asset_rejections += 1
		return false
	}


	owned := slice.clone(data)
	if !assetstore.Register_As(id, owned, path, kind) {
		delete(owned)
		fmt.eprintf("[Replication] refused a malformed asset entry: %s\n", id)
		service.asset_rejections += 1
		return false
	}
	service.assets_received += 1
	service.asset_bytes_received += u64(len(data))
	return true
}

replication_receive_asset :: proc(
	service: ^ReplicatorService,
	peer: ^Replication_Transport_Peer,
	reader: ^Replication_Reader,
) {
	if service.mode != .Client || peer != service.remote {return}
	if reader.offset >= len(reader.data) {reader.valid = false; return}
	subtype := reader.data[reader.offset]
	reader.offset += 1

	if subtype == Replication_Asset_Subtype_End {


		if service.asset_pending_id != "" {
			fmt.eprintf(
				"[Replication] asset table closed with %s still incomplete (%d of %d bytes)\n",
				service.asset_pending_id,
				len(service.asset_pending_bytes),
				service.asset_pending_total,
			)
			service.asset_rejections += 1
			replication_asset_pending_reset(service)
		}
		count := replication_read_u32(reader)
		if !reader.valid {return}


		if u64(count) != service.assets_received {
			fmt.eprintf(
				"[Replication] asset table is incomplete: the server closed it after %d entries but only %d arrived\n",
				count,
				service.assets_received,
			)
			service.asset_rejections += 1
			return
		}
		service.asset_table_complete = true
		fmt.printf("Received %d embedded assets from the server\n", count)
		return
	}

	if subtype == Replication_Asset_Subtype_Begin {
		id, path, kind, total, ok := decode_asset_begin(reader)
		if !ok {return}


		replication_asset_pending_reset(service)


		service.asset_pending_id = strings.clone(id)
		service.asset_pending_path = strings.clone(path)
		service.asset_pending_kind = kind
		service.asset_pending_total = total
		service.asset_pending_next = 0
		service.asset_pending_bytes = make([dynamic]u8, 0, int(total))


		if total == 0 {
			replication_asset_commit(
				service,
				service.asset_pending_id,
				service.asset_pending_path,
				service.asset_pending_kind,
				service.asset_pending_bytes[:],
			)
			replication_asset_pending_reset(service)
		}
		return
	}

	if subtype == Replication_Asset_Subtype_Chunk {
		if service.asset_pending_id == "" {


			fmt.eprintln("[Replication] refused an asset chunk with no transfer open")
			service.asset_rejections += 1
			return
		}
		index, data, ok := decode_asset_chunk(reader)
		if !ok {return}


		if index != service.asset_pending_next {
			fmt.eprintf(
				"[Replication] refused an out of order asset chunk for %s: got %d, wanted %d\n",
				service.asset_pending_id,
				index,
				service.asset_pending_next,
			)
			service.asset_rejections += 1
			replication_asset_pending_reset(service)
			return
		}


		if len(service.asset_pending_bytes) + len(data) > int(service.asset_pending_total) {
			fmt.eprintf(
				"[Replication] refused an oversized asset chunk for %s\n",
				service.asset_pending_id,
			)
			service.asset_rejections += 1
			replication_asset_pending_reset(service)
			return
		}
		append(&service.asset_pending_bytes, ..data)
		service.asset_pending_next += 1
		if len(service.asset_pending_bytes) == int(service.asset_pending_total) {
			replication_asset_commit(
				service,
				service.asset_pending_id,
				service.asset_pending_path,
				service.asset_pending_kind,
				service.asset_pending_bytes[:],
			)
			replication_asset_pending_reset(service)
		}
		return
	}

	if subtype != Replication_Asset_Subtype_Entry {reader.valid = false; return}

	id, path, kind, data, ok := decode_asset_entry_body(reader)
	if !ok {return}


	if service.asset_pending_id != "" {replication_asset_pending_reset(service)}
	replication_asset_commit(service, id, path, kind, data)
}

replication_receive :: proc(
	service: ^ReplicatorService,
	L: ^vm.State,
	peer: ^Replication_Transport_Peer,
	data: []u8,
) {
	if len(data) < 5 ||
	   data[0] != 'K' ||
	   data[1] != 'R' ||
	   data[2] != 'P' ||
	   u32(data[3]) < Replication_Minimum_Framing_Version {
		service.malformed_packets += 1
		return
	}
	reader := Replication_Reader {
		data  = data[5:],
		valid = true,
	}


	rejected := false
	switch data[4] {
	case Replication_Kind_Join_Batch:
		replication_receive_join_batch(service, L, peer, &reader)
	case Replication_Kind_Model_Pivot:
		replication_receive_model_pivot(service, peer, &reader)
	case 1:
		replication_receive_hello(service, L, peer, &reader)
	case 3:
		replication_receive_welcome(service, L, peer, &reader)
	case 19:
		replication_receive_time_sync(service, peer, &reader)
	case 20:
		replication_receive_time_sync_reply(service, peer, &reader)
	case Replication_Kind_Asset:
		replication_receive_asset(service, peer, &reader)
	case Replication_Kind_Terrain:
		replication_receive_terrain(service, peer, &reader)
	case Replication_Kind_Deformable:
		replication_receive_deformable(service, peer, &reader)
	case Replication_Kind_Script_Source:
		replication_receive_script_source(service, L, peer, &reader)
	case Replication_Kind_Metadata:
		replication_receive_metadata(service, L, peer, &reader)
	case Replication_Kind_Scene_Ready:
		if service.mode != .Client || peer != service.remote {return}
		if !service.scene_ready {
			service.scene_ready = true
			CharacterService_Flush_Pending_Binds(service.data_model)
			fmt.println("Network scene ready; client may now build its character")
		}
	case Replication_Kind_World_Gravity:
		if service.mode != .Client ||
		   peer != service.remote ||
		   !service.handshake_complete {return}
		gravity := replication_read_f32(&reader)
		if !reader.valid ||
		   reader.offset != len(reader.data) ||
		   !physics_finite_f32(gravity) ||
		   gravity < 0 {
			reader.valid = false
			break
		}
		Physics_Set_Gravity(
			cast(^Physics)DataModel_Get_Service(service.data_model, "Physics"),
			gravity,
		)
	case Replication_Kind_Finished_Replicating:
		if service.mode != .Client || peer != service.remote {return}
		if service.replication_finished {return}
		service.replication_finished = true
		if players := cast(^Players)DataModel_Get_Service(service.data_model, "Players");
		   players != nil {
			PlayerGui_Prepare(players.local_player, L)
		}
		workspace_object := DataModel_Get_Service(service.data_model, "Workspace")
		workspace := cast(^Workspace)workspace_object
		Workspace_Fire_Finished_Replicating(L, workspace)
	case 2:
		if service.mode != .Client || peer != service.remote {return}
		id := replication_read_u32(&reader)
		name := replication_read_string(&reader)
		if !reader.valid || id == 0 || len(name) > 64 {break}
		players := cast(^Players)DataModel_Get_Service(service.data_model, "Players")
		if players != nil && players.local_player == nil {
			players.local_player = Players_Add(players, L, id, name)
		}
		service.connected = true
		fmt.printf("Network client connected as %s (user %d)\n", name, id)
	case 4:
		if service.mode != .Server {return}
		connection: ^Replication_Peer
		for &candidate in service.peers {if candidate.peer == peer {connection = &candidate; break}}
		if connection == nil {return}
		count := replication_read_u32(&reader)
		if !reader.valid || count > 8192 {reader.valid = false; break}
		for _ in 0 ..< int(count) {
			id := replication_read_u32(&reader)
			state_token := replication_read_u32(&reader)
			property_token := replication_read_u32(&reader)
			extra_token := replication_read_u32(&reader)
			if !reader.valid {break}
			if connection.known[id] == 0 {continue}
			connection.acked_state[id] = state_token
			connection.acked_property[id] = property_token
			connection.acked_extra[id] = extra_token
		}
		if !reader.valid {break}
		service.acks_received += 1
	case 5:
		if service.mode != .Client || peer != service.remote {return}
		if reader.offset >= len(reader.data) {reader.valid = false; break}
		subtype := reader.data[reader.offset]
		reader.offset += 1
		id := replication_read_u32(&reader)
		tick := replication_read_u32(&reader)
		name := replication_read_string(&reader)
		entity := replication_entity_by_id(service, id)
		if entity == nil {return}
		object := entity.object
		if subtype == 2 {
			if entity.last_property_tick != 0 &&
			   transmute(i32)(tick - entity.last_property_tick) < 0 {return}
			schema := replication_schema(service, classes.Get_Class_Name(object))
			if name != "Name" &&
			   (name != "Value" || !classes.Is_A(object, "ValueBase")) &&
			   !replication_builtin_property(object, name) &&
			   !replication_schema_has(schema, name) {reader.valid = false; break}
			top := vm.StackTop(L)
			previous := vm.GetThreadSecurityCapabilities(L)
			vm.SetThreadSecurityCapabilities(L, vm.THREAD_SECURITY_ALL)
			defer vm.SetThreadSecurityCapabilities(L, previous)
			defer vm.SetStackTop(L, top)
			if name == "CFrame" || name == "Position" {
				players := cast(^Players)DataModel_Get_Service(service.data_model, "Players")
				if players != nil &&
				   players.local_player != nil &&
				   entity.owner_id == players.local_player.user_id &&
				   object.parent != nil &&
				   classes.Is_A(object.parent, "CharacterModel") &&
				   (cast(^classes.CharacterModel)object.parent).owner_user_id ==
					   players.local_player.user_id {
					break
				}
			}
			vm.PushString(L, name)
			vm.PushFunction(L, "replication_apply_property", replication_apply_property, 1)
			classes.Push_Object(L, object)
			replication_decode_value(L, &reader, service.signal_registry.datatypes, 0, service)
			if !reader.valid {break}
			if ok, err := vm.ProtectedCall(L, 2, 0); !ok {
				fmt.eprintf(
					"[Replication] failed to apply property %q to %s: %s\n",
					name,
					classes.Get_Class_Name(object),
					err,
				)
				vm.Pop(L)
			}
			entity.last_property_tick = tick


			stream := replication_read_u8(&reader)
			batch_token := replication_read_u32(&reader)
			member_index := replication_read_u8(&reader)
			member_count := replication_read_u8(&reader)
			if stream > replication_property_stream_extra ||
			   member_count == 0 ||
			   member_count > replication_property_batch_limit ||
			   member_index >= member_count {
				reader.valid = false
				break
			}
			channel := int(stream)
			if entity.property_batch_token[channel] != batch_token ||
			   entity.property_batch_size[channel] != member_count {


				entity.property_batch_token[channel] = batch_token
				entity.property_batch_size[channel] = member_count
				entity.property_batch_mask[channel] = 0
			}
			entity.property_batch_mask[channel] |= u64(1) << member_index


			full := (u64(1) << member_count) - 1
			if entity.property_batch_mask[channel] == full {
				if stream == replication_property_stream_extra {
					entity.applied_extra_token = batch_token
				} else {
					entity.applied_property_token = batch_token
				}


				service.ack_elapsed = 1.0
			}
			break
		}
		if entity.last_state_tick != 0 &&
		   transmute(i32)(tick - entity.last_state_tick) < 0 {return}
		if subtype != 1 || !classes.Is_A(object, "Part") {reader.valid = false; break}
		part := cast(^classes.Part)object
		frame := replication_read_cframe(&reader)
		size := datatypes.Vector3 {
			replication_read_f32(&reader),
			replication_read_f32(&reader),
			replication_read_f32(&reader),
		}
		color := datatypes.Color3 {
			R = replication_read_f32(&reader),
			G = replication_read_f32(&reader),
			B = replication_read_f32(&reader),
		}
		transparency := replication_read_f32(&reader)
		if reader.offset + 8 > len(reader.data) {reader.valid = false; break}
		anchored := reader.data[reader.offset] != 0
		can_collide := reader.data[reader.offset + 1] != 0
		material := enums.Material(reader.data[reader.offset + 2])
		shape := enums.PartType(reader.data[reader.offset + 3])
		reader.offset += 4
		if reader.valid {
			players := cast(^Players)DataModel_Get_Service(service.data_model, "Players")
			character := object.parent
			for character != nil && !classes.Is_A(character, "CharacterModel") {
				character = character.parent
			}
			local_character :=
				players != nil &&
				players.local_player != nil &&
				character != nil &&
				(cast(^classes.CharacterModel)character).owner_user_id ==
					players.local_player.user_id
			owned :=
				players != nil &&
				players.local_player != nil &&
				entity.owner_id == players.local_player.user_id
			local_root :=
				local_character && object.parent == character && object.name == "HumanoidRootPart"
			if local_root {


				entity.server_frame = frame
				entity.server_frame_valid = true
			}
			if local_root && owned {
				characters := cast(^CharacterService)Ensure_Service(
					service.data_model.registry,
					"CharacterService",
				)
				if entity.force_correction {
					character_set_root_frame(part, frame)
					entity.force_correction = false
				}
				if characters != nil && !characters.authoritative_received {
					character_translate(
						cast(^classes.CharacterModel)object.parent,
						frame.x - part.cframe.x,
						frame.y - part.cframe.y,
						frame.z - part.cframe.z,
					)
					characters.authoritative_received = true
				}
			} else if local_character && !local_root {


				if entity.last_state_tick == 0 {
					part.cframe = frame
					part.position = datatypes.Vector3{frame.x, frame.y, frame.z}
				}
			} else if entity.force_correction || !owned {
				snap := entity.force_correction || len(entity.samples) == 0
				if len(entity.samples) > 0 {
					last := entity.samples[len(entity.samples) - 1].frame
					dx := frame.x - last.x
					dy := frame.y - last.y
					dz := frame.z - last.z
					if dx * dx + dy * dy + dz * dz >
					   service.teleport_threshold * service.teleport_threshold {
						snap = true
					}
				}
				if snap {


					clear(&entity.samples)
					entity.frame_seeded = false
				}
				if len(entity.samples) > 0 &&
				   entity.samples[len(entity.samples) - 1].tick == tick {
					entity.samples[len(entity.samples) - 1].frame = frame
				} else {
					append(&entity.samples, Replication_Sample{tick = tick, frame = frame})
				}
				if len(entity.samples) > 32 {ordered_remove(&entity.samples, 0)}
				entity.sample_age = 0
				if snap {
					part.cframe = frame
					part.position = datatypes.Vector3{frame.x, frame.y, frame.z}
				}
				entity.force_correction = false
			}
			part.size = size
			part.color = color
			part.transparency = f64(transparency)
			part.anchored = anchored
			part.can_collide = can_collide
			if enums.Material_Is_Valid(int(material)) {
				part.material = material
			}
			if int(shape) >= 0 && int(shape) <= int(enums.PartType.Capsule) {
				part.shape = shape
			}
			classes.Set_Name(object, name)
			entity.last_state_tick = tick


			if !entity.has_transform {


				entity.has_transform = true
				Physics_Request_Sync_For_Data_Model(service.data_model)
			}
			entity.applied_state_token = replication_read_u32(&reader)
			service.states_applied += 1
		}
	case 7:
		if service.mode != .Client || peer != service.remote {return}
		id := replication_read_u32(&reader)
		parent_id := replication_read_u32(&reader)
		class_name := replication_read_string(&reader)
		name := replication_read_string(&reader)
		root_name := replication_read_string(&reader)
		owner_user_id := replication_read_u32(&reader)
		if !reader.valid ||
		   id == 0 ||
		   replication_entity_object(service, id) != nil ||
		   service.data_model == nil {break}
		if !replication_builtin_class(class_name) &&
		   replication_schema(service, class_name) == nil {break}
		parent: ^classes.Object
		if root_name == "PlayerGui" && parent_id == 0 {
			if !replication_uses_server_player_gui(service) {break}
			players := cast(^Players)DataModel_Get_Service(service.data_model, "Players")
			if players == nil ||
			   players.local_player == nil ||
			   owner_user_id != players.local_player.user_id {break}
			parent = PlayerGui_Prepare(players.local_player, L)
		} else if parent_id == 0 && replication_root_allowed(root_name) {
			parent = DataModel_Get_Service(service.data_model, root_name)
		} else if parent_id != 0 && root_name == "" {
			parent = replication_entity_object(service, parent_id)
		}
		if parent == nil || service.data_model.registry == nil {break}


		if classes.Is_A(parent, "StarterPlayer") {
			if existing := classes.Find_First_Child(parent, name); existing != nil {


				existing.network_id = id
				_ = replication_entity_new(service, id, existing)
				return
			}
		}
		if character_subtree_class(class_name) {


			if existing := classes.Find_First_Child_Of_Class(parent, class_name); existing != nil {
				existing.network_id = id
				_ = replication_entity_new(service, id, existing)
				return
			}
		}
		object, ok := classes.Push_New(
			service.data_model.registry.classes,
			service.data_model.registry.vm_state,
			class_name,
			require_creatable = class_name != "PlayerScripts" &&
			class_name != "PlayerGui" &&
			class_name != "StarterCharacterScripts" &&
			class_name != "UnionOperation" &&
			class_name != "NegateOperation" &&
			class_name != "IntersectOperation",
		)
		if !ok || object == nil {break}
		classes.Set_Name(object, name)
		if classes.Is_A(object, "CharacterModel") {
			(cast(^classes.CharacterModel)object).owner_user_id = owner_user_id
		}
		object.network_id = id
		_ = replication_entity_new(service, id, object)
		classes.Set_Parent(object, parent)
		vm.Pop(L)
		if parent != nil &&
		   classes.Is_A(parent, "CharacterModel") &&
		   object.name == "HumanoidRootPart" {
			CharacterService_Bind(service.data_model, cast(^classes.CharacterModel)parent, L)
		}
	case 8:
		if service.mode != .Client || peer != service.remote {return}
		id := replication_read_u32(&reader)
		entity := replication_entity_by_id(service, id)
		if entity != nil {
			object := entity.object
			if object != nil && classes.Is_A(object, "CharacterModel") {
				CharacterService_Unbind(service.data_model, cast(^classes.CharacterModel)object, L)
			}


			_ = replication_entity_remove(service, id)
			if object != nil && !object.destroyed {classes.Destroy_Hierarchy(object)}
		}
	case 9:
		character_receive_input(service, peer, &reader)
	case 10:
		if service.mode != .Client || peer != service.remote {return}
		id := replication_read_u32(&reader)
		owner_id := replication_read_u32(&reader)
		has_extended := reader.offset + 25 == len(reader.data)
		model_flag := false
		linear := datatypes.Vector3{}
		angular := datatypes.Vector3{}
		if has_extended {
			model_flag = replication_read_u8(&reader) != 0
			linear = datatypes.Vector3 {
				replication_read_f32(&reader),
				replication_read_f32(&reader),
				replication_read_f32(&reader),
			}
			angular = datatypes.Vector3 {
				replication_read_f32(&reader),
				replication_read_f32(&reader),
				replication_read_f32(&reader),
			}
		}
		changed := false
		for item in service.entity_list {
			if item.id == id {
				if item.owner_id != owner_id || item.owned_request_pending {
					clear(&item.samples)
					item.sample_age = 0
					item.frame_seeded = false
					item.owned_rest_upload_tick = 0
					item.owned_request_pending = false
					changed = true
				}
				item.owner_id = owner_id
				if has_extended {item.owned_as_model = model_flag}
				if changed {
					item.pending_linear_velocity = linear
					item.pending_angular_velocity = angular
					item.pending_velocity_valid = true
				}
				break
			}
		}


		if changed {Physics_Request_Sync_For_Data_Model(service.data_model)}
		if changed {
			ownership_fire_changed(service, replication_entity_by_id(service, id), owner_id)
		}
	case Replication_Kind_Group_Ownership:
		if service.mode == .Client && peer == service.remote {
			replication_receive_group_ownership(service, &reader)
		}
	case Replication_Kind_Owned_State:
		if service.mode != .Server {return}
		id := replication_read_u32(&reader)
		upload_tick := replication_read_u32(&reader)
		entity := replication_entity_by_id(service, id)
		connection: ^Replication_Peer
		for &candidate in service.peers {if candidate.peer == peer {connection = &candidate; break}}
		if !reader.valid ||
		   entity == nil ||
		   connection == nil ||
		   connection.player == nil ||
		   entity.owner_id != connection.player.user_id ||
		   entity.object == nil ||
		   !classes.Is_A(entity.object, "Part") {
			service.owned_states_rejected += 1
			return
		}
		part := cast(^classes.Part)entity.object
		if entity.pivot_pending ||
		   (entity.pivot_upload_guard &&
				   transmute(i32)(upload_tick - entity.pivot_upload_after) <= 0) {return}
		if entity.last_upload_owner == entity.owner_id &&
		   transmute(i32)(upload_tick - entity.last_upload_tick) <= 0 {return}
		if reader.offset + 72 != len(reader.data) {
			service.owned_states_rejected += 1
			return
		}
		frame := datatypes.CFrame{}
		frame.x = replication_read_f32(&reader)
		frame.y = replication_read_f32(&reader)
		frame.z = replication_read_f32(&reader)
		frame.r00 = replication_read_f32(&reader)
		frame.r01 = replication_read_f32(&reader)
		frame.r02 = replication_read_f32(&reader)
		frame.r10 = replication_read_f32(&reader)
		frame.r11 = replication_read_f32(&reader)
		frame.r12 = replication_read_f32(&reader)
		frame.r20 = replication_read_f32(&reader)
		frame.r21 = replication_read_f32(&reader)
		frame.r22 = replication_read_f32(&reader)
		linear := datatypes.Vector3 {
			replication_read_f32(&reader),
			replication_read_f32(&reader),
			replication_read_f32(&reader),
		}
		angular := datatypes.Vector3 {
			replication_read_f32(&reader),
			replication_read_f32(&reader),
			replication_read_f32(&reader),
		}


		if !reader.valid ||
		   !replication_frame_finite(frame) ||
		   !replication_vector3_finite(linear) ||
		   !replication_vector3_finite(angular) {
			service.owned_states_rejected += 1
			return
		}


		if !replication_frame_rotation_valid(frame) {
			service.owned_states_rejected += 1
			return
		}
		now := service.clock


		if entity.owned_rate_window_time == 0 || now - entity.owned_rate_window_time >= 1 {
			entity.owned_rate_window_time = now
			entity.owned_updates_window = 0
		}
		if entity.owned_updates_window >= service.owned_max_updates_per_second {
			service.owned_states_rejected += 1
			return
		}
		dx := frame.x - part.cframe.x
		dy := frame.y - part.cframe.y
		dz := frame.z - part.cframe.z
		if dx * dx + dy * dy + dz * dz >
		   service.owned_teleport_tolerance * service.owned_teleport_tolerance {
			service.owned_states_rejected += 1
			replication_send_owned_correction(service, connection, id, part.cframe)
			return
		}


		if entity.owned_window_time == 0 || now - entity.owned_window_time >= 1 {
			entity.owned_window_time = now
			entity.owned_window_origin = datatypes.Vector3 {
				part.cframe.x,
				part.cframe.y,
				part.cframe.z,
			}
		} else {
			ox := frame.x - entity.owned_window_origin.x
			oy := frame.y - entity.owned_window_origin.y
			oz := frame.z - entity.owned_window_origin.z
			if ox * ox + oy * oy + oz * oz > service.owned_max_speed * service.owned_max_speed {
				service.owned_states_rejected += 1
				replication_send_owned_correction(service, connection, id, part.cframe)
				return
			}
		}


		if linear.x * linear.x + linear.y * linear.y + linear.z * linear.z >
			   service.owned_max_speed * service.owned_max_speed ||
		   angular.x * angular.x + angular.y * angular.y + angular.z * angular.z >
			   service.owned_max_speed * service.owned_max_speed {
			service.owned_states_rejected += 1
			return
		}
		entity.owned_updates_window += 1
		entity.last_upload_owner = entity.owner_id
		entity.last_upload_tick = upload_tick
		character_set_root_frame(part, frame)
		entity.owned_linear_velocity = linear
		entity.owned_angular_velocity = angular
		service.owned_states_accepted += 1


		Physics_Request_Sync_For_Data_Model(service.data_model)
	case 13:
		replication_receive_ownership_request(service, peer, &reader)
	case 14:
		if service.mode != .Client || peer != service.remote {return}
		id := replication_read_u32(&reader)
		ack := replication_read_u32(&reader)
		if !reader.valid || id == 0 {break}
		entity := replication_entity_by_id(service, id)
		if entity == nil || !entity.server_frame_valid {break}
		character_reconcile(service, entity, entity.server_frame, ack)
		service.char_acks_received += 1
	case Replication_Kind_Owned_Correction:
		if service.mode != .Client || peer != service.remote {return}
		id := replication_read_u32(&reader)
		if !reader.valid {break}
		entity := replication_entity_by_id(service, id)
		if entity == nil ||
		   entity.object == nil ||
		   entity.object.destroyed ||
		   !classes.Is_A_Class(entity.object, &classes.Part_Class) {return}
		if reader.offset == len(reader.data) {
			// Older servers send only a marker and expect a later state packet.
			entity.force_correction = true
			break
		}
		frame := replication_read_cframe(&reader)
		if !reader.valid ||
		   reader.offset != len(reader.data) ||
		   !replication_frame_finite(frame) ||
		   !replication_frame_rotation_valid(frame) {
			reader.valid = false
			break
		}
		if entity.owner_id == 0 || entity.owner_id != ownership_local_user_id(service) {return}
		character_set_root_frame(cast(^classes.Part)entity.object, frame)
		entity.server_frame = frame
		entity.server_frame_valid = true
		entity.force_correction = false
		entity.owned_rest_upload_tick = 0
		clear(&entity.samples)
		entity.frame_seeded = false
		Physics_Request_Sync_For_Data_Model(service.data_model)
	case 12:
		name := replication_read_string(&reader)
		if !reader.valid || len(name) > 256 {break}
		if service.mode == .Server {
			known := false
			for connection in service.peers {if connection.peer == peer {known = true; break}}
			if !known {return}
		} else if peer != service.remote {return}
		top := vm.StackTop(L)
		defer vm.SetStackTop(L, top)
		replication_decode_value(L, &reader, service.signal_registry.datatypes, 0, service)
		if !reader.valid {break}
		payload_ref := vm.RetainValue(L)
		vm.Pop(L)
		if service.event_signal != nil {
			vm.PushString(L, name)
			vm.PushRegistryReference(L, payload_ref)
			signals.Fire(L, service.event_signal, 2)
		}
		for callback in service.event_callbacks {
			if callback.name != name {continue}
			vm.PushRegistryReference(L, callback.reference)
			vm.PushRegistryReference(L, payload_ref)
			ok, err := vm.ProtectedCall(L, 1, 0)
			if !ok && err != "" {delete(err)}
		}
		vm.ReleaseValue(L, payload_ref)
	case 16:
		if service.mode == .Server {
			known := false
			for connection in service.peers {if connection.peer == peer {known = true; break}}
			if !known {return}
		} else if peer != service.remote {return}
		id := replication_read_u32(&reader)
		if !reader.valid || id == 0 {break}
		remote_receive_fire(service, L, peer, id, &reader)
		if !reader.valid {break}
	case 17:
		if service.mode == .Server {
			known := false
			for connection in service.peers {if connection.peer == peer {known = true; break}}
			if !known {return}
		} else if peer != service.remote {return}
		id := replication_read_u32(&reader)
		invoke_id := replication_read_u32(&reader)
		if !reader.valid || id == 0 {break}
		remote_run_invoke(service, L, peer, id, invoke_id, &reader)
		if !reader.valid {break}
	case 18:
		if service.mode == .Server {
			known := false
			for connection in service.peers {if connection.peer == peer {known = true; break}}
			if !known {return}
		} else if peer != service.remote {return}
		remote_receive_invoke_response(service, L, &reader)
		if !reader.valid {break}
	case:
		service.rejected_packets += 1
		rejected = true
		if service.rejected_packets == 1 || service.rejected_packets % 100 == 0 {
			fmt.eprintf(
				"[Replication] ignored %d packets of unknown or reserved kind (first was kind %d)\n",
				service.rejected_packets,
				data[4],
			)
		}
	}
	if !rejected && (!reader.valid || reader.offset != len(reader.data)) {
		service.malformed_packets += 1
	}
}


replication_send_acks :: proc(service: ^ReplicatorService) {
	if service.mode != .Client || service.remote == nil || !service.connected {return}
	bytes: [dynamic]u8
	defer delete(bytes)
	count: u32


	force := service.ack_full_elapsed >= 0.3
	for entity in service.entity_list {
		if entity == nil {continue}
		changed :=
			entity.applied_state_token != entity.reported_state_token ||
			entity.applied_property_token != entity.reported_property_token ||
			entity.applied_extra_token != entity.reported_extra_token
		if !changed && !force {continue}
		if entity.applied_state_token == 0 &&
		   entity.applied_property_token == 0 &&
		   entity.applied_extra_token == 0 {continue}
		replication_put_u32(&bytes, entity.id)
		replication_put_u32(&bytes, entity.applied_state_token)
		replication_put_u32(&bytes, entity.applied_property_token)
		replication_put_u32(&bytes, entity.applied_extra_token)
		entity.reported_state_token = entity.applied_state_token
		entity.reported_property_token = entity.applied_property_token
		entity.reported_extra_token = entity.applied_extra_token
		count += 1
	}
	if count == 0 {return}
	payload: [dynamic]u8
	defer delete(payload)
	replication_put_u32(&payload, count)
	append(&payload, ..bytes[:])
	_ = replication_send(service, service.remote, 4, payload[:], false)
	service.acks_sent += 1
	if force {service.ack_full_elapsed = 0}
}

Replication_Step :: proc(service: ^ReplicatorService, L: ^vm.State, delta_time: f32) {
	if service == nil || service.host == nil {return}
	remote_invoke_timeouts(service, L)
	for {
		event, has_event := transport_host_service(service.host)
		if !has_event {break}
		switch event.type {
		case .CONNECT:
			if service.mode == .Server {


				append(
					&service.peers,
					Replication_Peer {
						peer = event.peer,
						known = make(map[u32]u64),
						initialized = make(map[u32]bool),
						part_states = make(map[u32]Replication_Part_Send_State),
						property_hashes = make(map[u32]u32),
						extra_hashes = make(map[u32]u32),
						acked_state = make(map[u32]u32),
						acked_property = make(map[u32]u32),
						acked_extra = make(map[u32]u32),
						deformable = make(map[u32]u64),
					},
				)
			} else if event.peer == service.remote {
				service.handshake_elapsed = 0
				replication_send_hello(service)
				fmt.println("Network transport connected; negotiating the protocol handshake")
			}
		case .DISCONNECT:
			if service.mode == .Server {
				for &item, index in service.peers {
					if item.peer == event.peer {
						players := cast(^Players)DataModel_Get_Service(
							service.data_model,
							"Players",
						)
						owner_id: u32
						if item.player != nil {
							owner_id = item.player.user_id
							Players_Remove(players, L, item.player)
						}
						Replication_Peer_Dispose(&item)
						ordered_remove(&service.peers, index)
						replication_reclaim_disconnected_owner(service, owner_id)
						break
					}
				}
				service.connected = false
				for item in service.peers {if item.handshake_complete {service.connected = true; break}}
				fmt.println("Network server lost a client")
			} else if event.peer == service.remote {
				fmt.eprintln(
					service.connected ? "Network client disconnected from the server" : "Network client could not connect to the server",
				)
				service.connected = false
				service.remote = nil
			}
		case .RECEIVE:
			service.packets_received += 1
			service.bytes_received += u64(len(event.data))
			if len(event.data) <= 1048581 {
				replication_receive(service, L, event.peer, event.data)
			} else {service.malformed_packets += 1}
			transport_event_dispose(&event)
		case .NONE:
		}
	}
	if service.mode == .Client &&
	   !service.connected &&
	   service.remote != nil &&
	   transport_peer_disconnected(service.remote) {
		fmt.eprintln("Network client could not connect to the server")
		service.remote = nil
	}
	service.clock += delta_time
	service.elapsed += delta_time
	if service.mode == .Server && service.elapsed >= 1 / service.snapshot_rate {


		service.elapsed -= 1 / service.snapshot_rate
		if service.elapsed >= 1 / service.snapshot_rate {service.elapsed = 0}
		replication_sync(service)
	} else if service.mode == .Client &&
	   !service.connected &&
	   service.remote != nil &&
	   service.elapsed >= 10 {
		if service.handshake_elapsed > 0 {


			fmt.eprintf(
				"[Replication] connected to %s but the handshake never completed; the server may be an incompatible build or may require a join token\n",
				service.join_address,
			)
		} else {
			fmt.eprintln("Network client connection timed out")
		}
		transport_peer_reset(service.remote)
		service.remote = nil
		service.elapsed = 0
		service.handshake_elapsed = 0
	} else if service.mode == .Client && service.connected && service.elapsed >= 1.0 / 30.0 {


		service.elapsed -= 1.0 / 30.0
		if service.elapsed >= 1.0 / 30.0 {service.elapsed = 0}
		service.tick += 1
		_ = character_send_input(service)
		players := cast(^Players)DataModel_Get_Service(service.data_model, "Players")
		if players != nil && players.local_player != nil {
			for entity in service.entity_list {
				if entity.owner_id ==
				   players.local_player.user_id {_ = replication_send_owned_state(service, entity)}
			}
		}
	}
	if service.mode == .Client {
		service.ack_elapsed += delta_time
		service.ack_full_elapsed += delta_time
		if service.ack_elapsed >= 1.0 / 10.0 {
			service.ack_elapsed = 0
			replication_send_acks(service)
		}
		if !service.handshake_complete {


			service.handshake_elapsed += delta_time
		} else {
			service.time_sync_elapsed += delta_time
			if service.time_sync_elapsed >= Replication_Time_Sync_Interval {
				service.time_sync_elapsed = 0
				replication_send_time_sync(service)
			}
		}
	}
	replication_render_interpolated(service, delta_time)
	transport_host_flush(service.host)
}
