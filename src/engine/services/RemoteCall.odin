package services


import classes "../classes"
import signals "../signals"
import vm "../vm"
import "core:fmt"

REMOTE_FUNCTION_TIMEOUT_MS :: 10_000
REMOTE_MAX_ARGS :: 256
REMOTE_CLIENT_RPC_LIMIT :: 200
REMOTE_CLIENT_RPC_BYTES :: 1536 * 1024
REMOTE_CLIENT_RPC_EXPANDED_BYTES :: 1536 * 1024
UNRELIABLE_REMOTE_MAX_PAYLOAD :: 1000

Remote_Invoke_Pending :: struct {
	entity_id:       u32,
	request_user_id: u32,
	invoke_id:       u32,
	thread:          ^vm.State,
	thread_ref:      i32,
	deadline:        u32,
}

remote_find_player_peer :: proc(
	service: ^ReplicatorService,
	player_object: ^classes.Object,
) -> (
	^Replication_Transport_Peer,
	^Replication_Peer,
) {
	if service == nil || service.mode != .Server {
		return nil, nil
	}
	for &connection in service.peers {
		if connection.peer != nil &&
		   connection.player != nil &&
		   &connection.player.object == player_object {
			return connection.peer, &connection
		}
	}
	return nil, nil
}

remote_common_capabilities :: proc(
	service: ^ReplicatorService,
	peer: ^Replication_Transport_Peer,
) -> u32 {
	if service.mode == .Client {
		return service.client_capabilities & service.server_capabilities
	}
	if peer != nil {
		connection := replication_peer_of(service, peer)
		return(
			service.server_capabilities & connection.client_capabilities if connection != nil else 0 \
		)
	}
	capabilities := service.server_capabilities
	for connection in service.peers {
		if connection.handshake_complete {capabilities &= connection.client_capabilities}
	}
	return capabilities
}

remote_encode_args :: proc(
	L: ^vm.State,
	first, last: int,
	bytes: ^[dynamic]u8,
	capabilities: u32,
) -> bool {
	if last - first + 1 > REMOTE_MAX_ARGS {return false}
	for index := first; index <= last; index += 1 {
		if !replication_encode_value(L, index, bytes, 0, remote_capabilities = capabilities) {
			return false
		}
	}
	return true
}


remote_can_send_to_peer :: proc(
	service: ^ReplicatorService,
	peer: ^Replication_Transport_Peer,
	entity_id: u32,
) -> bool {
	if service == nil || peer == nil || entity_id == 0 {return false}
	switch service.mode {
	case .Client:
		return service.handshake_complete && service.remote == peer
	case .Server:
		connection := replication_peer_of(service, peer)
		entity := replication_entity_by_id(service, entity_id)
		return(
			connection != nil &&
			connection.handshake_complete &&
			connection.known[entity_id] != 0 &&
			entity != nil &&
			entity.object != nil &&
			!entity.object.destroyed &&
			replication_visible(service, connection, entity.object) \
		)
	case .Stopped:
		return false
	}
	return false
}

remote_client_send_permitted :: proc(service: ^ReplicatorService, wire_size, expanded_size: int) -> bool {
	if service.mode != .Client {return true}
	now := transport_time_get()
	if now - service.client_remote_window_ms >= 1000 {
		service.client_remote_window_ms = now
		service.client_remote_window_count = 0
		service.client_remote_window_bytes = 0
		service.client_remote_window_expanded_bytes = 0
	}
	return service.client_remote_window_count < REMOTE_CLIENT_RPC_LIMIT &&
	       wire_size <= REMOTE_CLIENT_RPC_BYTES - int(service.client_remote_window_bytes) &&
	       expanded_size <= REMOTE_CLIENT_RPC_EXPANDED_BYTES - int(service.client_remote_window_expanded_bytes)
}

remote_client_record_send :: proc(service: ^ReplicatorService, wire_size, expanded_size: int) {
	if service.mode != .Client {return}
	service.client_remote_window_count += 1
	service.client_remote_window_bytes += u32(wire_size)
	service.client_remote_window_expanded_bytes += u32(expanded_size)
}

remote_send_fire :: proc(
	service: ^ReplicatorService,
	peer: ^Replication_Transport_Peer,
	entity_id: u32,
	args: []u8,
	unreliable: bool = false,
) -> bool {
	if !remote_can_send_to_peer(service, peer, entity_id) {return false}
	if len(args) > REPLICATION_REMOTE_ZSTD_MAX_EXPANDED - 4 {return false}
	if unreliable {
		if len(args) > UNRELIABLE_REMOTE_MAX_PAYLOAD {return false}
		if (remote_common_capabilities(service, peer) &
			   Replication_Capability_Unreliable_Remote) ==
		   0 {return false}
	}
	bytes := make([dynamic]u8, 0, 4 + len(args))
	defer delete(bytes)
	replication_put_u32(&bytes, entity_id)
	append(&bytes, ..args)
	kind := Replication_Kind_Unreliable_Remote if unreliable else u8(16)
	return replication_send(service, peer, kind, bytes[:], !unreliable)
}

remote_send_invoke_request :: proc(
	service: ^ReplicatorService,
	peer: ^Replication_Transport_Peer,
	entity_id: u32,
	invoke_id: u32,
	args: []u8,
) -> bool {
	if !remote_can_send_to_peer(service, peer, entity_id) {return false}
	bytes := make([dynamic]u8, 0, 8 + len(args))
	defer delete(bytes)
	replication_put_u32(&bytes, entity_id)
	replication_put_u32(&bytes, invoke_id)
	append(&bytes, ..args)
	return replication_send(service, peer, 17, bytes[:])
}

remote_send_invoke_result :: proc(
	service: ^ReplicatorService,
	peer: ^Replication_Transport_Peer,
	entity_id: u32,
	invoke_id: u32,
	results: []u8,
) -> bool {
	bytes := make([dynamic]u8, 0, 9 + len(results))
	defer delete(bytes)
	replication_put_u32(&bytes, entity_id)
	replication_put_u32(&bytes, invoke_id)
	append(&bytes, 1)
	append(&bytes, ..results)
	return replication_send(service, peer, 18, bytes[:])
}

remote_send_invoke_error :: proc(
	service: ^ReplicatorService,
	peer: ^Replication_Transport_Peer,
	entity_id: u32,
	invoke_id: u32,
	message: string,
) -> bool {
	bytes := make([dynamic]u8, 0, 13 + len(message))
	defer delete(bytes)
	replication_put_u32(&bytes, entity_id)
	replication_put_u32(&bytes, invoke_id)
	append(&bytes, 0)
	replication_put_string(&bytes, message)
	return replication_send(service, peer, 18, bytes[:])
}

remote_yield_for_invoke :: proc(
	service: ^ReplicatorService,
	L: ^vm.State,
	entity_id: u32,
	invoke_id: u32,
	request_user_id: u32 = 0,
) {
	vm.PushCurrentThread(L)
	thread_ref := vm.RetainValue(L)
	vm.Pop(L)
	append(
		&service.invoke_pending,
		Remote_Invoke_Pending {
			entity_id = entity_id,
			request_user_id = request_user_id,
			invoke_id = invoke_id,
			thread = L,
			thread_ref = thread_ref,
			deadline = transport_time_get() + REMOTE_FUNCTION_TIMEOUT_MS,
		},
	)
	service.next_invoke_id += 1
}

remote_call_dispatch :: proc(
	ctx: rawptr,
	L: ^vm.State,
	instance: ^classes.Object,
	method: string,
) -> (
	i32,
	bool,
) {
	if instance == nil || instance.destroyed || ctx == nil {
		return 0, false
	}
	data_model := cast(^DataModel)ctx
	if data_model == nil || data_model.registry == nil {
		return 0, false
	}
	replicator := cast(^ReplicatorService)DataModel_Get_Service(data_model, "ReplicatorService")
	if replicator == nil {
		return vm.RaiseError(L, "ReplicatorService is unavailable"), true
	}

	top := vm.StackTop(L)

	unreliable := instance.class == &classes.UnreliableRemoteEvent_Class
	if classes.Is_A(instance, "RemoteEvent") || unreliable {
		switch method {
		case "FireServer":
			switch replicator.mode {
			case .Client:
				bytes: [dynamic]u8
				defer delete(bytes)
				if !remote_encode_args(
					L,
					2,
					top,
					&bytes,
					remote_common_capabilities(replicator, replicator.remote),
				) {
					return vm.RaiseError(L, "FireServer arguments cannot be serialized (maximum nesting depth 8, 256 arguments, 1 MiB serialized payload)"), true
				}
				if unreliable && len(bytes) > UNRELIABLE_REMOTE_MAX_PAYLOAD {
					return vm.RaiseError(L, "UnreliableRemoteEvent serialized arguments exceed 1000 bytes"), true
				}
				if !remote_send_fire(
					replicator,
					replicator.remote,
					replication_entity_id(replicator, instance),
					bytes[:],
					unreliable,
				) {
					return vm.RaiseError(L, "FireServer rejected: remote is not ready, payload is too large, transport is congested, or the 200 RPC/s client limit was reached"), true
				}
			case .Server:

			case .Stopped:
				vm.PushNil(L)
				for index := 2; index <= top; index += 1 {
					vm.PushValue(L, index)
				}
				signal := classes.RemoteEvent_Server_Signal(cast(^classes.RemoteEvent)instance)
				signals.Fire(L, signal, max(top - 1, 0) + 1)
			}
			return 0, true
		case "FireClient", "FireAllClients":
			target: ^classes.Object
			first_arg := 2
			if method == "FireClient" {
				if !vm.IsNoneOrNil(L, 2) {
					target = classes.Object_From_Argument(L, 2)
				}
				if target == nil || !classes.Is_A(target, "Player") {
					return vm.RaiseError(L, "FireClient expects a Player as the first argument"),
						true
				}
				first_arg = 3
			}
			switch replicator.mode {
			case .Server:
				peer, _ := remote_find_player_peer(replicator, target)
				bytes: [dynamic]u8
				defer delete(bytes)
				if !remote_encode_args(
					L,
					first_arg,
					top,
					&bytes,
					remote_common_capabilities(replicator, peer),
				) {
					return vm.RaiseError(L, "RemoteEvent arguments cannot be serialized (maximum nesting depth 8, 256 arguments, 1 MiB serialized payload)"), true
				}
				if unreliable && len(bytes) > UNRELIABLE_REMOTE_MAX_PAYLOAD {
					return vm.RaiseError(L, "UnreliableRemoteEvent serialized arguments exceed 1000 bytes"), true
				}
				entity_id := replication_entity_id(replicator, instance)
				if method == "FireClient" {
					if peer == nil || !remote_send_fire(replicator, peer, entity_id, bytes[:], unreliable) {
						return vm.RaiseError(L, "FireClient rejected: remote unavailable, payload too large, transport congested, or 200 RPC/s limit reached"), true
					}
				} else {
					failed := false
					for &connection in replicator.peers {
						if connection.peer != nil {
							if !remote_send_fire(
								replicator,
								connection.peer,
								entity_id,
								bytes[:],
								unreliable,
							) {failed = true}
						}
					}
					if failed {
						return vm.RaiseError(L, "FireAllClients rejected by one or more clients: payload too large or transport congested"), true
					}
				}
			case .Client:

			case .Stopped:
				signal := classes.RemoteEvent_Client_Signal(cast(^classes.RemoteEvent)instance)
				signals.Fire(L, signal, max(top - first_arg + 1, 0))
			}
			return 0, true
		}
	} else if classes.Is_A(instance, "RemoteFunction") {
		switch method {
		case "InvokeServer":
			switch replicator.mode {
			case .Client:
				bytes: [dynamic]u8
				defer delete(bytes)
				if !remote_encode_args(
					L,
					2,
					top,
					&bytes,
					remote_common_capabilities(replicator, replicator.remote),
				) {
					return vm.RaiseError(L, "InvokeServer arguments cannot be serialized (maximum nesting depth 8, 256 arguments, 1 MiB serialized payload)"), true
				}
				invoke_id := replicator.next_invoke_id
				entity_id := replication_entity_id(replicator, instance)
				if !remote_send_invoke_request(
					replicator,
					replicator.remote,
					entity_id,
					invoke_id,
					bytes[:],
				) {return vm.RaiseError(L, "Failed to send RemoteFunction request"), true}
				remote_yield_for_invoke(replicator, L, entity_id, invoke_id)
				return vm.YieldThread(L), true
			case .Server:
				return vm.RaiseError(L, "InvokeServer can only be called from a client"), true
			case .Stopped:
				return remote_invoke_loopback(replicator, L, instance, 2, max(top - 1, 0), true),
					true
			}
			return 0, true
		case "InvokeClient", "InvokeClients":
			target: ^classes.Object
			first_arg := 2
			if method == "InvokeClient" {
				if !vm.IsNoneOrNil(L, 2) {
					target = classes.Object_From_Argument(L, 2)
				}
				if target == nil || !classes.Is_A(target, "Player") {
					return vm.RaiseError(L, "InvokeClient expects a Player as the first argument"),
						true
				}
				first_arg = 3
			}
			switch replicator.mode {
			case .Server:
				peer, _ := remote_find_player_peer(replicator, target)
				bytes: [dynamic]u8
				defer delete(bytes)
				if !remote_encode_args(
					L,
					first_arg,
					top,
					&bytes,
					remote_common_capabilities(replicator, peer),
				) {
					return vm.RaiseError(L, "RemoteFunction arguments cannot be serialized (maximum nesting depth 8, 256 arguments, 1 MiB serialized payload)"), true
				}
				invoke_id := replicator.next_invoke_id
				entity_id := replication_entity_id(replicator, instance)
				sent := false
				if method == "InvokeClient" {
					if peer != nil {
						sent = remote_send_invoke_request(
							replicator,
							peer,
							entity_id,
							invoke_id,
							bytes[:],
						)
					}
				} else {
					for &connection in replicator.peers {
						if connection.peer != nil {
							sent =
								remote_send_invoke_request(
									replicator,
									connection.peer,
									entity_id,
									invoke_id,
									bytes[:],
								) ||
								sent
						}
					}
				}
				if !sent {
					return vm.RaiseError(L, "No client is connected to InvokeClient"), true
				}
				remote_yield_for_invoke(
					replicator,
					L,
					entity_id,
					invoke_id,
					(cast(^Player)target).user_id if target != nil else 0,
				)
				return vm.YieldThread(L), true
			case .Client:
				return vm.RaiseError(L, "InvokeClient can only be called from the server"), true
			case .Stopped:
				return remote_invoke_loopback(
						replicator,
						L,
						instance,
						first_arg,
						max(top - first_arg + 1, 0),
						false,
					),
					true
			}
			return 0, true
		}
	}
	return 0, false
}

remote_invoke_loopback :: proc(
	service: ^ReplicatorService,
	L: ^vm.State,
	instance: ^classes.Object,
	first_arg_index: int,
	arg_count: int,
	server_side: bool,
) -> i32 {
	remote_function := cast(^classes.RemoteFunction)instance
	handler: i32
	if server_side {
		handler = classes.RemoteFunction_Server_Handler(remote_function)
	} else {
		handler = classes.RemoteFunction_Client_Handler(remote_function)
	}
	if handler == classes.REMOTE_FUNCTION_NO_HANDLER {
		vm.PushNil(L)
		vm.PushString(L, "RemoteFunction has no handler on the target")
		return 2
	}

	top := vm.StackTop(L)
	base := top

	vm.PushRegistryReference(L, handler)
	if server_side {

		vm.PushNil(L)
	}
	for offset := 0; offset < arg_count; offset += 1 {
		vm.PushValue(L, first_arg_index + offset)
	}
	actual_args := arg_count + (server_side ? 1 : 0)
	ok, err := vm.ProtectedCall(L, actual_args, -1)
	if !ok {
		vm.SetStackTop(L, base)
		vm.PushNil(L)
		vm.PushString(L, err)
		delete(err)
		return 2
	}
	return i32(max(vm.StackTop(L) - base, 0))
}


remote_receive_fire :: proc(
	service: ^ReplicatorService,
	L: ^vm.State,
	peer: ^Replication_Transport_Peer,
	entity_id: u32,
	reader: ^Replication_Reader,
	unreliable: bool = false,
) {
	entity := replication_entity_by_id(service, entity_id)
	if entity == nil || entity.object == nil || entity.object.destroyed {
		reader.offset = len(reader.data)
		return
	}
	expected_class :=
		&classes.UnreliableRemoteEvent_Class if unreliable else &classes.RemoteEvent_Class
	if !classes.Is_A_Class(entity.object, expected_class) {
		reader.valid = false
		return
	}
	if service.mode == .Server {
		connection := replication_peer_of(service, peer)
		if connection == nil ||
		   !connection.handshake_complete ||
		   connection.known[entity_id] == 0 ||
		   !replication_visible(service, connection, entity.object) {
			reader.offset = len(reader.data)
			return
		}
	}
	top := vm.StackTop(L)
	defer vm.SetStackTop(L, top)


	player_object: ^classes.Object
	offset_before := 0
	if service.mode == .Server {
		for &connection in service.peers {
			if connection.peer == peer && connection.player != nil {
				player_object = &connection.player.object
				break
			}
		}
		if player_object != nil {
			classes.Push_Object(L, player_object)
			offset_before = 1
		}
	}

	arg_count := offset_before
	for reader.valid && reader.offset < len(reader.data) {
		if arg_count - offset_before >= REMOTE_MAX_ARGS ||
		   !vm.CheckStack(L, 16) {reader.valid = false; return}
		replication_decode_value(L, reader, service.signal_registry.datatypes, 0, service)
		if !reader.valid {
			return
		}
		arg_count += 1
	}

	if service.mode == .Server {
		signal := classes.RemoteEvent_Server_Signal(cast(^classes.RemoteEvent)entity.object)
		signals.Fire(L, signal, arg_count)
	} else {
		signal := classes.RemoteEvent_Client_Signal(cast(^classes.RemoteEvent)entity.object)
		signals.Fire(L, signal, arg_count)
	}
}

remote_run_invoke :: proc(
	service: ^ReplicatorService,
	L: ^vm.State,
	request_peer: ^Replication_Transport_Peer,
	entity_id: u32,
	invoke_id: u32,
	reader: ^Replication_Reader,
) {
	entity := replication_entity_by_id(service, entity_id)
	if entity == nil || entity.object == nil || entity.object.destroyed {
		reader.offset = len(reader.data)
		return
	}
	if !classes.Is_A(entity.object, "RemoteFunction") {
		reader.valid = false
		return
	}
	if service.mode == .Server {
		connection := replication_peer_of(service, request_peer)
		if connection == nil ||
		   !connection.handshake_complete ||
		   connection.known[entity_id] == 0 ||
		   !replication_visible(service, connection, entity.object) {
			reader.offset = len(reader.data)
			return
		}
	}
	remote_function := cast(^classes.RemoteFunction)entity.object

	handler: i32
	player_object: ^classes.Object
	if service.mode == .Server {
		handler = classes.RemoteFunction_Server_Handler(remote_function)
		for &connection in service.peers {
			if connection.peer == request_peer && connection.player != nil {
				player_object = &connection.player.object
				break
			}
		}
	} else {
		handler = classes.RemoteFunction_Client_Handler(remote_function)
	}

	if handler == classes.REMOTE_FUNCTION_NO_HANDLER {
		reader.offset = len(reader.data)
		err := "RemoteFunction has no handler on the server"
		if service.mode != .Server {err = "RemoteFunction has no handler on the client"}
		_ = remote_send_invoke_error(service, request_peer, entity_id, invoke_id, err)
		return
	}

	top := vm.StackTop(L)
	defer vm.SetStackTop(L, top)

	arg_count := 0
	for reader.valid && reader.offset < len(reader.data) {
		if arg_count >= REMOTE_MAX_ARGS || !vm.CheckStack(L, 16) {reader.valid = false; return}
		replication_decode_value(L, reader, service.signal_registry.datatypes, 0, service)
		if !reader.valid {
			reader.valid = false
			return
		}
		arg_count += 1
	}
	if !vm.CheckStack(L, arg_count + 2) {reader.valid = false; return}
	arg_base := top + 1

	base := vm.StackTop(L)
	vm.PushRegistryReference(L, handler)
	if player_object != nil {
		classes.Push_Object(L, player_object)
	}
	for offset := 0; offset < arg_count; offset += 1 {
		vm.PushValue(L, arg_base + offset)
	}
	actual_args := arg_count + (player_object == nil ? 0 : 1)

	ok, err := vm.ProtectedCall(L, actual_args, -1)
	if !ok {
		_ = remote_send_invoke_error(service, request_peer, entity_id, invoke_id, err)
		delete(err)
		return
	}

	result_count := vm.StackTop(L) - base
	if result_count <= 0 {
		_ = remote_send_invoke_result(service, request_peer, entity_id, invoke_id, nil)
		return
	}
	results: [dynamic]u8
	defer delete(results)
	if !remote_encode_args(
		L,
		base + 1,
		vm.StackTop(L),
		&results,
		remote_common_capabilities(service, request_peer),
	) {
		_ = remote_send_invoke_error(service, request_peer, entity_id, invoke_id, "RemoteFunction result cannot be serialized")
		return
	}
	if !remote_send_invoke_result(service, request_peer, entity_id, invoke_id, results[:]) {
		_ = remote_send_invoke_error(
			service,
			request_peer,
			entity_id,
			invoke_id,
			"RemoteFunction result could not be sent or exceeded the transport limit",
		)
	}
}

remote_receive_invoke_response :: proc(
	service: ^ReplicatorService,
	L: ^vm.State,
	peer: ^Replication_Transport_Peer,
	reader: ^Replication_Reader,
) {
	entity_id := replication_read_u32(reader)
	invoke_id := replication_read_u32(reader)
	if !reader.valid || reader.offset >= len(reader.data) {
		return
	}
	status := reader.data[reader.offset]
	reader.offset += 1
	if status > 1 {
		reader.valid = false
		return
	}

	pending_index := -1
	for pending, index in service.invoke_pending {
		if pending.invoke_id == invoke_id && pending.entity_id == entity_id {
			if service.mode == .Server {
				connection := replication_peer_of(service, peer)
				entity := replication_entity_by_id(service, entity_id)
				if connection == nil ||
				   !connection.handshake_complete ||
				   connection.player == nil ||
				   (pending.request_user_id != 0 &&
						   pending.request_user_id != connection.player.user_id) ||
				   entity == nil ||
				   entity.object == nil ||
				   connection.known[entity_id] == 0 ||
				   !replication_visible(service, connection, entity.object) {continue}
			}
			pending_index = index
			break
		}
	}
	if pending_index == -1 {
		reader.offset = len(reader.data)
		return
	}
	pending := service.invoke_pending[pending_index]
	ordered_remove(&service.invoke_pending, pending_index)

	top := vm.StackTop(L)
	defer vm.SetStackTop(L, top)

	value_count := 0
	if status == 1 {
		for reader.valid && reader.offset < len(reader.data) {
			if value_count >= REMOTE_MAX_ARGS ||
			   !vm.CheckStack(L, 16) {reader.valid = false; break}
			replication_decode_value(L, reader, service.signal_registry.datatypes, 0, service)
			if reader.valid {value_count += 1}
		}
		if !reader.valid {
			vm.SetStackTop(L, top)
			vm.PushNil(L)
			vm.PushString(L, "RemoteFunction invocation failed")
			value_count = 2
		}
	} else {
		err_text := replication_read_string(reader)
		if reader.offset != len(reader.data) {reader.valid = false}
		vm.PushNil(L)
		vm.PushString(
			L,
			err_text if reader.valid && err_text != "" else "RemoteFunction invocation failed",
		)
		value_count = 2
	}
	if !vm.CheckStack(pending.thread, value_count) {
		vm.SetStackTop(L, top)
		vm.PushNil(L)
		vm.PushString(L, "RemoteFunction response exceeds stack capacity")
		value_count = 2
	}
	for index := top + 1; index <= top + value_count; index += 1 {
		vm.CopyValueToThread(L, pending.thread, index)
	}
	_, _, err := vm.ResumeThread(pending.thread, L, value_count)
	if err != "" {
		fmt.eprintf("[Replication] invoke resume failed: %s\n", err)
		delete(err)
	}
	vm.ReleaseValue(L, pending.thread_ref)
}

remote_invoke_timeouts :: proc(service: ^ReplicatorService, L: ^vm.State) {
	if service == nil || L == nil || len(service.invoke_pending) == 0 {
		return
	}
	now := transport_time_get()
	for index := len(service.invoke_pending) - 1; index >= 0; index -= 1 {
		pending := service.invoke_pending[index]
		if transmute(i32)(now - pending.deadline) < 0 {
			continue
		}
		ordered_remove(&service.invoke_pending, index)
		top := vm.StackTop(L)
		vm.PushNil(L)
		vm.PushString(L, "RemoteFunction invocation timed out")
		vm.CopyValueToThread(L, pending.thread, -2)
		vm.CopyValueToThread(L, pending.thread, -1)
		_, _, err := vm.ResumeThread(pending.thread, L, 2)
		if err != "" {
			fmt.eprintf("[Replication] invoke timeout resume failed: %s\n", err)
			delete(err)
		}
		vm.SetStackTop(L, top)
		vm.ReleaseValue(L, pending.thread_ref)
	}
}
