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
	last_tick:              u32,
	last_accepted_ms:       u32,
	last_accepted_position: datatypes.Vector3,
	force_correction:       bool,
	samples:                [dynamic]Replication_Sample,
	sample_age:             f32,
}

Replication_Peer :: struct {
	peer:            ^enet.Peer,
	player:          ^Player,
	known:           map[u32]u32,
	initialized:     map[u32]bool,
	bytes_this_tick: u32,
}

Replication_Event_Callback :: struct {
	name:      string,
	reference: i32,
}

Replication_Group_Member :: struct {
	name:    string,
	user_id: u32,
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
	entities:                  [dynamic]Replication_Entity,
	suppressed:                map[^classes.Object]bool,
	next_id:                   u32,
	next_user_id:              u32,
	tick:                      u32,
	elapsed:                   f32,
	snapshot_rate:             f32,
	interpolation_delay_ticks: f32,
	teleport_threshold:        f32,
	relevancy_distance:       f32,
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
	malformed_packets:         u64,
	owned_states_accepted:     u64,
	owned_states_rejected:     u64,
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
	service.bandwidth_budget = 48 * 1024
	service.next_id = 1
	service.next_user_id = 1
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
		for item in service.peers {
			if item.peer != nil {enet.peer_disconnect_now(item.peer, 0)}
			if L != nil && item.player != nil {Players_Remove(players, L, item.player)}
			delete(item.known)
			delete(item.initialized)
		}
		enet.host_destroy(service.host)
		service.host = nil
	}
	delete(service.peers)
	service.peers = nil
	client_objects: [dynamic]^classes.Object
	if service.mode == .Client && L != nil {
		for item in service.entities {
			if item.object == nil || item.object.destroyed {continue}
			if classes.Is_A(item.object, "CharacterModel") {
				CharacterService_Unbind(service.data_model, cast(^classes.CharacterModel)item.object, L)
			}
			append(&client_objects, item.object)
		}
	}
	for item in service.entities {delete(item.recipients); delete(item.samples)}
	delete(service.entities)
	service.entities = nil
	for object in client_objects {
		if !object.destroyed {classes.Destroy_Hierarchy(object)}
	}
	delete(client_objects)
	for member in service.group_members {delete(member.name)}
	delete(service.group_members)
	service.group_members = nil
	delete(service.suppressed)
	service.suppressed = nil
	service.remote = nil
	service.mode = .Stopped
	service.connected = false
	if service.data_model != nil && service.data_model.registry != nil && service.data_model.registry.vm_state != nil && service.data_model.registry.vm_state.L != nil {
		vm.AddGlobal_Boolean(service.data_model.registry.vm_state, "IsServer", target.IS_SERVER)
		vm.AddGlobal_Boolean(service.data_model.registry.vm_state, "IsClient", target.IS_CLIENT)
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
		return true
	}
	if key == "BandwidthBudget" {
		budget := vm.ArgNumber(L, value_index)
		if budget < 1024 || budget > 16 * 1024 * 1024 || f64(u32(budget)) != budget {
			_ = vm.RaiseError(L, "BandwidthBudget must be between 1024 and 16777216")
			return true
		}
		service.bandwidth_budget = u32(budget)
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
		if ok {classes.Push_Object(L, object)} else {vm.PushNil(L)}
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
			   property == "Parent" ||
			   property == "Source" {
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
		for item, index in service.entities {if item.id == id && id != 0 {delete(item.recipients); delete(item.samples); ordered_remove(&service.entities, index); break}}
		for &connection in service.peers {
			if connection.known[id] != 0 {
				bytes: [dynamic]u8
				replication_put_u32(&bytes, id)
				_ = replication_send(service, connection.peer, 8, bytes[:])
				delete(bytes)
				delete_key(&connection.known, id)
				delete_key(&connection.initialized, id)
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
		entity.owner_id = owner_id
		if classes.Is_A(instance, "Part") {
			part := cast(^classes.Part)instance
			entity.last_accepted_position = datatypes.Vector3 {
				part.cframe.x,
				part.cframe.y,
				part.cframe.z,
			}
			entity.last_accepted_ms = enet.time_get()
		}
		bytes: [dynamic]u8
		replication_put_u32(&bytes, entity.id)
		replication_put_u32(&bytes, owner_id)
		for connection in service.peers {if connection.known[entity.id] != 0 {_ = replication_send(service, connection.peer, 10, bytes[:])}}
		delete(bytes)
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
	case "GetStats":
		vm.NewTable(L, 0, 12)
		vm.PushBoolean(L, service.connected); vm.SetField(L, -2, "connected")
		vm.PushInteger(L, i64(len(service.entities))); vm.SetField(L, -2, "replicatedEntities")
		vm.PushInteger(L, i64(len(service.peers))); vm.SetField(L, -2, "peers")
		vm.PushInteger(L, i64(service.packets_sent)); vm.SetField(L, -2, "packetsSent")
		vm.PushNumber(L, f64(service.bytes_sent)); vm.SetField(L, -2, "bytesSent")
		vm.PushInteger(L, i64(service.packets_received)); vm.SetField(L, -2, "packetsReceived")
		vm.PushInteger(L, i64(service.malformed_packets)); vm.SetField(L, -2, "malformedPackets")
		vm.PushNumber(L, f64(service.tick)); vm.SetField(L, -2, "tick")
		vm.PushNumber(
			L,
			f64(service.owned_states_accepted),
		); vm.SetField(L, -2, "ownedStatesAccepted")
		vm.PushNumber(
			L,
			f64(service.owned_states_rejected),
		); vm.SetField(L, -2, "ownedStatesRejected")
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
