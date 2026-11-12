package services
// wire:service

import assetstore "../assetstore"
import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import signals "../signals"
import target "../target"
import vm "../vm"
import "core:fmt"
import "core:strings"

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
	id:                       u32,
	object:                   ^classes.Object,
	owner_id:                 u32,
	owner_locked:             bool,
	recipients:               map[u32]bool,
	last_state_tick:          u32,
	last_property_tick:       u32,
	has_transform:            bool,
	applied_state_token:      u32,
	applied_property_token:   u32,
	applied_extra_token:      u32,
	property_batch_token:     [2]u32,
	property_batch_size:      [2]u8,
	property_batch_mask:      [2]u64,
	reported_state_token:     u32,
	reported_property_token:  u32,
	reported_extra_token:     u32,
	ack_repeat:               f32,
	last_accepted_ms:         u32,
	last_accepted_position:   datatypes.Vector3,
	owned_window_origin:      datatypes.Vector3,
	owned_window_time:        f32,
	owned_updates_window:     u32,
	last_upload_owner:        u32,
	last_upload_tick:         u32,
	owned_rest_upload_tick:   u32,
	owned_rest_upload_hash:   u64,
	owned_rate_window_time:   f32,
	force_correction:         bool,
	pivot_revision:           u32,
	pivot_pending:            bool,
	pivot_upload_guard:       bool,
	pivot_upload_after:       u32,
	owned_request_pending:    bool,
	owned_linear_velocity:    datatypes.Vector3,
	owned_angular_velocity:   datatypes.Vector3,
	pending_linear_velocity:  datatypes.Vector3,
	pending_angular_velocity: datatypes.Vector3,
	pending_velocity_valid:   bool,
	owned_as_model:           bool,
	samples:                  [dynamic]Replication_Sample,
	sample_age:               f32,
	velocity_sq:              f32,
	velocity_origin:          datatypes.Vector3,
	velocity_seeded:          bool,
	last_frame:               datatypes.CFrame,
	frame_seeded:             bool,
	last_velocity:            datatypes.Vector3,
	dr_age:                   f32,
	render_correction:        datatypes.Vector3,
	server_frame:             datatypes.CFrame,
	server_frame_valid:       bool,
}

Replication_Part_Send_State :: struct {
	token:     u32,
	tick:      u32,
	rest_sent: bool,
}

Replication_Peer :: struct {
	peer:                      ^Replication_Transport_Peer,
	player:                    ^Player,
	known:                     map[u32]u64,
	mesh_assets:               map[string]bool,
	initialized:               map[u32]bool,
	part_states:               map[u32]Replication_Part_Send_State,
	property_hashes:           map[u32]u32,
	extra_hashes:              map[u32]u32,
	acked_state:               map[u32]u32,
	acked_property:            map[u32]u32,
	acked_extra:               map[u32]u32,
	deformable:                map[u32]u64,
	bytes_this_tick:           u32,
	join_batch:                [dynamic]u8,
	join_batch_enabled:        bool,
	reliable_join_properties:  map[u64]u32,
	handshake_complete:        bool,
	terrain_initial_sent:      bool,
	terrain_cursor:            u64,
	terrain_epoch:             u64,
	terrain_deltas_sent:       u64,
	scene_ready_sent:          bool,
	finished_replicating_sent: bool,
	gravity_sent:              bool,
	last_gravity:              f32,
	focus_x:                   f32,
	focus_y:                   f32,
	focus_z:                   f32,
	focus_ok:                  bool,
	client_capabilities:       u32,
	snapshot_clock_rate:       f32,
	client_nonce:              u32,
	server_nonce:              u32,
	bandwidth_cursor:          u32,
	init_cursor:               u32,
	last_ack_sent:             u32,
	script_sources:            map[u32]u64,
	script_send:               Replication_Script_Send,
	metadata_revisions:        map[u64]u64,
	metadata_send:             Replication_Metadata_Send,
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
	delete(connection.join_batch)
	delete(connection.reliable_join_properties)
	for id in connection.mesh_assets {delete(id)}
	delete(connection.mesh_assets)
	delete(connection.script_sources)
	connection.script_sources = nil
	replication_clear_script_send(&connection.script_send)
	delete(connection.metadata_revisions)
	connection.metadata_revisions = nil
	replication_clear_metadata_send(&connection.metadata_send)
	delete(connection.initialized)
	delete(connection.part_states)
	delete(connection.property_hashes)
	delete(connection.extra_hashes)
	delete(connection.acked_state)
	delete(connection.acked_property)
	delete(connection.acked_extra)
	delete(connection.deformable)
	connection.known = nil
	connection.initialized = nil
	connection.part_states = nil
	connection.property_hashes = nil
	connection.extra_hashes = nil
	connection.acked_state = nil
	connection.acked_property = nil
	connection.acked_extra = nil
	connection.deformable = nil
}

Replication_Schema :: struct {
	class_name: string,
	properties: [dynamic]string,
}

ReplicatorService :: struct {
	using service:                 Service,
	mode:                          Replication_Mode,
	host:                          ^Replication_Transport_Host,
	remote:                        ^Replication_Transport_Peer,
	peers:                         [dynamic]Replication_Peer,
	entity_list:                   [dynamic]^Replication_Entity,
	entity_by_id:                  map[u32]^Replication_Entity,
	entity_ids:                    map[^classes.Object]u32,
	suppressed:                    map[^classes.Object]bool,
	next_id:                       u32,
	next_user_id:                  u32,
	client_capabilities:           u32,
	server_capabilities:           u32,
	handshake_complete:            bool,
	handshake_status:              u8,
	handshake_elapsed:             f32,
	join_token:                    string,
	username:                      string,
	join_address:                  string,
	server_nonce:                  u32,
	time_offset:                   f32,
	time_offset_measured:          bool,
	time_sync_sequence:            u32,
	time_sync_elapsed:             f32,
	handshake_rejections:          u64,
	tick:                          u32,
	elapsed:                       f32,
	clock:                         f32,
	snapshot_rate:                 f32,
	snapshot_clock_rate:           f32,
	interpolation_delay_ticks:     f32,
	teleport_threshold:            f32,
	relevancy_distance:            f32,
	lod_near_fraction:             f32,
	lod_far_interval:              int,
	bandwidth_budget:              u32,
	connected:                     bool,
	transport_initialized:         bool,
	scene_ready:                   bool,
	replication_finished:          bool,
	script_receive:                Replication_Script_Receive,
	metadata_receive:              Replication_Metadata_Receive,
	event_signal:                  ^signals.Signal,
	event_callbacks:               [dynamic]Replication_Event_Callback,
	group_members:                 [dynamic]Replication_Group_Member,
	schemas:                       [dynamic]Replication_Schema,
	packets_sent:                  u64,
	bytes_sent:                    u64,
	packets_received:              u64,
	bytes_received:                u64,
	malformed_packets:             u64,
	rejected_packets:              u64,
	version_mismatches:            u64,
	schema_mismatches:             u64,
	auth_failures:                 u64,
	bandwidth_drops:               u64,
	unchanged_states_skipped:      u64,
	owned_states_accepted:         u64,
	owned_states_rejected:         u64,
	acks_received:                 u64,
	char_acks_received:            u64,
	acks_sent:                     u64,
	states_applied:                u64,
	assets_sent:                   u64,
	assets_received:               u64,
	asset_bytes_received:          u64,
	asset_rejections:              u64,
	asset_table_complete:          bool,
	asset_pending_id:              string,
	asset_pending_path:            string,
	asset_pending_kind:            assetstore.Asset_Kind,
	asset_pending_total:           u32,
	asset_pending_next:            u32,
	asset_pending_bytes:           [dynamic]u8,
	terrain_batches_received:      int,
	terrain_cells_received:        int,
	terrain_cells_declared:        u32,
	terrain_draw_version:          u32,
	terrain_rejections:            u64,
	terrain_header_seen:           bool,
	terrain_table_complete:        bool,
	terrain_receiving:             bool,
	terrain_pending:               map[Terrain_Voxel_Key]Terrain_Cell_Record,
	terrain_pending_voxel_size:    f32,
	terrain_pending_iso_level:     f32,
	terrain_sync_tick:             u32,
	terrain_sync_due:              bool,
	ack_elapsed:                   f32,
	ack_full_elapsed:              f32,
	diag_kind_counts:              [32]u64,
	diag_kind_bytes:               [32]u64,
	diag_subtype_counts:           [16][32]u64,
	invoke_pending:                [dynamic]Remote_Invoke_Pending,
	next_invoke_id:                u32,
	drops_window:                  u64,
	drop_pressure:                 f32,
	adaptive_scale:                f32,
	base_bandwidth_budget:         u32,
	bandwidth_budget_configured:   bool,
	base_snapshot_rate:            f32,
	adaptive_min_scale:            f32,
	owned_teleport_tolerance:      f32,
	owned_max_speed:               f32,
	owned_max_updates_per_second:  u32,
	auto_ownership_enabled:        bool,
	auto_ownership_acquire_radius: f32,
	auto_ownership_release_radius: f32,
	auto_ownership_clock:          f32,
}

replication_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(ReplicatorService)
	service.service = Service_Init(&ReplicatorService_Class, "ReplicatorService", data_model)


	service.snapshot_rate = 30
	service.interpolation_delay_ticks = 2
	service.teleport_threshold = 12
	service.relevancy_distance = 1024


	service.lod_near_fraction = 0.5
	service.lod_far_interval = 4
	service.bandwidth_budget = 48 * 1024
	service.base_snapshot_rate = 30
	service.adaptive_scale = 1


	service.adaptive_min_scale = 0.05
	service.owned_teleport_tolerance = 128
	service.owned_max_speed = 1024
	service.owned_max_updates_per_second = 120


	service.auto_ownership_enabled = true
	service.auto_ownership_acquire_radius = 50
	service.auto_ownership_release_radius = 80
	service.base_bandwidth_budget = 48 * 1024
	service.next_id = 1
	service.next_user_id = 1


	service.client_capabilities = Replication_Local_Capabilities
	service.server_capabilities = Replication_Local_Capabilities
	return &service.object
}

replication_stop :: proc(service: ^ReplicatorService) {
	delete(service.terrain_pending)
	service.terrain_pending = nil
	service.terrain_receiving = false
	service.terrain_header_seen = false
	service.terrain_table_complete = false
	service.terrain_batches_received = 0
	service.terrain_cells_received = 0
	L: ^vm.State
	// A VM finalizer can run after Players or a replicated character is gone.
	// During lua_close, release transport state and let the VM destroy its objects.
	if !vm.Is_Closing() && service.signal_registry != nil && service.signal_registry.vm_state != nil {
		L = service.signal_registry.vm_state.L
	}
	players := cast(^Players)DataModel_Get_Service(service.data_model, "Players") if L != nil else nil
	if service.host != nil {
		if service.mode == .Client && service.remote != nil {
			transport_peer_disconnect(service.remote)
			transport_host_flush(service.host)
		}
		for &item in service.peers {
			if item.peer != nil {transport_peer_disconnect_now(item.peer)}
			if L != nil && item.player != nil {Players_Remove(players, L, item.player)}
			Replication_Peer_Dispose(&item)
		}
		transport_host_destroy(service.host)
		service.host = nil
	}
	delete(service.peers)
	service.peers = nil


	replication_asset_pending_reset(service)
	replication_clear_script_receive(&service.script_receive)
	replication_clear_metadata_receive(&service.metadata_receive)
	client_objects: [dynamic]^classes.Object
	if service.mode == .Client && L != nil {
		replication_clear_root_metadata(service, L)
		for item in service.entity_list {
			if item.object == nil || item.object.destroyed {continue}
			if classes.Is_A(item.object, "CharacterModel") {
				CharacterService_Unbind(
					service.data_model,
					cast(^classes.CharacterModel)item.object,
					L,
				)
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
		if pending.thread_ref != 0 && L != nil {
			vm.ReleaseValue(L, pending.thread_ref)
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
	service.scene_ready = false
	service.replication_finished = false


	service.handshake_complete = false
	service.handshake_status = Replication_Handshake_Ok
	service.handshake_elapsed = 0
	service.time_sync_elapsed = 0


	service.time_offset = 0
	service.time_offset_measured = false
	service.snapshot_clock_rate = 0
	service.time_sync_sequence = 0
	service.server_nonce = 0
	if L != nil {
		vm.AddGlobal_Boolean(service.signal_registry.vm_state, "IsServer", target.is_server())
		vm.AddGlobal_Boolean(service.signal_registry.vm_state, "IsClient", target.is_client())
	}
	service.elapsed = 0
	service.tick = 0


	service.clock = 0
	service.next_id = 1
	service.next_user_id = 1
	if L != nil &&
	   players != nil &&
	   players.local_player != nil {Players_Remove(players, L, players.local_player)}
	if service.transport_initialized {
		transport_deinit()
		service.transport_initialized = false
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
	for callback in service.event_callbacks {
		if !vm.Is_Closing() && service.signal_registry != nil &&
		   service.signal_registry.vm_state != nil &&
		   service.signal_registry.vm_state.L != nil {
			vm.ReleaseValue(service.signal_registry.vm_state.L, callback.reference)
		}
		delete(callback.name)
	}
	delete(service.event_callbacks)


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
	case "SceneReady":
		vm.PushBoolean(L, service.scene_ready)
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
		if !(rate >= 1 && rate <= 120) {
			_ = vm.RaiseError(L, "SnapshotRate must be between 1 and 120")
			return true
		}
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
		service.bandwidth_budget_configured = true
		return true
	}
	if key == "InterpolationDelayTicks" {
		delay := vm.ArgNumber(L, value_index)
		if delay < 0 ||
		   delay >
			   8 {_ = vm.RaiseError(L, "InterpolationDelayTicks must be between 0 and 8"); return true}
		service.interpolation_delay_ticks = f32(delay)
		return true
	}
	if key == "TeleportThreshold" {
		threshold := vm.ArgNumber(L, value_index)
		if threshold < 0 ||
		   threshold >
			   100000 {_ = vm.RaiseError(L, "TeleportThreshold must be between 0 and 100000"); return true}
		service.teleport_threshold = f32(threshold)
		return true
	}
	if key == "RelevancyDistance" {
		distance := vm.ArgNumber(L, value_index)
		if distance < 0 ||
		   distance >
			   1000000 {_ = vm.RaiseError(L, "RelevancyDistance must be between 0 and 1000000"); return true}
		service.relevancy_distance = f32(distance)
		return true
	}
	if key == "LODNearFraction" {
		fraction := vm.ArgNumber(L, value_index)


		if fraction < 0 ||
		   fraction >
			   1 {_ = vm.RaiseError(L, "LODNearFraction must be between 0 and 1"); return true}
		service.lod_near_fraction = f32(fraction)
		return true
	}
	if key == "LODFarInterval" {
		interval := vm.ArgNumber(L, value_index)
		if interval < 1 ||
		   interval >
			   64 {_ = vm.RaiseError(L, "LODFarInterval must be between 1 and 64"); return true}
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
			if len(property) == 0 || len(property) > 64 || property == "Parent" {
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
		if id == 0 {vm.PushNil(L)} else {vm.PushNumber(L, f64(id))}
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
		entity.owner_locked = true
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
		token := vm.ArgString(L, 2)
		if len(token) >
		   256 {return vm.RaiseError(L, "join token must be 256 characters or fewer"), true}
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


		vm.PushNumber(L, f64(service.assets_sent)); vm.SetField(L, -2, "assetsSent")
		vm.PushNumber(L, f64(service.assets_received)); vm.SetField(L, -2, "assetsReceived")
		vm.PushNumber(L, f64(service.asset_rejections)); vm.SetField(L, -2, "assetRejections")
		vm.PushBoolean(L, service.asset_table_complete); vm.SetField(L, -2, "assetTableComplete")


		vm.PushBoolean(L, service.terrain_header_seen); vm.SetField(L, -2, "terrainHeaderSeen")
		vm.PushNumber(
			L,
			f64(service.terrain_batches_received),
		); vm.SetField(L, -2, "terrainBatchesReceived")
		vm.PushNumber(
			L,
			f64(service.terrain_cells_received),
		); vm.SetField(L, -2, "terrainCellsReceived")
		vm.PushNumber(
			L,
			f64(service.terrain_cells_declared),
		); vm.SetField(L, -2, "terrainCellsDeclared")
		vm.PushNumber(L, f64(service.terrain_rejections)); vm.SetField(L, -2, "terrainRejections")
		vm.PushBoolean(
			L,
			service.terrain_table_complete,
		); vm.SetField(L, -2, "terrainTableComplete")


		vm.PushNumber(L, f64(service.rejected_packets)); vm.SetField(L, -2, "rejectedPackets")
		vm.PushNumber(L, f64(service.version_mismatches)); vm.SetField(L, -2, "versionMismatches")
		vm.PushNumber(L, f64(service.schema_mismatches)); vm.SetField(L, -2, "schemaMismatches")
		vm.PushNumber(L, f64(service.auth_failures)); vm.SetField(L, -2, "authFailures")


		vm.PushBoolean(L, service.handshake_complete); vm.SetField(L, -2, "handshakeComplete")
		vm.PushBoolean(L, service.scene_ready); vm.SetField(L, -2, "sceneReady")
		vm.PushBoolean(L, service.replication_finished); vm.SetField(L, -2, "replicationFinished")
		vm.PushNumber(L, f64(service.handshake_status)); vm.SetField(L, -2, "handshakeStatus")
		vm.PushNumber(L, f64(Replication_Protocol_Version)); vm.SetField(L, -2, "protocolVersion")
		vm.PushNumber(
			L,
			f64(service.server_capabilities),
		); vm.SetField(L, -2, "serverCapabilities")


		vm.PushNumber(L, f64(service.time_offset)); vm.SetField(L, -2, "timeOffset")
		vm.PushNumber(
			L,
			f64(service.unchanged_states_skipped),
		); vm.SetField(L, -2, "unchangedStatesSkipped")
		vm.PushNumber(L, f64(service.tick)); vm.SetField(L, -2, "tick")


		vm.PushNumber(L, f64(service.states_applied)); vm.SetField(L, -2, "statesApplied")
		vm.PushNumber(L, f64(service.acks_sent)); vm.SetField(L, -2, "acksSent")
		vm.PushNumber(L, f64(service.acks_received)); vm.SetField(L, -2, "acksReceived")
		vm.PushNumber(L, f64(service.char_acks_received)); vm.SetField(L, -2, "charAcksReceived")


		vm.PushNumber(L, f64(service.adaptive_scale)); vm.SetField(L, -2, "adaptiveScale")
		vm.PushNumber(
			L,
			f64(service.bandwidth_budget),
		); vm.SetField(L, -2, "effectiveBandwidthBudget")
		vm.PushNumber(L, f64(service.snapshot_rate)); vm.SetField(L, -2, "effectiveSnapshotRate")
		vm.PushNumber(
			L,
			f64(service.owned_states_accepted),
		); vm.SetField(L, -2, "ownedStatesAccepted")
		vm.PushNumber(
			L,
			f64(service.owned_states_rejected),
		); vm.SetField(L, -2, "ownedStatesRejected")
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
		properties = []string {
			"SnapshotRate",
			"BandwidthBudget",
			"InterpolationDelayTicks",
			"TeleportThreshold",
			"RelevancyDistance",
			"LODNearFraction",
			"LODFarInterval",
			"EventReceived",
			"Connected",
			"SceneReady",
		},
		events = []string{"EventReceived"},
		methods = []string {
			"StartServer",
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
			"GetActiveReplicator",
			"SetJoinToken",
		},
	)
}
