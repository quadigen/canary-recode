package classes

import "base:runtime"
import "core:fmt"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import renderer "../renderer"
import signals "../signals"

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
	// Objects that have been destroyed (and released from Lua) but whose native
	// memory is kept alive until the next Step so no code reads a freed object.
	pending_destroy:      [dynamic]Pending_Destroy,
	destroy_hook:         Destroy_Hook,
	destroy_hook_ctx:     rawptr,
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
	}
}

Set_Data_Model :: proc(registry: ^Registry, data_model: rawptr) {
	if registry == nil { return }
	registry.data_model = data_model
}

Set_Require_Resolver :: proc(registry: ^Registry, resolver: Require_Resolver, ctx: rawptr) {
	if registry == nil { return }
	registry.require_resolver = resolver
	registry.require_resolver_ctx = ctx
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

descriptor_namecall :: proc(
	L: ^vm.State,
	value, ctx: rawptr,
	method: string,
) -> (i32, bool) {
	descriptor := cast(^Class_Descriptor)ctx
	object := cast(^Object)value

	if !Object_Is_Accessible(L, object) {
		return vm.RaiseError(L, "insufficient security capabilities to access this Instance"), true
	}

	if !Can_Access_Member(L, descriptor, method, .Call) {
		return vm.RaiseError(L, "insufficient security capabilities to call this member"), true
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

require_fallback :: proc(L: ^vm.State, registry: ^Registry) -> i32 {
	if registry.fallback_require_ref <= 0 {
		return vm.RaiseError(L, "require expects a Script or ModuleScript")
	}

	vm.PushRegistryReference(L, registry.fallback_require_ref)
	vm.PushValue(L, 1)
	ok, err := vm.ProtectedCall(L, 1, 1)
	if !ok {
		return vm.RaiseOwnedError(L, &err)
	}

	return 1
}

require_script :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	registry := cast(^Registry)vm.UpvaluePointer(L)

	if vm.IsString(L, 1) {
		path := vm.ArgString(L, 1)
		if registry.require_resolver != nil &&
		   registry.require_resolver(L, path, registry.require_resolver_ctx) {
			return 1
		}
		return require_fallback(L, registry)
	}

	object := object_from_argument(L, 1)
	if object == nil || !Is_A(object, "ModuleScript") {
		return require_fallback(L, registry)
	}

	module := cast(^Script)object
	switch module.module_state {
	case .Loaded:
		vm.PushRegistryReference(L, module.module_ref)
		return 1
	case .Loading:
		return vm.RaiseError(L, "cyclic require detected")
	case .Unloaded:
	}

	if registry == nil || registry.vm_state == nil {
		return vm.RaiseError(L, "script runtime is unavailable")
	}

	module.module_state = .Loading

	chunk_name := fmt.tprintf("@%s", Get_Full_Name(object))
	defer delete(chunk_name)

	ok, err := vm.LoadSource(
		registry.vm_state,
		L,
		module.source,
		chunk_name,
	)

	if !ok {
		module.module_state = .Unloaded
		return vm.RaiseOwnedError(L, &err)
	}

	if !Script_Apply_Environment(L, object) {
		module.module_state = .Unloaded
		return vm.RaiseError(
			L,
			"failed to create ModuleScript environment",
		)
	}

	ok, err = vm.ProtectedCall(L, 0, 1)
	if !ok {
		module.module_state = .Unloaded
		return vm.RaiseOwnedError(L, &err)
	}

	module.module_ref = vm.RetainValue(L)
	module.module_state = .Loaded
	return 1
}

Install_Instance_Library :: proc(registry: ^Registry, vm_state: ^vm.VM) {
	registry.vm_state = vm_state

	vm.NewTable(vm_state.L, 0, 1)
	vm.PushLightUserdata(vm_state.L, registry)
	vm.PushFunction(vm_state.L, "Instance.new", instance_new, 1)
	vm.SetField(vm_state.L, -2, "new")
	vm.SetGlobalFromStack(vm_state, "Instance")

	_ = vm.GetGlobal(vm_state.L, "require")
	registry.fallback_require_ref = vm.RetainValue(vm_state.L)
	vm.Pop(vm_state.L)

	vm.PushLightUserdata(vm_state.L, registry)
	vm.PushFunction(vm_state.L, "require", require_script, 1)
	vm.SetGlobalFromStack(vm_state, "require")
}

Register_Default_Classes :: proc(registry: ^Registry) {
	// wire:begin classes
	Register_Instance(registry)
	Register_ArcHandles(registry)
	Register_BoolValue(registry)
	Register_BrickColorValue(registry)
	Register_Camera(registry)
	Register_CFrameValue(registry)
	Register_Color3Value(registry)
	Register_ColorSequenceValue(registry)
	Register_Decal(registry)
	Register_DoubleConstrainedValue(registry)
	Register_Folder(registry)
	Register_Frame(registry)
	Register_GuiButton(registry)
	Register_GuiObject(registry)
	Register_Handles(registry)
	Register_ImageButton(registry)
	Register_ImageLabel(registry)
	Register_InputObject(registry)
	Register_IntConstrainedValue(registry)
	Register_IntValue(registry)
	Register_Light(registry)
	Register_Lighting_Effect(registry)
	Register_MeshPart(registry)
	Register_Model(registry)
	Register_ModuleModuleScript(registry)
	Register_ModuleScript(registry)
	Register_NumberRangeValue(registry)
	Register_NumberSequenceValue(registry)
	Register_NumberValue(registry)
	Register_ObjectValue(registry)
	Register_Part(registry)
	Register_PointLight(registry)
	Register_RayValue(registry)
	Register_ScreenGui(registry)
	Register_Script(registry)
	Register_ScrollingFrame(registry)
	Register_Sound(registry)
	Register_SpotLight(registry)
	Register_StringValue(registry)
	Register_SurfaceLight(registry)
	Register_TextBox(registry)
	Register_TextButton(registry)
	Register_TextLabel(registry)
	Register_UIBackdrop(registry)
	Register_UICorner(registry)
	Register_UIGradient(registry)
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
