package classes

import datatypes "../datatypes"
import enums "../enum"
import luauh "../vm/luauh"
import renderer "../renderer"
import signals "../signals"
import target "../target"
import vm "../vm"
import "base:runtime"
import "core:fmt"
import "core:strings"

Renderer_Object :: renderer.RendererObject
Class_Constructor :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object
// Class_Constructor_With_Context is the context-carrying form of
// Class_Constructor. Only classes whose callbacks live in another module need
// it -- the native plugin loader uses `ctx` to recover the record describing
// which plugin class is being constructed, since a bare Class_Constructor gets
// no argument identifying the class it is being called for.
Class_Constructor_With_Context :: proc(
	ctx: rawptr,
	renderer: ^Renderer_Object,
	data_model: rawptr,
) -> ^Object
Class_Destructor :: proc(object: ^Object, renderer: ^Renderer_Object)
Class_Getter :: proc(
	L: ^vm.State,
	object: ^Object,
	datatypes: ^datatypes.Registry,
	enums: ^enums.Registry,
	key: string,
) -> bool
Class_Setter :: proc(
	L: ^vm.State,
	object: ^Object,
	datatypes: ^datatypes.Registry,
	enums: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool
Class_Namecall :: proc(
	L: ^vm.State,
	object: ^Object,
	datatypes: ^datatypes.Registry,
	enums: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
)
Class_Clone :: proc(source: ^Object, destination: ^Object)
Require_Resolver :: proc(L: ^vm.State, path: string, ctx: rawptr) -> bool

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
	return Member_Security{name = name, access = .Read, requirement = requirement}
}

Property_Write_Security :: proc(
	name: string,
	requirement: vm.Security_Requirement,
) -> Member_Security {
	return Member_Security{name = name, access = .Write, requirement = requirement}
}

Method_Security :: proc(name: string, requirement: vm.Security_Requirement) -> Member_Security {
	return Member_Security{name = name, access = .Call, requirement = requirement}
}

Class_Descriptor :: struct {
	info:               ^Class_Info,
	construct:          Class_Constructor,
	// construct_with_ctx, when set, replaces `construct`. The pair is how a
	// module that owns its class callbacks identifies which of its classes is
	// being built: `construct` is the shared engine-side entry point and
	// `construct_ctx` is the per-class record it forwards.
	construct_with_ctx: Class_Constructor_With_Context,
	construct_ctx:      rawptr,
	destroy:            Class_Destructor,
	get:                Class_Getter,
	set:                Class_Setter,
	namecall:           Class_Namecall,
	_step:              Class_Step,
	_step_phase:        Class_Step_Phase,
	creatable:          bool,
	clone:              Class_Clone,
	binding:            vm.Userdata_Binding,
	registry:           ^Registry,
	instances:          [dynamic]^Object,
	properties:         [dynamic]string,
	methods:            [dynamic]string,
	events:             [dynamic]string,
	member_security:    [dynamic]Member_Security,
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
) -> (
	i32,
	bool,
)

Remote_Call_Dispatch :: proc(
	ctx: rawptr,
	L: ^vm.State,
	instance: ^Object,
	method: string,
) -> (
	i32,
	bool,
)

// Part_Body_Access bridges the rigid-body members of a Part --
// AssemblyLinearVelocity, AssemblyAngularVelocity and ApplyImpulse -- to the
// physics service.
//
// The bridge is necessary because of the package graph: services imports
// classes, so classes cannot import services and a Part has no way to reach the
// Jolt body that represents it. Network ownership and remote calls already cross
// this boundary the same way, through hooks the services layer installs at
// startup. Every entry point is optional; a Part with no installed access, or
// one whose service has no body for it, reads as a zero velocity and ignores
// writes, which is what an anchored Part should report anyway.
Part_Body_Access :: struct {
	get_linear_velocity:  proc(ctx: rawptr, part: ^Object) -> (datatypes.Vector3, bool),
	set_linear_velocity:  proc(ctx: rawptr, part: ^Object, velocity: datatypes.Vector3),
	get_angular_velocity: proc(ctx: rawptr, part: ^Object) -> (datatypes.Vector3, bool),
	set_angular_velocity: proc(ctx: rawptr, part: ^Object, velocity: datatypes.Vector3),
	apply_impulse:        proc(ctx: rawptr, part: ^Object, impulse: datatypes.Vector3) -> bool,
}

Part_Linear_Velocity :: proc(registry: ^Registry, part: ^Object) -> datatypes.Vector3 {
	if registry == nil || part == nil || registry.part_body.get_linear_velocity == nil {
		return datatypes.Vector3{}
	}
	velocity, _ := registry.part_body.get_linear_velocity(registry.part_body_ctx, part)
	return velocity
}

Part_Set_Linear_Velocity :: proc(registry: ^Registry, part: ^Object, velocity: datatypes.Vector3) {
	if registry == nil || part == nil || registry.part_body.set_linear_velocity == nil {return}
	registry.part_body.set_linear_velocity(registry.part_body_ctx, part, velocity)
}

Part_Angular_Velocity :: proc(registry: ^Registry, part: ^Object) -> datatypes.Vector3 {
	if registry == nil || part == nil || registry.part_body.get_angular_velocity == nil {
		return datatypes.Vector3{}
	}
	velocity, _ := registry.part_body.get_angular_velocity(registry.part_body_ctx, part)
	return velocity
}

Part_Set_Angular_Velocity :: proc(
	registry: ^Registry,
	part: ^Object,
	velocity: datatypes.Vector3,
) {
	if registry == nil || part == nil || registry.part_body.set_angular_velocity == nil {return}
	registry.part_body.set_angular_velocity(registry.part_body_ctx, part, velocity)
}

Part_Apply_Impulse :: proc(
	registry: ^Registry,
	part: ^Object,
	impulse: datatypes.Vector3,
) -> bool {
	if registry == nil || part == nil || registry.part_body.apply_impulse == nil {return false}
	return registry.part_body.apply_impulse(registry.part_body_ctx, part, impulse)
}

Registry :: struct {
	classes:               [dynamic]^Class_Descriptor,
	datatypes:             ^datatypes.Registry,
	enums:                 ^enums.Registry,
	renderer:              ^Renderer_Object,
	data_model:            rawptr,
	vm_state:              ^vm.VM,
	signal_registry:       ^signals.Registry,
	fallback_require_ref:  i32,
	require_resolver:      Require_Resolver,
	require_resolver_ctx:  rawptr,
	require_frames:        map[^vm.State]^Require_Frame_Stack,
	mode:                  target.Mode,
	pending_destroy:       [dynamic]Pending_Destroy,
	destroy_hook:          Destroy_Hook,
	destroy_hook_ctx:      rawptr,
	network_ownership:     Network_Ownership_Dispatch,
	network_ownership_ctx: rawptr,
	remote_call:           Remote_Call_Dispatch,
	remote_call_ctx:       rawptr,
	part_body:             Part_Body_Access,
	part_body_ctx:         rawptr,
}

Registry_Init :: proc(
	datatype_registry: ^datatypes.Registry = nil,
	enum_registry: ^enums.Registry = nil,
	renderer: ^Renderer_Object = nil,
	data_model: rawptr = nil,
	signal_registry: ^signals.Registry = nil,
) -> Registry {
	return Registry {
		datatypes = datatype_registry,
		enums = enum_registry,
		renderer = renderer,
		data_model = data_model,
		signal_registry = signal_registry,
		mode = target.current_mode,
	}
}

Set_Data_Model :: proc(registry: ^Registry, data_model: rawptr) {
	if registry == nil {return}
	registry.data_model = data_model
}

Set_Mode :: proc(registry: ^Registry, mode: target.Mode) {
	if registry == nil {return}
	registry.mode = mode
}

Set_Require_Resolver :: proc(registry: ^Registry, resolver: Require_Resolver, ctx: rawptr) {
	if registry == nil {return}
	registry.require_resolver = resolver
	registry.require_resolver_ctx = ctx
}

Set_Network_Ownership :: proc(
	registry: ^Registry,
	dispatch: Network_Ownership_Dispatch,
	ctx: rawptr,
) {
	if registry == nil {return}
	registry.network_ownership = dispatch
	registry.network_ownership_ctx = ctx
}

Set_Remote_Call :: proc(registry: ^Registry, dispatch: Remote_Call_Dispatch, ctx: rawptr) {
	if registry == nil {return}
	registry.remote_call = dispatch
	registry.remote_call_ctx = ctx
}

Set_Part_Body_Access :: proc(registry: ^Registry, access: Part_Body_Access, ctx: rawptr) {
	if registry == nil {return}
	registry.part_body = access
	registry.part_body_ctx = ctx
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

	if descriptor != nil &&
	   descriptor.get != nil &&
	   descriptor.get(L, object, descriptor.registry.datatypes, descriptor.registry.enums, key) {
		return true
	}

	return Object_Get_Property(L, value, ctx, key)
}

descriptor_set :: proc(L: ^vm.State, value, ctx: rawptr, key: string, value_index: int) -> bool {
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

	if descriptor != nil &&
	   descriptor.set != nil &&
	   descriptor.set(
		   L,
		   object,
		   descriptor.registry.datatypes,
		   descriptor.registry.enums,
		   key,
		   value_index,
	   ) {
		// The write succeeded, so notify subscribers of this exact property.
		// Funnelling here means every class gets change signals for free,
		// without each setter having to remember to fire its own.
		Object_Fire_Property_Changed(object, key)
		return true
	}

	if Object_Set_Property(L, value, ctx, key, value_index) {
		Object_Fire_Property_Changed(object, key)
		return true
	}

	return false
}

append_properties :: proc(registry: ^Registry, class: ^Class_Info, result: ^[dynamic]string) {
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

Get_Properties :: proc(registry: ^Registry, object: ^Object) -> [dynamic]string {
	result: [dynamic]string

	if registry == nil || object == nil {
		return result
	}

	append_properties(registry, object.class, &result)

	return result
}

Class_Property_List :: proc(registry: ^Registry, class_name: string) -> [dynamic]string {
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

// Class_Member_Entry pairs a reflected member with the class that declares it.
// Owner is what ReflectedProperty/Method/Event report, and it is the declaring
// class rather than the queried one, so an inherited member keeps pointing at
// its original owner.
Class_Member_Entry :: struct {
	name:  string,
	owner: string,
}

// Class_Member_List selects which declared-member list a reflection query reads.
Class_Member_List :: enum {
	Properties,
	Methods,
	Events,
}

// descriptor_member_list returns the requested list for a class.
descriptor_member_list :: proc(
	descriptor: ^Class_Descriptor,
	list: Class_Member_List,
) -> [dynamic]string {
	switch list {
	case .Properties:
		return descriptor.properties
	case .Methods:
		return descriptor.methods
	case .Events:
		return descriptor.events
	}
	return nil
}

// Collect_Class_Members gathers the members a class declares in `list`, plus
// those it inherits, base class first, so callers see members in inheritance
// order. A name redeclared by a subclass keeps the subclass as its owner while
// the base declaration is dropped, matching how a real lookup would resolve the
// shadowed member.
Collect_Class_Members :: proc(
	registry: ^Registry,
	class_name: string,
	list: Class_Member_List,
) -> [dynamic]Class_Member_Entry {
	result: [dynamic]Class_Member_Entry

	if registry == nil {
		return result
	}

	descriptor := Find_Class(registry, class_name)
	if descriptor == nil {
		return result
	}

	// Walk root -> leaf so subclasses can shadow inherited names.
	chain: [dynamic]^Class_Info
	class := descriptor.info
	for class != nil {
		append(&chain, class)
		class = class.parent
	}
	defer delete(chain)

	for index := len(chain) - 1; index >= 0; index -= 1 {
		owner_class := chain[index]
		owner := Find_Class(registry, owner_class.name)
		if owner == nil {
			continue
		}

		for name in descriptor_member_list(owner, list) {
			shadowed := false
			for &entry in result {
				if entry.name == name {
					entry.owner = owner_class.name
					shadowed = true
					break
				}
			}
			if !shadowed {
				append(&result, Class_Member_Entry{name = name, owner = owner_class.name})
			}
		}
	}

	return result
}

descriptor_namecall :: proc(L: ^vm.State, value, ctx: rawptr, method: string) -> (i32, bool) {
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

	if descriptor.registry != nil && descriptor.registry.network_ownership != nil {
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

	if descriptor.registry != nil && descriptor.registry.remote_call != nil {
		switch method {
		case "FireServer",
		     "FireClient",
		     "FireAllClients",
		     "InvokeServer",
		     "InvokeClient",
		     "InvokeClients":
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
	methods: []string = nil,
	events: []string = nil,
	member_security: []Member_Security = nil,
	construct_with_ctx: Class_Constructor_With_Context = nil,
	construct_ctx: rawptr = nil,
) {
	assert(registry != nil)
	assert(info != nil)
	assert(construct != nil)
	assert(destroy != nil)

	descriptor := new(Class_Descriptor)
	descriptor^ = Class_Descriptor {
		info               = info,
		construct          = construct,
		construct_with_ctx = construct_with_ctx,
		construct_ctx      = construct_ctx,
		destroy            = destroy,
		get                = get,
		set                = set,
		namecall           = namecall,
		_step              = _step,
		_step_phase        = _step_phase,
		creatable          = creatable,
		clone              = clone,
		registry           = registry,
	}

	for property in properties {
		append(&descriptor.properties, property)
	}

	for method in methods {
		append(&descriptor.methods, method)
	}

	for event in events {
		append(&descriptor.events, event)
	}

	for rule in member_security {
		append(&descriptor.member_security, rule)
	}

	descriptor.binding = vm.Userdata_Binding {
		name     = "Instance",
		ctx      = descriptor,
		get      = descriptor_get,
		set      = descriptor_set,
		namecall = descriptor_namecall,
		string   = descriptor_string,
		destroy  = descriptor_destroy,
	}

	append(&registry.classes, descriptor)

	// Materialise the inheritance chain now that the class is known to the
	// engine, rather than lazily on the first Is_A. Done per registration so
	// the very first physics walk does not pay to build several hundred chains,
	// and so a class registered after its subclass still ends up correct: the
	// walk reads `parent` pointers, not the registry.
	Class_Register_Ancestors(info)
}

// Member_Requirement returns the security requirement registered for a member
// access on a class, or SECURITY_REQUIREMENT_NONE when the class declares no
// rule for it. ReflectionService uses this to report a member's Permits.
Member_Requirement :: proc(
	descriptor: ^Class_Descriptor,
	name: string,
	access: Member_Access,
) -> vm.Security_Requirement {
	if descriptor == nil {
		return vm.SECURITY_REQUIREMENT_NONE
	}

	for rule in descriptor.member_security {
		if rule.name == name && rule.access == access {
			return rule.requirement
		}
	}

	return vm.SECURITY_REQUIREMENT_NONE
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
		Clone_Class_State(registry, info.parent, source, destination)
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
) -> (
	^Object,
	bool,
) {
	descriptor := Find_Class(registry, class_name)
	if descriptor == nil || (require_creatable && !descriptor.creatable) {
		return nil, false
	}

	object: ^Object

	if descriptor.construct_with_ctx != nil {
		object = descriptor.construct_with_ctx(
			descriptor.construct_ctx,
			registry.renderer,
			registry.data_model,
		)
	} else {
		object = descriptor.construct(registry.renderer, registry.data_model)
	}

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

		if descriptor.registry != nil &&
		   descriptor.registry.renderer != nil &&
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

// ScreenGui.RenderOnTop and StarterGui residency already decide which pass a
// screen draws in, but nothing ordered screens *within* a pass: they rendered in
// creation order, so DisplayOrder was accepted, stored, and then ignored. Sort
// the ScreenGui instances by it so the editor's chrome can be layered above
// game GUIs. Insertion sort keeps this stable, preserving creation order for
// equal DisplayOrder values.
Sort_ScreenGui_Instances :: proc(descriptor: ^Class_Descriptor) {
	if descriptor == nil || len(descriptor.instances) < 2 {
		return
	}

	instances := &descriptor.instances

	display_order := proc(object: ^Object) -> f64 {
		if object == nil {
			return 0
		}

		screen := cast(^ScreenGui)object

		return screen.displayorder
	}

	for i := 1; i < len(instances); i += 1 {
		current := instances[i]
		key := display_order(current)

		j := i - 1
		for j >= 0 && display_order(instances[j]) > key {
			instances[j + 1] = instances[j]
			j -= 1
		}

		instances[j + 1] = current
	}
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
	if registry == nil || L == nil {return}

	Flush_Pending_Destroy(registry)

	targets: [dynamic]class_step_target

	for descriptor in registry.classes {
		if descriptor._step == nil || descriptor._step_phase != phase {continue}

		if descriptor.info != nil && descriptor.info.name == "ScreenGui" {
			Sort_ScreenGui_Instances(descriptor)
		}

		for object in descriptor.instances {
			if object != nil && !object.destroyed {
				append(&targets, class_step_target{object, descriptor._step})
			}
		}
	}

	step_context := Class_Step_Context {
		L               = L,
		delta_time      = delta_time,
		renderer        = registry.renderer,
		data_model      = registry.data_model,
		viewport_width  = viewport_width,
		viewport_height = viewport_height,
		gui_overlay     = gui_overlay,
	}

	for target in targets {
		if target.object != nil && !target.object.destroyed {
			target._step(target.object, &step_context)
		}
	}

	delete(targets)
}

Object_From_Argument :: proc "c" (L: ^vm.State, index: int) -> ^Object {
	context = runtime.default_context()
	return object_from_argument(L, index)
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

// A require frame records the ModuleScript whose chunk is currently running on
// a given thread. Frames are keyed by lua_State because a yield suspends the
// whole thread, so execution within one thread is strictly nested: the frame a
// require pushes is always the frame popped when it completes.
// Require_Frame_Stack is a per-thread stack of the ModuleScripts whose chunks
// are currently running. Frames are keyed by lua_State because a yield suspends
// the whole thread, so execution within one thread is strictly nested: the frame
// a require pushes is the frame popped when that require completes.
//
// The registry holds a *pointer* to this struct. Holding the struct inline would
// let a map rehash copy it, leaving two owners of one backing array. `owner` and
// `thread` are kept here so that popping needs nothing but the stack itself --
// require's continuation cannot rely on the registry upvalue.
Require_Frame_Stack :: struct {
	items:  [dynamic]^Object,
	depth:  int,
	owner:  ^Registry,
	thread: ^vm.State,
}

// Require_Frame_Stack_For returns the thread's stack, creating it on first use.
Require_Frame_Stack_For :: proc(
	registry: ^Registry,
	L: ^vm.State,
) -> ^Require_Frame_Stack {
	if stack, ok := registry.require_frames[L]; ok {
		return stack
	}
	stack := new(Require_Frame_Stack)
	stack.owner = registry
	stack.thread = L
	registry.require_frames[L] = stack
	return stack
}

// Require_Frame_Push records `object` as the module running on this thread.
Require_Frame_Push :: proc(
	registry: ^Registry,
	L: ^vm.State,
	common: ^Script_Common,
	object: ^Object,
) {
	if registry == nil || object == nil {
		return
	}
	stack := Require_Frame_Stack_For(registry, L)
	if stack.depth < len(stack.items) {
		stack.items[stack.depth] = object
	} else {
		append(&stack.items, object)
	}
	stack.depth += 1
	if common != nil {
		common.require_frame_stack = stack
	}
}

// Require_Frame_Pop drops the top frame of the thread's stack.
Require_Frame_Pop :: proc(registry: ^Registry, L: ^vm.State) {
	if registry == nil {
		return
	}
	stack, ok := registry.require_frames[L]
	if !ok {
		return
	}
	Require_Frame_Pop_Stack(stack)
}

// Require_Frame_Pop_Stack drops the top frame and releases the stack when empty.
Require_Frame_Pop_Stack :: proc(stack: ^Require_Frame_Stack) {
	if stack == nil || stack.depth == 0 {
		return
	}
	stack.depth -= 1
	stack.items[stack.depth] = nil
}

// Require_Frame_Pop_Owned pops the frame pushed for `object`, if it is on top.
//
// The owning stack is reached through the module's own script state, which the
// continuation already holds, so no registry upvalue is needed. Popping only when
// the frame is on top keeps this harmless for the cached-result path, which
// returns before pushing a frame of its own.
Require_Frame_Pop_Owned :: proc(common: ^Script_Common, object: ^Object) {
	if common == nil || object == nil {
		return
	}
	stack := common.require_frame_stack
	common.require_frame_stack = nil
	if stack == nil || stack.depth == 0 || stack.items[stack.depth - 1] != object {
		return
	}
	Require_Frame_Pop_Stack(stack)
}

Require_Current_Script :: proc(registry: ^Registry, L: ^vm.State) -> ^Object {
	if registry == nil {
		return nil
	}
	stack, ok := registry.require_frames[L]
	if !ok || stack == nil || stack.depth == 0 {
		return nil
	}
	return stack.items[stack.depth - 1]
}

// require_walk_children resolves `path` as a chain of child names below `root`.
require_walk_children :: proc(root: ^Object, path: string) -> ^Object {
	target := root
	remaining := path
	for remaining != "" && target != nil {
		slash := strings.index(remaining, "/")
		segment :=
			remaining
		if slash >= 0 {
			segment = remaining[:slash]
			remaining = remaining[slash + 1:]
		} else {
			remaining = ""
		}
		if segment == "" {
			continue
		}
		target = Find_First_Child(target, segment)
	}
	return target
}

// require_replace_arg1 swaps the require argument for the resolved Instance.
//
// The alias path resolves to an object rather than a string, but require's
// continuation re-reads argument 1 to identify the module, so the slot has to be
// overwritten in place instead of pushing a second value.
require_replace_arg1 :: proc(L: ^vm.State, object: ^Object) {
	// A require invoked from Lua sees only its arguments on the stack, so the
	// alias slot is the only occupied one here. Clearing and re-pushing overwrites
	// it in place, which avoids lua_replace -- the vendored Luau build does not
	// export it.
	luauh.lua_settop(L, 0)
	Push_Object(L, object)
}

// require_resolve_alias implements the documented require-by-string aliases:
// `@self/X` names a child of the script that is calling require, and `@game/X`
// names a child of the DataModel root. Returns false when the alias does not
// apply or does not resolve, letting the caller fall back.
require_resolve_alias :: proc(
	L: ^vm.State,
	registry: ^Registry,
	path: string,
) -> bool {
	if strings.has_prefix(path, "@self/") {
		caller := Require_Current_Script(registry, L)
		if caller == nil {
			return false
		}
		target := require_walk_children(caller, path[len("@self/"):])
		if target == nil {
			return false
		}
		require_replace_arg1(L, target)
		return true
	}

	if strings.has_prefix(path, "@game/") {
		if registry.data_model == nil {
			return false
		}
		root := cast(^Object)registry.data_model
		target := require_walk_children(root, path[len("@game/"):])
		if target == nil {
			return false
		}
		require_replace_arg1(L, target)
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

	Require_Frame_Pop_Owned(common, object)

	if status != 0 {
		common.module_state = .Unloaded
		return vm.Reraise(L)
	}

	// Stack layout is [argument 1 (the ModuleScript), ...results].
	result_count := vm.StackTop(L) - 1
	if result_count != 1 {
		common.module_state = .Unloaded
		return vm.RaiseError(
			L,
			strings.concatenate({REQUIRE_RESULT_COUNT_ERROR, ": ", Get_Full_Name(object)}),
		)
	}

	// Retain the module's return value. `lua_ref` returns 0 for nil, which is
	// still a valid cached result and pushed back as nil on later requires.
	common.module_ref = vm.RetainValue(L)
	common.module_state = .Loaded
	return 1
}

require_script :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	registry := cast(^Registry)vm.UpvaluePointer(L)

	// Engine-internal modules are addressed by string path ("@internal/...").
	if vm.IsString(L, 1) {
		path := vm.ArgString(L, 1)
		if require_resolve_alias(L, registry, path) {
			return require_script_body(L, registry)
		}
		if registry != nil &&
		   registry.require_resolver != nil &&
		   registry.require_resolver(L, path, registry.require_resolver_ctx) {
			return 1
		}
		return require_fallback(L, registry)
	}

	return require_script_body(L, registry)
}

require_script_body :: proc(L: ^vm.State, registry: ^Registry) -> i32 {
	object := object_from_argument(L, 1)
	if object == nil {
		return vm.RaiseError(L, "require expects a ModuleScript, got a non-Instance value")
	}
	if !Script_Is_Script(object) {
		describe := Script_Describe(object)
		defer delete(describe)
		return vm.RaiseError(
			L,
			strings.concatenate({"require expects a ModuleScript, got ", describe}),
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
			strings.concatenate({"require: ", describe, " cannot be required from ", reason}),
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
			strings.concatenate({"cyclic require detected while loading ", describe}),
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
	// The frame makes this module the `@self` target while its chunk runs.
	// require_continuation pops it once the chunk completes, including after a
	// yield resumes the thread.
	Require_Frame_Push(registry, L, common, object)
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
	vm.PushFunctionWithContinuation(vm_state.L, "require", require_script, require_continuation, 1)
	vm.SetGlobalFromStack(vm_state, "require")
}


Register_Default_Classes :: proc(registry: ^Registry) {
	// wire:begin classes
	Register_Instance(registry)
	Register_ArcHandles(registry)
	Register_BasePart(registry)
	Register_BindableEvent(registry)
	Register_BindableFunction(registry)
	Register_BlurImageFilter(registry)
	Register_BoolValue(registry)
	Register_BrickColorValue(registry)
	Register_Camera(registry)
	Register_CFrameValue(registry)
	Register_CharacterAnimator(registry)
	Register_CharacterController(registry)
	Register_CharacterInput(registry)
	Register_CharacterModel(registry)
	Register_CharacterMotor(registry)
	Register_CollisionController(registry)
	Register_Color3Value(registry)
	Register_ColorSequenceValue(registry)
	Register_Decal(registry)
	Register_DoubleConstrainedValue(registry)
	Register_EditableMesh(registry)
	Register_Folder(registry)
	Register_Frame(registry)
	Register_GroundDetector(registry)
	Register_GuiButton(registry)
	Register_GuiObject(registry)
	Register_Handles(registry)
	Register_Highlight(registry)
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
	Register_UIPadding(registry)
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

	// Require frame stacks are released here rather than when a frame is popped:
	// a stack can still be referenced by a script that has not finished, so
	// freeing it eagerly is a use-after-free.
	for _, stack in registry.require_frames {
		if stack != nil {
			delete(stack.items)
			free(stack)
		}
	}
	delete(registry.require_frames)
	registry.require_frames = nil
}
