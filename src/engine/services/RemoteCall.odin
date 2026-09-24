#+build !js
package services

// wire:remote-call

import classes "../classes"
import signals "../signals"
import vm "../vm"
import "core:fmt"
import enet "vendor:ENet"

REMOTE_FUNCTION_TIMEOUT_MS :: 10_000

Remote_Invoke_Pending :: struct {
	entity_id:  u32,
	invoke_id:  u32,
	thread:     ^vm.State,
	thread_ref: i32,
	deadline:   u32, // enet.time_get() ms when the call must be answered
}

remote_find_player_peer :: proc(
	service: ^ReplicatorService,
	player_object: ^classes.Object,
) -> (^enet.Peer, ^Replication_Peer) {
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

remote_encode_args :: proc(
	L: ^vm.State,
	first: int,
	last: int,
	bytes: ^[dynamic]u8,
) -> bool {
	for index := first; index <= last; index += 1 {
		if !replication_encode_value(L, index, bytes, 0) {
			return false
		}
	}
	return true
}

remote_send_fire :: proc(
	service: ^ReplicatorService,
	peer: ^enet.Peer,
	entity_id: u32,
	args: []u8,
) -> bool {
	bytes: [dynamic]u8
	defer delete(bytes)
	replication_put_u32(&bytes, entity_id)
	append(&bytes, ..args)
	return replication_send(service, peer, 16, bytes[:])
}

remote_send_invoke_request :: proc(
	service: ^ReplicatorService,
	peer: ^enet.Peer,
	entity_id: u32,
	invoke_id: u32,
	args: []u8,
) -> bool {
	bytes: [dynamic]u8
	defer delete(bytes)
	replication_put_u32(&bytes, entity_id)
	replication_put_u32(&bytes, invoke_id)
	append(&bytes, ..args)
	return replication_send(service, peer, 17, bytes[:])
}

remote_send_invoke_result :: proc(
	service: ^ReplicatorService,
	peer: ^enet.Peer,
	entity_id: u32,
	invoke_id: u32,
	results: []u8,
) -> bool {
	bytes: [dynamic]u8
	defer delete(bytes)
	replication_put_u32(&bytes, entity_id)
	replication_put_u32(&bytes, invoke_id)
	append(&bytes, 1)
	append(&bytes, ..results)
	return replication_send(service, peer, 18, bytes[:])
}

remote_send_invoke_error :: proc(
	service: ^ReplicatorService,
	peer: ^enet.Peer,
	entity_id: u32,
	invoke_id: u32,
	message: string,
) -> bool {
	bytes: [dynamic]u8
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
) {
	vm.PushCurrentThread(L)
	thread_ref := vm.RetainValue(L)
	vm.Pop(L)
	append(
		&service.invoke_pending,
		Remote_Invoke_Pending {
			entity_id  = entity_id,
			invoke_id  = invoke_id,
			thread     = L,
			thread_ref = thread_ref,
			deadline   = enet.time_get() + REMOTE_FUNCTION_TIMEOUT_MS,
		},
	)
	service.next_invoke_id += 1
}

remote_call_dispatch :: proc(
	ctx: rawptr,
	L: ^vm.State,
	instance: ^classes.Object,
	method: string,
) -> (i32, bool) {
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

	if classes.Is_A(instance, "RemoteEvent") {
		switch method {
		case "FireServer":
			switch replicator.mode {
			case .Client:
				bytes: [dynamic]u8
				defer delete(bytes)
				if !remote_encode_args(L, 2, top, &bytes) {
					return 0, true
				}
				_ = remote_send_fire(
					replicator,
					replicator.remote,
					replication_entity_id(replicator, instance),
					bytes[:],
				)
			case .Server:
				// Roblox semantics: FireServer on the server is a no-op.
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
					target = cast(^classes.Object)vm.UserdataValue(L, 2)
				}
				if target == nil || !classes.Is_A(target, "Player") {
					return vm.RaiseError(L, "FireClient expects a Player as the first argument"), true
				}
				first_arg = 3
			}
			switch replicator.mode {
			case .Server:
				bytes: [dynamic]u8
				defer delete(bytes)
				if !remote_encode_args(L, first_arg, top, &bytes) {
					return 0, true
				}
				entity_id := replication_entity_id(replicator, instance)
				if method == "FireClient" {
					peer, _ := remote_find_player_peer(replicator, target)
					if peer != nil {
						_ = remote_send_fire(replicator, peer, entity_id, bytes[:])
					}
				} else {
					for &connection in replicator.peers {
						if connection.peer != nil {
							_ = remote_send_fire(replicator, connection.peer, entity_id, bytes[:])
						}
					}
				}
			case .Client:
				// Roblox semantics: FireClient on the client is a no-op.
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
				if !remote_encode_args(L, 2, top, &bytes) {
					return 0, true
				}
				invoke_id := replicator.next_invoke_id
				entity_id := replication_entity_id(replicator, instance)
				_ = remote_send_invoke_request(
					replicator,
					replicator.remote,
					entity_id,
					invoke_id,
					bytes[:],
				)
				remote_yield_for_invoke(replicator, L, entity_id, invoke_id)
				return vm.YieldThread(L), true
			case .Server:
				return vm.RaiseError(L, "InvokeServer can only be called from a client"), true
			case .Stopped:
				return remote_invoke_loopback(
					replicator,
					L,
					instance,
					2,
					max(top - 1, 0),
					true,
				), true
			}
			return 0, true
		case "InvokeClient", "InvokeClients":
			target: ^classes.Object
			first_arg := 2
			if method == "InvokeClient" {
				if !vm.IsNoneOrNil(L, 2) {
					target = cast(^classes.Object)vm.UserdataValue(L, 2)
				}
				if target == nil || !classes.Is_A(target, "Player") {
					return vm.RaiseError(L, "InvokeClient expects a Player as the first argument"), true
				}
				first_arg = 3
			}
			switch replicator.mode {
			case .Server:
				bytes: [dynamic]u8
				defer delete(bytes)
				if !remote_encode_args(L, first_arg, top, &bytes) {
					return 0, true
				}
				invoke_id := replicator.next_invoke_id
				entity_id := replication_entity_id(replicator, instance)
				sent := false
				if method == "InvokeClient" {
					peer, _ := remote_find_player_peer(replicator, target)
					if peer != nil {
						sent = remote_send_invoke_request(replicator, peer, entity_id, invoke_id, bytes[:])
					}
				} else {
					for &connection in replicator.peers {
						if connection.peer != nil {
							sent = remote_send_invoke_request(replicator, connection.peer, entity_id, invoke_id, bytes[:]) || sent
						}
					}
				}
				if !sent {
					return vm.RaiseError(L, "No client is connected to InvokeClient"), true
				}
				remote_yield_for_invoke(replicator, L, entity_id, invoke_id)
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
				), true
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
	server_side: bool, // true = run OnServerInvoke handler (InvokeServer)
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
		// OnServerInvoke receives the player first; the loopback has none.
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

// ---- receive side ----------------------------------------------------------

remote_receive_fire :: proc(
	service: ^ReplicatorService,
	L: ^vm.State,
	peer: ^enet.Peer,
	entity_id: u32,
	reader: ^Replication_Reader,
) {
	entity := replication_entity_by_id(service, entity_id)
	if entity == nil || entity.object == nil || entity.object.destroyed {
		reader.offset = len(reader.data)
		return
	}
	if !classes.Is_A(entity.object, "RemoteEvent") {
		reader.valid = false
		return
	}
	top := vm.StackTop(L)
	defer vm.SetStackTop(L, top)

	// On the server the player is the first callback argument, so push it
	// before decoding the data arguments.
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
		replication_decode_value(L, reader, service.signal_registry.datatypes, 0)
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
	request_peer: ^enet.Peer,
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
		replication_decode_value(L, reader, service.signal_registry.datatypes, 0)
		if !reader.valid {
			reader.valid = false
			return
		}
		arg_count += 1
	}
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
	for index := base + 1; index <= vm.StackTop(L); index += 1 {
		if !replication_encode_value(L, index, &results, 0) {
			delete(results)
			_ = remote_send_invoke_result(service, request_peer, entity_id, invoke_id, nil)
			return
		}
	}
	_ = remote_send_invoke_result(service, request_peer, entity_id, invoke_id, results[:])
	delete(results)
}

remote_receive_invoke_response :: proc(
	service: ^ReplicatorService,
	L: ^vm.State,
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
		if pending.invoke_id == invoke_id &&
		   pending.entity_id == entity_id {
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
			replication_decode_value(L, reader, service.signal_registry.datatypes, 0)
			if !reader.valid {
				value_count = 0
				vm.PushNil(L)
				vm.PushString(L, "RemoteFunction invocation failed")
				value_count = 2
				reader.valid = true
				reader.offset = len(reader.data)
				break
			}
			value_count += 1
		}
	} else {
		err_text := replication_read_string(reader)
		reader.offset = len(reader.data)
		vm.PushNil(L)
		vm.PushString(L, err_text == "" ? "RemoteFunction invocation failed" : err_text)
		value_count = 2
	}

	for index := top + 1; index <= top + value_count; index += 1 {
		vm.CopyValueToThread(L, pending.thread, index)
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
	now := enet.time_get()
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