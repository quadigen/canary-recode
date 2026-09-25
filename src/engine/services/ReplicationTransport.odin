#+build !js
package services

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import signals "../signals"
import vm "../vm"
import "core:fmt"
import "core:strings"
import "base:runtime"
import enet "vendor:ENet"

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

replication_send :: proc(
	service: ^ReplicatorService,
	peer: ^enet.Peer,
	kind: u8,
	payload: []u8,
	reliable: bool = true,
) -> bool {
	if peer == nil || service.host == nil || len(payload) > 1048576 {return false}
	if service.mode == .Server && kind != 2 {
		for &connection in service.peers {
			if connection.peer != peer {continue}
			if u64(connection.bytes_this_tick) + u64(len(payload)) + 5 >
			   u64(service.bandwidth_budget) {
				service.bandwidth_drops += 1
				return false
			}
			break
		}
	}
	bytes := make([dynamic]u8, 0, len(payload) + 5)
	defer delete(bytes)
	append(&bytes, 'K', 'R', 'P', 5, kind)
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
	if service.mode == .Server && kind != 2 {
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

replication_receive :: proc(
	service: ^ReplicatorService,
	L: ^vm.State,
	peer: ^enet.Peer,
	data: []u8,
) {
	if len(data) < 5 || data[0] != 'K' || data[1] != 'R' || data[2] != 'P' || data[3] != 5 {
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
		fmt.printf("Network client connected as %s (user %d)\n", name, id)
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
			entity.last_tick = tick
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
		if reader.offset + 8 > len(reader.data) {reader.valid = false; break}
		anchored := reader.data[reader.offset] != 0
		can_collide := reader.data[reader.offset + 1] != 0
		material := enums.Material(reader.data[reader.offset + 2])
		shape := enums.PartType(reader.data[reader.offset + 3])
		reader.offset += 4
		ack := replication_read_u32(&reader)
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
			if local_character && object.name == "HumanoidRootPart" {
				if owned {
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
				} else {
					character_reconcile(service, entity, frame, ack)
				}
			} else if local_character {
				if entity.last_tick == 0 {
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
				if snap {clear(&entity.samples)}
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
			entity.last_tick = tick
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
			append(&service.entities, Replication_Entity{id = id, object = existing})
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
			append(&service.entities, Replication_Entity{id = id, object = existing})
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
		append(&service.entities, Replication_Entity{id = id, object = object})
		if parent != nil &&
		   classes.Is_A(parent, "CharacterModel") &&
		   object.name == "HumanoidRootPart" {
			CharacterService_Bind(service.data_model, cast(^classes.CharacterModel)parent, L)
		}
	case 8:
		if service.mode != .Client || peer != service.remote {return}
		id := replication_read_u32(&reader)
		for item, index in service.entities {
			if item.id == id {
				if item.object != nil && classes.Is_A(item.object, "CharacterModel") {
					CharacterService_Unbind(
						service.data_model,
						cast(^classes.CharacterModel)item.object,
						L,
					)
				}
				if item.object != nil &&
				   !item.object.destroyed {classes.Destroy_Hierarchy(item.object)}
				delete(item.recipients)
				delete(item.samples)
				ordered_remove(&service.entities, index)
				break
			}
		}
	case 9:
		character_receive_input(service, peer, &reader)
	case 10:
		if service.mode != .Client || peer != service.remote {return}
		id := replication_read_u32(&reader)
		owner_id := replication_read_u32(&reader)
		for &item in service.entities {
			if item.id == id {
				if item.owner_id != owner_id {
					clear(&item.samples)
					item.sample_age = 0
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
		dx := frame.x - part.cframe.x
		dy := frame.y - part.cframe.y
		dz := frame.z - part.cframe.z
		if dx * dx + dy * dy + dz * dz > 128 * 128 {
			service.owned_states_rejected += 1
			payload := []u8{u8(id), u8(id >> 8), u8(id >> 16), u8(id >> 24)}
			_ = replication_send(service, connection.peer, 15, payload)
			return
		}
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
		reader.valid = false
	}
	if !reader.valid || reader.offset != len(reader.data) {service.malformed_packets += 1}
}

Replication_Step :: proc(service: ^ReplicatorService, L: ^vm.State, delta_time: f32) {
	if service == nil || service.host == nil {return}
	remote_invoke_timeouts(service, L)
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
				character_service := cast(^CharacterService)Ensure_Service(
					service.data_model.registry,
					"CharacterService",
				)
				if character_service != nil &&
				   player != nil {CharacterService_Load(character_service, player)}
				append(
					&service.peers,
					Replication_Peer {
						peer = event.peer,
						player = player,
						known = make(map[u32]u32),
						initialized = make(map[u32]bool),
						state_hashes = make(map[u32]u64),
						property_hashes = make(map[u32]u64),
					},
				)
				bytes: [dynamic]u8
				replication_put_u32(&bytes, id)
				replication_put_string(&bytes, name)
				_ = replication_send(service, event.peer, 2, bytes[:])
				delete(bytes)
				service.connected = true
				fmt.printf("Network server accepted %s (user %d)\n", name, id)
			} else if event.peer == service.remote {
				fmt.println("Network transport connected; waiting for the server handshake")
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
						delete(item.initialized)
						delete(item.state_hashes)
						delete(item.property_hashes)
						ordered_remove(&service.peers, index)
						break
					}
				}
				service.connected = len(service.peers) > 0
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
	service.elapsed += delta_time
	if service.mode == .Server && service.elapsed >= 1 / service.snapshot_rate {
		service.elapsed = 0
		replication_sync(service)
	} else if service.mode == .Client &&
	          !service.connected &&
	          service.remote != nil &&
	          service.elapsed >= 10 {
		fmt.eprintln("Network client connection timed out")
		enet.peer_reset(service.remote)
		service.remote = nil
		service.elapsed = 0
	} else if service.mode == .Client && service.connected && service.elapsed >= 1.0 / 30.0 {
		service.elapsed = 0
		service.tick += 1
		_ = character_send_input(service)
		players := cast(^Players)DataModel_Get_Service(service.data_model, "Players")
		if players != nil && players.local_player != nil {
			for &entity in service.entities {
				if entity.owner_id ==
				   players.local_player.user_id {_ = replication_send_owned_state(service, &entity)}
			}
		}
	}
	replication_render_interpolated(service, delta_time)
	enet.host_flush(service.host)
}
