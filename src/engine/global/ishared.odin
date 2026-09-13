package globals

import "core:strings"

import datatypes "../datatypes"
import vm "../vm"

ISHARED_USERDATA_TAG :: 43

IShared_Entry :: struct {
	key:       string,
	value_ref: i32,
}

ishared_find :: proc(registry: ^Registry, key: string) -> int {
	if registry == nil {
		return -1
	}

	for entry, index in registry.ishared_entries {
		if entry.key == key {
			return index
		}
	}

	return -1
}

ishared_check_access :: proc(L: ^vm.State) -> bool {
	if vm.ThreadHasSecurityCapability(
		L,
		datatypes.SECURITY_CAPABILITY_INTERNAL_SHARED_ACCESS,
	) {
		return true
	}

	_ = vm.RaiseError(
		L,
		"ishared is restricted to internal scripts",
	)

	return false
}

ishared_get :: proc(
	L: ^vm.State,
	value: rawptr,
	ctx: rawptr,
	key: string,
) -> bool {
	if !ishared_check_access(L) {
		return true
	}

	registry := cast(^Registry)value
	if registry == nil {
		vm.PushNil(L)
		return true
	}

	index := ishared_find(registry, key)

	if index < 0 {
		vm.PushNil(L)
		return true
	}

	vm.PushRegistryReference(
		L,
		registry.ishared_entries[index].value_ref,
	)

	return true
}

ishared_set :: proc(
	L: ^vm.State,
	value: rawptr,
	ctx: rawptr,
	key: string,
	value_index: int,
) -> bool {
	if !ishared_check_access(L) {
		return true
	}

	registry := cast(^Registry)value
	if registry == nil {
		return true
	}

	index := ishared_find(registry, key)

	if vm.IsNil(L, value_index) {
		if index >= 0 {
			vm.ReleaseValue(
				L,
				registry.ishared_entries[index].value_ref,
			)

			delete(registry.ishared_entries[index].key)
			ordered_remove(&registry.ishared_entries, index)
		}

		return true
	}

	vm.PushValue(L, value_index)
	new_ref := vm.RetainValue(L)
	vm.Pop(L)

	if index >= 0 {
		vm.ReleaseValue(
			L,
			registry.ishared_entries[index].value_ref,
		)

		registry.ishared_entries[index].value_ref = new_ref
		return true
	}

	append(
		&registry.ishared_entries,
		IShared_Entry{
			key       = strings.clone(key),
			value_ref = new_ref,
		},
	)

	return true
}

ishared_tostring :: proc(value: rawptr, ctx: rawptr) -> string {
	return "ishared"
}

Install_IShared :: proc(
	registry: ^Registry,
	vm_state: ^vm.VM,
) {
	assert(registry != nil)
	assert(vm_state != nil)

	registry.ishared_binding = vm.Userdata_Binding{
		name   = "ishared",
		tag    = ISHARED_USERDATA_TAG,
		ctx    = registry,
		owner  = registry,
		get    = ishared_get,
		set    = ishared_set,
		string = ishared_tostring,
	}

	vm.PushUserdata(
		vm_state,
		registry,
		&registry.ishared_binding,
	)

	vm.SetGlobalFromStack(vm_state, "ishared")
}

Destroy_IShared :: proc(
	registry: ^Registry,
	L: ^vm.State = nil,
) {
	if registry == nil {
		return
	}

	for entry in registry.ishared_entries {
		if L != nil && entry.value_ref > 0 {
			vm.ReleaseValue(L, entry.value_ref)
		}

		delete(entry.key)
	}

	delete(registry.ishared_entries)
	registry.ishared_entries = nil
}