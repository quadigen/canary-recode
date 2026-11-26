package native_api

import classes "../classes"
import datatypes "../datatypes"
import gpu "../gpucompute"
import renderer "../renderer"
import services "../services"
import target "../target"
import vm "../vm"
import odin_runtime "base:runtime"
import "core:strings"

Handle_Slot :: struct {
	object:     ^classes.Object,
	descriptor: ^classes.Class_Descriptor,
	generation: u32,
}

next_handle_generation: u32 = 1

next_generation :: proc() -> u32 {
	result := next_handle_generation
	next_handle_generation += 1
	if next_handle_generation == 0 {next_handle_generation = 1}
	return result
}

Context :: struct {
	script_vm:              ^vm.VM,
	classes:                ^classes.Registry,
	datatypes:              ^datatypes.Registry,
	services:               ^services.Registry,
	renderer:               ^renderer.RendererObject,
	mode:                   target.Mode,
	root:                   ^Context,
	active:                 bool,
	owns_engine:            bool,
	engine_owner:           rawptr,
	plugin_owner:           rawptr,
	gpu_device:             ^gpu.Device,
	last_error:             string,
	handle_slots:           [dynamic]Handle_Slot,
	native_callbacks:       [dynamic]^Native_Registration,
	native_classes:         [dynamic]^Native_Class_Registration,
	native_datatypes:       [dynamic]^Native_Datatype_Registration,
	retired_datatypes:      [dynamic]^Native_Datatype_Registration,
	plugin_id:              string,
	all_connections:        [dynamic]^Native_Connection,
	all_retained_callbacks: [dynamic]^Native_Retained_Callback,
	previous_destroy_hook:  proc(_: ^classes.Object, _: rawptr),
	previous_destroy_ctx:   rawptr,
	plugin_manager:         rawptr,
	plugin_hooks:           Plugin_Manager_Hooks,
}

Context_Init :: proc(
	ctx: ^Context,
	registry: ^classes.Registry,
	datatypes_registry: ^datatypes.Registry,
	service_registry: ^services.Registry,
	script_vm: ^vm.VM,
	renderer_object: ^renderer.RendererObject,
	mode: target.Mode,
) {
	ctx^ = Context {
		script_vm = script_vm,
		classes   = registry,
		datatypes = datatypes_registry,
		services  = service_registry,
		renderer  = renderer_object,
		mode      = mode,
		root      = ctx,
		active    = true,
	}
	if registry != nil {
		ctx.previous_destroy_hook = registry.destroy_hook
		ctx.previous_destroy_ctx = registry.destroy_hook_ctx
		registry.destroy_hook = invalidate_destroyed_object
		registry.destroy_hook_ctx = ctx
	}
}

Context_Borrow :: proc(ctx: ^Context, root: ^Context, owner: rawptr = nil) {
	if root == nil || !root.active {return}
	ctx^ = Context {
		script_vm    = root.script_vm,
		classes      = root.classes,
		datatypes    = root.datatypes,
		services     = root.services,
		renderer     = root.renderer,
		mode         = root.mode,
		root         = root.root,
		active       = true,
		plugin_owner = owner,
	}
}

Context_Disable :: proc(ctx: ^Context) {
	if ctx == nil || !ctx.active {return}
	gpu_compute_release(ctx)
	ctx.active = false
	for registration in ctx.native_callbacks {
		if registration.ctx == ctx && registration.callback != nil {
			sdk_unregister_native_callback(ctx, registration)
		}
		registration.callback = nil
		registration.ctx = nil
	}
}

Context_Destroy :: proc(ctx: ^Context) {
	if ctx == nil {return}
	ClearOwnerConnections(ctx)
	ClearOwnerCallbacks(ctx)
	UnregisterOwnerDatatypes(ctx)
	UnregisterOwnerClasses(ctx)
	Context_Disable(ctx)
	if ctx.root == ctx {
		if ctx.classes != nil && ctx.classes.destroy_hook_ctx == ctx {
			ctx.classes.destroy_hook = ctx.previous_destroy_hook
			ctx.classes.destroy_hook_ctx = ctx.previous_destroy_ctx
		}
		delete(ctx.handle_slots)
		for registration in ctx.retired_datatypes {free(registration)}
		delete(ctx.retired_datatypes)
	}
	delete(ctx.last_error)
	delete(ctx.plugin_id)
	if ctx.root != ctx && ctx.root != nil && ctx.root.active {
		append(&ctx.root.native_callbacks, ..ctx.native_callbacks[:])
	} else {
		for registration in ctx.native_callbacks {
			delete(registration.name)
			delete(registration.library)
			free(registration)
		}
	}
	delete(ctx.native_callbacks)
	ctx.root = nil
}

@(export)
Kinemium_GetABIVersion :: proc "c" () -> u32 {
	return 2
}

@(export)
Kinemium_ContextIsBorrowed :: proc "c" (ctx: ^Context) -> bool {
	return ctx != nil && ctx.active && ctx.plugin_owner != nil
}

@(export)
Kinemium_ContextGetCapabilities :: proc "c" (ctx: ^Context) -> u64 {
	if ctx == nil || !ctx.active {return 0}
	if ctx.plugin_owner != nil {return 1}
	return 0xffffffffffffffff
}

@(export)
Kinemium_ContextGetPlugin :: proc "c" (ctx: ^Context) -> u64 {
	if ctx == nil || !ctx.active || ctx.plugin_owner == nil {return 0}
	return u64(uintptr(ctx.plugin_owner))
}

@(export)
Kinemium_RunLuau :: proc "c" (ctx: ^Context, source: cstring) -> bool {
	context = odin_runtime.default_context()
	if ctx == nil || !ctx.active || source == nil {return false}
	delete(ctx.last_error)
	ctx.last_error = ""
	ok, err := vm.Run(ctx.script_vm, string(source))
	if !ok {ctx.last_error = err}
	return ok
}

@(export)
Kinemium_GetLastErrorLength :: proc "c" (ctx: ^Context) -> u64 {
	context = odin_runtime.default_context()
	if ctx == nil {return 0}
	return u64(len(ctx.last_error))
}

@(export)
Kinemium_CopyLastError :: proc "c" (ctx: ^Context, buffer: [^]u8, capacity: u64) -> u64 {
	context = odin_runtime.default_context()
	if ctx == nil {return 0}
	message := ctx.last_error
	if buffer != nil && capacity > 0 {
		count := min(u64(len(message)), capacity - 1)
		for i in 0 ..< int(count) {buffer[i] = message[i]}
		buffer[int(count)] = 0
	}
	return u64(len(message))
}

@(export)
Kinemium_SetGlobalNumber :: proc "c" (ctx: ^Context, name: cstring, value: f64) -> bool {
	context = odin_runtime.default_context()
	if ctx == nil || name == nil {return false}
	vm.PushNumber(ctx.script_vm.L, value)
	vm.SetGlobal(ctx.script_vm.L, string(name))
	return true
}

@(export)
Kinemium_GetGlobalNumber :: proc "c" (ctx: ^Context, name: cstring, output: ^f64) -> bool {
	context = odin_runtime.default_context()
	if ctx == nil || name == nil || output == nil {return false}
	vm.GetGlobal(ctx.script_vm.L, string(name))
	defer vm.Pop(ctx.script_vm.L)
	value, ok := vm.ToNumber(ctx.script_vm.L, -1)
	if ok {output^ = value}
	return ok
}

@(export)
Kinemium_SetGlobalString :: proc "c" (ctx: ^Context, name: cstring, value: cstring) -> bool {
	context = odin_runtime.default_context()
	if ctx == nil || name == nil || value == nil {return false}
	vm.PushString(ctx.script_vm.L, string(value))
	vm.SetGlobal(ctx.script_vm.L, string(name))
	return true
}

@(export)
Kinemium_CopyGlobalString :: proc "c" (
	ctx: ^Context,
	name: cstring,
	buffer: [^]u8,
	capacity: u64,
) -> i64 {
	context = odin_runtime.default_context()
	if ctx == nil || name == nil {return -1}
	vm.GetGlobal(ctx.script_vm.L, string(name))
	defer vm.Pop(ctx.script_vm.L)
	value, ok := vm.ToString(ctx.script_vm.L, -1)
	if !ok {return -1}
	if buffer != nil && capacity > 0 {
		count := min(u64(len(value)), capacity - 1)
		for i in 0 ..< int(count) {buffer[i] = value[i]}
		buffer[int(count)] = 0
	}
	return i64(len(value))
}

find_object_descriptor :: proc(
	ctx: ^Context,
	object: ^classes.Object,
) -> ^classes.Class_Descriptor {
	if ctx == nil || object == nil {return nil}
	for descriptor in ctx.classes.classes {
		for instance in descriptor.instances {
			if instance == object {return descriptor}
		}
	}
	return nil
}

invalidate_destroyed_object :: proc(object: ^classes.Object, opaque: rawptr) {
	ctx := cast(^Context)opaque
	if ctx == nil || !ctx.active {return}
	for &slot in ctx.root.handle_slots {
		if slot.object == object {
			slot.object = nil
			slot.descriptor = nil
			slot.generation = next_generation()
		}
	}
	if ctx.previous_destroy_hook != nil && ctx.previous_destroy_ctx != ctx {
		ctx.previous_destroy_hook(object, ctx.previous_destroy_ctx)
	}
}

register_handle :: proc(ctx: ^Context, object: ^classes.Object) -> u64 {
	if ctx == nil || !ctx.active || object == nil {return 0}
	descriptor := find_object_descriptor(ctx, object)
	if descriptor == nil || object.destroyed {return 0}
	for slot, i in ctx.root.handle_slots {
		if slot.object == object && slot.descriptor == descriptor {
			return (u64(slot.generation) << 32) | u64(u32(i) + 1)
		}
	}
	for i in 0 ..< len(ctx.root.handle_slots) {
		if ctx.root.handle_slots[i].object == nil {
			ctx.root.handle_slots[i].object = object
			ctx.root.handle_slots[i].descriptor = descriptor
			ctx.root.handle_slots[i].generation = next_generation()
			return (u64(ctx.root.handle_slots[i].generation) << 32) | u64(u32(i) + 1)
		}
	}
	generation := next_generation()
	append(
		&ctx.root.handle_slots,
		Handle_Slot{object = object, descriptor = descriptor, generation = generation},
	)
	return (u64(generation) << 32) | u64(len(ctx.root.handle_slots))
}

resolve_handle :: proc(ctx: ^Context, handle: u64) -> ^classes.Object {
	if ctx == nil || !ctx.active || ctx.root == nil || !ctx.root.active || handle == 0 {return nil}
	index := u32(handle & 0xffffffff)
	generation := u32(handle >> 32)
	if index == 0 || u64(index) > u64(len(ctx.root.handle_slots)) {return nil}
	slot := &ctx.root.handle_slots[int(index) - 1]
	if slot.object == nil || slot.descriptor == nil || slot.generation != generation {return nil}
	found := false
	for candidate in slot.descriptor.instances {
		if candidate == slot.object {
			found = true
			break
		}
	}
	if !found {
		slot.object = nil
		slot.descriptor = nil
		slot.generation = next_generation()
		return nil
	}
	if slot.object.destroyed {return nil}
	return slot.object
}

@(export)
Kinemium_HandleService :: proc "c" (ctx: ^Context, name: cstring) -> u64 {
	context = odin_runtime.default_context()
	if ctx == nil || name == nil {return 0}
	object := services.DataModel_Get_Service(ctx.services.data_model, string(name))
	return register_handle(ctx, object)
}

@(export)
Kinemium_HandleCreateInstance :: proc "c" (ctx: ^Context, class_name: cstring) -> u64 {
	context = odin_runtime.default_context()
	if ctx == nil ||
	   !ctx.active ||
	   ctx.script_vm == nil ||
	   ctx.script_vm.L == nil ||
	   class_name == nil {return 0}
	L := ctx.script_vm.L
	if !vm.CheckStack(L, 16) {
		sdk_error(ctx, "insufficient Luau stack space for Instance creation")
		return 0
	}
	top := vm.StackTop(L)
	defer vm.SetStackTop(L, top)
	object, ok := classes.Push_New(ctx.classes, ctx.script_vm, string(class_name))
	if !ok {return 0}
	return register_handle(ctx, object)
}

@(export)
Kinemium_HandleIsValid :: proc "c" (ctx: ^Context, handle: u64) -> bool {
	context = odin_runtime.default_context()
	return resolve_handle(ctx, handle) != nil
}

@(export)
Kinemium_HandleSetName :: proc "c" (ctx: ^Context, handle: u64, name: cstring) -> bool {
	context = odin_runtime.default_context()
	object := resolve_handle(ctx, handle)
	if object == nil || name == nil {return false}
	classes.Set_Name(object, string(name))
	return true
}

@(export)
Kinemium_HandleSetParent :: proc "c" (ctx: ^Context, handle: u64, parent: u64) -> bool {
	context = odin_runtime.default_context()
	object := resolve_handle(ctx, handle)
	if object == nil {return false}
	parent_object: ^classes.Object
	if parent != 0 {
		parent_object = resolve_handle(ctx, parent)
		if parent_object == nil {return false}
	}
	if parent_object == object ||
	   (parent_object != nil && classes.Is_Descendant_Of(parent_object, object)) {return false}
	classes.Set_Parent(object, parent_object)
	return true
}

@(export)
Kinemium_HandleGetParent :: proc "c" (ctx: ^Context, handle: u64) -> u64 {
	context = odin_runtime.default_context()
	object := resolve_handle(ctx, handle)
	if object == nil {return 0}
	return register_handle(ctx, classes.Get_Parent(object))
}

@(export)
Kinemium_HandleFindChild :: proc "c" (ctx: ^Context, handle: u64, name: cstring) -> u64 {
	context = odin_runtime.default_context()
	object := resolve_handle(ctx, handle)
	if object == nil || name == nil {return 0}
	return register_handle(ctx, classes.Find_First_Child(object, string(name)))
}

@(export)
Kinemium_HandleRelease :: proc "c" (ctx: ^Context, handle: u64) -> bool {
	context = odin_runtime.default_context()
	if ctx == nil || !ctx.active || handle == 0 {return false}
	index := u32(handle & 0xffffffff)
	generation := u32(handle >> 32)
	if index == 0 || u64(index) > u64(len(ctx.root.handle_slots)) {return false}
	slot := &ctx.root.handle_slots[int(index) - 1]
	if slot.object == nil || slot.generation != generation {return false}
	slot.object = nil
	slot.descriptor = nil
	slot.generation = next_generation()
	return true
}

@(export)
Kinemium_HandleGetChildCount :: proc "c" (ctx: ^Context, handle: u64) -> u64 {
	context = odin_runtime.default_context()
	object := resolve_handle(ctx, handle)
	if object == nil {return 0}
	return u64(len(classes.Get_Children(object)))
}

@(export)
Kinemium_HandleGetChildAt :: proc "c" (ctx: ^Context, handle: u64, index: u64) -> u64 {
	context = odin_runtime.default_context()
	object := resolve_handle(ctx, handle)
	if object == nil {return 0}
	children := classes.Get_Children(object)
	if index >= u64(len(children)) {return 0}
	return register_handle(ctx, children[int(index)])
}

@(export)
Kinemium_HandleIsA :: proc "c" (ctx: ^Context, handle: u64, class_name: cstring) -> bool {
	context = odin_runtime.default_context()
	object := resolve_handle(ctx, handle)
	if object == nil || class_name == nil {return false}
	return classes.Is_A(object, string(class_name))
}

@(export)
Kinemium_HandleCopyName :: proc "c" (
	ctx: ^Context,
	handle: u64,
	buffer: [^]u8,
	capacity: u64,
) -> i64 {
	context = odin_runtime.default_context()
	object := resolve_handle(ctx, handle)
	if object == nil {return -1}
	name := classes.Get_Name(object)
	if buffer != nil && capacity > 0 {
		count := min(u64(len(name)), capacity - 1)
		for i in 0 ..< int(count) {buffer[i] = name[i]}
		buffer[int(count)] = 0
	}
	return i64(len(name))
}

@(export)
Kinemium_HandleCopyClassName :: proc "c" (
	ctx: ^Context,
	handle: u64,
	buffer: [^]u8,
	capacity: u64,
) -> i64 {
	context = odin_runtime.default_context()
	object := resolve_handle(ctx, handle)
	if object == nil {return -1}
	name := classes.Get_Class_Name(object)
	if buffer != nil && capacity > 0 {
		count := min(u64(len(name)), capacity - 1)
		for i in 0 ..< int(count) {buffer[i] = name[i]}
		buffer[int(count)] = 0
	}
	return i64(len(name))
}

@(export)
Kinemium_HandleGetBooleanProperty :: proc "c" (
	ctx: ^Context,
	handle: u64,
	property: cstring,
	output: ^bool,
) -> bool {
	context = odin_runtime.default_context()
	object := resolve_handle(ctx, handle)
	if object == nil || property == nil || output == nil {return false}
	switch string(property) {
	case "Archivable":
		output^ = object.archivable
	case "CanReplicate":
		output^ = object.can_replicate
	case "Sandboxed":
		output^ = object.sandboxed
	case "Destroyed":
		output^ = object.destroyed
	case:
		return false
	}
	return true
}

@(export)
Kinemium_HandleSetBooleanProperty :: proc "c" (
	ctx: ^Context,
	handle: u64,
	property: cstring,
	value: bool,
) -> bool {
	context = odin_runtime.default_context()
	object := resolve_handle(ctx, handle)
	if object == nil || property == nil {return false}
	switch string(property) {
	case "Archivable":
		object.archivable = value
	case "CanReplicate":
		object.can_replicate = value
	case:
		return false
	}
	return true
}

@(export)
Kinemium_HandleGetNumberProperty :: proc "c" (
	ctx: ^Context,
	handle: u64,
	property: cstring,
	output: ^f64,
) -> bool {
	context = odin_runtime.default_context()
	object := resolve_handle(ctx, handle)
	if object == nil || property == nil || output == nil {return false}
	switch string(property) {
	case "NetworkId":
		output^ = f64(object.network_id)
	case:
		return false
	}
	return true
}

@(export)
Kinemium_HandleCopyStringProperty :: proc "c" (
	ctx: ^Context,
	handle: u64,
	property: cstring,
	buffer: [^]u8,
	capacity: u64,
) -> i64 {
	context = odin_runtime.default_context()
	object := resolve_handle(ctx, handle)
	if object == nil || property == nil {return -1}
	value: string
	switch string(property) {
	case "Name":
		value = classes.Get_Name(object)
	case "ClassName":
		value = classes.Get_Class_Name(object)
	case "ReplicationGroup":
		value = object.replication_group
	case:
		return -1
	}
	if buffer != nil && capacity > 0 {
		count := min(u64(len(value)), capacity - 1)
		for i in 0 ..< int(count) {buffer[i] = value[i]}
		buffer[int(count)] = 0
	}
	return i64(len(value))
}

@(export)
Kinemium_HandleSetStringProperty :: proc "c" (
	ctx: ^Context,
	handle: u64,
	property: cstring,
	value: cstring,
) -> bool {
	context = odin_runtime.default_context()
	object := resolve_handle(ctx, handle)
	if object == nil || property == nil || value == nil {return false}
	switch string(property) {
	case "Name":
		classes.Set_Name(object, string(value))
	case "ReplicationGroup":
		delete(object.replication_group)
		object.replication_group = strings.clone(string(value))
	case:
		return false
	}
	return true
}

@(export)
Kinemium_HandleGetPropertyCount :: proc "c" (ctx: ^Context, handle: u64) -> u64 {
	context = odin_runtime.default_context()
	object := resolve_handle(ctx, handle)
	if object == nil {return 0}
	properties := classes.Get_Properties(ctx.classes, object)
	defer delete(properties)
	return u64(len(properties))
}

@(export)
Kinemium_HandleCopyPropertyName :: proc "c" (
	ctx: ^Context,
	handle: u64,
	index: u64,
	buffer: [^]u8,
	capacity: u64,
) -> i64 {
	context = odin_runtime.default_context()
	object := resolve_handle(ctx, handle)
	if object == nil {return -1}
	properties := classes.Get_Properties(ctx.classes, object)
	defer delete(properties)
	if index >= u64(len(properties)) {return -1}
	name := properties[int(index)]
	if buffer != nil && capacity > 0 {
		count := min(u64(len(name)), capacity - 1)
		for i in 0 ..< int(count) {buffer[i] = name[i]}
		buffer[int(count)] = 0
	}
	return i64(len(name))
}

@(export)
Kinemium_HandleHasProperty :: proc "c" (ctx: ^Context, handle: u64, name: cstring) -> bool {
	context = odin_runtime.default_context()
	object := resolve_handle(ctx, handle)
	if object == nil || name == nil {return false}
	properties := classes.Get_Properties(ctx.classes, object)
	defer delete(properties)
	for property in properties {
		if property == string(name) {return true}
	}
	return false
}

property_exists :: proc(ctx: ^Context, object: ^classes.Object, name: string) -> bool {
	properties := classes.Get_Properties(ctx.classes, object)
	defer delete(properties)
	for property in properties {
		if property == name {return true}
	}
	return false
}

@(export)
Kinemium_HandleGetDynamicNumber :: proc "c" (
	ctx: ^Context,
	handle: u64,
	property: cstring,
	output: ^f64,
) -> bool {
	context = odin_runtime.default_context()
	object := resolve_handle(ctx, handle)
	if ctx == nil || property == nil || output == nil || object == nil {return false}
	L := ctx.script_vm.L
	top := vm.StackTop(L)
	defer vm.SetStackTop(L, top)
	if !sdk_property_get(ctx, object, string(property)) {return false}
	if vm.TypeOf(L, -1) != .Number && vm.TypeOf(L, -1) != .Integer {
		sdk_error(ctx, "property is not a number")
		return false
	}
	value, ok := vm.ToNumber(L, -1)
	if !ok {return false}
	output^ = value
	sdk_clear_error(ctx)
	return true
}

@(export)
Kinemium_HandleGetDynamicString :: proc "c" (
	ctx: ^Context,
	handle: u64,
	property: cstring,
	buffer: [^]u8,
	capacity: u64,
) -> i64 {
	context = odin_runtime.default_context()
	object := resolve_handle(ctx, handle)
	if ctx == nil || property == nil || object == nil {return -1}
	L := ctx.script_vm.L
	top := vm.StackTop(L)
	defer vm.SetStackTop(L, top)
	if !sdk_property_get(ctx, object, string(property)) {return -1}
	value, ok := vm.ToString(L, -1)
	if !ok {
		sdk_error(ctx, "property is not a string")
		return -1
	}
	result := sdk_copy_string(value, buffer, capacity)
	sdk_clear_error(ctx)
	return result
}
