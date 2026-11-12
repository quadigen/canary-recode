package classes

import datatypes "../datatypes"
import enums "../enum"
import signals "../signals"
import tracy "../util/odin-tracy"
import vm "../vm"
import "core:fmt"
import "core:slice"
import "core:strings"

Class_Info :: struct {
	name:      string,
	parent:    ^Class_Info,
	ancestors: [dynamic]^Class_Info,
}


Is_A_Class :: proc(self: ^Object, class: ^Class_Info) -> bool {


	if self == nil || class == nil || self.class == nil {
		return false
	}
	if self.class == class {
		return true
	}
	if ancestors := self.class.ancestors; ancestors != nil {
		for ancestor in ancestors {
			if ancestor == class {
				return true
			}
		}
		return false
	}
	return Is_A(self, class.name)
}


Is_Class_A :: proc(class: ^Class_Info, base: ^Class_Info) -> bool {
	if class == nil || base == nil {
		return false
	}
	if class == base {
		return true
	}
	if ancestors := class.ancestors; ancestors != nil {
		for ancestor in ancestors {
			if ancestor == base {
				return true
			}
		}
		return false
	}
	for walk := class.parent; walk != nil; walk = walk.parent {
		if walk == base {
			return true
		}
	}
	return false
}


Class_Register_Ancestors :: proc(class: ^Class_Info) {
	if class == nil || class.ancestors != nil {
		return
	}


	if class.parent != nil && class.parent.ancestors == nil {
		Class_Register_Ancestors(class.parent)
	}


	chain: [dynamic]^Class_Info
	parent := class.parent
	for parent != nil {
		append(&chain, parent)
		parent = parent.parent
	}
	class.ancestors = chain
}

Object_Class := Class_Info {
	name   = "Object",
	parent = nil,
}


hierarchy_epoch: u64


Hierarchy_Epoch :: proc() -> u64 {
	return hierarchy_epoch
}


Hierarchy_Touched :: proc() {
	hierarchy_epoch += 1
}

Object_Attribute :: struct {
	name:      string,
	value_ref: i32,
}


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
	signal_registry:      ^Registry,
	attributes:           [dynamic]Object_Attribute,
	tags:                 [dynamic]string,
	metadata_revision:    u64,
	server_attributes:    [dynamic]string,
	server_tags:          [dynamic]string,
	imported_values:      map[string]i32,
	property_signals:     [dynamic]Object_Property_Signal,
	unique_id:            datatypes.UniqueId,
	capabilities:         datatypes.SecurityCapabilities,
	security_requirement: vm.Security_Requirement,
	sandboxed:            bool,
	lua_ref:              i32,
	destroyed:            bool,
	archivable:           bool,
	editor_scene_helper:  bool,
	can_replicate:        bool,
	replication_mode:     enums.ReplicationMode,
	replication_group:    string,
	network_id:           u32,
	child_added:          ^signals.Signal,
	child_removed:        ^signals.Signal,
	descendant_added:     ^signals.Signal,
	descendant_removing:  ^signals.Signal,
	destroying:           ^signals.Signal,
	ancestry_changed:     ^signals.Signal,
	changed:              ^signals.Signal,
}

Object_Init :: proc(class: ^Class_Info = nil, name: string = "Object") -> Object {
	resolved_class := class
	if resolved_class == nil {
		resolved_class = &Object_Class
	}

	return Object {
		class = resolved_class,
		name = name,
		parent = nil,
		children = nil,
		archivable = true,
		can_replicate = true,
		unique_id = datatypes.UniqueId_New(),
		lua_ref = -1,
	}
}


Object_Find_Property_Signal :: proc(self: ^Object, name: string) -> ^signals.Signal {
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


Object_Get_Or_Create_Property_Signal :: proc(self: ^Object, name: string) -> ^signals.Signal {
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


	append(
		&self.property_signals,
		Object_Property_Signal{name = strings.clone(name), signal = signal},
	)

	return signal
}


Object_Changed_Signal :: proc(self: ^Object) -> ^signals.Signal {
	if self == nil {
		return nil
	}
	if self.changed == nil {
		self.changed = Object_Create_Hierarchy_Signal(self)
	}
	return self.changed
}


Object_Fire_Property_Changed :: proc(self: ^Object, name: string, L: ^vm.State = nil) {
	if self.signal_registry == nil || self.signal_registry.signal_registry == nil {
		return
	}
	L := L if L != nil else self.signal_registry.signal_registry.L
	if L == nil {
		return
	}

	if signal := Object_Find_Property_Signal(self, name); signal != nil {
		signals.Fire(L, signal, 0)
	}

	if changed := self.changed; changed != nil {
		vm.PushString(L, name)
		signals.Fire(L, changed, 1)
		vm.Pop(L, 1)
	}
}

Hierarchy_Signal_Kind :: enum {
	Child_Added,
	Child_Removed,
	Descendant_Added,
	Descendant_Removing,
	Ancestry_Changed,
}

Object_Hierarchy_Signal :: proc(self: ^Object, kind: Hierarchy_Signal_Kind) -> ^signals.Signal {
	// lua_close runs destructors while the collector is tearing down the VM.
	if vm.Is_Closing() {return nil}
	if self == nil {
		return nil
	}
	if kind == .Child_Added {
		if self.child_added == nil {
			self.child_added = Object_Create_Hierarchy_Signal(self)
		}
		return self.child_added
	}
	if kind == .Child_Removed {
		if self.child_removed == nil {
			self.child_removed = Object_Create_Hierarchy_Signal(self)
		}
		return self.child_removed
	}
	if kind == .Descendant_Added {
		if self.descendant_added == nil {
			self.descendant_added = Object_Create_Hierarchy_Signal(self)
		}
		return self.descendant_added
	}
	if kind == .Ancestry_Changed {
		if self.ancestry_changed == nil {
			self.ancestry_changed = Object_Create_Hierarchy_Signal(self)
		}
		return self.ancestry_changed
	}
	if self.descendant_removing == nil {
		self.descendant_removing = Object_Create_Hierarchy_Signal(self)
	}
	return self.descendant_removing
}

Object_Fire_Destroying :: proc(self: ^Object) {
	if self == nil || self.destroying == nil || vm.Is_Closing() {
		return
	}
	L := self.signal_registry.signal_registry.L
	if L == nil {
		return
	}
	signals.Fire(L, self.destroying, 0)
}

Object_Fire_Ancestry_Changed :: proc(self: ^Object, parent: ^Object) {
	if self == nil {
		return
	}
	signal := self.ancestry_changed
	if signal == nil {
		return
	}
	L := self.signal_registry.signal_registry.L
	if L == nil {
		return
	}
	Push_Object(L, self)
	Push_Object(L, parent)
	signals.Fire(L, signal, 2)
	vm.Pop(L, 2)
}

Object_Create_Hierarchy_Signal :: proc(self: ^Object) -> ^signals.Signal {
	if self == nil || self.signal_registry == nil || self.signal_registry.signal_registry == nil {
		return nil
	}
	return signals.Create(self.signal_registry.signal_registry)
}

Object_Fire_Descendant_Added :: proc(self: ^Object, child: ^Object) {
	if self == nil || child == nil {
		return
	}
	signal := self.descendant_added
	if signal == nil {
		return
	}
	L := self.signal_registry.signal_registry.L
	if L == nil {
		return
	}
	Push_Object(L, child)
	signals.Fire(L, signal, 1)
	vm.Pop(L)
}

Object_Fire_Descendant_Removing :: proc(self: ^Object, child: ^Object) {
	if self == nil || child == nil {
		return
	}
	signal := self.descendant_removing
	if signal == nil {
		return
	}
	L := self.signal_registry.signal_registry.L
	if L == nil {
		return
	}
	Push_Object(L, child)
	signals.Fire(L, signal, 1)
	vm.Pop(L)
}

Object_Fire_Child_Added :: proc(self: ^Object, child: ^Object) {
	if self == nil || child == nil {
		return
	}
	signal := self.child_added
	if signal == nil {
		return
	}
	L := self.signal_registry.signal_registry.L
	if L == nil {
		return
	}
	Push_Object(L, child)
	signals.Fire(L, signal, 1)
	vm.Pop(L)
}

Object_Fire_Child_Removed :: proc(self: ^Object, child: ^Object) {
	if self == nil || child == nil {
		return
	}
	signal := self.child_removed
	if signal == nil {
		return
	}
	L := self.signal_registry.signal_registry.L
	if L == nil {
		return
	}
	Push_Object(L, child)
	signals.Fire(L, signal, 1)
	vm.Pop(L)
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

	if !self.destroyed {Object_Fire_Destroying(self)}

	for child in self.children {
		if child != nil && child.parent == self {
			child.parent = nil
		}
	}
	delete(self.children)
	self.children = nil
	for attribute in self.attributes {
		if self.signal_registry != nil &&
		   self.signal_registry.vm_state != nil &&
		   self.signal_registry.vm_state.L != nil {
			vm.ReleaseValue(self.signal_registry.vm_state.L, attribute.value_ref)
		}
		delete(attribute.name)
	}
	delete(self.attributes)
	self.attributes = nil
	if self.signal_registry != nil && len(self.tags) != 0 {
		delete_key(&self.signal_registry.tagged_objects, self)
	}
	for tag in self.tags {delete(tag)}
	delete(self.tags)
	for name in self.server_attributes {delete(name)}
	delete(self.server_attributes)
	for name in self.server_tags {delete(name)}
	delete(self.server_tags)
	if self.signal_registry != nil && self.signal_registry.vm_state != nil {
		L := self.signal_registry.vm_state.L
		if L != nil {
			for _, value_ref in self.imported_values {vm.ReleaseValue(L, value_ref)}
		}
	}
	delete(self.imported_values)
	self.imported_values = nil

	Object_Free_Property_Signals(self)

	if self.child_added != nil {
		signals.Destroy(self.child_added)
		self.child_added = nil
	}
	if self.child_removed != nil {
		signals.Destroy(self.child_removed)
		self.child_removed = nil
	}
	if self.descendant_added != nil {
		signals.Destroy(self.descendant_added)
		self.descendant_added = nil
	}
	if self.descendant_removing != nil {
		signals.Destroy(self.descendant_removing)
		self.descendant_removing = nil
	}
	if self.ancestry_changed != nil {
		signals.Destroy(self.ancestry_changed)
		self.ancestry_changed = nil
	}
	if self.changed != nil {
		signals.Destroy(self.changed)
		self.changed = nil
	}
	if self.destroying != nil {
		signals.Destroy(self.destroying)
		self.destroying = nil
	}

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


	copy := strings.clone(name)
	delete(self.owned_name)
	self.owned_name = copy
	self.name = copy
}


Set_Can_Replicate :: proc(self: ^Object, value: bool) {
	if self == nil {
		return
	}

	self.can_replicate = value
}

Is_A :: proc(self: ^Object, class_name: string) -> bool {
	return self != nil && class_has_name(self.class, class_name)
}

class_has_name :: proc(class: ^Class_Info, class_name: string) -> bool {
	for current := class; current != nil; current = current.parent {
		if current.name == class_name {return true}
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

	if new_parent != nil && (self.destroyed || new_parent.destroyed || Is_Descendant_Of(new_parent, self)) {
		return
	}

	previous := self.parent

	if previous != nil {
		for child, i in previous.children {
			if child == self {
				ordered_remove(&previous.children, i)
				break
			}
		}
	}

	self.parent = new_parent

	if new_parent != nil {
		append(&new_parent.children, self)
	}


	if Is_A(self, "GuiObject") || Is_A(previous, "GuiObject") || Is_A(new_parent, "GuiObject") {
		Gui_Layout_Mark_Dirty()
	}

	surfacegui_mark_dirty_for(self)

	if previous != nil {
		surfacegui_mark_dirty_for(previous)
	}

	if previous != nil {
		Object_Fire_Child_Removed(previous, self)
		ancestor := previous
		for ancestor != nil {
			Object_Fire_Descendant_Removing(ancestor, self)
			ancestor = ancestor.parent
		}
	}

	if new_parent != nil {
		Object_Fire_Child_Added(new_parent, self)
		ancestor := new_parent
		for ancestor != nil {
			Object_Fire_Descendant_Added(ancestor, self)
			ancestor = ancestor.parent
		}
	}

	Object_Fire_Ancestry_Changed(self, new_parent)


	Render_3D_Mark_Dirty()
	Hierarchy_Touched()
}

Destroy_Hierarchy :: proc(self: ^Object) {
	if self == nil || self.destroyed {
		return
	}

	if Is_A(self, "GuiObject") || Is_A(self.parent, "GuiObject") {
		Gui_Layout_Mark_Dirty()
	}

	surfacegui_mark_dirty_for(self)

	self.destroyed = true
	// Listeners can unregister this exact userdata before it is detached.
	Object_Fire_Destroying(self)

	Render_3D_Mark_Dirty()
	Hierarchy_Touched()

	registry := self.signal_registry
	L: ^vm.State
	if registry != nil && registry.vm_state != nil {
		L = registry.vm_state.L
	}

	for len(self.children) > 0 {
		child := self.children[len(self.children) - 1]
		Destroy_Hierarchy(child)
		if child != nil && child.parent == self {
			Set_Parent(child, nil)
		}
	}
	Set_Parent(self, nil)

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
			append(
				&registry.pending_destroy,
				Pending_Destroy{object = self, descriptor = descriptor},
			)
		}
	}
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
	if binding == nil || binding.name != "Instance" {return nil}

	object := cast(^Object)vm.UserdataValue(L, index)
	if !Object_Is_Accessible(L, object) {return nil}
	return object
}

is_object_method :: proc(name: string) -> bool {
	switch name {
	case "Clone",
	     "Destroy",
	     "ClearAllChildren",
	     "FindFirstChild",
	     "FindFirstChildOfClass",
	     "FindFirstAncestor",
	     "FindFirstAncestorOfClass",
	     "FindFirstAncestorWhichIsA",
	     "GetChildren",
	     "GetDescendants",
	     "GetFullName",
	     "GetProperties",
	     "IsA",
	     "IsAncestorOf",
	     "IsDescendantOf",
	     "GetAttribute",
	     "GetAttributes",
	     "SetAttribute",
	     "AddTag",
	     "RemoveTag",
	     "HasTag",
	     "GetTags",
	     "WaitForChild",
	     "WaitForChildOfClass",
	     "GetPropertyChangedSignal":
		return true
	}

	return false
}

object_method :: proc "c" (L: ^vm.State) -> i32 {
	context = tracy.DefaultContext()

	method := vm.ArgString(L, int(vm.UpvalueIndex(1)))
	binding := vm.UserdataBindingOf(L, 1)
	object := object_from_argument(L, 1)
	if object == nil {
		if method == "Destroy" && binding != nil && binding.name == "Instance" && vm.UserdataValue(L, 1) == nil {
			return 0
		}
		return vm.RaiseError(L, "expected an Instance")
	}

	method_ctx: rawptr = nil

	if binding != nil {
		method_ctx = binding.ctx
	}

	result_count, handled := Object_Namecall(L, object, method_ctx, method)

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
		if descriptor == nil ||
		   descriptor.registry == nil ||
		   descriptor.registry.enums == nil {return false}
		_ = enums.Push_Item_By_Value(
			L,
			descriptor.registry.enums,
			"ReplicationMode",
			i64(object.replication_mode),
		)
	case "ReplicationGroup":
		vm.PushString(L, object.replication_group)
	case "NetworkId":
		vm.PushNumber(L, f64(object.network_id))
	case "Parent":
		Push_Object(L, object.parent)
	case "UniqueId":
		descriptor := cast(^Class_Descriptor)ctx
		if descriptor == nil ||
		   descriptor.registry == nil ||
		   descriptor.registry.datatypes == nil {return false}
		datatypes.Push_UniqueId(L, descriptor.registry.datatypes, object.unique_id)
	case "Capabilities":
		descriptor := cast(^Class_Descriptor)ctx
		if descriptor == nil ||
		   descriptor.registry == nil ||
		   descriptor.registry.datatypes == nil {return false}
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
	case "ChildAdded":
		signals.Push(L, Object_Hierarchy_Signal(object, .Child_Added))
	case "ChildRemoved":
		signals.Push(L, Object_Hierarchy_Signal(object, .Child_Removed))
	case "DescendantAdded":
		signals.Push(L, Object_Hierarchy_Signal(object, .Descendant_Added))
	case "DescendantRemoving":
		signals.Push(L, Object_Hierarchy_Signal(object, .Descendant_Removing))
	case "AncestryChanged":
		signals.Push(L, Object_Hierarchy_Signal(object, .Ancestry_Changed))
	case "Changed":
		signals.Push(L, Object_Changed_Signal(object))
	case "Destroying":
		if object.destroying == nil {
			object.destroying = Object_Create_Hierarchy_Signal(object)
		}
		signals.Push(L, object.destroying)
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

// Bumped whenever anything that can change the rendered 3D scene changes, so
// the renderer can skip Filament completely on frames where nothing moved.
render_3d_revision: u64

Render_3D_Mark_Dirty :: #force_inline proc "contextless" () {render_3d_revision += 1}

Render_3D_Revision :: #force_inline proc "contextless" () -> u64 {return render_3d_revision}


Object_Set_Property :: proc(
	L: ^vm.State,
	value, ctx: rawptr,
	key: string,
	value_index: int,
) -> bool {
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
		if descriptor == nil ||
		   descriptor.registry == nil ||
		   descriptor.registry.enums == nil {return false}
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
		if !vm.ThreadHasSecurityCapability(
			L,
			datatypes.SECURITY_CAPABILITY_INTERNAL_SECURITY_ADMIN,
		) {
			_ = vm.RaiseError(L, "Capabilities is restricted to internal scripts")
			return true
		}
		descriptor := cast(^Class_Descriptor)ctx
		if descriptor == nil ||
		   descriptor.registry == nil ||
		   descriptor.registry.datatypes == nil {return false}
		object.capabilities = datatypes.Arg_SecurityCapabilities(
			L,
			value_index,
			descriptor.registry.datatypes,
		)
	case "Sandboxed":
		if !vm.ThreadHasSecurityCapability(
			L,
			datatypes.SECURITY_CAPABILITY_INTERNAL_SECURITY_ADMIN,
		) {
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
	if object == nil {return -1}
	for attribute, index in object.attributes {
		if attribute.name == name {return index}
	}
	return -1
}

Attribute_Name_Is_Valid :: proc(name: string) -> bool {
	if len(name) == 0 || len(name) > 100 {return false}
	if len(name) >= 3 &&
	   (name[0] == 'R' || name[0] == 'r') &&
	   (name[1] == 'B' || name[1] == 'b') &&
	   (name[2] == 'X' || name[2] == 'x') {
		return false
	}
	for character in name {
		if (character >= 'a' && character <= 'z') ||
		   (character >= 'A' && character <= 'Z') ||
		   (character >= '0' && character <= '9') ||
		   character == '_' ||
		   character == '-' ||
		   character == '.' ||
		   character == '/' {
			continue
		}
		return false
	}
	return true
}

Attribute_Value_Is_Supported :: proc(L: ^vm.State, index: int) -> bool {
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
	if !Attribute_Name_Is_Valid(name) {
		_ = vm.RaiseError(
			L,
			"attribute name must be 1-100 valid characters and cannot start with RBX",
		)
		return false
	}
	index := attribute_index(object, name)
	if vm.IsNil(L, value_index) {
		if index >= 0 {
			vm.ReleaseValue(L, object.attributes[index].value_ref)
			delete(object.attributes[index].name)
			ordered_remove(&object.attributes, index)
			object.metadata_revision += 1
		}
		return true
	}
	if !Attribute_Value_Is_Supported(L, value_index) {
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
		append(
			&object.attributes,
			Object_Attribute{name = strings.clone(name), value_ref = value_ref},
		)
	}
	object.metadata_revision += 1
	return true
}

Tag_Name_Is_Valid :: proc(tag: string) -> bool {
	return len(tag) > 0 && len(tag) <= 100 && !strings.contains(tag, "\x00")
}

Object_Has_Tag :: proc(object: ^Object, tag: string) -> bool {
	return slice.contains(object.tags[:], tag)
}

Object_Add_Tag :: proc(object: ^Object, tag: string) {
	if Object_Has_Tag(object, tag) {return}
	append(&object.tags, strings.clone(tag))
	if object.signal_registry != nil && len(object.tags) == 1 {
		object.signal_registry.tagged_objects[object] = true
	}
	object.metadata_revision += 1
}

Object_Remove_Tag :: proc(object: ^Object, tag: string) {
	for name, index in object.tags {
		if name != tag {continue}
		delete(name)
		ordered_remove(&object.tags, index)
		if object.signal_registry != nil && len(object.tags) == 0 {
			delete_key(&object.signal_registry.tagged_objects, object)
		}
		object.metadata_revision += 1
		return
	}
}

Object_Push_Tags :: proc(L: ^vm.State, object: ^Object) {
	vm.NewTable(L, len(object.tags))
	for tag, index in object.tags {
		vm.PushString(L, tag)
		vm.SetArrayValue(L, -2, index + 1)
	}
}

Object_Copy_Metadata :: proc(L: ^vm.State, source, destination: ^Object) {
	for attribute in source.attributes {
		vm.PushRegistryReference(L, attribute.value_ref)
		_ = Set_Attribute(L, destination, attribute.name, -1)
		vm.Pop(L)
	}
	for tag in source.tags {Object_Add_Tag(destination, tag)}
}

Object_Replace_Metadata :: proc(L: ^vm.State, source, destination: ^Object) {
	if source == destination {return}
	vm.PushNil(L)
	for len(destination.attributes) > 0 {
		_ = Set_Attribute(L, destination, destination.attributes[len(destination.attributes) - 1].name, -1)
	}
	vm.Pop(L)
	for len(destination.tags) > 0 {
		Object_Remove_Tag(destination, destination.tags[len(destination.tags) - 1])
	}
	Object_Copy_Metadata(L, source, destination)
}

clone_base_state :: proc(L: ^vm.State, source: ^Object, destination: ^Object) {
	if source == nil || destination == nil {
		return
	}


	Set_Name(destination, source.name)
	destination.archivable = source.archivable
	destination.capabilities = source.capabilities
	destination.security_requirement = source.security_requirement
	destination.sandboxed = source.sandboxed
	destination.can_replicate = source.can_replicate
	destination.replication_mode = source.replication_mode
	delete(destination.replication_group)
	destination.replication_group = strings.clone(source.replication_group)


	Object_Copy_Metadata(L, source, destination)
	for name, value_ref in source.imported_values {
		vm.PushRegistryReference(L, value_ref)
		destination.imported_values[name] = vm.RetainValue(L)
		vm.Pop(L)
	}
}

Clone_Object :: proc(L: ^vm.State, registry: ^Registry, source: ^Object) -> (^Object, bool) {
	if L == nil || registry == nil || source == nil {return nil, false}
	clones: map[^Object]^Object
	defer delete(clones)
	destination, ok := clone_object_tree(L, registry, source, &clones)
	if !ok {return nil, false}

	remap_cloned_attachment_and_weld_refs(clones)
	return destination, true
}

remap_cloned_attachment_and_weld_refs :: proc(clones: map[^Object]^Object) {
	for original, copy in clones {
		if Is_A_Class(original, &Cloth_Class) {
			cloth := cast(^Cloth)copy
			if endpoint := clones[cloth.attachment]; endpoint != nil {cloth.attachment = endpoint}
			if endpoint := clones[cloth.attachment1]; endpoint != nil {cloth.attachment1 = endpoint}
		}
		if Is_A_Class(original, &Constraint_Class) {
			constraint := cast(^Constraint)copy
			if endpoint := clones[constraint.attachment0]; endpoint != nil {
				constraint.attachment0 = endpoint
			}
			if endpoint := clones[constraint.attachment1]; endpoint != nil {
				constraint.attachment1 = endpoint
			}
		}
		if Is_A_Class(original, &WeldConstraint_Class) {
			weld := cast(^WeldConstraint)copy
			if endpoint := clones[weld.part0]; endpoint != nil {weld.part0 = endpoint}
			if endpoint := clones[weld.part1]; endpoint != nil {weld.part1 = endpoint}
		}
	}
}

clone_object_tree :: proc(
	L: ^vm.State,
	registry: ^Registry,
	source: ^Object,
	clones: ^map[^Object]^Object,
) -> (^Object, bool) {
	if !source.archivable {return nil, false}
	destination, ok := Push_New(registry, &vm.VM{L = L}, Get_Class_Name(source), false)
	if !ok || destination == nil {return nil, false}

	clones^[source] = destination
	clone_base_state(L, source, destination)
	Clone_Class_State(registry, source.class, source, destination)
	clone_children_into(L, registry, source, destination, clones)
	if Is_A_Class(source, &ViewportFrame_Class) {
		ViewportFrame_Remap_Cloned_Camera(source, destination)
	}
	return destination, true
}

clone_object_children :: proc(L: ^vm.State, registry: ^Registry, source, destination: ^Object) {
	clones: map[^Object]^Object
	defer delete(clones)
	clones[source] = destination
	clone_children_into(L, registry, source, destination, &clones)
	remap_cloned_attachment_and_weld_refs(clones)
}

clone_children_into :: proc(
	L: ^vm.State,
	registry: ^Registry,
	source, destination: ^Object,
	clones: ^map[^Object]^Object,
) {
	for child in source.children {
		if child == nil {continue}
		cloned_child, child_ok := clone_object_tree(L, registry, child, clones)
		if child_ok {
			Set_Parent(cloned_child, destination)
			vm.Pop(L)
		}
	}
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
	case "ContainsPoint":
		if !Is_A_Class(object, &GuiObject_Class) {return 0, false}
		x := f32(vm.ArgNumber(L, 2))
		y := f32(vm.ArgNumber(L, 3))
		vm.PushBoolean(L, GuiObject_contains_point(cast(^GuiObject)object, x, y))
		return 1, true
	case "Clone":
		if !object.archivable {
			vm.PushNil(L)
			return 1, true
		}

		descriptor := cast(^Class_Descriptor)ctx

		if descriptor == nil || descriptor.registry == nil {
			count := vm.RaiseError(L, "cannot clone Instance without a class registry")
			return count, true
		}

		_, ok := Clone_Object(L, descriptor.registry, object)

		if !ok {
			vm.PushNil(L)
			return 1, true
		}


		return 1, true
	case "Destroy":
		Destroy_Hierarchy(object)
		return 0, true
	case "ClearAllChildren":
		children := slice.clone(object.children[:])
		defer delete(children)
		for child in children {
			if child.parent == object && Object_Is_Accessible(L, child) {
				Destroy_Hierarchy(child)
			}
		}
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
	case "WaitForChild":
		name := vm.ArgString(L, 2)
		timeout := vm.ArgOptionalNumber(L, 3, 10)
		deadline := f64(timeout)
		waited := f64(0)
		step := f64(1.0 / 60.0)
		for {
			child := Find_First_Child(object, name)
			if child != nil {
				Push_Object(L, child)
				return 1, true
			}
			if waited >= deadline {
				Push_Object(L, nil)
				return 1, true
			}
			waited += step
		}
	case "WaitForChildOfClass":
		class_name := vm.ArgString(L, 2)
		timeout := vm.ArgOptionalNumber(L, 3, 10)
		deadline := f64(timeout)
		waited := f64(0)
		step := f64(1.0 / 60.0)
		for {
			child := Find_First_Child_Of_Class(object, class_name)
			if child != nil {
				Push_Object(L, child)
				return 1, true
			}
			if waited >= deadline {
				Push_Object(L, nil)
				return 1, true
			}
			waited += step
		}
	case "FindFirstAncestor":
		name := vm.ArgString(L, 2)
		ancestor := object.parent
		for ancestor != nil {
			if ancestor.name == name {
				Push_Object(L, ancestor)
				return 1, true
			}
			ancestor = ancestor.parent
		}
		Push_Object(L, nil)
		return 1, true
	case "FindFirstAncestorOfClass":
		class_name := vm.ArgString(L, 2)
		ancestor := object.parent
		for ancestor != nil {
			if Is_A(ancestor, class_name) {
				Push_Object(L, ancestor)
				return 1, true
			}
			ancestor = ancestor.parent
		}
		Push_Object(L, nil)
		return 1, true
	case "FindFirstAncestorWhichIsA":
		class_name := vm.ArgString(L, 2)
		ancestor := object.parent
		for ancestor != nil {
			if ancestor.class != nil && ancestor.class.name == class_name {
				Push_Object(L, ancestor)
				return 1, true
			}
			ancestor = ancestor.parent
		}
		Push_Object(L, nil)
		return 1, true
	case "GetChildren":
		vm.NewTable(L, len(object.children))
		index := 0
		for child in object.children {
			if !Object_Is_Accessible(L, child) || child.lua_ref <= 0 {continue}
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
			if !Object_Is_Accessible(L, descendant) || descendant.lua_ref <= 0 {continue}
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
	case "AddTag", "RemoveTag", "HasTag":
		tag := vm.ArgString(L, 2)
		if !Tag_Name_Is_Valid(tag) {return vm.RaiseError(L, "tag must be 1-100 characters"), true}
		switch method {
		case "AddTag": Object_Add_Tag(object, tag)
		case "RemoveTag": Object_Remove_Tag(object, tag)
		case "HasTag": vm.PushBoolean(L, Object_Has_Tag(object, tag)); return 1, true
		}
		return 0, true
	case "GetTags":
		Object_Push_Tags(L, object)
		return 1, true
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
		append_class_properties(L, descriptor.registry, object.class, &index)

		return 1, true
	}

	return 0, false
}
