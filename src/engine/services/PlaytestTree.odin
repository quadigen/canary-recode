#+build !js
package services

import classes "../classes"
import datatypes "../datatypes"
import serializer "../serializer"
import tracy "../util/odin-tracy"
import vm "../vm"
import "core:fmt"
import "core:hash"
import "core:os"
import "core:strconv"
import "core:time"

PLAYTEST_TREE_LIMIT :: 16 * 1024 * 1024
PLAYTEST_TREE_NODE_LIMIT :: 50000
PLAYTEST_TREE_TIMEOUT :: 2 * time.Second

Playtest_Tree_Op :: enum u8 {
	Tree = 1,
	Properties,
	Get,
	Set,
	Create,
	Destroy,
	Reparent,
	Reference,
	Tree_Versioned,
	Copy,
}

Playtest_Tree_Pending :: struct {
	sequence: u32,
	op:       Playtest_Tree_Op,
	deadline: time.Tick,
}

Playtest_Tree_Reader :: struct {
	data: []u8,
	pos:  int,
	bad:  bool,
}

pt_put_u32 :: proc(out: ^[dynamic]u8, n: u32) {
	append(out, u8(n), u8(n >> 8), u8(n >> 16), u8(n >> 24))
}

pt_get_u32 :: proc(r: ^Playtest_Tree_Reader) -> u32 {
	if r.bad || len(r.data) - r.pos < 4 {r.bad = true; return 0}
	d := r.data[r.pos:][:4]
	r.pos += 4
	return u32(d[0]) | u32(d[1]) << 8 | u32(d[2]) << 16 | u32(d[3]) << 24
}

pt_put_bytes :: proc(out: ^[dynamic]u8, value: []u8) {
	pt_put_u32(out, u32(len(value)))
	append(out, ..value[:])
}

pt_put_string :: proc(out: ^[dynamic]u8, value: string) {
	pt_put_bytes(out, transmute([]u8)value)
}

pt_get_bytes :: proc(r: ^Playtest_Tree_Reader) -> []u8 {
	n := int(pt_get_u32(r))
	if r.bad || n < 0 || n > len(r.data) - r.pos {r.bad = true; return nil}
	result := r.data[r.pos:][:n]
	r.pos += n
	return result
}

pt_get_string :: proc(r: ^Playtest_Tree_Reader) -> string {
	return string(pt_get_bytes(r))
}

pt_read_file :: proc(path: string) -> ([]u8, bool) {
	info, err := os.lstat(path, context.allocator)
	if err != nil {return nil, false}
	defer os.file_info_delete(info, context.allocator)
	if info.type != .Regular ||
	   info.size < 0 ||
	   info.size > PLAYTEST_TREE_LIMIT {return nil, false}
	data, read_err := os.read_entire_file(path, context.allocator)
	if read_err != nil {return nil, false}
	if len(data) > PLAYTEST_TREE_LIMIT {delete(data); return nil, false}
	return data, true
}

pt_path :: proc(dir, name: string) -> string {
	path, err := os.join_path({dir, name}, context.temp_allocator)
	if err != nil {return ""}
	return path
}

pt_atomic_write :: proc(path: string, data: []u8) -> bool {
	if path == "" || len(data) > PLAYTEST_TREE_LIMIT {return false}
	tmp := fmt.aprintf("%s.tmp", path)
	defer delete(tmp)
	defer _ = os.remove(tmp)
	if os.write_entire_file(tmp, data) != nil {return false}
	return os.rename(tmp, path) == nil
}

pt_id :: proc(object: ^classes.Object) -> string {
	if object == nil {return ""}
	return fmt.aprintf(
		"%016x%08x%08x",
		cast(u64)object.unique_id.Random,
		object.unique_id.Time,
		object.unique_id.Index,
	)
}

pt_find :: proc(registry: ^Registry, id: string) -> ^classes.Object {
	if registry == nil || registry.data_model == nil || len(id) != 32 {return nil}
	random, ok1 := strconv.parse_u64(id[:16], 16)
	stamp, ok2 := strconv.parse_u64(id[16:24], 16)
	index, ok3 := strconv.parse_u64(id[24:], 16)
	if !ok1 || !ok2 || !ok3 {return nil}
	wanted := datatypes.UniqueId {
		Random = cast(i64)random,
		Time   = u32(stamp),
		Index  = u32(index),
	}
	root := &registry.data_model.object
	for descriptor in registry.classes.classes {
		if descriptor == nil {continue}
		for object in descriptor.instances {
			if object == nil || object.destroyed {continue}
			if object.unique_id != wanted {continue}
			if object == root || classes.Is_Descendant_Of(object, root) {return object}
		}
	}
	return nil
}

pt_protected_object :: proc(object: ^classes.Object) -> bool {
	return(
		object == nil ||
		classes.Is_A(object, "Service") ||
		classes.Is_A(object, "DataModel") ||
		(object.parent != nil && classes.Is_A(object.parent, "DataModel")) \
	)
}

pt_property_known :: proc(registry: ^Registry, object: ^classes.Object, key: string) -> bool {
	properties := classes.Get_Properties(registry.classes, object)
	defer delete(properties)
	for property in properties {if property == key {return true}}
	return false
}

Playtest_Tree_Access :: struct {
	object:     ^classes.Object,
	descriptor: ^classes.Class_Descriptor,
	key:        string,
}

pt_get_protected :: proc "c" (L: ^vm.State) -> i32 {
	context = tracy.DefaultContext()
	a := cast(^Playtest_Tree_Access)vm.UpvaluePointer(L)
	if !classes.descriptor_get(
		L,
		a.object,
		a.descriptor,
		a.key,
	) {return vm.RaiseError(L, "unknown property")}
	return 1
}

pt_set_protected :: proc "c" (L: ^vm.State) -> i32 {
	context = tracy.DefaultContext()
	a := cast(^Playtest_Tree_Access)vm.UpvaluePointer(L)
	if !classes.descriptor_set(
		L,
		a.object,
		a.descriptor,
		a.key,
		1,
	) {return vm.RaiseError(L, "unknown or read-only property")}
	return 0
}


pt_encode_value :: proc(out: ^[dynamic]u8, L: ^vm.State, registry: ^Registry) -> bool {
	if binding := vm.UserdataBindingOf(L, -1); binding != nil && binding.name == "Instance" {
		object := cast(^classes.Object)vm.UserdataValue(L, -1)
		if object == nil || object.destroyed {return false}
		root := &registry.data_model.object
		if object != root && !classes.Is_Descendant_Of(object, root) {return false}
		append(out, 1)
		id := pt_id(object)
		defer delete(id)
		pt_put_string(out, id)
		return true
	}
	wire: [dynamic]u8
	defer delete(wire)
	if !serializer.Append_Replicated_Value(&wire, L, registry.classes) ||
	   len(wire) > PLAYTEST_TREE_LIMIT {return false}
	append(out, 0)
	pt_put_bytes(out, wire[:])
	return true
}

pt_read_value :: proc(
	r: ^Playtest_Tree_Reader,
	L: ^vm.State,
	registry: ^classes.Registry,
) -> bool {
	if r.bad || r.pos >= len(r.data) {return false}
	kind := r.data[r.pos]
	r.pos += 1
	data := pt_get_bytes(r)
	if r.bad {return false}
	switch kind {
	case 0:
		consumed, ok := serializer.Read_Replicated_Value(data, L, registry)
		return ok && consumed == len(data)
	case 1:
		vm.NewTable(L, 0, 1)
		vm.PushString(L, string(data))
		vm.SetField(L, -2, "InstanceId")
		return true
	}
	return false
}

pt_get_property :: proc(
	out: ^[dynamic]u8,
	L: ^vm.State,
	registry: ^Registry,
	object: ^classes.Object,
	key: string,
) -> bool {
	top := vm.StackTop(L)
	defer vm.SetStackTop(L, top)
	a := Playtest_Tree_Access{object, classes.Find_Class(registry.classes, object.class.name), key}
	if a.descriptor == nil {return false}
	vm.PushLightUserdata(L, &a)
	vm.PushFunction(L, "playtest_tree_get", pt_get_protected, 1)
	ok, err := vm.ProtectedCall(L, 0, 1)
	defer delete(err)
	return ok && pt_encode_value(out, L, registry)
}

pt_set_property :: proc(
	L: ^vm.State,
	registry: ^Registry,
	object: ^classes.Object,
	key: string,
	value_index: int,
) -> bool {
	a := Playtest_Tree_Access{object, classes.Find_Class(registry.classes, object.class.name), key}
	if a.descriptor == nil {return false}
	vm.PushLightUserdata(L, &a)
	vm.PushFunction(L, "playtest_tree_set", pt_set_protected, 1)
	vm.PushValue(L, value_index)
	ok, err := vm.ProtectedCall(L, 1, 0)
	defer delete(err)
	return ok
}

pt_snapshot :: proc(out: ^[dynamic]u8, registry: ^Registry) -> bool {
	root := &registry.data_model.object
	nodes: [dynamic]^classes.Object
	defer delete(nodes)
	append(&nodes, root)
	for i := 0; i < len(nodes); i += 1 {
		object := nodes[i]
		for child in object.children {
			if child != nil && !child.destroyed && child.parent == object {
				append(&nodes, child)
				if len(nodes) > PLAYTEST_TREE_NODE_LIMIT {return false}
			}
		}
	}
	pt_put_u32(out, u32(len(nodes)))
	for object in nodes {
		id, parent := pt_id(object), pt_id(object.parent)
		pt_put_string(out, id)
		pt_put_string(out, parent)
		delete(id)
		delete(parent)
		pt_put_string(out, object.name)
		pt_put_string(out, object.class.name)
		if len(out^) > PLAYTEST_TREE_LIMIT {return false}
	}
	return true
}

pt_execute :: proc(
	out: ^[dynamic]u8,
	registry: ^Registry,
	L: ^vm.State,
	op: Playtest_Tree_Op,
	id, key, aux: string,
	wire: []u8,
) -> string {
	if op == .Tree {
		if !pt_snapshot(out, registry) {return "game tree exceeds snapshot limit"}
		return ""
	}
	if op == .Tree_Versioned {
		snapshot: [dynamic]u8
		defer delete(snapshot)
		if !pt_snapshot(&snapshot, registry) {return "game tree exceeds snapshot limit"}
		version := fmt.tprintf("%016x", hash.fnv64a(snapshot[:]))
		pt_put_string(out, version)
		changed := id != version
		append(out, u8(1) if changed else u8(0))
		if changed {append(out, ..snapshot[:])}
		return ""
	}
	object := pt_find(registry, id)
	if object == nil {return "instance no longer exists in this game tree"}
	switch op {
	case .Copy:
		if pt_protected_object(object) {return "cannot copy a game service or DataModel"}


		container := classes.Object_Init(&classes.Folder_Class, "SerializedInstances")
		roots: [dynamic]^classes.Object
		append(&roots, object)
		defer delete(roots)
		container.children = roots
		data, err := serializer.Serialize(registry.classes, L, &container)
		defer delete(data)
		if !serializer.Error_Is_None(err) {
			serializer.Error_Delete(&err)
			return "could not serialize the live instance"
		}
		if len(data) >= PLAYTEST_TREE_LIMIT - 8 {return "instance exceeds clipboard size limit"}
		pt_put_bytes(out, data)
	case .Properties:
		properties := classes.Get_Properties(registry.classes, object)
		defer delete(properties)
		seen: map[string]bool
		defer delete(seen)
		count: u32
		pt_put_u32(out, 0)
		for property in properties {
			if property in seen {continue}
			seen[property] = true
			value: [dynamic]u8
			ok := pt_get_property(&value, L, registry, object, property)
			if ok {
				pt_put_string(out, property)
				append(out, ..value[:])
				count += 1
			}
			delete(value)
			if len(out^) > PLAYTEST_TREE_LIMIT {return "property snapshot exceeds size limit"}
		}
		for i in 0 ..< 4 {out^[i] = u8(count >> uint(i * 8))}
	case .Get:
		if !pt_property_known(registry, object, key) ||
		   !pt_get_property(
				   out,
				   L,
				   registry,
				   object,
				   key,
			   ) {return "unknown or unsupported property"}
	case .Set, .Reference:
		if key == "Parent" ||
		   key == "Capabilities" ||
		   key == "Sandboxed" ||
		   (key == "Name" && pt_protected_object(object)) ||
		   !pt_property_known(
				   registry,
				   object,
				   key,
			   ) {return "property is protected or unknown; use ReparentInstance for Parent"}
		if op == .Reference {
			reference: ^classes.Object
			if aux != "" {
				reference = pt_find(registry, aux)
				if reference == nil {return "referenced instance does not exist"}
			}
			classes.Push_Object(L, reference)
		} else {
			consumed, ok := serializer.Read_Replicated_Value(wire, L, registry.classes)
			if !ok || consumed != len(wire) {return "unsupported property value"}
		}
		if !pt_set_property(
			L,
			registry,
			object,
			key,
			vm.StackTop(L),
		) {return "property setter rejected the value"}
	case .Create:
		if classes.Is_A(
			object,
			"DataModel",
		) {return "create instances under a game service, not DataModel"}
		descriptor := classes.Find_Class(registry.classes, key)
		if descriptor == nil ||
		   !descriptor.creatable ||
		   classes.Is_Class_A(descriptor.info, &Service_Class) {return "class is not creatable"}
		created, ok := classes.Push_New(registry.classes, &vm.VM{L = L}, key)
		if !ok {return "could not create instance"}
		new_id := pt_id(created)
		defer delete(new_id)
		if aux != "" {classes.Set_Name(created, aux)}
		classes.Set_Parent(created, object)
		if created.destroyed ||
		   created.parent != object {return "instance was not retained by its parent"}
		pt_put_string(out, new_id)
	case .Destroy:
		if pt_protected_object(object) {return "cannot destroy a game service or DataModel"}
		classes.Destroy_Hierarchy(object)
	case .Reparent:
		if pt_protected_object(object) {return "cannot reparent a game service or DataModel"}
		parent := pt_find(registry, aux)
		if parent == nil ||
		   classes.Is_A(parent, "DataModel") ||
		   parent == object ||
		   classes.Is_Descendant_Of(parent, object) {return "invalid parent or hierarchy cycle"}
		classes.Set_Parent(object, parent)
		if object.destroyed || object.parent != parent {return "reparenting was rejected"}
	case .Tree, .Tree_Versioned:
	}
	return ""
}


Playtest_Tree_Pump :: proc(dir: string, registry: ^Registry, L: ^vm.State) {
	Playtest_Debugger_Pump(dir, registry, L)
	if dir == "" || registry == nil || registry.data_model == nil || L == nil {return}
	request, path_err := os.join_path({dir, "request.bin"}, context.allocator)
	if path_err != nil {return}
	defer delete(request)
	data, found := pt_read_file(request)
	if !found {return}
	defer delete(data)
	_ = os.remove(request)
	r := Playtest_Tree_Reader {
		data = data,
	}
	sequence := pt_get_u32(&r)
	raw_op := pt_get_u32(&r)
	id := pt_get_string(&r)
	key := pt_get_string(&r)
	aux := pt_get_string(&r)
	wire := pt_get_bytes(&r)
	if r.bad ||
	   r.pos != len(data) ||
	   sequence == 0 ||
	   raw_op < 1 ||
	   raw_op > u32(Playtest_Tree_Op.Copy) {return}
	top := vm.StackTop(L)
	security := vm.GetThreadSecurityCapabilities(L)
	vm.SetThreadSecurityCapabilities(L, vm.THREAD_SECURITY_ALL)
	defer {
		vm.SetStackTop(L, top)
		vm.SetThreadSecurityCapabilities(L, security)
	}
	payload: [dynamic]u8
	defer delete(payload)
	err := pt_execute(&payload, registry, L, Playtest_Tree_Op(raw_op), id, key, aux, wire)
	response: [dynamic]u8
	defer delete(response)
	if err != "" || len(payload) >= PLAYTEST_TREE_LIMIT {
		append(&response, 0)
		pt_put_string(&response, err if err != "" else "response exceeds size limit")
	} else {
		append(&response, 1)
		append(&response, ..payload[:])
	}
	name := fmt.aprintf("response-%d.bin", sequence)
	defer delete(name)
	path, response_path_err := os.join_path({dir, name}, context.allocator)
	if response_path_err == nil {
		defer delete(path)
		_ = pt_atomic_write(path, response[:])
	}
}

playtest_tree_method :: proc(method: string) -> (Playtest_Tree_Op, bool) {
	switch method {
	case "GetGameTree":
		return .Tree, true
	case "RequestCopyInstance":
		return .Copy, true
	case "RequestGameTree":
		return .Tree_Versioned, true
	case "GetInstanceProperties", "RequestInstanceProperties":
		return .Properties, true
	case "GetInstanceProperty":
		return .Get, true
	case "SetInstanceProperty", "RequestSetInstanceProperty":
		return .Set, true
	case "CreateInstance":
		return .Create, true
	case "DestroyInstance":
		return .Destroy, true
	case "ReparentInstance":
		return .Reparent, true
	case "SetInstanceReference", "RequestSetInstanceReference":
		return .Reference, true
	}
	return {}, false
}

pt_fail :: proc(L: ^vm.State, message: string) -> (i32, bool) {
	vm.PushNil(L)
	vm.PushString(L, message)
	return 2, true
}

pt_decode_result :: proc(
	L: ^vm.State,
	registry: ^classes.Registry,
	op: Playtest_Tree_Op,
	data: []u8,
) -> (
	i32,
	bool,
) {
	if len(data) == 0 {return pt_fail(L, "empty playtest response")}
	r := Playtest_Tree_Reader {
		data = data[1:],
	}
	if data[0] == 0 {return pt_fail(L, pt_get_string(&r))}
	top := vm.StackTop(L)
	version: string
	switch op {
	case .Tree, .Tree_Versioned:
		if op == .Tree_Versioned {
			version = pt_get_string(&r)
			if r.bad || r.pos >= len(r.data) {return pt_fail(L, "invalid versioned tree response")}
			changed := r.data[r.pos]
			r.pos += 1
			if changed == 0 {
				if r.pos != len(r.data) {return pt_fail(L, "invalid unchanged tree response")}
				vm.PushBoolean(L, false)
				vm.PushString(L, version)
				return 2, true
			}
			if changed != 1 {return pt_fail(L, "invalid versioned tree response")}
		}
		count := pt_get_u32(&r)
		if count > PLAYTEST_TREE_NODE_LIMIT {return pt_fail(L, "invalid tree response")}
		vm.NewTable(L, int(count), 0)
		for i in 0 ..< int(count) {
			id, parent, name, class_name :=
				pt_get_string(&r), pt_get_string(&r), pt_get_string(&r), pt_get_string(&r)
			if r.bad {break}
			vm.NewTable(L, 0, 4)
			vm.PushString(L, id); vm.SetField(L, -2, "Id")
			vm.PushString(L, parent); vm.SetField(L, -2, "ParentId")
			vm.PushString(L, name); vm.SetField(L, -2, "Name")
			vm.PushString(L, class_name); vm.SetField(L, -2, "ClassName")
			vm.RawSetIndex(L, -2, i + 1)
		}
	case .Copy:
		vm.PushBuffer(L, pt_get_bytes(&r))
	case .Properties:
		count := pt_get_u32(&r)
		if count > 10000 {return pt_fail(L, "invalid property response")}
		vm.NewTable(L, 0, int(count))
		for _ in 0 ..< int(count) {
			key := pt_get_string(&r)
			if !pt_read_value(&r, L, registry) {r.bad = true; break}
			vm.SetField(L, -2, key)
		}
	case .Get:
		if !pt_read_value(&r, L, registry) {r.bad = true}
	case .Create:
		vm.PushString(L, pt_get_string(&r))
	case .Set, .Destroy, .Reparent, .Reference:
		vm.PushBoolean(L, true)
	}
	if r.bad || r.pos != len(r.data) {
		vm.SetStackTop(L, top)
		return pt_fail(L, "invalid playtest response")
	}
	if op == .Tree_Versioned {
		vm.PushString(L, version)
		return 2, true
	}
	return 1, true
}

playtest_tree_namecall :: proc(
	L: ^vm.State,
	service: ^PlaytestService,
	op: Playtest_Tree_Op,
	asynchronous := false,
) -> (
	i32,
	bool,
) {
	if !vm.ThreadHasSecurityCapability(
		L,
		PROJECT_INTERNALS_CAPABILITY,
	) {return vm.RaiseError(L, "Playtest tree APIs require Internals capability"), true}
	role := vm.ArgString(L, 2)
	id, key, aux: string
	if op ==
	   .Tree_Versioned {id = vm.ArgOptionalString(L, 3)} else if op != .Tree {id = vm.ArgString(L, 3)}
	switch op {
	case .Get, .Set, .Reference:
		key = vm.ArgString(L, 4)
	case .Create:
		key = vm.ArgString(L, 4)
		aux = vm.ArgOptionalString(L, 5)
	case .Reparent:
		aux = vm.ArgString(L, 4)
	case .Tree, .Tree_Versioned, .Properties, .Destroy, .Copy:
	}
	if op == .Reference {aux = vm.ArgOptionalString(L, 5)}
	if !asynchronous {playtest_refresh(service)}
	if !service.running ||
	   service.tree_dir == "" {return pt_fail(L, "no inspectable local playtest is running")}
	if service.singleplayer && (role == "Server" || role == "Client") {role = "Client"}
	if role == "Server" && !playtest_process_active(service.server_process) ||
	   role == "Client" &&
		   !playtest_process_active(
				   service.client_process,
			   ) {return pt_fail(L, "requested playtest process is not running")}
	if role != "Server" && role != "Client" {return pt_fail(L, "target must be Server or Client")}
	slot := 0 if role == "Server" else 1
	if service.tree_pending[slot].sequence !=
	   0 {return pt_fail(L, "previous playtest request is still pending")}
	dir := pt_path(service.tree_dir, role)
	request := pt_path(dir, "request.bin")
	if os.exists(request) {return pt_fail(L, "previous playtest request is still pending")}

	wire: [dynamic]u8
	defer delete(wire)
	if op == .Set {
		vm.PushValue(L, 5)
		ok := serializer.Append_Replicated_Value(&wire, L, service.data_model.registry.classes)
		vm.Pop(L)
		if !ok {return pt_fail(L, "unsupported property value; use SetInstanceReference for instances")}
	}
	service.tree_sequence += 1
	if service.tree_sequence == 0 {service.tree_sequence = 1}
	sequence := service.tree_sequence
	packet: [dynamic]u8
	defer delete(packet)
	pt_put_u32(&packet, sequence)
	pt_put_u32(&packet, u32(op))
	pt_put_string(&packet, id)
	pt_put_string(&packet, key)
	pt_put_string(&packet, aux)
	pt_put_bytes(&packet, wire[:])
	if !pt_atomic_write(request, packet[:]) {return pt_fail(L, "could not send playtest request")}
	response := pt_path(dir, fmt.tprintf("response-%d.bin", sequence))
	deadline := time.tick_add(time.tick_now(), PLAYTEST_TREE_TIMEOUT)
	if asynchronous {
		service.tree_pending[slot] = {sequence, op, deadline}
		vm.PushNumber(L, f64(sequence))
		return 1, true
	}
	for time.tick_diff(time.tick_now(), deadline) > 0 {
		if data, ok := pt_read_file(response); ok {
			defer delete(data)
			_ = os.remove(response)
			return pt_decode_result(L, service.data_model.registry.classes, op, data)
		}
		time.sleep(5 * time.Millisecond)
	}
	return pt_fail(L, "playtest request timed out; edit outcome is unknown")
}


playtest_tree_poll :: proc(L: ^vm.State, service: ^PlaytestService) -> (i32, bool) {
	if !vm.ThreadHasSecurityCapability(L, PROJECT_INTERNALS_CAPABILITY) {
		return vm.RaiseError(L, "Playtest tree APIs require Internals capability"), true
	}
	role := vm.ArgString(L, 2)
	expected := vm.ArgNumber(L, 3)
	if role != "Server" && role != "Client" {return pt_fail(L, "target must be Server or Client")}
	if service.singleplayer {role = "Client"}
	slot := 0 if role == "Server" else 1
	pending := service.tree_pending[slot]
	if pending.sequence == 0 ||
	   expected != f64(pending.sequence) ||
	   !service.running ||
	   service.tree_dir == "" {
		return pt_fail(L, "playtest request is no longer active")
	}
	dir := pt_path(service.tree_dir, role)
	response := pt_path(dir, fmt.tprintf("response-%d.bin", pending.sequence))
	if data, ok := pt_read_file(response); ok {
		defer delete(data)
		_ = os.remove(response)
		service.tree_pending[slot] = {}
		return pt_decode_result(L, service.data_model.registry.classes, pending.op, data)
	}
	if time.tick_diff(time.tick_now(), pending.deadline) <= 0 {
		service.tree_pending[slot] = {}


		_ = os.remove(pt_path(dir, "request.bin"))
		return pt_fail(L, "playtest request timed out; edit outcome is unknown")
	}
	vm.PushNil(L)
	vm.PushNil(L)
	return 2, true
}
