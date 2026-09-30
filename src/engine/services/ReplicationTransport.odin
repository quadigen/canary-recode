#+build !js
package services

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import signals "../signals"
import vm "../vm"
import "core:fmt"
import "core:slice"
import "core:sort"
import "core:strings"
import "base:runtime"
import assetstore "../assetstore"
import enet "vendor:ENet"

// Wire protocol revision. Bumping this is the only supported way to change the
// packet layout: both sides compare it during the handshake and refuse to talk
// to a peer they cannot parse, instead of silently misinterpreting frames.
Replication_Protocol_Version: u32 = 7

// The framing layer still accepts revision 5 so that a stale client can reach
// the HELLO handler and be told why it is being refused. Rejecting it at the
// framing check instead would drop the packet and leave it hanging until timeout.
Replication_Minimum_Framing_Version: u32 = 5

Replication_Capability_Ack_Tokens:     u32 = 1 << 0
Replication_Capability_Batch_Properties: u32 = 1 << 1
Replication_Capability_Time_Sync:       u32 = 1 << 2
// The server pushes its asset table at connect time. Advertised separately so a
// peer that cannot apply the frames is never sent them in the first place,
// rather than having the frames arrive and be dropped as unknown kinds.
Replication_Capability_Asset_Transfer: u32 = 1 << 3

// Every feature this build implements, advertised during the handshake.
Replication_Local_Capabilities: u32 =
	Replication_Capability_Ack_Tokens |
	Replication_Capability_Batch_Properties |
	Replication_Capability_Time_Sync |
	Replication_Capability_Asset_Transfer

Replication_Handshake_Ok:                u8 = 0
Replication_Handshake_Version_Mismatch:  u8 = 1
Replication_Handshake_Auth_Rejected:     u8 = 2
Replication_Handshake_Malformed:         u8 = 3
Replication_Handshake_Already_Complete:  u8 = 4
Replication_Handshake_Schema_Mismatch:   u8 = 5

// Frame kinds are numbered by capability, so a new one takes the next free
// number rather than reusing a retired meaning.
Replication_Kind_Asset: u8 = 21

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

// replication_schema_hash fingerprints the replicated class surface: for every
// class the build can replicate, the class name and the ordered list of property
// names that would go on the wire. Two builds agree only if both the set of
// replicable classes and the shape of each one match.
//
// This exists because a matching protocol version is necessary but not
// sufficient. Property replication sends names, not indices, so a client whose
// build added, removed or reordered a replicated property still parses every
// frame correctly and then applies the wrong values, or rejects them as unknown,
// with nothing in the logs to distinguish it from a bug in the property code.
// Comparing fingerprints at connect time turns that silent corruption into a
// refusal naming the cause.
//
// Only classes that actually produce a schema are included, and the hash is
// order independent within a class as well as across classes, because
// registration order is an implementation detail that can change between builds
// without changing a single byte of what is replicated.
replication_schema_hash :: proc(service: ^ReplicatorService) -> u64 {
	FNV_OFFSET: u64 = 14695981039346656037
	FNV_PRIME:  u64 = 1099511628211
	hash: u64 = FNV_OFFSET
	if service == nil ||
	   service.data_model == nil ||
	   service.data_model.registry == nil ||
	   service.data_model.registry.classes == nil {return hash}
	registry := service.data_model.registry.classes
	// Folding each class in independently and only then combining the per-class
	// digests keeps this to one allocation per class instead of a formatted
	// string per property, and the ordering of the class loop cannot leak into
	// the result because class_digests is sorted before it is combined.
	class_digests: [dynamic]u64
	defer delete(class_digests)
	for descriptor in registry.classes {
		if descriptor == nil || descriptor.info == nil {continue}
		if replication_builtin_class(descriptor.info.name) {continue}
		properties := classes.Class_Property_List(registry, descriptor.info.name)
		// A class with nothing replicable never reaches the wire, so including it
		// would make the fingerprint depend on classes no session will ever send.
		filtered: [dynamic]string
		defer delete(filtered)
		for property in properties {
			switch property {
			case "Parent", "Name", "ReplicationMode", "ReplicationGroup",
			     "AbsolutePosition", "AbsoluteSize",
			     "TextBounds", "SelectedText", "LineCount",
			     "AbsoluteCellCount", "AbsoluteCellSize", "AbsoluteContentSize",
			     "ClassName", "NetworkId", "UniqueId", "Capabilities", "IsInSandbox":
				continue
			}
			append(&filtered, property)
		}
		delete(properties)
		if len(filtered) == 0 {continue}
		// Sorted so the fingerprint does not depend on the order properties were
		// registered in, which is free to change without changing the wire.
		sort.quick_sort_proc(filtered[:], replication_string_compare)
		digest: u64 = FNV_OFFSET
		for byte in transmute([]u8)descriptor.info.name {
			digest = (digest ~ u64(byte)) * FNV_PRIME
		}
		digest = (digest ~ 0xFF) * FNV_PRIME
		for property in filtered {
			for byte in transmute([]u8)property {digest = (digest ~ u64(byte)) * FNV_PRIME}
			// Length prefixed so {"ab", "c"} and {"a", "bc"} cannot collide.
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

// replication_tokens_equal compares two secrets without an early exit, so the
// comparison time does not leak how much of the token matched.
replication_tokens_equal :: proc(a: string, b: string) -> bool {
	if len(a) != len(b) {return false}
	difference: u8
	for index in 0 ..< len(a) {
		difference |= u8(a[index]) ~ u8(b[index])
	}
	return difference == 0
}

// replication_make_nonce derives a per-session nonce. It mixes the service's
// own address-independent state with the clock, which is enough to make
// accidental collisions and replayed handshakes distinguishable in a listen
// server context.
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
	// The schema fingerprint goes in HELLO so a server can refuse a client whose
	// build replicates a different property surface, rather than accepting it and
	// then misapplying every frame that follows.
	replication_put_u64(&bytes, replication_schema_hash(service))
	replication_put_string(&bytes, service.join_token)
	_ = replication_send(service, service.remote, 1, bytes[:], true)
}

replication_send_welcome :: proc(
	service: ^ReplicatorService,
	peer: ^enet.Peer,
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
	// The server's own fingerprint, so the client can refuse in turn. A client
	// that trusted this implicitly would have no way to tell a stale server from
	// a working one until state started arriving that it could not apply.
	replication_put_u64(&bytes, schema_hash)
	replication_put_u32(&bytes, user_id)
	replication_put_string(&bytes, name)
	replication_put_u32(&bytes, nonce)
	replication_put_u32(&bytes, u32(service.snapshot_rate))
	_ = replication_send(service, peer, 3, bytes[:], true)
}

replication_peer_of :: proc(
	service: ^ReplicatorService,
	peer: ^enet.Peer,
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
	peer: ^enet.Peer,
	reader: ^Replication_Reader,
) {
	if service.mode != .Server {reader.valid = false; return}
	version := replication_read_u32(reader)
	capabilities := replication_read_u32(reader)
	schema_hash := replication_read_u64(reader)
	token := replication_read_string(reader)
	if !reader.valid || len(token) > 256 {reader.valid = false; return}
	connection: ^Replication_Peer
	for &candidate in service.peers {if candidate.peer == peer {connection = &candidate; break}}
	if connection == nil {reader.valid = false; return}
	if connection.handshake_complete {
		// A second HELLO on an established connection is either a client that
		// retried or someone trying to re-negotiate mid-session. Refuse it rather
		// than reassigning the player out from under the live session.
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
		enet.peer_disconnect_now(peer, 0)
		return
	}
	// The revision can agree while the replicated property surface does not. A
	// client built against a different set of classes parses every frame cleanly
	// and then applies the wrong values, or discards them as unknown properties,
	// so the mismatch has to be caught while there is still nothing to corrupt.
	// Checked before authentication because a mismatched build is a
	// configuration fault and reporting that is more useful than reporting a bad
	// token the client may not even have set.
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
		enet.peer_disconnect_now(peer, 0)
		return
	}
	// A server with a token set requires a match. An empty server token means no
	// authentication, which is the sane default for a local listen server.
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
		enet.peer_disconnect_now(peer, 0)
		return
	}

	id := service.next_user_id
	service.next_user_id += 1
	name := fmt.tprintf("Player%d", id)
	players := cast(^Players)DataModel_Get_Service(service.data_model, "Players")
	player := Players_Add(players, L, id, name)
	character_service := cast(^CharacterService)Ensure_Service(
		service.data_model.registry,
		"CharacterService",
	)
	if character_service != nil && player != nil {CharacterService_Load(character_service, player)}
	connection.player = player
	connection.client_capabilities = capabilities
	connection.handshake_complete = true
	connection.server_nonce = replication_make_nonce(service)
	replication_send_welcome(
		service,
		peer,
		Replication_Handshake_Ok,
		id,
		name,
		service.server_capabilities,
		connection.server_nonce,
		local_schema,
	)
	service.connected = true
	fmt.printf("Network server accepted %s (user %d)\n", name, id)
	// Assets go out after WELCOME, on the same reliable channel, so ENet ordering
	// guarantees they are applied before any spawn that references one.
	replication_send_asset_table(service, peer, capabilities)
}

replication_receive_welcome :: proc(
	service: ^ReplicatorService,
	L: ^vm.State,
	peer: ^enet.Peer,
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
	snapshot_rate := replication_read_u32(reader)
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
			// Counted so the two ends agree. A real skewed pair never reaches the
			// client's own hash comparison below, because the server refuses it
			// first, so without this the client would report zero mismatches on
			// exactly the connection that is mismatched.
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
	// The server agreed to the session before checking its own fingerprint, so a
	// stale server still has to be caught here. Otherwise the client would accept
	// a session it cannot apply and only discover it as properties silently
	// failing to set.
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
	if user_id == 0 || len(name) == 0 || len(name) > 64 {service.handshake_status = Replication_Handshake_Malformed; return}
	service.server_nonce = nonce
	service.handshake_status = Replication_Handshake_Ok
	service.handshake_complete = true
	service.connected = true
	// The server dictates the snapshot rate so a client cannot ask for more
	// updates than the server is willing to produce.
	if snapshot_rate >= 1 && snapshot_rate <= 120 {service.snapshot_rate = f32(snapshot_rate)}
	players := cast(^Players)DataModel_Get_Service(service.data_model, "Players")
	if players != nil && players.local_player == nil {players.local_player = Players_Add(players, L, user_id, name)}
	fmt.printf("Network client connected as %s (user %d)\n", name, user_id)
}

replication_send_time_sync :: proc(service: ^ReplicatorService) {
	if service.mode != .Client ||
	   service.remote == nil ||
	   !service.handshake_complete {return}
	service.time_sync_sequence += 1
	bytes: [dynamic]u8
	defer delete(bytes)
	replication_put_u32(&bytes, u32(service.clock * 1000))
	replication_put_u32(&bytes, service.time_sync_sequence)
	// Echoing the server nonce proves this client actually completed the
	// handshake rather than merely holding an open socket.
	replication_put_u32(&bytes, service.server_nonce)
	_ = replication_send(service, service.remote, 19, bytes[:], false)
}

replication_receive_time_sync :: proc(
	service: ^ReplicatorService,
	peer: ^enet.Peer,
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
		// The peer never processed our WELCOME, so its time samples are not
		// trustworthy and are dropped rather than folded into the estimate.
		return
	}
	bytes: [dynamic]u8
	defer delete(bytes)
	replication_put_u32(&bytes, client_ms)
	replication_put_u32(&bytes, u32(service.clock * 1000))
	replication_put_u32(&bytes, sequence)
	replication_put_u32(&bytes, connection.server_nonce)
	_ = replication_send(service, peer, 20, bytes[:], false)
}

replication_receive_time_sync_reply :: proc(
	service: ^ReplicatorService,
	peer: ^enet.Peer,
	reader: ^Replication_Reader,
) {
	if service.mode != .Client || peer != service.remote {return}
	client_ms := replication_read_u32(reader)
	server_ms := replication_read_u32(reader)
	sequence := replication_read_u32(reader)
	nonce := replication_read_u32(reader)
	if !reader.valid {return}
	if sequence == 0 || service.server_nonce != nonce {return}
	now_ms := u32(service.clock * 1000)
	// Only accept samples whose round trip is short enough to be meaningful.
	// Assuming a roughly symmetric path, the server stamped the request halfway
	// through, so the offset is server minus the local midpoint.
	elapsed: u32 = 0
	if now_ms > client_ms {elapsed = now_ms - client_ms}
	if elapsed > 2000 {return}
	local_midpoint := f64(client_ms) + f64(elapsed) / 2
	offset := (f64(server_ms) - local_midpoint) / 1000
	if !service.time_offset_measured {
		// The first sample is taken as-is rather than eased toward. A client that
		// joins a server which has been up for a while can be many seconds behind
		// it, and easing a constant toward that from zero leaves the render target
		// badly behind the sample window for as long as the ease takes, which shows
		// up as every replicated object sitting at a stale position.
		service.time_offset = f32(offset)
		service.time_offset_measured = true
		return
	}
	// Later samples are eased so a single delayed or reordered reply cannot yank
	// the interpolation timebase around.
	service.time_offset = service.time_offset +
		f32((offset - f64(service.time_offset)) * 0.25)
}

replication_start :: proc(
	service: ^ReplicatorService,
	address: string,
	port: u16,
	mode: Replication_Mode,
) -> bool {
	replication_stop(service)
	if mode == .Client && (address == "" || address == "0.0.0.0") {
		fmt.eprintln("Network client needs a reachable server address; use 127.0.0.1 for a server on this computer")
		return false
	}
	if replication_enet_users == 0 && enet.initialize() != 0 {
		fmt.eprintln("Could not initialize ENet")
		return false
	}
	replication_enet_users += 1
	service.enet_initialized = true
	endpoint := enet.Address {
		port = port,
	}
	if mode == .Server {
		if address != "" && address != "0.0.0.0" {
			name := strings.clone_to_cstring(address)
			defer delete(name)
			if enet.address_set_host(&endpoint, name) != 0 {
				fmt.eprintf("Could not resolve server bind address %s\n", address)
				replication_stop(service)
				return false
			}
		}
		service.host = enet.host_create(&endpoint, 32, 2, 0, 0)
	} else {
		service.host = enet.host_create(nil, 1, 2, 0, 0)
		if service.host != nil {
			name := strings.clone_to_cstring(address)
			defer delete(name)
			if enet.address_set_host(&endpoint, name) != 0 {
				fmt.eprintf("Could not resolve server address %s\n", address)
				replication_stop(service)
				return false
			}
			service.remote = enet.host_connect(service.host, &endpoint, 2, 0)
		}
	}
	if service.host == nil || (mode == .Client && service.remote == nil) {
		if service.host == nil {
			fmt.eprintf("Could not create the %s network host\n", mode == .Server ? "server" : "client")
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

// replication_budgeted reports whether a frame of this kind is charged against
// the peer's per-snapshot bandwidth budget.
//
// The budget exists to shed optional streaming load under pressure. Charging it
// for the handshake means a congested server can refuse the very packets a
// client needs to learn it is congested, and charging it for despawns is worse:
// a client that never hears about a destroyed object keeps a ghost of it
// forever, and because the pressure that shrank the budget is partly caused by
// the cleanup that can no longer get through, the controller deadlocks at its
// floor. Spawns are exempt for the same reason.
//
// replication_remaining_budget mirrors this, so the pre-flight check there and
// the charge in replication_send cannot disagree about whether a frame counts.
replication_budgeted :: proc(
	service: ^ReplicatorService,
	kind: u8,
) -> bool {
	if service == nil || service.mode != .Server {return false}
	// The asset table is a connect time transfer, not part of the per tick
	// snapshot, so it must not be measured against the tick budget. A drop here
	// would leave the client permanently missing a mesh, and unlike a lost
	// property frame nothing would ever retry it.
	return kind != 1 &&
	       kind != 2 &&
	       kind != 3 &&
	       kind != 8 &&
	       kind != 20 &&
	       kind != Replication_Kind_Asset
}

replication_send :: proc(
	service: ^ReplicatorService,
	peer: ^enet.Peer,
	kind: u8,
	payload: []u8,
	reliable: bool = true,
) -> bool {
	if peer == nil || service.host == nil || len(payload) > 1048576 {return false}
	if int(kind) < len(service.diag_kind_counts) {
		service.diag_kind_counts[int(kind)] += 1
		service.diag_kind_bytes[int(kind)] += u64(len(payload))
		// Kinds 5 and 6 multiplex several frame types behind a leading subtype
		// byte, so a per-kind tally alone cannot tell a transform update from a
		// property update.
		if len(payload) > 0 && int(payload[0]) < 16 {
			service.diag_subtype_counts[int(payload[0])][int(kind)] += 1
		}
	}
	if replication_budgeted(service, kind) {
		for &connection in service.peers {
			if connection.peer != peer {continue}
			if u64(connection.bytes_this_tick) + u64(len(payload)) + 5 >
			   u64(service.bandwidth_budget) {
				service.bandwidth_drops += 1
				service.drops_window += 1
				return false
			}
			break
		}
	}
	bytes := make([dynamic]u8, 0, len(payload) + 5)
	defer delete(bytes)
	append(&bytes, 'K', 'R', 'P', u8(Replication_Protocol_Version), kind)
	append(&bytes, ..payload)
	flags: enet.PacketFlags
	if reliable {flags += {.RELIABLE}}
	if !reliable {flags += {.UNRELIABLE_FRAGMENT}}
	packet := enet.packet_create(raw_data(bytes[:]), uint(len(bytes)), flags)
	if packet == nil {return false}
	if enet.peer_send(peer, reliable ? 0 : 1, packet) !=
	   0 {enet.packet_destroy(packet); return false}
	service.packets_sent += 1
	service.bytes_sent += u64(len(bytes))
	if replication_budgeted(service, kind) {
		for &connection in service.peers {
			if connection.peer == peer {connection.bytes_this_tick += u32(len(bytes)); break}
		}
	}
	return true
}

replication_apply_property :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	name := vm.ArgString(L, int(vm.UpvalueIndex(1)))
	vm.SetField(L, -2, name)
	return 0
}

// replication_send_asset_table hands a freshly connected client every asset the
// loaded map published. Without it the client's store stays empty for the life
// of the process, because only deserializing a .kine stream ever fills it, and
// a network client never loads one.
//
// Sent right after WELCOME on the reliable channel, so ENet's per channel
// ordering puts the whole table ahead of the first spawn that references it.
replication_send_asset_table :: proc(
	service: ^ReplicatorService,
	peer: ^enet.Peer,
	client_capabilities: u32,
) {
	if (client_capabilities & Replication_Capability_Asset_Transfer) == 0 {return}
	total := assetstore.Count()

	sent := 0
	for index := 0; index < total; index += 1 {
		// At borrows the entry, and nothing registers during this loop, so the
		// pointer stays valid to the end of the iteration.
		entry, ok := assetstore.At(index)
		if !ok || entry == nil {continue}
		payload: [dynamic]u8
		encode_asset_entry(&payload, entry.id, entry.path, entry.kind, entry.bytes)
		sent_ok := replication_send(service, peer, Replication_Kind_Asset, payload[:], true)
		// Freed here rather than with defer: a defer inside a loop body runs at
		// procedure exit, so one per iteration would free the same final buffer
		// once per asset.
		delete(payload)
		if !sent_ok {return}
		sent += 1
	}

	// A closing frame so the client can tell a complete table from a truncated
	// one instead of silently running with whatever happened to arrive. It is sent
	// even when the map published nothing, so an empty table is reported as a
	// complete empty table rather than leaving the client waiting forever.
	footer: [dynamic]u8
	append(&footer, Replication_Asset_Subtype_End)
	replication_put_u32(&footer, u32(sent))
	replication_send(service, peer, Replication_Kind_Asset, footer[:], true)
	delete(footer)

	service.assets_sent += u64(sent)
	fmt.printf("Sent %d embedded assets to a client\n", sent)
}

replication_receive_asset :: proc(
	service: ^ReplicatorService,
	peer: ^enet.Peer,
	reader: ^Replication_Reader,
) {
	if service.mode != .Client || peer != service.remote {return}
	if reader.offset >= len(reader.data) {reader.valid = false; return}
	subtype := reader.data[reader.offset]
	reader.offset += 1

	if subtype == Replication_Asset_Subtype_End {
		count := replication_read_u32(reader)
		if !reader.valid {return}
		// The declared count is checked against what actually arrived rather than
		// just recorded. Taking the server's word for it would let a truncated or
		// hostile table mark itself complete, which is the one thing this frame
		// exists to rule out.
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
	if subtype != Replication_Asset_Subtype_Entry {reader.valid = false; return}

	id, path, kind, data, ok := decode_asset_entry_body(reader)
	if !ok {return}
	// The cumulative caps are enforced here rather than left to the store, because
	// bytes now arrive from the network instead of a file the user chose. Count
	// and total size are both bounded so a peer cannot make this client reserve
	// an unbounded amount of memory by claiming more than it sent.
	if service.assets_received >= u64(assetstore.MAX_ASSET_COUNT) {
		fmt.eprintln("[Replication] refused an asset past the asset count limit")
		service.asset_rejections += 1
		return
	}
	if service.asset_bytes_received + u64(len(data)) > u64(assetstore.MAX_ASSET_TOTAL_BYTES) {
		fmt.eprintln("[Replication] refused an asset past the total size limit")
		service.asset_rejections += 1
		return
	}

	// Register_As takes ownership, and the packet buffer is released once this
	// dispatch returns, so the store gets a copy it may keep.
	owned := slice.clone(data)
	if !assetstore.Register_As(id, owned, path, kind) {
		fmt.eprintf("[Replication] refused a malformed asset entry: %s\n", id)
		service.asset_rejections += 1
		return
	}
	service.assets_received += 1
	service.asset_bytes_received += u64(len(data))
}

replication_receive :: proc(
	service: ^ReplicatorService,
	L: ^vm.State,
	peer: ^enet.Peer,
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
	// `rejected` separates "we do not know what this is" from "we know what this
	// is and it is wrong". The former is a version-skew signal; the latter is
	// corruption. Sharing one counter hid skew behind the corruption metric.
	rejected := false
	switch data[4] {
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
		// Content acknowledgement: which state/property batches the client has
		// actually applied. The server will not suppress a repeat of a batch
		// until this confirms it landed, which is what makes loss recoverable.
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
			replication_decode_value(L, &reader, service.signal_registry.datatypes, 0)
			if !reader.valid {break}
			if ok, err := vm.ProtectedCall(L, 2, 0); !ok {
				fmt.eprintf("[Replication] failed to apply property %q to %s: %s\n", name, classes.Get_Class_Name(object), err)
				vm.Pop(L)
			}
			entity.last_property_tick = tick
			// The trailer names the suppression channel, carries the token for the
			// whole batch, and says which member of that batch this frame is. The
			// token is only reported back once every member has arrived, so a batch
			// that lost a frame in transit is resent in full rather than being
			// silently acked and suppressed.
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
				// A different token or a different size means this is a new group. A
				// same-token size change should not happen because the token is a
				// hash of the encoded content, but resetting is the safe reaction if
				// it ever does.
				entity.property_batch_token[channel] = batch_token
				entity.property_batch_size[channel] = member_count
				entity.property_batch_mask[channel] = 0
			}
			entity.property_batch_mask[channel] |= u64(1) << member_index
			// Bits 0 through member_count-1. Written as a single shift because in
			// Odin '|' and '-' share a precedence and associate left to right, so the
			// obvious spelling `1 << (n-1) | (1 << (n-1)) - 1` silently groups as
			// `(A | B) - 1`. That produced a mask one bit short of the group, which
			// made every group declare itself complete one member early.
			full := (u64(1) << member_count) - 1
			if entity.property_batch_mask[channel] == full {
				if stream == replication_property_stream_extra {
					entity.applied_extra_token = batch_token
				} else {
					entity.applied_property_token = batch_token
				}
				// The accumulator is deliberately left armed. Members of a group can
				// arrive out of order or be retried, and clearing it here would let a
				// straggler re-arm the group with no members left to complete it, so it
				// would sit unpublished forever while the server kept resending it.
				// A repeat frame just re-sets a bit that is already set and
				// re-publishes the same token, which is idempotent. Only a different
				// token resets the group.
				//
				// Acknowledge as soon as a group completes rather than waiting for
				// the periodic timer. The server re-sends any group it has not had
				// confirmed every snapshot, so with acks only on a 10Hz timer and
				// snapshots at 20Hz every group was sent two or three times before
				// the confirmation that would have stopped it. The periodic timer
				// stays in place to re-report in case this very packet is lost.
				service.ack_elapsed = 1.0
			}
			break
		}
		if entity.last_state_tick != 0 &&
		   transmute(i32)(tick - entity.last_state_tick) < 0 {return}
		if subtype != 1 || !classes.Is_A(object, "Part") {reader.valid = false; break}
		part := cast(^classes.Part)object
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
			local_character :=
				players != nil &&
				players.local_player != nil &&
				object.parent != nil &&
				classes.Is_A(object.parent, "CharacterModel") &&
				(cast(^classes.CharacterModel)object.parent).owner_user_id ==
					players.local_player.user_id
			owned :=
				players != nil &&
				players.local_player != nil &&
				entity.owner_id == players.local_player.user_id
			local_root := local_character && object.name == "HumanoidRootPart"
			if local_root {
				// Always remember the authoritative transform for our own root
				// part, whether or not this client owns it. Reconciliation
				// replays it against the input acknowledgement, which now
				// arrives separately in a kind 14 packet. This used to be
				// stashed only in the !owned branch, but a client's own
				// HumanoidRootPart is normally owned by it, so the frame was
				// never recorded and prediction was never corrected.
				entity.server_frame = frame
				entity.server_frame_valid = true
			}
			if local_root && owned {
				characters := cast(^CharacterService)Ensure_Service(
					service.data_model.registry,
					"CharacterService",
				)
				if entity.force_correction {
					dx := frame.x - part.cframe.x
					dy := frame.y - part.cframe.y
					dz := frame.z - part.cframe.z
					part.cframe = frame
					part.position = datatypes.Vector3{frame.x, frame.y, frame.z}
					character_translate_followers(
						cast(^classes.CharacterModel)object.parent,
						part,
						dx,
						dy,
						dz,
					)
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
				// A follower part of our own locally-driven character: the local
				// controller already moved it, so only the first authoritative
				// frame is worth applying.
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
					// The buffer restarts here, so the dead-reckoning seed has to
					// restart with it. Leaving a stale frame_seeded would let the
					// next sample-less pass extrapolate from a transform that
					// belongs to the pre-snap timeline.
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
			if int(material) >= 0 && int(material) <= int(enums.Material.debug) {
				part.material = material
			}
			if int(shape) >= 0 && int(shape) <= int(enums.PartType.Capsule) {
				part.shape = shape
			}
			classes.Set_Name(object, name)
			entity.last_state_tick = tick
			// The first accepted transform frame is what makes this Part's
			// placement authoritative; until it lands the client is looking at the
			// constructor's placeholder transform.
			entity.has_transform = true
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
		if root_name != "" && !replication_root_allowed(root_name) {break}
		if !replication_builtin_class(class_name) &&
		   replication_schema(service, class_name) == nil {break}
		parent :=
			parent_id == 0 ? DataModel_Get_Service(service.data_model, root_name) : replication_entity_object(service, parent_id)
		if parent == nil || service.data_model.registry == nil {break}
		// Containers the runtime owns locally (StarterPlayerScripts and
		// StarterCharacterScripts live under StarterPlayer) must not be
		// duplicated by a replicated copy: keep ours and let the ClientScripts
		// merge step move the replicated contents into them instead.
		if classes.Is_A(parent, "StarterPlayer") {
			if existing := classes.Find_First_Child(parent, name); existing != nil {
				// Adopt the server's id so later property updates for this
				// replicated shell land on our existing container.
				existing.network_id = id
				_ = replication_entity_new(service, id, existing)
				return
			}
		}
		if character_subtree_class(class_name) {
			// The client builds a prediction controller for each character as
			// soon as its HumanoidRootPart arrives (CharacterService_Bind). Adopt
			// the server's entity id onto the locally-built instance instead of
			// duplicating the subtree, mirroring the StarterPlayer pattern above.
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
		)
		if !ok || object == nil {break}
		classes.Set_Name(object, name)
		if classes.Is_A(object, "CharacterModel") {
			(cast(^classes.CharacterModel)object).owner_user_id = owner_user_id
		}
		classes.Set_Parent(object, parent)
		object.network_id = id
		vm.Pop(L)
		_ = replication_entity_new(service, id, object)
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
				CharacterService_Unbind(
					service.data_model,
					cast(^classes.CharacterModel)object,
					L,
				)
			}
			// Detach from the indexes before destroying so a destroy hook that
			// re-enters replication cannot observe a freed entity.
			_ = replication_entity_remove(service, id)
			if object != nil && !object.destroyed {classes.Destroy_Hierarchy(object)}
		}
	case 9:
		character_receive_input(service, peer, &reader)
	case 10:
		if service.mode != .Client || peer != service.remote {return}
		id := replication_read_u32(&reader)
		owner_id := replication_read_u32(&reader)
		for item in service.entity_list {
			if item.id == id {
				if item.owner_id != owner_id {
					clear(&item.samples)
					item.sample_age = 0
					item.frame_seeded = false
				}
				item.owner_id = owner_id
				break
			}
		}
	case 11:
		if service.mode != .Server {return}
		id := replication_read_u32(&reader)
		_ = replication_read_u32(&reader)
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
		if reader.offset + 48 != len(reader.data) {
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
		// Every component has to be finite, not just the position. A single NaN
		// in the rotation basis would propagate through physics, interpolation
		// and rendering, and unlike a bad position it would not be caught by the
		// displacement check below.
		if !reader.valid || !replication_frame_finite(frame) {
			service.owned_states_rejected += 1
			return
		}
		// The basis has to be a real rotation. Without this a client can upload a
		// skewed or mirrored matrix, which produces geometry that is not a rigid
		// transform of the original and can defeat collision assumptions.
		if !replication_frame_rotation_valid(frame) {
			service.owned_states_rejected += 1
			return
		}
		now := service.clock
		// Rate limit, per part. The displacement and speed checks below are only
		// meaningful if they cannot simply be stepped around by sending more
		// packets.
		if entity.owned_rate_window_time == 0 ||
		   now - entity.owned_rate_window_time >= 1 {
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
			payload := []u8{u8(id), u8(id >> 8), u8(id >> 16), u8(id >> 24)}
			_ = replication_send(service, connection.peer, 15, payload)
			return
		}
		// Sustained travel bound. A client that moves just under the per-packet
		// tolerance every packet would otherwise accumulate an unbounded
		// teleport, so travel is also capped across a one-second window.
		//
		// A rejection deliberately does NOT re-anchor the window. Resetting on
		// violation handed the client a fresh budget every time it tripped, which
		// still let it walk arbitrarily far, just in 1024-stud steps. The window
		// is left to expire on its own so the cap is a genuine sustained-speed
		// limit. An honest client that overshoots once is server-authoritative
		// for the rest of that second, which is the intended trade.
		if entity.owned_window_time == 0 || now - entity.owned_window_time >= 1 {
			entity.owned_window_time = now
			entity.owned_window_origin =
				datatypes.Vector3{part.cframe.x, part.cframe.y, part.cframe.z}
		} else {
			ox := frame.x - entity.owned_window_origin.x
			oy := frame.y - entity.owned_window_origin.y
			oz := frame.z - entity.owned_window_origin.z
			if ox * ox + oy * oy + oz * oz > service.owned_max_speed * service.owned_max_speed {
				service.owned_states_rejected += 1
				payload := []u8{u8(id), u8(id >> 8), u8(id >> 16), u8(id >> 24)}
				_ = replication_send(service, connection.peer, 15, payload)
				return
			}
		}
		entity.owned_updates_window += 1
		part.cframe = frame
		part.position = datatypes.Vector3{frame.x, frame.y, frame.z}
		if part.parent != nil && classes.Is_A(part.parent, "CharacterModel") {
			character_translate_followers(
				cast(^classes.CharacterModel)part.parent,
				part,
				dx,
				dy,
				dz,
			)
		}
		service.owned_states_accepted += 1
	case 13:
		replication_receive_ownership_request(service, peer, &reader)
	case 14:
		// Input acknowledgement: the last input sequence the server consumed
		// for the character whose HumanoidRootPart carries this entity id.
		if service.mode != .Client || peer != service.remote {return}
		id := replication_read_u32(&reader)
		ack := replication_read_u32(&reader)
		if !reader.valid || id == 0 {break}
		entity := replication_entity_by_id(service, id)
		if entity == nil || !entity.server_frame_valid {break}
		character_reconcile(service, entity, entity.server_frame, ack)
		service.char_acks_received += 1
	case 15:
		if service.mode != .Client || peer != service.remote {return}
		id := replication_read_u32(&reader)
		entity := replication_entity_by_id(service, id)
		if entity != nil {entity.force_correction = true}
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
		replication_decode_value(L, &reader, service.signal_registry.datatypes, 0)
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
		// RemoteEvent fire.
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
		// RemoteFunction invoke request.
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
		// RemoteFunction invoke response.
		if service.mode == .Server {
			known := false
			for connection in service.peers {if connection.peer == peer {known = true; break}}
			if !known {return}
		} else if peer != service.remote {return}
		remote_receive_invoke_response(service, L, &reader)
		if !reader.valid {break}
	case:
		// A6: an unknown kind is a version skew signal, not corruption, and gets
		// its own counter so a rolling upgrade is visible instead of being buried
		// inside the malformed-packet count.
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

// replication_send_acks reports the content tokens the client currently holds,
// per suppression channel. Runs at a fixed low rate.
//
// Tokens are deliberately not latched after a send. The previous version marked
// each entity as "already told the server" before the packet even left, so a
// single dropped acknowledgement left the server permanently unsure and it would
// re-send forever with no way to learn the client already had the content. Now
// any token that changed since the last round is reported immediately, and
// everything is re-reported on a timer, so a lost ack heals within one interval.
replication_send_acks :: proc(service: ^ReplicatorService) {
	if service.mode != .Client ||
	   service.remote == nil ||
	   !service.connected {return}
	bytes: [dynamic]u8
	defer delete(bytes)
	count: u32
	// A full re-report is due when nothing has changed for a while. Without it
	// a single lost acknowledgement would leave the server permanently unsure
	// and it would re-send that entity's content forever.
	force := service.ack_full_elapsed >= 0.3
	for entity in service.entity_list {
		if entity == nil {continue}
		changed := entity.applied_state_token != entity.reported_state_token ||
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
	event: enet.Event
	for enet.host_service(service.host, &event, 0) > 0 {
		switch event.type {
		case .CONNECT:
			if service.mode == .Server {
				// The peer is created unassigned. Player creation, id assignment and
				// character loading all wait for a HELLO that passes the version
				// and token checks, so a rejected or spoofed client never reaches
				// the simulation as a live player.
				append(
					&service.peers,
					Replication_Peer {
						peer    = event.peer,
						known   = make(map[u32]u32),
						initialized = make(map[u32]bool),
						state_hashes = make(map[u32]u32),
						property_hashes = make(map[u32]u32),
						extra_hashes = make(map[u32]u32),
						acked_state = make(map[u32]u32),
						acked_property = make(map[u32]u32),
						acked_extra = make(map[u32]u32),
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
						if item.player != nil {Players_Remove(players, L, item.player)}
						Replication_Peer_Dispose(&item)
						ordered_remove(&service.peers, index)
						break
					}
				}
			service.connected = false
			for item in service.peers {if item.handshake_complete {service.connected = true; break}}
			fmt.println("Network server lost a client")
			} else if event.peer ==
			   service.remote {
				fmt.eprintln(service.connected ? "Network client disconnected from the server" : "Network client could not connect to the server")
				service.connected = false
				service.remote = nil
			}
		case .RECEIVE:
			if event.packet != nil {
				service.packets_received += 1
				service.bytes_received += u64(event.packet.dataLength)
				if event.packet.dataLength <= 1048581 {
					replication_receive(
						service,
						L,
						event.peer,
						event.packet.data[:int(event.packet.dataLength)],
					)
				} else {service.malformed_packets += 1}
				enet.packet_destroy(event.packet)
			}
		case .NONE:
		}
	}
	if service.mode == .Client &&
	   !service.connected &&
	   service.remote != nil &&
	   service.remote.state == .DISCONNECTED {
		fmt.eprintln("Network client could not connect to the server")
		service.remote = nil
	}
	service.clock += delta_time
	service.elapsed += delta_time
	if service.mode == .Server && service.elapsed >= 1 / service.snapshot_rate {
		service.elapsed = 0
		replication_sync(service)
	} else if service.mode == .Client &&
	          !service.connected &&
	          service.remote != nil &&
	          service.elapsed >= 10 {
		if service.handshake_elapsed > 0 {
			// The socket came up but the protocol negotiation never finished, so
			// name that rather than reporting a generic connection failure. The
			// address is named deliberately and the join token is not: the token is
			// a shared secret and this goes to the log, which is routinely shipped
			// off the machine.
			fmt.eprintf(
				"[Replication] connected to %s but the handshake never completed; the server may be an incompatible build or may require a join token\n",
				service.join_address,
			)
		} else {
			fmt.eprintln("Network client connection timed out")
		}
		enet.peer_reset(service.remote)
		service.remote = nil
		service.elapsed = 0
		service.handshake_elapsed = 0
	} else if service.mode == .Client && service.connected && service.elapsed >= 1.0 / 30.0 {
		service.elapsed = 0
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
			// Without a deadline a client whose server is old, misconfigured or
			// silently dropping its HELLO waits forever with no explanation.
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
	enet.host_flush(service.host)
}
