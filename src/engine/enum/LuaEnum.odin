package engine_enums

import "core:reflect"
import "core:strings"
import "base:runtime"
import vm "../vm"

ENUM_TAG :: 47
ENUM_ITEM_TAG :: 48

Enum_Type :: struct {
	name:         string,
	display_name: string,
	items:        [dynamic]^Enum_Item,
	lua_ref:      i32,
}

Enum_Item :: struct {
	enum_type: ^Enum_Type,
	name:         string,
	display_name: string,
	value:        i64,
	lua_ref:      i32,
}

Registry :: struct {
	types:        [dynamic]^Enum_Type,
	enum_binding: vm.Userdata_Binding,
	item_binding: vm.Userdata_Binding,
}

find_type :: proc(registry: ^Registry, name: string) -> ^Enum_Type {
	if registry == nil {
		return nil
	}
	for enum_type in registry.types {
		if enum_type.name == name {
			return enum_type
		}
	}
	return nil
}

find_item_by_name :: proc(enum_type: ^Enum_Type, name: string) -> ^Enum_Item {
	if enum_type == nil {
		return nil
	}
	for item in enum_type.items {
		if item.name == name {
			return item
		}
	}
	return nil
}

find_item_by_value :: proc(enum_type: ^Enum_Type, value: i64) -> ^Enum_Item {
	if enum_type == nil {
		return nil
	}
	for item in enum_type.items {
		if item.value == value {
			return item
		}
	}
	return nil
}

push_enum_type :: proc(L: ^vm.State, registry: ^Registry, enum_type: ^Enum_Type) {
	if registry == nil || enum_type == nil {
		vm.PushNil(L)
		return
	}
	if enum_type.lua_ref > 0 {
		vm.PushRegistryReference(L, enum_type.lua_ref)
		return
	}
	vm.PushUserdata(&vm.VM{L = L}, enum_type, &registry.enum_binding)
	enum_type.lua_ref = vm.RetainValue(L)
}

push_enum_item :: proc(L: ^vm.State, registry: ^Registry, item: ^Enum_Item) {
	if registry == nil || item == nil {
		vm.PushNil(L)
		return
	}
	if item.lua_ref > 0 {
		vm.PushRegistryReference(L, item.lua_ref)
		return
	}
	vm.PushUserdata(&vm.VM{L = L}, item, &registry.item_binding)
	item.lua_ref = vm.RetainValue(L)
}

enum_type_get :: proc(L: ^vm.State, value, ctx: rawptr, key: string) -> bool {
	registry := cast(^Registry)ctx
	enum_type := cast(^Enum_Type)value
	if enum_type == nil {
		return false
	}

	switch key {
	case "Name":
		vm.PushString(L, enum_type.name)
	case "GetEnumItems":
		vm.PushUserdataMethod(L, key)
	case:
		item := find_item_by_name(enum_type, key)
		if item == nil {
			return false
		}
		push_enum_item(L, registry, item)
	}
	return true
}

enum_type_namecall :: proc(L: ^vm.State, value, ctx: rawptr, method: string) -> (i32, bool) {
	registry := cast(^Registry)ctx
	enum_type := cast(^Enum_Type)value
	if method != "GetEnumItems" || enum_type == nil {
		return 0, false
	}

	vm.NewTable(L, len(enum_type.items))
	for item, index in enum_type.items {
		push_enum_item(L, registry, item)
		vm.SetArrayValue(L, -2, index+1)
	}
	return 1, true
}

enum_type_string :: proc(value, ctx: rawptr) -> string {
	enum_type := cast(^Enum_Type)value
	if enum_type == nil {
		return "Enum"
	}
	return enum_type.display_name
}

enum_item_get :: proc(L: ^vm.State, value, ctx: rawptr, key: string) -> bool {
	registry := cast(^Registry)ctx
	item := cast(^Enum_Item)value
	if item == nil {
		return false
	}

	switch key {
	case "Name":
		vm.PushString(L, item.name)
	case "Value":
		vm.PushNumber(L, f64(item.value))
	case "EnumType":
		push_enum_type(L, registry, item.enum_type)
	case:
		return false
	}
	return true
}

enum_item_string :: proc(value, ctx: rawptr) -> string {
	item := cast(^Enum_Item)value
	if item == nil {
		return "EnumItem"
	}
	return item.display_name
}

enum_pointer_equal :: proc(value, other, ctx: rawptr) -> bool {
	return value == other
}

Register_Reflected_Enum :: proc(registry: ^Registry, name: string, Enum_Type_Id: typeid) {
	assert(registry != nil)
	assert(find_type(registry, name) == nil)

	enum_type := new(Enum_Type)
	enum_type.name = name
	enum_type.display_name = strings.concatenate({"Enum.", name})
	for field in reflect.enum_fields_zipped(Enum_Type_Id) {
		item := new(Enum_Item)
		item^ = Enum_Item{
			enum_type = enum_type,
			name      = field.name,
			display_name = strings.concatenate({enum_type.display_name, ".", field.name}),
			value     = i64(field.value),
		}
		append(&enum_type.items, item)
	}
	append(&registry.types, enum_type)
}

Registry_Init :: proc(registry: ^Registry) {
	assert(registry != nil)
	registry.enum_binding = vm.Userdata_Binding{
		name     = "Enum",
		tag      = ENUM_TAG,
		ctx      = registry,
		get      = enum_type_get,
		namecall = enum_type_namecall,
		string   = enum_type_string,
		equal    = enum_pointer_equal,
	}
	registry.item_binding = vm.Userdata_Binding{
		name   = "EnumItem",
		tag    = ENUM_ITEM_TAG,
		ctx    = registry,
		get    = enum_item_get,
		string = enum_item_string,
		equal  = enum_pointer_equal,
	}
	Register_Default_Enums(registry)
}

Push_Item_By_Value :: proc(L: ^vm.State, registry: ^Registry, enum_name: string, value: i64) -> bool {
	item := find_item_by_value(find_type(registry, enum_name), value)
	if item == nil {
		vm.PushNil(L)
		return false
	}
	push_enum_item(L, registry, item)
	return true
}

Arg_Item :: proc(L: ^vm.State, index: int, registry: ^Registry, enum_name: string = "") -> ^Enum_Item {
	if registry == nil || !vm.IsUserdataType(L, index, &registry.item_binding) {
		_ = vm.RaiseError(L, "expected EnumItem")
		return nil
	}
	item := cast(^Enum_Item)vm.UserdataValue(L, index)
	if enum_name != "" && item.enum_type.name != enum_name {
		_ = vm.RaiseError(L, "EnumItem belongs to the wrong Enum")
		return nil
	}
	return item
}

enum_item_from_name :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	registry := cast(^Registry)vm.UpvaluePointer(L)
	if !vm.IsUserdataType(L, 1, &registry.enum_binding) {
		return vm.RaiseError(L, "expected Enum")
	}
	enum_type := cast(^Enum_Type)vm.UserdataValue(L, 1)
	push_enum_item(L, registry, find_item_by_name(enum_type, vm.ArgString(L, 2)))
	return 1
}

enum_item_from_value :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	registry := cast(^Registry)vm.UpvaluePointer(L)
	if !vm.IsUserdataType(L, 1, &registry.enum_binding) {
		return vm.RaiseError(L, "expected Enum")
	}
	enum_type := cast(^Enum_Type)vm.UserdataValue(L, 1)
	push_enum_item(L, registry, find_item_by_value(enum_type, i64(vm.ArgNumber(L, 2))))
	return 1
}

Install :: proc(registry: ^Registry, vm_state: ^vm.VM) {
	vm.NewTable(vm_state.L, 0, len(registry.types))
	for enum_type in registry.types {
		push_enum_type(vm_state.L, registry, enum_type)
		vm.SetField(vm_state.L, -2, enum_type.name)
	}
	vm.SetReadOnly(vm_state.L, -1)
	vm.SetGlobalFromStack(vm_state, "Enum")

	vm.NewTable(vm_state.L, 0, 2)
	vm.PushLightUserdata(vm_state.L, registry)
	vm.PushFunction(vm_state.L, "EnumItem.fromName", enum_item_from_name, 1)
	vm.SetField(vm_state.L, -2, "fromName")
	vm.PushLightUserdata(vm_state.L, registry)
	vm.PushFunction(vm_state.L, "EnumItem.fromValue", enum_item_from_value, 1)
	vm.SetField(vm_state.L, -2, "fromValue")
	vm.SetReadOnly(vm_state.L, -1)
	vm.SetGlobalFromStack(vm_state, "EnumItem")
}

Registry_Destroy :: proc(registry: ^Registry) {
	if registry == nil {
		return
	}
	for enum_type in registry.types {
		for item in enum_type.items {
			delete(item.display_name)
			free(item)
		}
		delete(enum_type.items)
		delete(enum_type.display_name)
		free(enum_type)
	}
	delete(registry.types)
	registry.types = nil
}
