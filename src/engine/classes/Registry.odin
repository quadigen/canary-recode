package classes

import "base:runtime"
import "core:fmt"
import "core:strings"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import renderer "../renderer"
import signals "../signals"
import target "../target"

Renderer_Object   :: renderer.RendererObject
Class_Constructor :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object
Class_Destructor  :: proc(object: ^Object, renderer: ^Renderer_Object)
Class_Getter      :: proc(L: ^vm.State, object: ^Object, datatypes: ^datatypes.Registry, enums: ^enums.Registry, key: string) -> bool
Class_Setter      :: proc(L: ^vm.State, object: ^Object, datatypes: ^datatypes.Registry, enums: ^enums.Registry, key: string, value_index: int) -> bool
Class_Namecall    :: proc(L: ^vm.State, object: ^Object, datatypes: ^datatypes.Registry, enums: ^enums.Registry, method: string) -> (i32, bool)
Class_Clone       :: proc(source: ^Object, destination: ^Object)
Require_Resolver  :: proc(L: ^vm.State, path: string, ctx: rawptr) -> bool

Class_Step_Phase :: enum {
	Update,
	Render_3D,
	Render_2D,
}

Class_Step_Context :: struct {
	L:               ^vm.State,
	delta_time:      f32,
	renderer:        ^Renderer_Object,
	data_model:      rawptr,
	viewport_width:  i32,
	viewport_height: i32,
	gui_overlay:     bool,
}

Class_Step :: proc(object: ^Object, ctx: ^Class_Step_Context)

class_step_target :: struct {
	object: ^Object,
	_step:  Class_Step,
}

Member_Access :: enum {
	Read,
	Write,
	Call,
}

Member_Security :: struct {
	name:        string,
	access:      Member_Access,
	requirement: vm.Security_Requirement,
}

Property_Read_Security :: proc(
	name: string,
	requirement: vm.Security_Requirement,
) -> Member_Security {
	return Member_Security{
		name = name,
		access = .Read,
		requirement = requirement,
	}
}

Property_Write_Security :: proc(
	name: string,
	requirement: vm.Security_Requirement,
) -> Member_Security {
	return Member_Security{
		name = name,
		access = .Write,
		requirement = requirement,
	}
}

Method_Security :: proc(
	name: string,
	requirement: vm.Security_Requirement,
) -> Member_Security {
	return Member_Security{
		name = name,
		access = .Call,
		requirement = requirement,
	}
}

Class_Descriptor :: struct {
	info:             ^Class_Info,
	construct:        Class_Constructor,
	destroy:          Class_Destructor,
	get:              Class_Getter,
	set:              Class_Setter,
	namecall:         Class_Namecall,
	_step:            Class_Step,
	_step_phase:      Class_Step_Phase,
	creatable:        bool,
	clone:            Class_Clone,
	binding:          vm.Userdata_Binding,
	registry:         ^Registry,
	instances:        [dynamic]^Object,
	properties:       [dynamic]string,
	member_security:  [dynamic]Member_Security,
}

Pending_Destroy :: struct {
	object:     ^Object,
	descriptor: ^Class_Descriptor,
}

Destroy_Hook :: proc(object: ^Object, ctx: rawptr)

Network_Ownership_Dispatch :: proc(
	ctx: rawptr,
	L: ^vm.State,
	object: ^Object,
	method: string,
) -> (i32, bool)

Remote_Call_Dispatch :: proc(
	ctx: rawptr,
	L: ^vm.State,
	instance: ^Object,
	method: string,
) -> (i32, bool)

Registry :: struct {
	classes:              [dynamic]^Class_Descriptor,
	datatypes:            ^datatypes.Registry,
	enums:                ^enums.Registry,
	renderer:             ^Renderer_Object,
	data_model:           rawptr,
	vm_state:             ^vm.VM,
	signal_registry:      ^signals.Registry,
	fallback_require_ref: i32,
	require_resolver:     Require_Resolver,
	require_resolver_ctx: rawptr,
	mode:                 target.Mode,
	pending_destroy:      [dynamic]Pending_Destroy,
	destroy_hook:         Destroy_Hook,
	destroy_hook_ctx:     rawptr,
	network_ownership:    Network_Ownership_Dispatch,
	network_ownership_ctx: rawptr,
	remote_call:          Remote_Call_Dispatch,
	remote_call_ctx:      rawptr,
}

Registry_Init :: proc(
	datatype_registry: ^datatypes.Registry = nil,
	enum_registry: ^enums.Registry = nil,
	renderer: ^Renderer_Object = nil,
	data_model: rawptr = nil,
	signal_registry: ^signals.Registry = nil,
) -> Registry {
	return Registry{
		datatypes = datatype_registry,
		enums = enum_registry,
		renderer = renderer,
		data_model = data_model,
		signal_registry = signal_registry,
		mode = target.current_mode,
	}
}

Set_Data_Model :: proc(registry: ^Registry, data_model: rawptr) {
	if registry == nil { return }
	registry.data_model = data_model
}

Set_Mode :: proc(registry: ^Registry, mode: target.Mode) {
	if registry == nil { return }
	registry.mode = mode
}

Set_Require_Resolver :: proc(registry: ^Registry, resolver: Require_Resolver, ctx: rawptr) {
	if registry == nil { return }
	registry.require_resolver = resolver
	registry.require_resolver_ctx = ctx
}

Set_Network_Ownership :: proc(registry: ^Registry, dispatch: Network_Ownership_Dispatch, ctx: rawptr) {
	if registry == nil { return }
	registry.network_ownership = dispatch
	registry.network_ownership_ctx = ctx
}

Set_Remote_Call :: proc(registry: ^Registry, dispatch: Remote_Call_Dispatch, ctx: rawptr) {
	if registry == nil { return }
	registry.remote_call = dispatch
	registry.remote_call_ctx = ctx
}

Can_Access_Member :: proc(
	L: ^vm.State,
	descriptor: ^Class_Descriptor,
	name: string,
	access: Member_Access,
) -> bool {
	if descriptor == nil {
		return true
	}

	for rule in descriptor.member_security {
		if rule.name == name && rule.access == access {
			return vm.ThreadMeetsSecurityRequirement(L, rule.requirement)
		}
	}

	return true
}

descriptor_get :: proc(L: ^vm.State, value, ctx: rawptr, key: string) -> bool {
	descriptor := cast(^Class_Descriptor)ctx
	object := cast(^Object)value

	if object == nil {
		_ = vm.RaiseError(L, "attempt to access a destroyed Instance")
		return true
	}

	if !Object_Is_Accessible(L, object) {
		_ = vm.RaiseError(L, "insufficient security capabilities to access this Instance")
		return true
	}

	if !Can_Access_Member(L, descriptor, key, .Read) {
		_ = vm.RaiseError(L, "insufficient security capabilities to read this member")
		return true
	}

	if descriptor != nil && descriptor.get != nil &&
	   descriptor.get(
		L,
		object,
		descriptor.registry.datatypes,
		descriptor.registry.enums,
		key,
	   ) {
		return true
	}

	return Object_Get_Property(L, value, ctx, key)
}

descriptor_set :: proc(
	L: ^vm.State,
	value, ctx: rawptr,
	key: string,
	value_index: int,
) -> bool {
	descriptor := cast(^Class_Descriptor)ctx
	object := cast(^Object)value

	if object == nil {
		_ = vm.RaiseError(L, "attempt to access a destroyed Instance")
		return true
	}

	if !Object_Is_Accessible(L, object) {
		_ = vm.RaiseError(L, "insufficient security capabilities to access this Instance")
		return true
	}

	if !Can_Access_Member(L, descriptor, key, .Write) {
		_ = vm.RaiseError(L, "insufficient security capabilities to write this member")
		return true
	}

	if descriptor != nil && descriptor.set != nil &&
	   descriptor.set(
		L,
		object,
		descriptor.registry.datatypes,
		descriptor.registry.enums,
		key,
		value_index,
	   ) {
		return true
	}

	return Object_Set_Property(L, value, ctx, key, value_index)
}

append_properties :: proc(
    registry: ^Registry,
    class: ^Class_Info,
    result: ^[dynamic]string,
) {
    if registry == nil || class == nil {
        return
    }

    append_properties(registry, class.parent, result)

    descriptor := Find_Class(registry, class.name)
    if descriptor == nil {
        return
    }

    for property in descriptor.properties {
        append(result, property)
    }
}

Get_Properties :: proc(
    registry: ^Registry,
    object: ^Object,
) -> [dynamic]string {
    result: [dynamic]string

    if registry == nil || object == nil {
        return result
    }

    append_properties(registry, object.class, &result)

    return result
}

Class_Property_List :: proc(
    registry: ^Registry,
    class_name: string,
) -> [dynamic]string {
    result: [dynamic]string

    if registry == nil {
        return result
    }

    descriptor := Find_Class(registry, class_name)
    if descriptor == nil {
        return result
    }

    append_properties(registry, descriptor.info, &result)

    return result
}

descriptor_namecall :: proc(
	L: ^vm.State,
	value, ctx: rawptr,
	method: string,
) -> (i32, bool) {
	descriptor := cast(^Class_Descriptor)ctx
	object := cast(^Object)value

	if object == nil {
		return vm.RaiseError(L, "attempt to access a destroyed Instance"), true
	}

	if !Object_Is_Accessible(L, object) {
		return vm.RaiseError(L, "insufficient security capabilities to access this Instance"), true
	}

	if !Can_Access_Member(L, descriptor, method, .Call) {
		return vm.RaiseError(L, "insufficient security capabilities to call this member"), true
	}

	if descriptor.registry != nil &&
	   descriptor.registry.network_ownership != nil {
		switch method {
		case "SetNetworkOwner", "GetNetworkOwner", "SetNetworkOwnershipAuto":
			result_count, handled := descriptor.registry.network_ownership(
				descriptor.registry.network_ownership_ctx,
				L,
				object,
				method,
			)
			if handled {
				return result_count, true
			}
		}
	}

	if descriptor.registry != nil &&
	   descriptor.registry.remote_call != nil {
		switch method {
		case "FireServer", "FireClient", "FireAllClients",
		     "InvokeServer", "InvokeClient", "InvokeClients":
			result_count, handled := descriptor.registry.remote_call(
				descriptor.registry.remote_call_ctx,
				L,
				object,
				method,
			)
			if handled {
				return result_count, true
			}
		}
	}

	if descriptor != nil && descriptor.namecall != nil {
		result_count, handled := descriptor.namecall(
			L,
			object,
			descriptor.registry.datatypes,
			descriptor.registry.enums,
			method,
		)
		if handled {
			return result_count, true
		}
	}

	return Object_Namecall(L, value, ctx, method)
}

descriptor_string :: proc(value, ctx: rawptr) -> string {
	return To_String(cast(^Object)value)
}

descriptor_destroy :: proc(value, ctx: rawptr) {
	descriptor := cast(^Class_Descriptor)ctx
	object := cast(^Object)value

	if descriptor != nil {
		for instance, index in descriptor.instances {
			if instance == object {
				ordered_remove(&descriptor.instances, index)
				break
			}
		}
	}

	if descriptor != nil && descriptor.destroy != nil {
		descriptor.destroy(object, descriptor.registry.renderer)
	}
}

Register_Class :: proc(
	registry: ^Registry,
	info: ^Class_Info,
	construct: Class_Constructor,
	destroy: Class_Destructor,
	creatable := true,
	get: Class_Getter = nil,
	set: Class_Setter = nil,
	namecall: Class_Namecall = nil,
	_step: Class_Step = nil,
	_step_phase: Class_Step_Phase = .Render_2D,
	clone: Class_Clone = nil,
	properties: []string = nil,
	member_security: []Member_Security = nil,
) {
	assert(registry != nil)
	assert(info != nil)
	assert(construct != nil)
	assert(destroy != nil)

	descriptor := new(Class_Descriptor)
	descriptor^ = Class_Descriptor{
		info        = info,
		construct   = construct,
		destroy     = destroy,
		get         = get,
		set         = set,
		namecall    = namecall,
		_step       = _step,
		_step_phase = _step_phase,
		creatable   = creatable,
		clone       = clone,
		registry    = registry,
	}

	for property in properties {
		append(&descriptor.properties, property)
	}

	for rule in member_security {
		append(&descriptor.member_security, rule)
	}

	descriptor.binding = vm.Userdata_Binding{
		name     = "Instance",
		ctx      = descriptor,
		get      = descriptor_get,
		set      = descriptor_set,
		namecall = descriptor_namecall,
		string   = descriptor_string,
		destroy  = descriptor_destroy,
	}

	append(&registry.classes, descriptor)
}

Find_Class :: proc(registry: ^Registry, name: string) -> ^Class_Descriptor {
	if registry == nil {
		return nil
	}

	for descriptor in registry.classes {
		if descriptor.info.name == name {
			return descriptor
		}
	}

	return nil
}

Clone_Class_State :: proc(
	registry: ^Registry,
	info: ^Class_Info,
	source: ^Object,
	destination: ^Object,
) {
	if registry == nil || info == nil {
		return
	}

	// Copy base-class state first.
	if info.parent != nil {
		Clone_Class_State(
			registry,
			info.parent,
			source,
			destination,
		)
	}

	descriptor := Find_Class(registry, info.name)

	if descriptor != nil && descriptor.clone != nil {
		descriptor.clone(source, destination)
	}
}

Push_New :: proc(
	registry: ^Registry,
	vm_state: ^vm.VM,
	class_name: string,
	require_creatable := true,
) -> (^Object, bool) {
	descriptor := Find_Class(registry, class_name)
	if descriptor == nil || (require_creatable && !descriptor.creatable) {
		return nil, false
	}

	object := descriptor.construct(registry.renderer, registry.data_model)
	if object == nil {
		return nil, false
	}

	object.signal_registry = registry

	vm.PushUserdata(vm_state, object, &descriptor.binding)
	object.lua_ref = vm.RetainValue(vm_state.L)
	append(&descriptor.instances, object)

	return object, true
}

// Flush_Pending_Destroy frees the native memory of every destroyed Instance.
// Destroyed objects are kept alive until the next Step so in-flight code that
// still holds a pointer (guand by the destroyed flag) never reads freed
// memory.
Flush_Pending_Destroy :: proc(registry: ^Registry) {
	if registry == nil {
		return
	}

	pending := registry.pending_destroy
	registry.pending_destroy = nil

	for pending_destroy in pending {
		if pending_destroy.object == nil || pending_destroy.descriptor == nil {
			continue
		}

		object := pending_destroy.object
		descriptor := pending_destroy.descriptor

		for instance, index in descriptor.instances {
			if instance == object {
				ordered_remove(&descriptor.instances, index)
				break
			}
		}

		if descriptor.registry != nil && descriptor.registry.renderer != nil &&
		   descriptor.registry.renderer.ActiveCamera == object {
			descriptor.registry.renderer.ActiveCamera = nil
		}

		if registry.destroy_hook != nil {
			registry.destroy_hook(object, registry.destroy_hook_ctx)
		}

		if descriptor.destroy != nil {
			descriptor.destroy(object, descriptor.registry.renderer)
		}
	}

	delete(pending)
}

Step :: proc(
	registry: ^Registry,
	L: ^vm.State,
	delta_time: f32,
	viewport_width: i32 = 0,
	viewport_height: i32 = 0,
	phase: Class_Step_Phase = .Render_2D,
	gui_overlay: bool = false,
) {
	if registry == nil || L == nil { return }

	Flush_Pending_Destroy(registry)

	targets: [dynamic]class_step_target

	for descriptor in registry.classes {
		if descriptor._step == nil || descriptor._step_phase != phase { continue }
		for object in descriptor.instances {
			if object != nil && !object.destroyed {
				append(&targets, class_step_target{object, descriptor._step})
			}
		}
	}

	step_context := Class_Step_Context{
		L = L,
		delta_time = delta_time,
		renderer = registry.renderer,
		data_model = registry.data_model,
		viewport_width = viewport_width,
		viewport_height = viewport_height,
		gui_overlay = gui_overlay,
	}

	for target in targets {
		if target.object != nil && !target.object.destroyed {
			target._step(target.object, &step_context)
		}
	}

	delete(targets)
}

instance_new :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	registry := cast(^Registry)vm.UpvaluePointer(L)
	class_name := vm.ArgString(L, 1)

	parent: ^Object
	if !vm.IsNoneOrNil(L, 2) {
		parent = object_from_argument(L, 2)
		if parent == nil {
			return vm.RaiseError(L, "Instance.new parent must be an Instance or nil")
		}
	}

	object, ok := Push_New(registry, &vm.VM{L = L}, class_name)
	if !ok {
		return vm.RaiseError(L, "unknown or non-creatable class")
	}

	if parent != nil {
		Set_Parent(object, parent)
	}

	return 1
}

// Script_Require_Context_Of reports whether a script Instance may be required in
// a runtime with the given role. Roblox modules run where they belong: a
// ModuleScript is portable, a Script belongs to a server runtime and a
// LocalScript to a client runtime. Editor runtimes host either side so in-editor
// playtesting can require both.
Script_Require_Context_Of :: proc(object: ^Object, mode: target.Mode) -> bool {
	kind, ok := Script_Kind_Of(object)
	if !ok {
		return false
	}
	switch mode {
	case .Server:
		return kind != .LocalScript
	case .Client:
		return kind != .Script
	case .Standalone:
		return true
	case .Editor:
		return true
	}
	return false
}

require_fallback :: proc(L: ^vm.State, registry: ^Registry) -> i32 {
	if registry == nil || registry.fallback_require_ref <= 0 {
		return vm.RaiseError(L, "require expects a ModuleScript")
	}

	vm.PushRegistryReference(L, registry.fallback_require_ref)
	vm.PushValue(L, 1)
	ok, err := vm.ProtectedCall(L, 1, 1)
	if !ok {
		return vm.RaiseOwnedError(L, &err)
	}

	return 1
}

REQUIRE_RESULT_COUNT_ERROR :: "Module code did not return exactly one value"

// require_continuation completes a require that may have suspended.
//
// Luau invokes this after the protected call started by require_script
// finishes, either immediately (the module did not yield) or when the calling
// thread is resumed (the module yielded via task.wait and friends). It caches
// the module result and produces require's return value.
require_continuation :: proc "c" (L: ^vm.State, status: i32) -> i32 {
	context = runtime.default_context()

	object := object_from_argument(L, 1)
	common := Script_Common_Of(object)
	if object == nil || common == nil || !Script_Is_Script(object) {
		if status != 0 {
			// Preserve the original error rather than masking it.
			return vm.Reraise(L)
		}
		return 1
	}

	if status != 0 {
		// The module raised. Roblox does not cache a failed module, so reset the
		// state and let the error propagate to the caller.
		common.module_state = .Unloaded
		return vm.Reraise(L)
	}

	// Stack layout is [argument 1 (the ModuleScript), ...results].
	result_count := vm.StackTop(L) - 1
	if result_count != 1 {
		common.module_state = .Unloaded
		return vm.RaiseError(
			L,
			strings.concatenate({
				REQUIRE_RESULT_COUNT_ERROR,
				": ",
				Get_Full_Name(object),
			}),
		)
	}

	// Retain the module's return value. `lua_ref` returns 0 for nil, which is
	// still a valid cached result and pushed back as nil on later requires.
	common.module_ref = vm.RetainValue(L)
	common.module_state = .Loaded
	return 1
}

// require_script implements Roblox's require() as a runtime operation:
//
//  1. validate the argument is a ModuleScript (or a Script/LocalScript, which
//     Roblox accepts and runs exactly like a module)
//  2. resolve the module's execution context (the calling VM)
//  3. consult that context's module cache
//  4. return the cached value when the module is already initialized
//  5. detect a circular dependency through the Loading state
//  6. execute the module in its own environment
//  7. capture the returned value, cache it and return it to the caller
//
// It is installed with a continuation so a module may yield; the cache write
// therefore happens in require_continuation once execution completes.
require_script :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	registry := cast(^Registry)vm.UpvaluePointer(L)

	// Engine-internal modules are addressed by string path ("@internal/...").
	if vm.IsString(L, 1) {
		path := vm.ArgString(L, 1)
		if registry != nil &&
		   registry.require_resolver != nil &&
		   registry.require_resolver(L, path, registry.require_resolver_ctx) {
			return 1
		}
		return require_fallback(L, registry)
	}

	object := object_from_argument(L, 1)
	if object == nil {
		return vm.RaiseError(
			L,
			"require expects a ModuleScript, got a non-Instance value",
		)
	}
	if !Script_Is_Script(object) {
		describe := Script_Describe(object)
		defer delete(describe)
		return vm.RaiseError(
			L,
			strings.concatenate({
				"require expects a ModuleScript, got ",
				describe,
			}),
		)
	}
	if object.destroyed {
		return vm.RaiseError(L, "require: the script has been destroyed")
	}

	common := Script_Common_Of(object)
	if common == nil {
		return vm.RaiseError(L, "require: the script has no script state")
	}

	// A Script may only be required by a server runtime and a LocalScript only by
	// a client runtime; ModuleScripts work in both. The check is skipped when the
	// class registry has no runtime role attached (bare VM harnesses).
	if registry != nil && !Script_Require_Context_Of(object, registry.mode) {
		describe := Script_Describe(object)
		defer delete(describe)
		reason := "a client runtime"
		if registry.mode == .Server {
			reason = "a server runtime"
		}
		return vm.RaiseError(
			L,
			strings.concatenate({
				"require: ",
				describe,
				" cannot be required from ",
				reason,
			}),
		)
	}

	switch common.module_state {
	case .Loaded:
		// Cached result; register 0 represents a cached nil.
		if common.module_ref > 0 {
			vm.PushRegistryReference(L, common.module_ref)
		} else {
			vm.PushNil(L)
		}
		return 1
	case .Loading:
		describe := Get_Full_Name(object)
		return vm.RaiseError(
			L,
			strings.concatenate({
				"cyclic require detected while loading ",
				describe,
			}),
		)
	case .Unloaded:
	}

	if registry == nil || registry.vm_state == nil || registry.vm_state.L == nil {
		return vm.RaiseError(L, "require: the script runtime is unavailable")
	}

	// Mark as loading before executing so a nested require of the same module
	// is reported as a circular dependency instead of recursing forever.
	common.module_state = .Loading

	// Luau formats a chunk name that does not start with '=' as
	// [string "<name"]:<line>; using the instance name keeps required-module
	// errors readable while the surrounding report names the full path.
	chunk_name := Get_Name(object)

	ok, err := vm.LoadSource(registry.vm_state, L, common.source, chunk_name)
	if !ok {
		common.module_state = .Unloaded
		return vm.RaiseOwnedError(L, &err)
	}

	if !Script_Apply_Environment(L, object) {
		common.module_state = .Unloaded
		return vm.RaiseError(L, "require: failed to create the ModuleScript environment")
	}

	// [argument 1 (the ModuleScript), module chunk]
	//
	// Yieldable protected call: the continuation caches the result. A negative
	// return value means the module suspended and the yield must propagate.
	return vm.CallYieldableProtected(L, 0, vm.MULTIPLE_RESULTS)
}

Install_Instance_Library :: proc(registry: ^Registry, vm_state: ^vm.VM) {
	registry.vm_state = vm_state

	vm.NewTable(vm_state.L, 0, 1)
	vm.PushLightUserdata(vm_state.L, registry)
	vm.PushFunction(vm_state.L, "Instance.new", instance_new, 1)
	vm.SetField(vm_state.L, -2, "new")
	vm.SetGlobalFromStack(vm_state, "Instance")

	// Preserve the stock Luau require (used by the engine's internal module
	// loader) before replacing the global with the script-aware version.
	_ = vm.GetGlobal(vm_state.L, "require")
	registry.fallback_require_ref = vm.RetainValue(vm_state.L)
	vm.Pop(vm_state.L)

	vm.PushLightUserdata(vm_state.L, registry)
	vm.PushFunctionWithContinuation(
		vm_state.L,
		"require",
		require_script,
		require_continuation,
		1,
	)
	vm.SetGlobalFromStack(vm_state, "require")
}


Register_Default_Classes :: proc(registry: ^Registry) {
	// wire:begin classes
	Register_Instance(registry)
	Register_ArcHandles(registry)
	Register_BlurImageFilter(registry)
	Register_BoolValue(registry)
	Register_BrickColorValue(registry)
	Register_Camera(registry)
	Register_CFrameValue(registry)
	Register_CharacterAnimator(registry)
	Register_CharacterCamera(registry)
	Register_CharacterController(registry)
	Register_CharacterInput(registry)
	Register_CharacterModel(registry)
	Register_CharacterMotor(registry)
	Register_CollisionController(registry)
	Register_Color3Value(registry)
	Register_ColorSequenceValue(registry)
	Register_Decal(registry)
	Register_DoubleConstrainedValue(registry)
	Register_Folder(registry)
	Register_Frame(registry)
	Register_GroundDetector(registry)
	Register_GuiButton(registry)
	Register_GuiObject(registry)
	Register_Handles(registry)
	Register_Humanoid(registry)
	Register_ImageButton(registry)
	Register_ImageLabel(registry)
	Register_InputObject(registry)
	Register_IntConstrainedValue(registry)
	Register_IntValue(registry)
	Register_Light(registry)
	Register_Lighting_Effect(registry)
	Register_LocalScript(registry)
	Register_MeshPart(registry)
	Register_Model(registry)
	Register_ModuleScript(registry)
	Register_MovementController(registry)
	Register_NumberRangeValue(registry)
	Register_NumberSequenceValue(registry)
	Register_NumberValue(registry)
	Register_ObjectValue(registry)
	Register_Part(registry)
	Register_PointLight(registry)
	Register_PostProcessShader(registry)
	Register_RayValue(registry)
	Register_RemoteEvent(registry)
	Register_RemoteFunction(registry)
	Register_RotationController(registry)
	Register_ScreenGui(registry)
	Register_Script(registry)
	Register_ScrollingFrame(registry)
	Register_Sound(registry)
	Register_SpotLight(registry)
	Register_StateMachine(registry)
	Register_StringValue(registry)
	Register_SurfaceLight(registry)
	Register_SyntaxHighlighter(registry)
	Register_TextBox(registry)
	Register_TextButton(registry)
	Register_TextLabel(registry)
	Register_UIBackdrop(registry)
	Register_UICorner(registry)
	Register_UIGradient(registry)
	Register_UIGridLayout(registry)
	Register_UIListLayout(registry)
	Register_UIShadow(registry)
	Register_UIStroke(registry)
	Register_ValueBase(registry)
	Register_Vector2Value(registry)
	Register_Vector3Value(registry)
	// wire:end classes
}

Registry_Destroy :: proc(registry: ^Registry) {
	if registry == nil {
		return
	}

	for descriptor in registry.classes {
		delete(descriptor.instances)
		delete(descriptor.properties)
		delete(descriptor.member_security)
		free(descriptor)
	}

	delete(registry.classes)
	registry.classes = nil
	delete(registry.pending_destroy)
	registry.pending_destroy = nil
}
