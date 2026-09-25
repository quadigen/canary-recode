package classes

import "core:fmt"
import "base:runtime"
import "core:strings"
import datatypes "../datatypes"
import enums "../enum"
import signals "../signals"
import vm "../vm"

Class_Info :: struct {
    name:   string,
    parent: ^Class_Info,
}

Object_Class := Class_Info{
    name   = "Object",
    parent = nil,
}

Object_Attribute :: struct {
	name:      string,
	value_ref: i32,
}

// Lazily-created per-property change signals backing
// `Instance:GetPropertyChangedSignal(name)`. Entries are only created when a
// script actually subscribes, so an Instance nobody observes costs nothing
// beyond the nil map.
Object_Property_Signal :: struct {
	name:   string,
	signal: ^signals.Signal,
}

Object :: struct {
	class:                ^Class_Info,
	name:                 string,
	owned_name:           string,
	parent:               ^Object,
	children:             [dynamic]^Object,
	signal_registry: ^Registry,
	attributes:           [dynamic]Object_Attribute,
	property_signals:     [dynamic]Object_Property_Signal,
	unique_id:            datatypes.UniqueId,
	capabilities:         datatypes.SecurityCapabilities,
	security_requirement: vm.Security_Requirement,
	sandboxed:            bool,
	lua_ref:              i32,
	destroyed:            bool,
	archivable:           bool,
	can_replicate:        bool,
	replication_mode:     enums.ReplicationMode,
	replication_group:    string,
	network_id:           u32,
}

Object_Init :: proc(class: ^Class_Info = nil, name: string = "Object") -> Object {
    resolved_class := class
    if resolved_class == nil {
        resolved_class = &Object_Class
    }

    return Object{
        class    = resolved_class,
        name     = name,
        parent   = nil,
        children = nil,
		archivable = true,
		can_replicate = true,
		unique_id  = datatypes.UniqueId_New(),
		lua_ref    = -1,
    }
}

// Returns the existing signal for `name`, or nil when nothing has subscribed
// to it yet. Never allocates, so the fire path stays allocation-free.
Object_Find_Property_Signal :: proc(
	self: ^Object,
	name: string,
) -> ^signals.Signal {
	if self == nil || len(self.property_signals) == 0 {
		return nil
	}

	for entry in self.property_signals {
		if entry.name == name {
			return entry.signal
		}
	}

	return nil
}

// Returns the signal for `name`, creating it on first request. This is the
// path `GetPropertyChangedSignal` takes.
Object_Get_Or_Create_Property_Signal :: proc(
	self: ^Object,
	name: string,
) -> ^signals.Signal {
	if self == nil {
		return nil
	}

	if self.signal_registry == nil || self.signal_registry.signal_registry == nil {
		return nil
	}

	if existing := Object_Find_Property_Signal(self, name); existing != nil {
		return existing
	}

	signal := signals.Create(self.signal_registry.signal_registry)
	if signal == nil {
		return nil
	}

	// The property name comes from a Luau string that can be collected once the
	// calling script yields, so the key needs native ownership.
	append(&self.property_signals, Object_Property_Signal{
		name   = strings.clone(name),
		signal = signal,
	})

	return signal
}

// Fires the change signal for `name` if one exists. Called after a successful
// property write from the single descriptor_set funnel, which is what makes
// this cover every class rather than just the ones with bespoke events.
Object_Fire_Property_Changed :: proc(
	self: ^Object,
	name: string,
) {
	signal := Object_Find_Property_Signal(self, name)
	if signal == nil {
		return
	}

	if self.signal_registry == nil || self.signal_registry.signal_registry == nil {
		return
	}

	signals.Fire(self.signal_registry.signal_registry.L, signal, 0)
}

Object_Free_Property_Signals :: proc(self: ^Object) {
	if self == nil {
		return
	}

	for entry in self.property_signals {
		if entry.signal != nil {
			signals.Destroy(entry.signal)
		}

		delete(entry.name)
	}

	delete(self.property_signals)
	self.property_signals = nil
}

Object_Destroy :: proc(self: ^Object) {
    if self == nil {
        return
    }

    for child in self.children {
        if child != nil && child.parent == self {
            child.parent = nil
        }
    }
    delete(self.children)
    self.children = nil
	for attribute in self.attributes {
		if self.signal_registry != nil && self.signal_registry.vm_state != nil && self.signal_registry.vm_state.L != nil {
			vm.ReleaseValue(self.signal_registry.vm_state.L, attribute.value_ref)
		}
		delete(attribute.name)
	}
	delete(self.attributes)
	self.attributes = nil

	Object_Free_Property_Signals(self)

    Set_Parent(self, nil)
	delete(self.owned_name)
	self.owned_name = ""
	delete(self.replication_group)
	self.replication_group = ""
}

Get_Class_Name :: proc(self: ^Object) -> string {
    if self == nil || self.class == nil {
        return "Object"
    }

    return self.class.name
}

Get_Name :: proc(self: ^Object) -> string {
    if self == nil {
        return ""
    }

    return self.name
}

Set_Name :: proc(self: ^Object, name: string) {
    if self == nil {
        return
    }

    // Lua strings can be collected after the assigning script completes.
    // Keep native ownership so later FindFirstChild calls remain reliable.
    copy := strings.clone(name)
    delete(self.owned_name)
    self.owned_name = copy
    self.name = copy
}

Is_A :: proc(self: ^Object, class_name: string) -> bool {
    if self == nil {
        return false
    }

    class := self.class

    for class != nil {
        if class.name == class_name {
            return true
        }

        class = class.parent
    }

    return false
}

Get_Parent :: proc(self: ^Object) -> ^Object {
    if self == nil {
        return nil
    }

    return self.parent
}

Set_Parent :: proc(self: ^Object, new_parent: ^Object) {
    if self == nil || self == new_parent || self.parent == new_parent {
        return
    }

    if new_parent != nil && Is_Descendant_Of(new_parent, self) {
        return
    }

    if self.parent != nil {
        for child, i in self.parent.children {
            if child == self {
                ordered_remove(&self.parent.children, i)
                break
            }
        }
    }

    self.parent = new_parent

    if new_parent != nil {
        append(&new_parent.children, self)
    }
}

Destroy_Hierarchy :: proc(self: ^Object) {
    if self == nil || self.destroyed {
        return
    }

    self.destroyed = true

    registry := self.signal_registry
    L: ^vm.State
    if registry != nil && registry.vm_state != nil {
        L = registry.vm_state.L
    }

    // Release the Lua registry pin so the userdata can be collected, and
    // detach the native value so the garbage collector skips its destroy
    // callback. Native memory is freed by Flush_Pending_Destroy at the next
    // Step instead of by the GC.
    if self.lua_ref > 0 && L != nil {
        vm.PushRegistryReference(L, self.lua_ref)
        vm.DetachUserdata(L, -1)
        vm.Pop(L)
        vm.ReleaseValue(L, self.lua_ref)
        self.lua_ref = -1
    }

    if registry != nil {
        descriptor := Find_Class(registry, Get_Class_Name(self))
        if descriptor != nil {
            append(&registry.pending_destroy, Pending_Destroy{object = self, descriptor = descriptor})
        }
    }

    for len(self.children) > 0 {
        child := self.children[len(self.children)-1]
        Destroy_Hierarchy(child)
        if child != nil && child.parent == self {
            Set_Parent(child, nil)
        }
    }
    Set_Parent(self, nil)
}

Get_Children :: proc(self: ^Object) -> []^Object {
    if self == nil {
        return nil
    }

    return self.children[:]
}

Find_First_Child :: proc(self: ^Object, name: string) -> ^Object {
    if self == nil {
        return nil
    }

    for child in self.children {
        if child.name == name {
            return child
        }
    }

    return nil
}

Find_First_Child_Of_Class :: proc(self: ^Object, class_name: string) -> ^Object {
    if self == nil {
        return nil
    }

    for child in self.children {
        if Is_A(child, class_name) {
            return child
        }
    }

    return nil
}

Is_Descendant_Of :: proc(self: ^Object, ancestor: ^Object) -> bool {
    if self == nil || ancestor == nil {
        return false
    }

    current := self.parent
    for current != nil {
        if current == ancestor {
            return true
        }
        current = current.parent
    }

    return false
}

Is_Ancestor_Of :: proc(self: ^Object, descendant: ^Object) -> bool {
    return Is_Descendant_Of(descendant, self)
}

To_String :: proc(self: ^Object) -> string {
    if self == nil {
        return "nil"
    }

    return fmt.tprintf("%s (%s)", self.name, Get_Class_Name(self))
}

Get_Full_Name :: proc(self: ^Object) -> string {
    if self == nil {
        return ""
    }

    if self.parent == nil {
        return self.name
    }
    return fmt.tprintf("%s.%s", Get_Full_Name(self.parent), self.name)
}

Object_Is_Accessible :: proc(L: ^vm.State, object: ^Object) -> bool {
	if object == nil {
		return false
	}

	current := object
	for current != nil {
		if !vm.ThreadMeetsSecurityRequirement(L, current.security_requirement) {
			return false
		}
		current = current.parent
	}

	return true
}

Push_Object :: proc(L: ^vm.State, object: ^Object) {
    if object == nil || object.lua_ref <= 0 || !Object_Is_Accessible(L, object) {
        vm.PushNil(L)
        return
    }
    vm.PushRegistryReference(L, object.lua_ref)
}

object_from_argument :: proc(L: ^vm.State, index: int) -> ^Object {
	binding := vm.UserdataBindingOf(L, index)
	if binding == nil || binding.name != "Instance" { return nil }

	object := cast(^Object)vm.UserdataValue(L, index)
	if !Object_Is_Accessible(L, object) { return nil }
    return object
}

is_object_method :: proc(name: string) -> bool {
	switch name {
	case "Clone", "Destroy", "FindFirstChild", "FindFirstChildOfClass",
		"GetChildren", "GetDescendants", "GetFullName", "GetProperties",
		"IsA", "IsAncestorOf", "IsDescendantOf",
		"GetAttribute", "GetAttributes", "SetAttribute",
		"GetPropertyChangedSignal":
		return true
	}

	return false
}

object_method :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()

	object := object_from_argument(L, 1)
	if object == nil {
		return vm.RaiseError(L, "expected an Instance")
	}

	method := vm.ArgString(L, int(vm.UpvalueIndex(1)))
	fmt.println("Object_Namecall method:", method)

	binding := vm.UserdataBindingOf(L, 1)

	method_ctx: rawptr = nil

	if binding != nil {
		method_ctx = binding.ctx
	}

	result_count, handled := Object_Namecall(
		L,
		object,
		method_ctx,
		method,
	)

	if handled {
		return result_count
	}

	return vm.RaiseError(L, "unknown Instance method")
}

Object_Get_Property :: proc(L: ^vm.State, value, ctx: rawptr, key: string) -> bool {
    object := cast(^Object)value
    if object == nil {
        return false
    }

    switch key {
    case "ClassName":
        vm.PushString(L, Get_Class_Name(object))
    case "Name":
        vm.PushString(L, object.name)
    case "Archivable":
        vm.PushBoolean(L, object.archivable)
	case "CanReplicate":
		vm.PushBoolean(L, object.can_replicate)
	case "ReplicationMode":
		descriptor := cast(^Class_Descriptor)ctx
		if descriptor == nil || descriptor.registry == nil || descriptor.registry.enums == nil { return false }
		_ = enums.Push_Item_By_Value(L, descriptor.registry.enums, "ReplicationMode", i64(object.replication_mode))
	case "ReplicationGroup":
		vm.PushString(L, object.replication_group)
	case "NetworkId":
		vm.PushNumber(L, f64(object.network_id))
    case "Parent":
        Push_Object(L, object.parent)
	case "UniqueId":
		descriptor := cast(^Class_Descriptor)ctx
		if descriptor == nil || descriptor.registry == nil || descriptor.registry.datatypes == nil { return false }
		datatypes.Push_UniqueId(L, descriptor.registry.datatypes, object.unique_id)
	case "Capabilities":
		descriptor := cast(^Class_Descriptor)ctx
		if descriptor == nil || descriptor.registry == nil || descriptor.registry.datatypes == nil { return false }
		datatypes.Push_SecurityCapabilities(L, descriptor.registry.datatypes, object.capabilities)
	case "Sandboxed":
		vm.PushBoolean(L, object.sandboxed)
	case "IsInSandbox":
		current := object
		is_sandboxed := false
		for current != nil {
			if current.sandboxed {
				is_sandboxed = true
				break
			}
			current = current.parent
		}
		vm.PushBoolean(L, is_sandboxed)
    case:
		child := Find_First_Child(object, key)
		if child != nil {
			Push_Object(L, child)
			return true
		}

        if !is_object_method(key) {
            return false
        }

        vm.PushString(L, key)
        vm.PushFunction(L, key, object_method, 1)
    }
    return true
}

Object_Set_Property :: proc(L: ^vm.State, value, ctx: rawptr, key: string, value_index: int) -> bool {
    object := cast(^Object)value
    if object == nil {
        return false
    }

    switch key {
    case "Name":
        Set_Name(object, vm.ArgString(L, value_index))
    case "Archivable":
        object.archivable = vm.ArgBoolean(L, value_index)
	case "CanReplicate":
		object.can_replicate = vm.ArgBoolean(L, value_index)
	case "ReplicationMode":
		descriptor := cast(^Class_Descriptor)ctx
		if descriptor == nil || descriptor.registry == nil || descriptor.registry.enums == nil { return false }
		item := enums.Arg_Item(L, value_index, descriptor.registry.enums, "ReplicationMode")
		object.replication_mode = enums.ReplicationMode(item.value)
	case "ReplicationGroup":
		delete(object.replication_group)
		object.replication_group = strings.clone(vm.ArgString(L, value_index))
    case "Parent":
        if vm.IsNil(L, value_index) {
            Set_Parent(object, nil)
            return true
        }

        parent := object_from_argument(L, value_index)
        if parent == nil {
            _ = vm.RaiseError(L, "Parent must be an Instance or nil")
            return true
        }
        if parent == object || Is_Descendant_Of(parent, object) {
            _ = vm.RaiseError(L, "cannot parent an Instance to itself or its descendant")
            return true
        }
        Set_Parent(object, parent)
	case "Capabilities":
		if !vm.ThreadHasSecurityCapability(L, datatypes.SECURITY_CAPABILITY_INTERNAL_SECURITY_ADMIN) {
			_ = vm.RaiseError(L, "Capabilities is restricted to internal scripts")
			return true
		}
		descriptor := cast(^Class_Descriptor)ctx
		if descriptor == nil || descriptor.registry == nil || descriptor.registry.datatypes == nil { return false }
		object.capabilities = datatypes.Arg_SecurityCapabilities(L, value_index, descriptor.registry.datatypes)
	case "Sandboxed":
		if !vm.ThreadHasSecurityCapability(L, datatypes.SECURITY_CAPABILITY_INTERNAL_SECURITY_ADMIN) {
			_ = vm.RaiseError(L, "Sandboxed is restricted to internal scripts")
			return true
		}
		object.sandboxed = vm.ArgBoolean(L, value_index)
    case:
        return false
    }
    return true
}

append_descendants :: proc(result: ^[dynamic]^Object, object: ^Object) {
    for child in object.children {
        append(result, child)
        append_descendants(result, child)
    }
}

attribute_index :: proc(object: ^Object, name: string) -> int {
	if object == nil { return -1 }
	for attribute, index in object.attributes {
		if attribute.name == name { return index }
	}
	return -1
}

attribute_name_is_valid :: proc(name: string) -> bool {
	if len(name) == 0 || len(name) > 100 { return false }
	if len(name) >= 3 && (name[0] == 'R' || name[0] == 'r') &&
	   (name[1] == 'B' || name[1] == 'b') && (name[2] == 'X' || name[2] == 'x') {
		return false
	}
	for character in name {
		if (character >= 'a' && character <= 'z') || (character >= 'A' && character <= 'Z') ||
		   (character >= '0' && character <= '9') || character == '_' || character == '-' ||
		   character == '.' || character == '/' {
			continue
		}
		return false
	}
	return true
}

attribute_value_is_supported :: proc(L: ^vm.State, index: int) -> bool {
	#partial switch vm.TypeOf(L, index) {
	case .Nil, .Boolean, .Number, .Integer, .String, .Vector:
		return true
	case .Userdata:
		binding := vm.UserdataBindingOf(L, index)
		return binding != nil && binding.tag >= datatypes.DATATYPE_TAG_BASE
	}
	return false
}

Set_Attribute :: proc(L: ^vm.State, object: ^Object, name: string, value_index: int) -> bool {
	if !attribute_name_is_valid(name) {
		_ = vm.RaiseError(L, "attribute name must be 1-100 valid characters and cannot start with RBX")
		return false
	}
	index := attribute_index(object, name)
	if vm.IsNil(L, value_index) {
		if index >= 0 {
			vm.ReleaseValue(L, object.attributes[index].value_ref)
			delete(object.attributes[index].name)
			ordered_remove(&object.attributes, index)
		}
		return true
	}
	if !attribute_value_is_supported(L, value_index) {
		_ = vm.RaiseError(L, "unsupported attribute value type")
		return false
	}
	vm.PushValue(L, value_index)
	value_ref := vm.RetainValue(L)
	vm.Pop(L)
	if index >= 0 {
		vm.ReleaseValue(L, object.attributes[index].value_ref)
		object.attributes[index].value_ref = value_ref
	} else {
		append(&object.attributes, Object_Attribute{name = strings.clone(name), value_ref = value_ref})
	}
	return true
}

clone_base_state :: proc(
	L: ^vm.State,
	source: ^Object,
	destination: ^Object,
) {
	if source == nil || destination == nil {
		return
	}

	// Do NOT copy:
	// - parent
	// - children
	// - unique_id
	// - lua_ref
	// - destroyed
	//
	// Those belong to the new Instance.

	Set_Name(destination, source.name)
	destination.archivable           = source.archivable
	destination.capabilities         = source.capabilities
	destination.security_requirement = source.security_requirement
	destination.sandboxed            = source.sandboxed
	destination.can_replicate         = source.can_replicate
	destination.replication_mode      = source.replication_mode
	delete(destination.replication_group)
	destination.replication_group = strings.clone(source.replication_group)

	// Attributes need their own registry references.
	for attribute in source.attributes {
		vm.PushRegistryReference(L, attribute.value_ref)

		value_ref := vm.RetainValue(L)

		vm.Pop(L)

		append(
			&destination.attributes,
			Object_Attribute{
				name      = strings.clone(attribute.name),
				value_ref = value_ref,
			},
		)
	}
}

Clone_Object :: proc(
	L: ^vm.State,
	registry: ^Registry,
	source: ^Object,
) -> (^Object, bool) {
	if L == nil || registry == nil || source == nil {
		return nil, false
	}

	if !source.archivable {
		return nil, false
	}

	// false here is important:
	// Clone should be able to reproduce registered Instances even if the
	// class isn't exposed through Instance.new().
	destination, ok := Push_New(
		registry,
		&vm.VM{L = L},
		Get_Class_Name(source),
		false,
	)

	if !ok || destination == nil {
		return nil, false
	}

	// Push_New leaves destination's userdata on the Luau stack.
	clone_base_state(L, source, destination)

	Clone_Class_State(
		registry,
		source.class,
		source,
		destination,
	)

	// Clone Archivable descendants.
	for child in source.children {
		if child == nil || !child.archivable {
			continue
		}

		cloned_child, child_ok := Clone_Object(
			L,
			registry,
			child,
		)

		if !child_ok {
			continue
		}

		Set_Parent(cloned_child, destination)

		// Clone_Object left cloned_child's userdata on the stack.
		// Its lua_ref keeps it alive, so remove the temporary stack value.
		vm.Pop(L)
	}

	return destination, true
}

append_class_properties :: proc(
	L: ^vm.State,
	registry: ^Registry,
	class: ^Class_Info,
	index: ^int,
) {
	if registry == nil || class == nil {
		return
	}

	append_class_properties(L, registry, class.parent, index)

	descriptor := Find_Class(registry, class.name)
	if descriptor == nil {
		return
	}

	for property in descriptor.properties {
		vm.PushString(L, property)
		vm.SetArrayValue(L, -2, index^)
		index^ += 1
	}
}

Object_Namecall :: proc(L: ^vm.State, value, ctx: rawptr, method: string) -> (i32, bool) {
    object := cast(^Object)value
    if object == nil {
        return 0, false
    }

    switch method {
    case "Clone":
	if !object.archivable {
		vm.PushNil(L)
		return 1, true
	}

	descriptor := cast(^Class_Descriptor)ctx

	if descriptor == nil || descriptor.registry == nil {
		count := vm.RaiseError(
			L,
			"cannot clone Instance without a class registry",
		)
		return count, true
	}

	_, ok := Clone_Object(
		L,
		descriptor.registry,
		object,
	)

	if !ok {
		vm.PushNil(L)
		return 1, true
	}

	// Clone_Object/Push_New already left the cloned userdata on top.
	return 1, true
    case "Destroy":
        Destroy_Hierarchy(object)
        return 0, true
    case "FindFirstChild":
        name := vm.ArgString(L, 2)
        recursive := vm.ArgOptionalBoolean(L, 3, false)
        child := Find_First_Child(object, name)
        if recursive && child == nil {
            descendants: [dynamic]^Object
            append_descendants(&descendants, object)
            for descendant in descendants {
                if descendant.name == name {
                    child = descendant
                    break
                }
            }
            delete(descendants)
        }
        Push_Object(L, child)
        return 1, true
    case "FindFirstChildOfClass":
        Push_Object(L, Find_First_Child_Of_Class(object, vm.ArgString(L, 2)))
        return 1, true
    case "GetChildren":
        vm.NewTable(L, len(object.children))
        index := 0
        for child in object.children {
            if !Object_Is_Accessible(L, child) || child.lua_ref <= 0 { continue }
            Push_Object(L, child)
            index += 1
            vm.SetArrayValue(L, -2, index)
        }
        return 1, true
    case "GetDescendants":
        descendants: [dynamic]^Object
        append_descendants(&descendants, object)
        vm.NewTable(L, len(descendants))
        index := 0
        for descendant in descendants {
            if !Object_Is_Accessible(L, descendant) || descendant.lua_ref <= 0 { continue }
            Push_Object(L, descendant)
            index += 1
            vm.SetArrayValue(L, -2, index)
        }
        delete(descendants)
        return 1, true
    case "GetFullName":
        vm.PushString(L, Get_Full_Name(object))
        return 1, true
	case "GetAttribute":
		index := attribute_index(object, vm.ArgString(L, 2))
		if index < 0 {
			vm.PushNil(L)
		} else {
			vm.PushRegistryReference(L, object.attributes[index].value_ref)
		}
		return 1, true
	case "GetAttributes":
		vm.NewTable(L, 0, len(object.attributes))
		for attribute in object.attributes {
			vm.PushRegistryReference(L, attribute.value_ref)
			vm.SetField(L, -2, attribute.name)
		}
		return 1, true
	case "SetAttribute":
		_ = Set_Attribute(L, object, vm.ArgString(L, 2), 3)
		return 0, true
	case "GetPropertyChangedSignal":
		signal := Object_Get_Or_Create_Property_Signal(object, vm.ArgString(L, 2))
		if signal == nil {
			vm.PushNil(L)
			return 1, true
		}
		signals.Push(L, signal)
		return 1, true
    case "IsA":
        vm.PushBoolean(L, Is_A(object, vm.ArgString(L, 2)))
        return 1, true
    case "IsAncestorOf":
        vm.PushBoolean(L, Is_Ancestor_Of(object, object_from_argument(L, 2)))
        return 1, true
    case "IsDescendantOf":
        vm.PushBoolean(L, Is_Descendant_Of(object, object_from_argument(L, 2)))
        return 1, true
	case "GetProperties":
		descriptor := cast(^Class_Descriptor)ctx
		if descriptor == nil || descriptor.registry == nil {
			return vm.RaiseError(L, "cannot get properties without a class registry"), true
		}

		vm.NewTable(L, 0)

		index := 1
		append_class_properties(
			L,
			descriptor.registry,
			object.class,
			&index,
		)

		return 1, true
    }

    return 0, false
}
