#+build !js
package services

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import signals "../signals"
import vm "../vm"
import "core:fmt"
import "core:strings"
import enet "vendor:ENet"
import target "../target"

ReplicatorService_Class := classes.Class_Info {
	name   = "ReplicatorService",
	parent = &Service_Class,
}

Replication_Mode :: enum {
	Stopped,
	Server,
	Client,
}

Replication_Sample :: struct {
	tick:  u32,
	frame: datatypes.CFrame,
}

Replication_Entity :: struct {
	id:                     u32,
	object:                 ^classes.Object,
	owner_id:               u32,
	recipients:             map[u32]bool,
	// last_state_tick and last_property_tick are tracked separately. Sharing one
	// counter let an interleaved property frame overwrite the ordering guard for
	// transform frames (and vice versa), which dropped legitimate snapshots.
	last_state_tick:         u32,
	last_property_tick:      u32,
	// has_transform records that an authoritative transform has been accepted for
	// this entity. On a client a freshly spawned instance exists at whatever
	// transform its constructor gave it (the world origin for a Part) until the
	// first transform frame lands, and physics must not act on that placeholder:
	// a body built there collides with whatever else is near the origin and, for
	// an unanchored Part, is immediately shoved out of it. Replication clears
	// this once the first transform arrives and the body is built from the real
	// one instead.
	has_transform:           bool,
	// The transform stream, the builtin property stream (Name/Value) and the
	// extra property stream (asset ids and schema properties) are three
	// independent suppression channels. They need separate tokens because a
	// client can hold an up-to-date transform while a property is still missing,
	// and sharing one token let any one of the three mask the other two.
	applied_state_token:      u32,
	applied_property_token:   u32,
	applied_extra_token:      u32,
	// property_batch_* accumulate a property batch member by member, indexed by
	// stream (0 builtin, 1 extra). The applied token above is only published once
	// every member of the batch has arrived. Publishing it on the first arrival
	// would tell the server the batch landed in full, and the server suppresses
	// against that token, so members lost in transit would never be resent and the
	// property would stay wrong on the client for the life of the session.
	property_batch_token: [2]u32,
	property_batch_size:  [2]u8,
	property_batch_mask:  [2]u64,
	// reported_* is what we last put on the wire. Tokens are re-reported on a
	// timer rather than latched, so a dropped kind 4 packet self-heals on the
	// next round instead of stranding the server's suppression state forever.
	reported_state_token:     u32,
	reported_property_token:  u32,
	reported_extra_token:     u32,
	ack_repeat:               f32,
	last_accepted_ms:       u32,
	last_accepted_position: datatypes.Vector3,
	// owned_window_origin anchors a one-second sliding window used to bound how
	// far an owning client may travel in total. The per-packet displacement cap
	// alone cannot catch a client that moves just under the cap on every packet
	// and accumulates an unbounded teleport.
	//
	// These are measured against the simulation clock rather than the wall clock.
	// ENet's clock does not advance in the loopback test harness, so a wall-clock
	// window never expires there and the rate limit latches off permanently.
	owned_window_origin:       datatypes.Vector3,
	owned_window_time:         f32,
	owned_updates_window:      u32,
	owned_rate_window_time:    f32,
	force_correction:       bool,
	samples:                [dynamic]Replication_Sample,
	sample_age:             f32,
	// velocity_sq is the squared magnitude of the last inter-sample delta,
	// updated on the server each tick and used to priority-sort state sends
	// so fast-moving parts are never starved out by the bandwidth budget.
	velocity_sq:            f32,
	// velocity_origin is the position the velocity delta was measured from. It
	// used to share last_accepted_position with the ownership-transfer path,
	// so a SetNetworkOwner on the same tick silently perturbed the sort.
	velocity_origin:        datatypes.Vector3,
	velocity_seeded:        bool,
	// dead_reckoning holds the last interpolated CFrame and the linear
	// velocity estimated from the two most recent samples. The client uses
	// it to extrapolate position when the sample buffer runs dry.
	last_frame:             datatypes.CFrame,
	// frame_seeded records whether last_frame holds a real transform yet. The
	// zero value of last_frame is a degenerate CFrame: the world origin with an
	// all-zero rotation basis, which is singular and collapses the Part's world
	// bounds to a point. Dead reckoning must never start from it.
	frame_seeded:           bool,
	last_velocity:          datatypes.Vector3,
	// dr_age tracks how many seconds the client has been dead-reckoning so
	// the extrapolation can be capped to avoid wild divergence.
	dr_age:                 f32,
	// server_frame holds the last authoritative transform the server sent for
	// an entity this client does not own. Reconciliation replays it against the
	// input sequence carried in a kind 14 packet, so the transform and the
	// acknowledgement no longer have to arrive in the same message.
	server_frame:           datatypes.CFrame,
	server_frame_valid:     bool,
}

Replication_Peer :: struct {
	peer:            ^enet.Peer,
	player:          ^Player,
	known:           map[u32]u32,
	initialized:     map[u32]bool,
	state_hashes:    map[u32]u32,
	property_hashes: map[u32]u32,
	extra_hashes:    map[u32]u32,
	// acked_* are what the client has confirmed holding, per suppression
	// channel. Suppression is only allowed when one of these agrees with what we
	// last sent on that same channel, so a lost packet is retried instead of
	// being silently assumed delivered.
	acked_state:     map[u32]u32,
	acked_property:  map[u32]u32,
	acked_extra:     map[u32]u32,
	bytes_this_tick: u32,
	// A peer is created as soon as ENet reports a connection but stays
	// unassigned, and therefore inert, until it completes the handshake. Every
	// inbound handler already requires player != nil, so a pending peer cannot
	// drive the simulation even if it starts sending immediately.
	handshake_complete: bool,
	// Cached focus point, in the form (x, y, z, valid).
	//
	// The live focus is the client's own character, which can disappear: a respawn
	// unbinds the old model, and there is a window where the client has no owned
	// Part on the server at all. Under spatial relevancy, having no focus means
	// "replicate nothing", so without a cache every respawn would briefly blank
	// the world for that client and then spend time re-spawning the scene. The
	// last known focus point is a much better answer than either extreme.
	focus_x:  f32,
	focus_y:  f32,
	focus_z:  f32,
	focus_ok: bool,
	client_capabilities: u32,
	client_nonce:        u32,
	// server_nonce is the value this peer was given in WELCOME. It is per peer
	// rather than per service because a service wide nonce is overwritten by the
	// next client to connect, after which every earlier client's time samples are
	// rejected as forged.
	server_nonce: u32,
	// bandwidth_cursor rotates which entity is considered first when the snapshot
	// budget runs out. Without it the send order is fixed, so the same entities
	// win the budget every tick and the rest are starved forever: they never get
	// sent, so they are never acknowledged, so they are retried every tick
	// forever. That is a hard deadlock, and it is reachable at the budget floor
	// whenever the scene needs more per snapshot than the degraded budget allows.
	bandwidth_cursor: u32,
	// init_cursor does the same for the first-content pass, which is separately
	// budget limited and separately ordered.
	init_cursor: u32,
	// last_ack_sent is the most recent input sequence shipped to this peer in
	// a kind 14 packet, so we only re-send when the server has actually
	// consumed new input.
	last_ack_sent:   u32,
}

Replication_Event_Callback :: struct {
	name:      string,
	reference: i32,
}

Replication_Group_Member :: struct {
	name:    string,
	user_id: u32,
}

Replication_Peer_Dispose :: proc(connection: ^Replication_Peer) {
	if connection == nil {return}
	delete(connection.known)
	delete(connection.initialized)
	delete(connection.state_hashes)
	delete(connection.property_hashes)
	delete(connection.extra_hashes)
	delete(connection.acked_state)
	delete(connection.acked_property)
	delete(connection.acked_extra)
	connection.known = nil
	connection.initialized = nil
	connection.state_hashes = nil
	connection.property_hashes = nil
	connection.extra_hashes = nil
	connection.acked_state = nil
	connection.acked_property = nil
	connection.acked_extra = nil
}

Replication_Schema :: struct {
	class_name: string,
	properties: [dynamic]string,
}

ReplicatorService :: struct {
	using service:             Service,
	mode:                      Replication_Mode,
	host:                      ^enet.Host,
	remote:                    ^enet.Peer,
	peers:                     [dynamic]Replication_Peer,
	// entity_list preserves registration order, which is parent-before-child
	// because the tree walk visits roots top-down. Spawn ordering depends on it.
	entity_list:               [dynamic]^Replication_Entity,
	// entity_by_id and entity_ids give O(1) lookup in both directions. Entities
	// are individually heap allocated so the pointers handed out by
	// replication_entity / replication_entity_by_id stay valid when the
	// container grows or an entry is removed.
	entity_by_id:              map[u32]^Replication_Entity,
	entity_ids:                map[^classes.Object]u32,
	suppressed:                map[^classes.Object]bool,
	next_id:                   u32,
	next_user_id:              u32,
	// Handshake state. The protocol previously had no handshake at all: the
	// server assigned an id the instant ENet reported a connection, so a client
	// speaking a different dialect was silently accepted and then misparsed, and
	// there was no way to authenticate the peer.
	//
	// client_capabilities / server_capabilities are feature bitmasks so a peer
	// can advertise what it understands and the other side can avoid sending
	// frames the receiver would drop.
	client_capabilities:       u32,
	server_capabilities:       u32,
	handshake_complete:        bool,
	handshake_status:          u8,
	handshake_elapsed:         f32,
	// join_token is the shared secret. On a server it is the value clients must
	// present; on a client it is the value to present. Empty means no
	// authentication, which is the right default for a local listen server.
	join_token:                string,
	// join_address is the endpoint StartServer/ConnectClient was given, kept only
	// so a stalled client can report which server it is stuck on.
	join_address:               string,
	// server_nonce is issued in WELCOME and echoed by the client in every time
	// sync, which proves the client actually processed the handshake rather than
	// just opening a socket. On a client this holds the nonce of its one remote
	// server. On a server the authoritative copy lives on the peer, because two
	// clients connecting at once must not overwrite each other's nonce and start
	// discarding each other's time samples.
	server_nonce:              u32,
	// time_offset is the estimated difference between the server clock and the
	// local one, in seconds. Clients need it to age interpolation samples against
	// the same timebase the server sampled on.
	//
	// time_offset_measured distinguishes "no estimate has arrived yet" from "the
	// estimate is genuinely zero". A client that joins a server which has been up
	// for a while has a large real offset but starts out at zero, and a renderer
	// that trusts a zero offset would anchor its samples to a clock that is
	// nowhere near the server's.
	time_offset:               f32,
	time_offset_measured:      bool,
	time_sync_sequence:        u32,
	time_sync_elapsed:         f32,
	handshake_rejections:      u64,
	tick:                      u32,
	elapsed:                   f32,
	// clock is a monotonic simulation clock in seconds. elapsed is not usable for
	// rate limiting because it is reset every time a snapshot fires, so a window
	// measured against it would restart constantly and never bound anything.
	clock:                     f32,
	snapshot_rate:             f32,
	interpolation_delay_ticks: f32,
	teleport_threshold:        f32,
	relevancy_distance:       f32,
	// Level of detail. Parts inside relevancy_distance * lod_near_fraction are
	// refreshed every snapshot; the rest are refreshed every lod_far_interval
	// snapshots. lod_near_fraction of 1 disables the split and restores the old
	// every-snapshot behaviour for everything in range.
	lod_near_fraction:         f32,
	lod_far_interval:          int,
	bandwidth_budget:          u32,
	connected:                 bool,
	enet_initialized:          bool,
	event_signal:              ^signals.Signal,
	event_callbacks:           [dynamic]Replication_Event_Callback,
	group_members:             [dynamic]Replication_Group_Member,
	schemas:                   [dynamic]Replication_Schema,
	packets_sent:              u64,
	bytes_sent:                u64,
	packets_received:          u64,
	bytes_received:            u64,
	malformed_packets:          u64,
	// rejected_packets counts frames whose kind is reserved or unknown. These are
	// tracked separately from malformed_packets: an unknown kind is a version
	// skew signal, not corruption, and lumping the two together hid it.
	rejected_packets:           u64,
	version_mismatches:         u64,
	// schema_mismatches counts connections refused because the two builds
	// replicate a different class surface. It is separate from version_mismatches
	// because the two are fixed by different things: the revision by a deliberate
	// protocol change, the schema by whichever classes and properties the build
	// happens to contain.
	schema_mismatches:     u64,
	auth_failures:          u64,
	bandwidth_drops:           u64,
	unchanged_states_skipped:  u64,
	owned_states_accepted:     u64,
	owned_states_rejected:     u64,
	acks_received:             u64,
	char_acks_received:        u64,
	acks_sent:                 u64,
	states_applied:            u64,
	// ack_elapsed paces the kind 4 rounds. ack_full_elapsed is a separate,
	// coarser clock that drives the periodic full re-report; reusing
	// ack_elapsed for it meant the threshold was never reached, because that
	// counter is reset on every round.
	ack_elapsed:               f32,
	ack_full_elapsed:          f32,
	// Per-packet-kind and per-(subtype, kind) tallies. Kinds 5 and 6 multiplex
	// several frame types behind a leading subtype byte, so a kind-only counter
	// cannot distinguish a transform update from a property update; suppression
	// bugs are only visible once the two are counted apart.
	diag_kind_counts:          [32]u64,
	diag_kind_bytes:           [32]u64,
	diag_subtype_counts:       [16][32]u64,
	invoke_pending:            [dynamic]Remote_Invoke_Pending,
	next_invoke_id:            u32,
	// drops_window counts budget refusals since the last snapshot. It is kept
	// separate from the cumulative bandwidth_drops stat, which used to be zeroed
	// here and therefore always reported 0 to GetStats.
	drops_window:               u64,
	// adaptive_scale is the fraction of the configured budget and snapshot rate
	// currently in force, in (0, 1]. It moves DOWN when the budget refuses
	// packets and creeps back UP when it does not.
	adaptive_scale:             f32,
	// base_bandwidth_budget / base_snapshot_rate are the values set by the
	// user (or defaults). The adaptive logic only ever scales down from them, so
	// a user's setting is a ceiling rather than something that gets overridden.
	base_bandwidth_budget:     u32,
	base_snapshot_rate:        f32,
	// Floors for the adaptive scale, so a sustained overload degrades to a
	// lower but still usable frame rate instead of starving replication entirely.
	adaptive_min_scale:         f32,
	adaptive_min_snapshot_rate: u32,
	// Limits applied to state a client uploads for a part it owns.
	// owned_teleport_tolerance is the largest single-packet jump still treated
	// as a teleport rather than a cheat, owned_max_speed bounds travel across a
	// one-second window, and owned_max_updates_per_second bounds the per-part
	// packet rate those two are enforced at. The rate limit is per part rather
	// than per connection: a single shared budget let a character uploading its
	// own root and followers starve every other part the client owns.
	owned_teleport_tolerance:     f32,
	owned_max_speed:              f32,
	owned_max_updates_per_second: u32,
}

replication_enet_users: int

replication_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(ReplicatorService)
	service.service = Service_Init(&ReplicatorService_Class, "ReplicatorService", data_model)
	service.snapshot_rate = 20
	service.interpolation_delay_ticks = 2
	service.teleport_threshold = 12
	service.relevancy_distance = 1024
	// Half the sphere is the near band; beyond it a part is refreshed every
	// fourth snapshot. Four is coarse enough to be worth having and fine enough
	// that a moving part still interpolates rather than visibly stuttering.
	service.lod_near_fraction = 0.5
	service.lod_far_interval = 4
	service.bandwidth_budget = 48 * 1024
	service.base_snapshot_rate = 20
	service.adaptive_scale = 1
	service.adaptive_min_scale = 0.25
	service.adaptive_min_snapshot_rate = 5
	service.owned_teleport_tolerance = 128
	service.owned_max_speed = 1024
	service.owned_max_updates_per_second = 120
	service.base_bandwidth_budget = 48 * 1024
	service.next_id = 1
	service.next_user_id = 1
	// Both roles advertise the same feature set; they are separate fields because
	// what matters is the intersection of the two, and folding them into one
	// would make "the peer does not support this" indistinguishable from "we do
	// not support this".
	service.client_capabilities = Replication_Local_Capabilities
	service.server_capabilities = Replication_Local_Capabilities
	return &service.object
}

replication_stop :: proc(service: ^ReplicatorService) {
	players := cast(^Players)DataModel_Get_Service(service.data_model, "Players")
	L: ^vm.State
	if service.signal_registry != nil && service.signal_registry.vm_state != nil {
		L = service.signal_registry.vm_state.L
	}
	if service.host != nil {
		if service.mode == .Client && service.remote != nil {
			enet.peer_disconnect(service.remote, 0)
			enet.host_flush(service.host)
		}
		for &item in service.peers {
			if item.peer != nil {enet.peer_disconnect_now(item.peer, 0)}
			if L != nil && item.player != nil {Players_Remove(players, L, item.player)}
			Replication_Peer_Dispose(&item)
		}
		enet.host_destroy(service.host)
		service.host = nil
	}
	delete(service.peers)
	service.peers = nil
	client_objects: [dynamic]^classes.Object
	if service.mode == .Client && L != nil {
		for item in service.entity_list {
			if item.object == nil || item.object.destroyed {continue}
			if classes.Is_A(item.object, "CharacterModel") {
				CharacterService_Unbind(service.data_model, cast(^classes.CharacterModel)item.object, L)
			}
			append(&client_objects, item.object)
		}
	}
	for item in service.entity_list {
		delete(item.recipients)
		delete(item.samples)
		free(item)
	}
	delete(service.entity_list)
	service.entity_list = nil
	delete(service.entity_by_id)
	service.entity_by_id = nil
	delete(service.entity_ids)
	service.entity_ids = nil
	for object in client_objects {
		if !object.destroyed {classes.Destroy_Hierarchy(object)}
	}
	delete(client_objects)
	for member in service.group_members {delete(member.name)}
	delete(service.group_members)
	service.group_members = nil
	for pending in service.invoke_pending {
		if pending.thread_ref != 0 && service.data_model != nil &&
		   service.data_model.registry != nil &&
		   service.data_model.registry.vm_state != nil &&
		   service.data_model.registry.vm_state.L != nil {
			vm.ReleaseValue(service.data_model.registry.vm_state.L, pending.thread_ref)
		}
	}
	delete(service.invoke_pending)
	service.invoke_pending = nil
	service.next_invoke_id = 0
	delete(service.suppressed)
	service.suppressed = nil
	service.remote = nil
	service.mode = .Stopped
	service.connected = false
	// The join token is a heap copy owned by the service, so it has to be
	// released on teardown. It is deliberately kept across a stop/start cycle
	// though: a server restarted in place should not silently drop the secret it
	// was configured with, which would turn into a wave of auth failures.
	service.handshake_complete = false
	service.handshake_status = Replication_Handshake_Ok
	service.handshake_elapsed = 0
	service.time_sync_elapsed = 0
	// The offset is only meaningful against the peer it was measured from, so it
	// is dropped with the rest of the session state. A reconnect to a different
	// peer would otherwise render against a timebase that no longer applies, and
	// until the first reply arrives there is no evidence the value was ever right.
	// The sample counter goes with it so a new session renegotiates from zero.
	service.time_offset = 0
	service.time_offset_measured = false
	service.time_sync_sequence = 0
	service.server_nonce = 0
	if service.data_model != nil && service.data_model.registry != nil && service.data_model.registry.vm_state != nil && service.data_model.registry.vm_state.L != nil {
		vm.AddGlobal_Boolean(service.data_model.registry.vm_state, "IsServer", target.is_server())
		vm.AddGlobal_Boolean(service.data_model.registry.vm_state, "IsClient", target.is_client())
	}
	service.elapsed = 0
	service.tick = 0
	service.next_id = 1
	service.next_user_id = 1
	if L != nil &&
	   players != nil &&
	   players.local_player != nil {Players_Remove(players, L, players.local_player)}
	if service.enet_initialized {
		replication_enet_users -= 1
		if replication_enet_users == 0 {enet.deinitialize()}
		service.enet_initialized = false
	}
}

replication_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	service := cast(^ReplicatorService)object
	replication_stop(service)
	for schema in service.schemas {
		delete(schema.class_name)
		for property in schema.properties {delete(property)}
		delete(schema.properties)
	}
	delete(service.schemas)
	if service.event_signal != nil {signals.Destroy(service.event_signal)}
	if service.signal_registry != nil &&
	   service.signal_registry.vm_state != nil &&
	   service.signal_registry.vm_state.L != nil {
		for callback in service.event_callbacks {
			vm.ReleaseValue(service.signal_registry.vm_state.L, callback.reference)
			delete(callback.name)
		}
	}
	delete(service.event_callbacks)
	// The join token survives stop/start so a server restarted in place keeps the
	// secret it was configured with, which means the only place it can be
	// released is here, at destruction.
	if len(service.join_token) > 0 {delete(service.join_token)}
	service.join_token = ""
	if len(service.join_address) > 0 {delete(service.join_address)}
	service.join_address = ""
	classes.Object_Destroy(object)
	free(service)
}

replication_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	service := cast(^ReplicatorService)object
	switch key {
	case "SnapshotRate":
		vm.PushNumber(L, f64(service.snapshot_rate))
	case "BandwidthBudget":
		vm.PushNumber(L, f64(service.bandwidth_budget))
	case "InterpolationDelayTicks":
		vm.PushNumber(L, f64(service.interpolation_delay_ticks))
	case "TeleportThreshold":
		vm.PushNumber(L, f64(service.teleport_threshold))
	case "RelevancyDistance":
		vm.PushNumber(L, f64(service.relevancy_distance))
	case "LODNearFraction":
		vm.PushNumber(L, f64(service.lod_near_fraction))
	case "LODFarInterval":
		vm.PushNumber(L, f64(service.lod_far_interval))
	case "EventReceived":
		if service.event_signal ==
		   nil {service.event_signal = signals.Create(service.signal_registry.signal_registry)}
		signals.Push(L, service.event_signal)
	case "Connected":
		vm.PushBoolean(L, service.connected)
	case "StartServer",
	     "ConnectClient",
	     "Stop",
	     "SendEvent",
	     "SendEventTo",
	     "OnEvent",
	     "Register",
	     "Unregister",
	     "RegisterSchema",
	     "CreateNetworkEmulator",
	     "AssignOwnership",
	     "AddPlayerToGroup",
	     "RemovePlayerFromGroup",
	     "IsPlayerInGroup",
	     "ReplicateTo",
	     "StopReplicatingTo",
	     "GetStats",
	     "GetActiveReplicator":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}
	return true
}

replication_set :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	service := cast(^ReplicatorService)object
	if key == "SnapshotRate" {
		rate := vm.ArgNumber(L, value_index)
		if rate < 1 ||
		   rate > 120 {_ = vm.RaiseError(L, "SnapshotRate must be between 1 and 120"); return true}
		service.snapshot_rate = f32(rate)
		service.base_snapshot_rate = f32(rate)
		return true
	}
	if key == "BandwidthBudget" {
		budget := vm.ArgNumber(L, value_index)
		if budget < 1024 || budget > 16 * 1024 * 1024 || f64(u32(budget)) != budget {
			_ = vm.RaiseError(L, "BandwidthBudget must be between 1024 and 16777216")
			return true
		}
		service.bandwidth_budget = u32(budget)
		service.base_bandwidth_budget = u32(budget)
		return true
	}
	if key == "InterpolationDelayTicks" {
		delay := vm.ArgNumber(L, value_index)
		if delay < 0 || delay > 8 {_ = vm.RaiseError(L, "InterpolationDelayTicks must be between 0 and 8"); return true}
		service.interpolation_delay_ticks = f32(delay)
		return true
	}
	if key == "TeleportThreshold" {
		threshold := vm.ArgNumber(L, value_index)
		if threshold < 0 || threshold > 100000 {_ = vm.RaiseError(L, "TeleportThreshold must be between 0 and 100000"); return true}
		service.teleport_threshold = f32(threshold)
		return true
	}
	if key == "RelevancyDistance" {
		distance := vm.ArgNumber(L, value_index)
		if distance < 0 || distance > 1000000 {_ = vm.RaiseError(L, "RelevancyDistance must be between 0 and 1000000"); return true}
		service.relevancy_distance = f32(distance)
		return true
	}
	if key == "LODNearFraction" {
		fraction := vm.ArgNumber(L, value_index)
		// 0 disables the near band, meaning everything in range is treated as far.
		// Values above 1 are the old behaviour, so they are allowed and clamped.
		if fraction < 0 || fraction > 1 {_ = vm.RaiseError(L, "LODNearFraction must be between 0 and 1"); return true}
		service.lod_near_fraction = f32(fraction)
		return true
	}
	if key == "LODFarInterval" {
		interval := vm.ArgNumber(L, value_index)
		if interval < 1 || interval > 64 {_ = vm.RaiseError(L, "LODFarInterval must be between 1 and 64"); return true}
		service.lod_far_interval = int(interval)
		return true
	}
	return false
}

replication_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	service := cast(^ReplicatorService)object
	switch method {
	case "StartServer", "ConnectClient":
		address := vm.ArgOptionalString(L, 2, method == "StartServer" ? "0.0.0.0" : "127.0.0.1")
		port := vm.ArgOptionalNumber(L, 3, 1234)
		if port < 1 ||
		   port > 65535 ||
		   f64(i64(port)) != port {return vm.RaiseError(L, "invalid network port"), true}
		ok := replication_start(
			service,
			address,
			u16(port),
			method == "StartServer" ? .Server : .Client,
		)
		if ok {
			// Remembered purely so a client can name the endpoint it is stuck
			// talking to. The join token must never be used for that; it is a
			// shared secret and this ends up in the log.
			if len(service.join_address) > 0 {delete(service.join_address)}
			service.join_address = strings.clone(address)
			classes.Push_Object(L, object)
		} else {
			vm.PushNil(L)
		}
		return 1, true
	case "Stop":
		replication_stop(service); return 0, true
	case "OnEvent":
		name := vm.ArgString(L, 2)
		if len(name) == 0 ||
		   len(name) > 256 ||
		   !vm.IsFunction(
				   L,
				   3,
			   ) {return vm.RaiseError(L, "OnEvent requires a name and callback"), true}
		vm.PushValue(L, 3)
		reference := vm.RetainValue(L)
		vm.Pop(L)
		append(
			&service.event_callbacks,
			Replication_Event_Callback{name = strings.clone(name), reference = reference},
		)
		return 0, true
	case "GetActiveReplicator":
		if service.mode == .Stopped {vm.PushNil(L)} else {classes.Push_Object(L, object)}
		return 1, true
	case "RegisterSchema":
		class_name := vm.ArgString(L, 2)
		if len(class_name) == 0 ||
		   len(class_name) > 64 ||
		   !vm.IsTable(L, 3) {return vm.RaiseError(L, "invalid replication schema"), true}
		if classes.Find_Class(service.data_model.registry.classes, class_name) ==
		   nil {return vm.RaiseError(L, "unknown replicated class"), true}
		// The client tracks which members of a property batch have arrived with a
		// fixed-width mask, so a schema wider than that could never be reported
		// complete and its properties would be resent forever. Refusing the
		// registration surfaces the mistake where it is made instead of as a
		// silent bandwidth leak at runtime.
		if vm.RawLen(L, 3) > int(replication_property_batch_limit) {
			return vm.RaiseError(
				L,
				fmt.tprintf(
					"a replication schema may declare at most %d properties",
					replication_property_batch_limit,
				),
			),
			       true
		}
		schema := replication_schema(service, class_name)
		if schema == nil {
			append(&service.schemas, Replication_Schema{class_name = strings.clone(class_name)})
			schema = &service.schemas[len(service.schemas) - 1]
		} else {
			for property in schema.properties {delete(property)}
			delete(schema.properties)
			schema.properties = nil
		}
		for index in 1 ..= vm.RawLen(L, 3) {
			_ = vm.RawGetIndex(L, 3, index)
			if !vm.IsString(
				L,
				-1,
			) {vm.Pop(L); return vm.RaiseError(L, "schema property must be a string"), true}
			property := vm.ArgString(L, -1)
			if len(property) == 0 ||
			   len(property) > 64 ||
			   property == "Parent" {
				vm.Pop(L)
				return vm.RaiseError(L, "invalid schema property"), true
			}
			if !replication_schema_has(
				schema,
				property,
			) {append(&schema.properties, strings.clone(property))}
			vm.Pop(L)
		}
		vm.NewTable(L, len(schema.properties) + 3)
		vm.PushString(L, "Name"); vm.SetArrayValue(L, -2, 1)
		vm.PushString(L, "ReplicationMode"); vm.SetArrayValue(L, -2, 2)
		vm.PushString(L, "ReplicationGroup"); vm.SetArrayValue(L, -2, 3)
		for property, index in schema.properties {
			vm.PushString(L, property)
			vm.SetArrayValue(L, -2, index + 4)
		}
		return 1, true
	case "CreateNetworkEmulator":
		created, ok := classes.Push_New(
			service.data_model.registry.classes,
			service.data_model.registry.vm_state,
			"NetworkEmulator",
			false,
		)
		if !ok || created == nil {vm.PushNil(L); return 1, true}
		emulator := cast(^NetworkEmulator)created
		if vm.IsTable(L, 2) {
			_ = vm.GetField(L, 2, "latency")
			emulator.latency = max(0, vm.ArgOptionalNumber(L, -1, 0))
			vm.Pop(L)
			_ = vm.GetField(L, 2, "jitter")
			emulator.jitter = max(0, vm.ArgOptionalNumber(L, -1, 0))
			vm.Pop(L)
			_ = vm.GetField(L, 2, "loss")
			emulator.loss = clamp(vm.ArgOptionalNumber(L, -1, 0), 0, 1)
			vm.Pop(L)
			_ = vm.GetField(L, 2, "reorder")
			emulator.reorder = clamp(vm.ArgOptionalNumber(L, -1, 0), 0, 1)
			vm.Pop(L)
		}
		return 1, true
	case "Register":
		id := replication_register(service, collection_object_from_argument(L, 2))
		if id == 0 {vm.PushNil(L)} else {vm.PushInteger(L, i64(id))}
		return 1, true
	case "Unregister":
		instance := collection_object_from_argument(L, 2)
		id := replication_entity_id(service, instance)
		if id != 0 {
			if service.suppressed == nil {service.suppressed = make(map[^classes.Object]bool)}
			service.suppressed[instance] = true
			instance.network_id = 0
		}
		for item in service.entity_list {if item.id == id && id != 0 {_ = replication_entity_remove(service, item.id); break}}
		for &connection in service.peers {
			if connection.known[id] != 0 {
				bytes: [dynamic]u8
				replication_put_u32(&bytes, id)
				_ = replication_send(service, connection.peer, 8, bytes[:])
				delete(bytes)
				replication_forget_peer_entity(&connection, id)
			}
		}
		vm.PushBoolean(L, id != 0)
		return 1, true
	case "AssignOwnership":
		instance := collection_object_from_argument(L, 2)
		entity := replication_entity(service, instance)
		if service.mode != .Server || entity == nil {vm.PushNil(L); return 1, true}
		owner_id: u32
		if !vm.IsNoneOrNil(L, 3) {
			player_object := collection_object_from_argument(L, 3)
			if player_object == nil ||
			   !classes.Is_A(
					   player_object,
					   "Player",
				   ) {return vm.RaiseError(L, "owner must be a Player or nil"), true}
			owner_id = (cast(^Player)player_object).user_id
		}
		replication_set_ownership(service, entity, owner_id)
		vm.NewTable(L, 0, 2)
		vm.PushNumber(L, f64(owner_id)); vm.SetField(L, -2, "owner")
		vm.PushNumber(L, f64(entity.id)); vm.SetField(L, -2, "id")
		return 1, true
	case "AddPlayerToGroup", "RemovePlayerFromGroup", "IsPlayerInGroup":
		player_object := collection_object_from_argument(L, 2)
		if service.mode != .Server ||
		   player_object == nil ||
		   !classes.Is_A(player_object, "Player") {vm.PushBoolean(L, false); return 1, true}
		name := vm.ArgString(L, 3)
		if len(name) == 0 ||
		   len(name) > 128 {return vm.RaiseError(L, "invalid replication group"), true}
		id := (cast(^Player)player_object).user_id
		index := -1
		for member, i in service.group_members {if member.user_id == id && member.name == name {index = i; break}}
		switch method {
		case "AddPlayerToGroup":
			if index <
			   0 {append(&service.group_members, Replication_Group_Member{name = strings.clone(name), user_id = id})}
			vm.PushBoolean(L, true)
		case "RemovePlayerFromGroup":
			if index >=
			   0 {delete(service.group_members[index].name); ordered_remove(&service.group_members, index)}
			vm.PushBoolean(L, index >= 0)
		case "IsPlayerInGroup":
			vm.PushBoolean(L, index >= 0)
		}
		return 1, true
	case "ReplicateTo", "StopReplicatingTo":
		instance := collection_object_from_argument(L, 2)
		player_object := collection_object_from_argument(L, 3)
		if service.mode != .Server ||
		   instance == nil ||
		   player_object == nil ||
		   !classes.Is_A(player_object, "Player") {vm.PushBoolean(L, false); return 1, true}
		entity := replication_entity(service, instance)
		if entity == nil {vm.PushBoolean(L, false); return 1, true}
		id := (cast(^Player)player_object).user_id
		if method == "ReplicateTo" {
			if entity.recipients == nil {entity.recipients = make(map[u32]bool)}
			entity.recipients[id] = true
		} else {delete_key(&entity.recipients, id)}
		vm.PushBoolean(L, true)
		return 1, true
	case "SendEvent", "SendEventTo":
		name_index := method == "SendEventTo" ? 3 : 2
		name := vm.ArgString(L, name_index)
		if len(name) == 0 || len(name) > 256 {return vm.RaiseError(L, "invalid event name"), true}
		reliable := vm.ArgOptionalBoolean(L, name_index + 2, true)
		bytes: [dynamic]u8
		defer delete(bytes)
		replication_put_string(&bytes, name)
		if !replication_encode_value(
			L,
			name_index + 1,
			&bytes,
			0,
		) {vm.PushBoolean(L, false); return 1, true}
		ok := false
		if service.mode == .Client && service.connected && method == "SendEvent" {
			ok = replication_send(service, service.remote, 12, bytes[:], reliable)
		} else if service.mode == .Server {
			target: ^Player
			if method == "SendEventTo" {
				object := collection_object_from_argument(L, 2)
				if object == nil ||
				   !classes.Is_A(object, "Player") {vm.PushBoolean(L, false); return 1, true}
				target = cast(^Player)object
			}
			for connection in service.peers {
				if target != nil && connection.player != target {continue}
				ok = replication_send(service, connection.peer, 12, bytes[:], reliable) || ok
			}
		}
		vm.PushBoolean(L, ok)
		return 1, true
	case "SetJoinToken":
		// On a server this is the value clients must present; on a client it is
		// the value to present. Rejecting an over-long token here means a
		// malformed value is caught at configuration time rather than turning
		// every future connection into an authentication failure.
		token := vm.ArgString(L, 2)
		if len(token) > 256 {return vm.RaiseError(L, "join token must be 256 characters or fewer"), true}
		if len(service.join_token) > 0 {delete(service.join_token)}
		if len(token) > 0 {service.join_token = strings.clone(token)}
		vm.PushBoolean(L, true)
		return 1, true
	case "GetStats":
		vm.NewTable(L, 0, 24)
		vm.PushBoolean(L, service.connected); vm.SetField(L, -2, "connected")
		vm.PushNumber(L, f64(len(service.entity_list))); vm.SetField(L, -2, "replicatedEntities")
		vm.PushNumber(L, f64(len(service.peers))); vm.SetField(L, -2, "peers")
		vm.PushNumber(L, f64(service.packets_sent)); vm.SetField(L, -2, "packetsSent")
		vm.PushNumber(L, f64(service.bytes_sent)); vm.SetField(L, -2, "bytesSent")
		vm.PushNumber(L, f64(service.packets_received)); vm.SetField(L, -2, "packetsReceived")
		vm.PushNumber(L, f64(service.bytes_received)); vm.SetField(L, -2, "bytesReceived")
		vm.PushNumber(L, f64(service.malformed_packets)); vm.SetField(L, -2, "malformedPackets")
		vm.PushNumber(L, f64(service.bandwidth_drops)); vm.SetField(L, -2, "bandwidthDrops")
		// rejectedPackets separates unknown or reserved kinds from genuine
		// corruption. A climb here during a rolling update means clients and
		// servers disagree about the protocol, which is a different and much more
		// actionable problem than a malformed-packet climb.
		vm.PushNumber(L, f64(service.rejected_packets)); vm.SetField(L, -2, "rejectedPackets")
		vm.PushNumber(L, f64(service.version_mismatches)); vm.SetField(L, -2, "versionMismatches")
		vm.PushNumber(L, f64(service.schema_mismatches)); vm.SetField(L, -2, "schemaMismatches")
		vm.PushNumber(L, f64(service.auth_failures)); vm.SetField(L, -2, "authFailures")
		// Handshake visibility: a client that is connected but has not completed
		// the negotiation is sitting in a state that used to be indistinguishable
		// from a healthy one.
		vm.PushBoolean(L, service.handshake_complete); vm.SetField(L, -2, "handshakeComplete")
		vm.PushNumber(L, f64(service.handshake_status)); vm.SetField(L, -2, "handshakeStatus")
		vm.PushNumber(L, f64(Replication_Protocol_Version)); vm.SetField(L, -2, "protocolVersion")
		vm.PushNumber(L, f64(service.server_capabilities)); vm.SetField(L, -2, "serverCapabilities")
		// timeOffset is the estimated server-minus-local clock difference and is
		// what makes client interpolation run on the server's timebase instead of
		// drifting by the round trip.
		vm.PushNumber(L, f64(service.time_offset)); vm.SetField(L, -2, "timeOffset")
		vm.PushNumber(L, f64(service.unchanged_states_skipped)); vm.SetField(L, -2, "unchangedStatesSkipped")
		vm.PushNumber(L, f64(service.tick)); vm.SetField(L, -2, "tick")
		// Acknowledgement counters. statesApplied counts transform snapshots the
		// client actually took, and the ack pair shows whether the kind 4
		// content-token exchange is flowing in both directions, which is what
		// makes unchanged-state suppression safe under packet loss.
		vm.PushNumber(L, f64(service.states_applied)); vm.SetField(L, -2, "statesApplied")
		vm.PushNumber(L, f64(service.acks_sent)); vm.SetField(L, -2, "acksSent")
		vm.PushNumber(L, f64(service.acks_received)); vm.SetField(L, -2, "acksReceived")
		vm.PushNumber(L, f64(service.char_acks_received)); vm.SetField(L, -2, "charAcksReceived")
		// adaptiveScale and the effective budget/rate make the load controller
		// observable; a scale pinned at the floor means replication is running
		// degraded and the scene is probably too large for the configured budget.
		vm.PushNumber(L, f64(service.adaptive_scale)); vm.SetField(L, -2, "adaptiveScale")
		vm.PushNumber(L, f64(service.bandwidth_budget)); vm.SetField(L, -2, "effectiveBandwidthBudget")
		vm.PushNumber(L, f64(service.snapshot_rate)); vm.SetField(L, -2, "effectiveSnapshotRate")
		vm.PushNumber(L, f64(service.owned_states_accepted)); vm.SetField(L, -2, "ownedStatesAccepted")
		vm.PushNumber(L, f64(service.owned_states_rejected)); vm.SetField(L, -2, "ownedStatesRejected")
		if service.mode == .Client && service.remote != nil {
			vm.PushNumber(L, f64(service.remote.roundTripTime)); vm.SetField(L, -2, "rtt")
			vm.PushNumber(
				L,
				f64(service.remote.roundTripTimeVariance),
			); vm.SetField(L, -2, "jitter")
		}
		return 1, true
	}
	return 0, false
}

Register_ReplicatorService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&ReplicatorService_Class,
		replication_construct,
		replication_destroy,
		creatable = false,
		get = replication_get,
		set = replication_set,
		namecall = replication_namecall,
	)
}
