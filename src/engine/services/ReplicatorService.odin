package services

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import signals "../signals"
import vm "../vm"
import "core:fmt"
import "core:strings"
import enet "vendor:ENet"

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
		for item in service.peers {
			if item.peer != nil {enet.peer_disconnect_now(item.peer, 0)}
			if L != nil && item.player != nil {Players_Remove(players, L, item.player)}
			delete(item.known)
		}
		enet.host_destroy(service.host)
		service.host = nil
	}
	delete(service.peers)
	service.peers = nil
	client_objects: [dynamic]^classes.Object
	if service.mode == .Client && L != nil {
		for item in service.entities {if item.object != nil && !item.object.destroyed {append(&client_objects, item.object)}}
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

replication_start :: proc(
	service: ^ReplicatorService,
	address: string,
	port: u16,
	mode: Replication_Mode,
) -> bool {
	replication_stop(service)
	if replication_enet_users == 0 && enet.initialize() != 0 {return false}
	replication_enet_users += 1
	service.enet_initialized = true
	endpoint := enet.Address {
		port = port,
	}
	if mode == .Server {
		if address != "" && address != "0.0.0.0" {
			name := strings.clone_to_cstring(address)
			defer delete(name)
			if enet.address_set_host(&endpoint, name) !=
			   0 {replication_stop(service); return false}
		}
		service.host = enet.host_create(&endpoint, 32, 2, 0, 0)
	} else {
		service.host = enet.host_create(nil, 1, 2, 0, 0)
		if service.host != nil {
			name := strings.clone_to_cstring(address)
			defer delete(name)
			if enet.address_set_host(&endpoint, name) == 0 {
				service.remote = enet.host_connect(service.host, &endpoint, 2, 0)
			}
		}
	}
	if service.host == nil || (mode == .Client && service.remote == nil) {
		replication_stop(service)
		return false
	}
	service.mode = mode
	return true
}

replication_put_u32 :: proc(bytes: ^[dynamic]u8, value: u32) {
	for shift := 0; shift < 32; shift += 8 {append(bytes, u8(value >> u32(shift)))}
}

replication_put_string :: proc(bytes: ^[dynamic]u8, value: string) {
	replication_put_u32(bytes, u32(len(value)))
	for byte in transmute([]u8)value {append(bytes, byte)}
}

replication_put_f32 :: proc(bytes: ^[dynamic]u8, value: f32) {
	replication_put_u32(bytes, transmute(u32)value)
}

Replication_Reader :: struct {
	data:   []u8,
	offset: int,
	valid:  bool,
}

replication_read_u32 :: proc(reader: ^Replication_Reader) -> u32 {
	if !reader.valid || reader.offset + 4 > len(reader.data) {reader.valid = false; return 0}
	value: u32
	for shift := 0; shift < 32; shift += 8 {
		value |= u32(reader.data[reader.offset]) << u32(shift)
		reader.offset += 1
	}
	return value
}

replication_read_string :: proc(reader: ^Replication_Reader) -> string {
	size := replication_read_u32(reader)
	if !reader.valid ||
	   size > 1048576 ||
	   int(size) > len(reader.data) - reader.offset {reader.valid = false; return ""}
	value := string(reader.data[reader.offset:reader.offset + int(size)])
	reader.offset += int(size)
	return value
}

replication_read_f32 :: proc(reader: ^Replication_Reader) -> f32 {
	return transmute(f32)replication_read_u32(reader)
}

replication_encode_value :: proc(
	L: ^vm.State,
	index: int,
	bytes: ^[dynamic]u8,
	depth: int,
) -> bool {
	if depth > 8 || len(bytes^) > 1048576 {return false}
	#partial switch vm.TypeOf(L, index) {
	case .Nil, .None:
		append(bytes, 0)
	case .Boolean:
		append(bytes, vm.ArgBoolean(L, index) ? u8(2) : u8(1))
	case .Number, .Integer:
		append(bytes, 3)
		bits := transmute(u64)vm.ArgNumber(L, index)
		for shift := 0; shift < 64; shift += 8 {append(bytes, u8(bits >> u64(shift)))}
	case .String:
		append(bytes, 4)
		value, _ := vm.ToString(L, index)
		replication_put_string(bytes, value)
	case .Table:
		append(bytes, 5)
		count_offset := len(bytes^)
		replication_put_u32(bytes, 0)
		count: u32
		table_index := index < 0 ? vm.StackTop(L) + index + 1 : index
		vm.PushNil(L)
		for vm.Next(L, table_index) {
			if count >= 256 ||
			   (vm.TypeOf(L, -2) != .String &&
					   vm.TypeOf(L, -2) != .Number &&
					   vm.TypeOf(L, -2) != .Integer) {
				vm.Pop(L)
				vm.Pop(L)
				return false
			}
			if !replication_encode_value(L, -2, bytes, depth + 1) ||
			   !replication_encode_value(L, -1, bytes, depth + 1) {
				vm.Pop(L)
				vm.Pop(L)
				return false
			}
			count += 1
			vm.Pop(L)
		}
		for i in 0 ..< 4 {bytes^[count_offset + i] = u8(count >> u32(i * 8))}
	case .Vector:
		append(bytes, 6)
		x, y, z := vm.ArgVector3(L, index)
		replication_put_f32(bytes, x)
		replication_put_f32(bytes, y)
		replication_put_f32(bytes, z)
	case .Userdata:
		binding := vm.UserdataBindingOf(L, index)
		if binding == nil {return false}
		if binding.name == "Color3" {
			append(bytes, 7)
			color := cast(^datatypes.Color3)vm.UserdataValue(L, index)
			replication_put_f32(bytes, color.R)
			replication_put_f32(bytes, color.G)
			replication_put_f32(bytes, color.B)
		} else if binding.name == "CFrame" {
			append(bytes, 8)
			frame := cast(^datatypes.CFrame)vm.UserdataValue(L, index)
			values := [12]f32 {
				frame.x,
				frame.y,
				frame.z,
				frame.r00,
				frame.r01,
				frame.r02,
				frame.r10,
				frame.r11,
				frame.r12,
				frame.r20,
				frame.r21,
				frame.r22,
			}
			for value in values {replication_put_f32(bytes, value)}
		} else {return false}
	case:
		return false
	}
	return len(bytes^) <= 1048576
}

replication_decode_value :: proc(
	L: ^vm.State,
	reader: ^Replication_Reader,
	datatype_registry: ^datatypes.Registry,
	depth: int,
) {
	if !reader.valid ||
	   depth > 8 ||
	   reader.offset >= len(reader.data) {reader.valid = false; vm.PushNil(L); return}
	tag := reader.data[reader.offset]
	reader.offset += 1
	switch tag {
	case 0:
		vm.PushNil(L)
	case 1, 2:
		vm.PushBoolean(L, tag == 2)
	case 3:
		if reader.offset + 8 > len(reader.data) {reader.valid = false; vm.PushNil(L); return}
		bits: u64
		for shift := 0;
		    shift < 64;
		    shift += 8 {bits |= u64(reader.data[reader.offset]) << u64(shift); reader.offset += 1}
		vm.PushNumber(L, transmute(f64)bits)
	case 4:
		vm.PushString(L, replication_read_string(reader))
	case 5:
		count := replication_read_u32(reader)
		if count > 256 {reader.valid = false; vm.PushNil(L); return}
		vm.NewTable(L, 0, int(count))
		for _ in 0 ..< int(count) {
			replication_decode_value(L, reader, datatype_registry, depth + 1)
			replication_decode_value(L, reader, datatype_registry, depth + 1)
			if !reader.valid {vm.Pop(L); vm.Pop(L); break}
			if vm.TypeOf(L, -2) == .String {
				key, _ := vm.ToString(L, -2)
				vm.PushValue(L, -1)
				vm.SetField(L, -4, key)
			} else if vm.IsNumber(L, -2) {
				key, valid := vm.ToNumber(L, -2)
				if !valid || key < 1 || key > 65535 || f64(i64(key)) != key {reader.valid = false}
				if reader.valid {
					vm.PushValue(L, -1)
					vm.RawSetIndex(L, -4, int(key))
				}
			} else {reader.valid = false}
			vm.Pop(L)
			vm.Pop(L)
		}
	case 6:
		x := replication_read_f32(reader)
		y := replication_read_f32(reader)
		z := replication_read_f32(reader)
		vm.PushVector3(L, x, y, z)
	case 7:
		color := datatypes.Color3 {
			R = replication_read_f32(reader),
			G = replication_read_f32(reader),
			B = replication_read_f32(reader),
		}
		datatypes.Push_Color3(L, datatype_registry, color)
	case 8:
		frame := datatypes.CFrame{}
		frame.x = replication_read_f32(reader)
		frame.y = replication_read_f32(reader)
		frame.z = replication_read_f32(reader)
		frame.r00 = replication_read_f32(reader)
		frame.r01 = replication_read_f32(reader)
		frame.r02 = replication_read_f32(reader)
		frame.r10 = replication_read_f32(reader)
		frame.r11 = replication_read_f32(reader)
		frame.r12 = replication_read_f32(reader)
		frame.r20 = replication_read_f32(reader)
		frame.r21 = replication_read_f32(reader)
		frame.r22 = replication_read_f32(reader)
		datatypes.Push_CFrame(L, datatype_registry, frame)
	case:
		reader.valid = false; vm.PushNil(L)
	}
}

replication_send :: proc(
	service: ^ReplicatorService,
	peer: ^enet.Peer,
	kind: u8,
	payload: []u8,
	reliable: bool = true,
) -> bool {
	if peer == nil || service.host == nil || len(payload) > 1048576 {return false}
	if service.mode == .Server && kind == 5 {
		for &connection in service.peers {
			if connection.peer != peer {continue}
			if u64(connection.bytes_this_tick) + u64(len(payload)) + 5 >
			   u64(service.bandwidth_budget) {return false}
			break
		}
	}
	bytes := make([dynamic]u8, 0, len(payload) + 5)
	defer delete(bytes)
	append(&bytes, 'K', 'R', 'P', 4, kind)
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
	if service.mode == .Server && kind == 5 {
		for &connection in service.peers {
			if connection.peer == peer {connection.bytes_this_tick += u32(len(bytes)); break}
		}
	}
	return true
}

replication_entity_id :: proc(service: ^ReplicatorService, object: ^classes.Object) -> u32 {
	for item in service.entities {if item.object == object {return item.id}}
	return 0
}

replication_entity_object :: proc(service: ^ReplicatorService, id: u32) -> ^classes.Object {
	for item in service.entities {if item.id == id {return item.object}}
	return nil
}

replication_entity_by_id :: proc(service: ^ReplicatorService, id: u32) -> ^Replication_Entity {
	for &item in service.entities {if item.id == id {return &item}}
	return nil
}

replication_forget_destroyed :: proc(service: ^ReplicatorService, object: ^classes.Object) {
	if service == nil || object == nil {return}
	for &connection in service.peers {
		if connection.player != nil &&
		   &connection.player.object == object {connection.player = nil}
	}
	delete_key(&service.suppressed, object)
	for item, index in service.entities {
		if item.object != object {continue}
		if service.mode == .Server {
			for &connection in service.peers {
				if connection.known[item.id] == 0 {continue}
				bytes: [dynamic]u8
				replication_put_u32(&bytes, item.id)
				_ = replication_send(service, connection.peer, 8, bytes[:])
				delete(bytes)
				delete_key(&connection.known, item.id)
			}
		}
		delete(item.recipients)
		delete(item.samples)
		ordered_remove(&service.entities, index)
		break
	}
}

replication_register :: proc(service: ^ReplicatorService, object: ^classes.Object) -> u32 {
	if object == nil || object.destroyed || service.mode != .Server {return 0}
	delete_key(&service.suppressed, object)
	id := replication_entity_id(service, object)
	if id != 0 {return id}
	id = service.next_id
	service.next_id += 1
	append(&service.entities, Replication_Entity{id = id, object = object})
	object.network_id = id
	return id
}

replication_entity :: proc(
	service: ^ReplicatorService,
	object: ^classes.Object,
) -> ^Replication_Entity {
	for &item in service.entities {if item.object == object {return &item}}
	return nil
}

replication_schema :: proc(
	service: ^ReplicatorService,
	class_name: string,
) -> ^Replication_Schema {
	for &schema in service.schemas {if schema.class_name == class_name {return &schema}}
	return nil
}

replication_schema_has :: proc(schema: ^Replication_Schema, property: string) -> bool {
	if schema == nil {return false}
	for item in schema.properties {if item == property {return true}}
	return false
}

replication_builtin_class :: proc(class_name: string) -> bool {
	return(
		class_name == "Part" ||
		class_name == "MeshPart" ||
		class_name == "Model" ||
		class_name == "Folder" ||
		class_name == "BoolValue" ||
		class_name == "IntValue" ||
		class_name == "NumberValue" ||
		class_name == "StringValue" ||
		class_name == "Vector3Value" ||
		class_name == "Color3Value" ||
		class_name == "CFrameValue" \
	)
}

replication_group_contains :: proc(
	service: ^ReplicatorService,
	user_id: u32,
	name: string,
) -> bool {
	for member in service.group_members {if member.user_id == user_id && member.name == name {return true}}
	return false
}

replication_visible :: proc(
	service: ^ReplicatorService,
	connection: ^Replication_Peer,
	object: ^classes.Object,
) -> bool {
	if !replication_in_scope(service, object) || connection.player == nil {return false}
	for current := object;
	    current != nil && !classes.Is_A(current, "Service");
	    current = current.parent {
		if !current.can_replicate {return false}
		switch current.replication_mode {
		case .Never, .ServerOnly:
			return false
		case .OwnerOnly:
			entity := replication_entity(service, current)
			if entity == nil || entity.owner_id != connection.player.user_id {return false}
		case .Manual:
			entity := replication_entity(service, current)
			if entity == nil || !entity.recipients[connection.player.user_id] {return false}
		case .Automatic:
		}
		if current.replication_group != "" &&
		   !replication_group_contains(
				   service,
				   connection.player.user_id,
				   current.replication_group,
			   ) {return false}
	}
	return true
}

replication_send_spawn :: proc(
	service: ^ReplicatorService,
	peer: ^enet.Peer,
	object: ^classes.Object,
) -> bool {
	id := replication_entity_id(service, object)
	if id == 0 {return false}
	parent_id := replication_entity_id(service, object.parent)
	bytes: [dynamic]u8
	defer delete(bytes)
	replication_put_u32(&bytes, id)
	replication_put_u32(&bytes, parent_id)
	replication_put_string(&bytes, classes.Get_Class_Name(object))
	replication_put_string(&bytes, object.name)
	replication_put_string(
		&bytes,
		parent_id == 0 && object.parent != nil ? object.parent.name : "",
	)
	if !replication_send(service, peer, 7, bytes[:]) {return false}
	entity := replication_entity(service, object)
	if entity != nil && entity.owner_id != 0 {
		ownership: [dynamic]u8
		replication_put_u32(&ownership, id)
		replication_put_u32(&ownership, entity.owner_id)
		_ = replication_send(service, peer, 10, ownership[:])
		delete(ownership)
	}
	return true
}

replication_send_owned_state :: proc(
	service: ^ReplicatorService,
	entity: ^Replication_Entity,
) -> bool {
	if entity == nil ||
	   entity.object == nil ||
	   entity.object.destroyed ||
	   !classes.Is_A(entity.object, "Part") {return false}
	part := cast(^classes.Part)entity.object
	if part.anchored {return false}
	bytes: [dynamic]u8
	defer delete(bytes)
	replication_put_u32(&bytes, entity.id)
	replication_put_u32(&bytes, service.tick)
	values := [12]f32 {
		part.cframe.x,
		part.cframe.y,
		part.cframe.z,
		part.cframe.r00,
		part.cframe.r01,
		part.cframe.r02,
		part.cframe.r10,
		part.cframe.r11,
		part.cframe.r12,
		part.cframe.r20,
		part.cframe.r21,
		part.cframe.r22,
	}
	for value in values {replication_put_f32(&bytes, value)}
	return replication_send(service, service.remote, 11, bytes[:], false)
}

replication_send_part_state :: proc(
	service: ^ReplicatorService,
	peer: ^enet.Peer,
	part: ^classes.Part,
) -> bool {
	bytes: [dynamic]u8
	defer delete(bytes)
	append(&bytes, 1)
	replication_put_u32(&bytes, replication_entity_id(service, &part.object))
	replication_put_u32(&bytes, service.tick)
	replication_put_string(&bytes, part.name)
	replication_put_f32(&bytes, part.cframe.x)
	replication_put_f32(&bytes, part.cframe.y)
	replication_put_f32(&bytes, part.cframe.z)
	replication_put_f32(&bytes, part.cframe.r00)
	replication_put_f32(&bytes, part.cframe.r01)
	replication_put_f32(&bytes, part.cframe.r02)
	replication_put_f32(&bytes, part.cframe.r10)
	replication_put_f32(&bytes, part.cframe.r11)
	replication_put_f32(&bytes, part.cframe.r12)
	replication_put_f32(&bytes, part.cframe.r20)
	replication_put_f32(&bytes, part.cframe.r21)
	replication_put_f32(&bytes, part.cframe.r22)
	replication_put_f32(&bytes, part.size.x)
	replication_put_f32(&bytes, part.size.y)
	replication_put_f32(&bytes, part.size.z)
	replication_put_f32(&bytes, part.color.R)
	replication_put_f32(&bytes, part.color.G)
	replication_put_f32(&bytes, part.color.B)
	replication_put_f32(&bytes, f32(part.transparency))
	append(&bytes, part.anchored ? u8(1) : u8(0))
	append(&bytes, part.can_collide ? u8(1) : u8(0))
	return replication_send(service, peer, 5, bytes[:], false)
}

replication_send_property :: proc(
	service: ^ReplicatorService,
	L: ^vm.State,
	peer: ^enet.Peer,
	object: ^classes.Object,
	property: string,
) -> bool {
	if service == nil || L == nil || object == nil || object.destroyed {return false}
	bytes: [dynamic]u8
	defer delete(bytes)
	append(&bytes, 2)
	replication_put_u32(&bytes, replication_entity_id(service, object))
	replication_put_u32(&bytes, service.tick)
	replication_put_string(&bytes, property)
	top := vm.StackTop(L)
	defer vm.SetStackTop(L, top)
	classes.Push_Object(L, object)
	_ = vm.GetField(L, -1, property)
	if !replication_encode_value(L, -1, &bytes, 0) {return false}
	return replication_send(service, peer, 5, bytes[:], false)
}

replication_sync_tree :: proc(service: ^ReplicatorService, object: ^classes.Object) {
	if object == nil || object.destroyed || object == &service.object {return}
	if object != &service.data_model.object &&
	   (replication_builtin_class(classes.Get_Class_Name(object)) ||
			   replication_schema(service, classes.Get_Class_Name(object)) != nil) &&
	   !service.suppressed[object] {
		_ = replication_register(service, object)
	}
	for child in object.children {replication_sync_tree(service, child)}
}

replication_in_scope :: proc(service: ^ReplicatorService, object: ^classes.Object) -> bool {
	if object == nil || object.destroyed {return false}
	workspace := DataModel_Get_Service(service.data_model, "Workspace")
	storage := DataModel_Get_Service(service.data_model, "ReplicatedStorage")
	for current := object; current != nil; current = current.parent {
		if current == workspace || current == storage {return true}
		if current == &service.data_model.object {return false}
	}
	return false
}

replication_sync :: proc(service: ^ReplicatorService) {
	if service.mode != .Server || service.data_model == nil {return}
	workspace := DataModel_Get_Service(service.data_model, "Workspace")
	storage := DataModel_Get_Service(service.data_model, "ReplicatedStorage")
	replication_sync_tree(service, workspace)
	replication_sync_tree(service, storage)
	for &connection in service.peers {
		connection.bytes_this_tick = 0
		for item in service.entities {
			if !replication_visible(service, &connection, item.object) ||
			   service.suppressed[item.object] {continue}
			parent_id := replication_entity_id(service, item.object.parent)
			if parent_id != 0 && connection.known[parent_id] == 0 {continue}
			if connection.known[item.id] == parent_id + 1 {continue}
			if connection.known[item.id] != 0 {
				bytes: [dynamic]u8
				replication_put_u32(&bytes, item.id)
				_ = replication_send(service, connection.peer, 8, bytes[:])
				delete(bytes)
			}
			if replication_send_spawn(
				service,
				connection.peer,
				item.object,
			) {connection.known[item.id] = parent_id + 1}
		}
		for item in service.entities {
			if connection.known[item.id] == 0 {continue}
			if replication_visible(service, &connection, item.object) &&
			   !service.suppressed[item.object] {continue}
			bytes: [dynamic]u8
			replication_put_u32(&bytes, item.id)
			_ = replication_send(service, connection.peer, 8, bytes[:])
			delete(bytes)
			delete_key(&connection.known, item.id)
		}
		for item in service.entities {
			if connection.known[item.id] == 0 ||
			   item.object == nil ||
			   item.object.destroyed {continue}
			if classes.Is_A(item.object, "Part") {
				_ = replication_send_part_state(
					service,
					connection.peer,
					cast(^classes.Part)item.object,
				)
			} else {
				_ = replication_send_property(
					service,
					service.data_model.registry.vm_state.L,
					connection.peer,
					item.object,
					"Name",
				)
				if classes.Is_A(item.object, "ValueBase") {
					_ = replication_send_property(
						service,
						service.data_model.registry.vm_state.L,
						connection.peer,
						item.object,
						"Value",
					)
				}
			}
			schema := replication_schema(service, classes.Get_Class_Name(item.object))
			if schema != nil {
				for property in schema.properties {
					if property != "Name" && property != "Value" {
						_ = replication_send_property(
							service,
							service.data_model.registry.vm_state.L,
							connection.peer,
							item.object,
							property,
						)
					}
				}
			}
		}
	}
	for index := len(service.entities) - 1; index >= 0; index -= 1 {
		item := service.entities[index]
		if !replication_in_scope(service, item.object) || service.suppressed[item.object] {
			if item.object != nil && !item.object.destroyed {item.object.network_id = 0}
			delete(item.recipients)
			delete(item.samples)
			ordered_remove(&service.entities, index)
		}
	}
	service.tick += 1
}

replication_receive :: proc(
	service: ^ReplicatorService,
	L: ^vm.State,
	peer: ^enet.Peer,
	data: []u8,
) {
	if len(data) < 5 || data[0] != 'K' || data[1] != 'R' || data[2] != 'P' || data[3] != 4 {
		service.malformed_packets += 1
		return
	}
	reader := Replication_Reader {
		data  = data[5:],
		valid = true,
	}
	switch data[4] {
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
		if entity.last_tick != 0 && transmute(i32)(tick - entity.last_tick) < 0 {return}
		object := entity.object
		if subtype == 2 {
			schema := replication_schema(service, classes.Get_Class_Name(object))
			if name != "Name" &&
			   (name != "Value" || !classes.Is_A(object, "ValueBase")) &&
			   !replication_schema_has(schema, name) {reader.valid = false; break}
			top := vm.StackTop(L)
			defer vm.SetStackTop(L, top)
			classes.Push_Object(L, object)
			replication_decode_value(L, &reader, service.signal_registry.datatypes, 0)
			if reader.valid {
				vm.SetField(L, -2, name)
				entity.last_tick = tick
			}
			break
		}
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
		if reader.offset + 2 > len(reader.data) {reader.valid = false; break}
		anchored := reader.data[reader.offset] != 0
		can_collide := reader.data[reader.offset + 1] != 0
		reader.offset += 2
		if reader.valid {
			players := cast(^Players)DataModel_Get_Service(service.data_model, "Players")
			owned :=
				players != nil &&
				players.local_player != nil &&
				entity.owner_id == players.local_player.user_id
			if !owned || entity.force_correction {
				part.cframe = frame
				part.position = datatypes.Vector3{frame.x, frame.y, frame.z}
				entity.force_correction = false
			}
			part.size = size
			part.color = color
			part.transparency = f64(transparency)
			part.anchored = anchored
			part.can_collide = can_collide
			classes.Set_Name(object, name)
			entity.last_tick = tick
		}
	case 7:
		if service.mode != .Client || peer != service.remote {return}
		id := replication_read_u32(&reader)
		parent_id := replication_read_u32(&reader)
		class_name := replication_read_string(&reader)
		name := replication_read_string(&reader)
		root_name := replication_read_string(&reader)
		if !reader.valid ||
		   id == 0 ||
		   replication_entity_object(service, id) != nil ||
		   service.data_model == nil {break}
		if root_name != "" && root_name != "Workspace" && root_name != "ReplicatedStorage" {break}
		if !replication_builtin_class(class_name) &&
		   replication_schema(service, class_name) == nil {break}
		parent :=
			parent_id == 0 ? DataModel_Get_Service(service.data_model, root_name) : replication_entity_object(service, parent_id)
		if parent == nil || service.data_model.registry == nil {break}
		object, ok := classes.Push_New(
			service.data_model.registry.classes,
			service.data_model.registry.vm_state,
			class_name,
		)
		if !ok || object == nil {break}
		classes.Set_Name(object, name)
		classes.Set_Parent(object, parent)
		object.network_id = id
		vm.Pop(L)
		append(&service.entities, Replication_Entity{id = id, object = object})
	case 8:
		if service.mode != .Client || peer != service.remote {return}
		id := replication_read_u32(&reader)
		for item, index in service.entities {
			if item.id == id {
				if item.object != nil &&
				   !item.object.destroyed {classes.Destroy_Hierarchy(item.object)}
				delete(item.recipients)
				ordered_remove(&service.entities, index)
				break
			}
		}
	case 10:
		if service.mode != .Client || peer != service.remote {return}
		id := replication_read_u32(&reader)
		owner_id := replication_read_u32(&reader)
		for &item in service.entities {if item.id == id {item.owner_id = owner_id; break}}
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
		if part.anchored || reader.offset + 48 != len(reader.data) {
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
		if !reader.valid ||
		   frame.x != frame.x ||
		   frame.y != frame.y ||
		   frame.z != frame.z ||
		   frame.x > 1e7 ||
		   frame.x < -1e7 ||
		   frame.y > 1e7 ||
		   frame.y < -1e7 ||
		   frame.z > 1e7 ||
		   frame.z < -1e7 {
			service.owned_states_rejected += 1
			return
		}
		now := enet.time_get()
		elapsed_ms := now - entity.last_accepted_ms
		if elapsed_ms > 1000 {elapsed_ms = 1000}
		dx := frame.x - entity.last_accepted_position.x
		dy := frame.y - entity.last_accepted_position.y
		dz := frame.z - entity.last_accepted_position.z
		limit := f32(12) + f32(elapsed_ms) * (256.0 / 1000.0)
		if dx * dx + dy * dy + dz * dz > limit * limit {
			service.owned_states_rejected += 1
			bytes: [dynamic]u8
			replication_put_u32(&bytes, id)
			_ = replication_send(service, peer, 15, bytes[:])
			delete(bytes)
			return
		}
		part.cframe = frame
		part.position = datatypes.Vector3{frame.x, frame.y, frame.z}
		entity.last_accepted_ms = now
		entity.last_accepted_position = part.position
		service.owned_states_accepted += 1
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
	case:
		reader.valid = false
	}
	if !reader.valid || reader.offset != len(reader.data) {service.malformed_packets += 1}
}

Replication_Step :: proc(service: ^ReplicatorService, L: ^vm.State, delta_time: f32) {
	if service == nil || service.host == nil {return}
	event: enet.Event
	for enet.host_service(service.host, &event, 0) > 0 {
		switch event.type {
		case .CONNECT:
			if service.mode == .Server {
				id := service.next_user_id
				service.next_user_id += 1
				name := fmt.tprintf("Player%d", id)
				players := cast(^Players)DataModel_Get_Service(service.data_model, "Players")
				player := Players_Add(players, L, id, name)
				append(
					&service.peers,
					Replication_Peer {
						peer = event.peer,
						player = player,
						known = make(map[u32]u32),
					},
				)
				bytes: [dynamic]u8
				replication_put_u32(&bytes, id)
				replication_put_string(&bytes, name)
				_ = replication_send(service, event.peer, 2, bytes[:])
				delete(bytes)
				service.connected = true
			}
		case .DISCONNECT:
			if service.mode == .Server {
				for item, index in service.peers {
					if item.peer == event.peer {
						players := cast(^Players)DataModel_Get_Service(
							service.data_model,
							"Players",
						)
						if item.player != nil {Players_Remove(players, L, item.player)}
						delete(item.known)
						ordered_remove(&service.peers, index)
						break
					}
				}
				service.connected = len(service.peers) > 0
			} else if event.peer ==
			   service.remote {service.connected = false; service.remote = nil}
		case .RECEIVE:
			if event.packet != nil {
				service.packets_received += 1
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
	service.elapsed += delta_time
	if service.mode == .Server && service.elapsed >= 1 / service.snapshot_rate {
		service.elapsed = 0
		replication_sync(service)
	} else if service.mode == .Client && service.connected && service.elapsed >= 1.0 / 30.0 {
		service.elapsed = 0
		service.tick += 1
		players := cast(^Players)DataModel_Get_Service(service.data_model, "Players")
		if players != nil && players.local_player != nil {
			for &entity in service.entities {
				if entity.owner_id ==
				   players.local_player.user_id {_ = replication_send_owned_state(service, &entity)}
			}
		}
	}
	enet.host_flush(service.host)
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
		for item, index in service.entities {if item.id == id && id != 0 {delete(item.recipients); ordered_remove(&service.entities, index); break}}
		for &connection in service.peers {
			if connection.known[id] != 0 {
				bytes: [dynamic]u8
				replication_put_u32(&bytes, id)
				_ = replication_send(service, connection.peer, 8, bytes[:])
				delete(bytes)
				delete_key(&connection.known, id)
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
