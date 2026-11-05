package extensions

import tracy "../util/odin-tracy"
import vm "../vm"
import "core:strings"

@(private)
kne_api_context :: proc(L: ^vm.State) -> ^Context {
	return cast(^Context)vm.UpvaluePointer(L)
}

@(private)
set_table_string :: proc(L: ^vm.State, key, value: string) {
	vm.PushString(L, value)
	vm.SetField(L, -2, key)
}

@(private)
push_extension_table :: proc(L: ^vm.State, record: ^Extension_Record) {
	vm.NewTable(L, 0, 8)
	set_table_string(L, "Id", record.manifest.id)
	set_table_string(L, "Name", record.manifest.name)
	set_table_string(L, "Version", record.manifest.version)
	set_table_string(L, "Author", record.manifest.author)
	set_table_string(L, "State", Extension_State_Name(record.state))
	set_table_string(L, "Directory", record.directory)
	if len(record.last_error) > 0 {
		set_table_string(L, "Error", record.last_error)
	}

	vm.NewTable(L, 0, 0)
	for capability, index in record.manifest.capabilities {
		vm.PushString(L, capability)
		vm.RawSetIndex(L, -2, index + 1)
	}
	vm.SetField(L, -2, "Capabilities")
}

kne_lua_get_extensions :: proc "c" (L: ^vm.State) -> i32 {
	context = tracy.DefaultContext()
	state := kne_api_context(L)
	if state == nil {
		vm.PushNil(L)
		return 1
	}

	vm.NewTable(L, 0, 0)
	index := 1
	for record in state.records {
		if record == nil || record.state == .Unloaded {
			continue
		}
		push_extension_table(L, record)
		vm.RawSetIndex(L, -2, index)
		index += 1
	}
	return 1
}

kne_lua_get_extension :: proc "c" (L: ^vm.State) -> i32 {
	context = tracy.DefaultContext()
	state := kne_api_context(L)
	if state == nil {
		vm.PushNil(L)
		return 1
	}

	record := Find(state, vm.ArgString(L, 1))
	if record == nil {
		vm.PushNil(L)
		return 1
	}

	push_extension_table(L, record)
	return 1
}

kne_lua_is_loaded :: proc "c" (L: ^vm.State) -> i32 {
	context = tracy.DefaultContext()
	state := kne_api_context(L)
	loaded := state != nil && Find(state, vm.ArgString(L, 1)) != nil
	vm.PushBoolean(L, loaded)
	return 1
}

kne_lua_load :: proc "c" (L: ^vm.State) -> i32 {
	context = tracy.DefaultContext()
	state := kne_api_context(L)
	if state == nil {
		vm.PushBoolean(L, false)
		vm.PushString(L, "the extension system is not initialized")
		return 2
	}

	_, err := Load_Directory(state, vm.ArgString(L, 1))
	if err != "" {
		vm.PushBoolean(L, false)
		vm.PushString(L, err)
		delete(err)
		return 2
	}

	vm.PushBoolean(L, true)
	return 1
}

kne_lua_unload :: proc "c" (L: ^vm.State) -> i32 {
	context = tracy.DefaultContext()
	state := kne_api_context(L)
	if state == nil {
		vm.PushBoolean(L, false)
		return 1
	}

	err := Unload(state, vm.ArgString(L, 1))
	if err != "" {
		vm.PushBoolean(L, false)
		vm.PushString(L, err)
		delete(err)
		return 2
	}

	vm.PushBoolean(L, true)
	return 1
}

kne_lua_reload :: proc "c" (L: ^vm.State) -> i32 {
	context = tracy.DefaultContext()
	state := kne_api_context(L)
	if state == nil {
		vm.PushBoolean(L, false)
		return 1
	}

	err := Reload(state, vm.ArgString(L, 1))
	if err != "" {
		vm.PushBoolean(L, false)
		vm.PushString(L, err)
		delete(err)
		return 2
	}

	vm.PushBoolean(L, true)
	return 1
}

kne_lua_api_version :: proc "c" (L: ^vm.State) -> i32 {
	context = tracy.DefaultContext()
	vm.NewTable(L, 0, 2)
	vm.PushInteger(L, i64(KNE_ABI_MAJOR))
	vm.SetField(L, -2, "major")
	vm.PushInteger(L, i64(KNE_ABI_MINOR))
	vm.SetField(L, -2, "minor")
	return 1
}

@(private)
register_api_function :: proc(
	L: ^vm.State,
	state: ^Context,
	name: string,
	function: vm.CFunction,
) {
	vm.PushLightUserdata(L, state)
	vm.PushFunction(L, strings.concatenate({"KNE.", name}), function, 1)
	vm.SetField(L, -2, name)
}


Install_Luau_Api :: proc(context_state: ^Context, vm_state: ^vm.VM) {
	if context_state == nil || vm_state == nil || vm_state.L == nil {
		return
	}

	L := vm_state.L
	vm.NewTable(L, 0, 8)

	register_api_function(L, context_state, "GetExtensions", kne_lua_get_extensions)
	register_api_function(L, context_state, "GetExtension", kne_lua_get_extension)
	register_api_function(L, context_state, "IsLoaded", kne_lua_is_loaded)
	register_api_function(L, context_state, "Load", kne_lua_load)
	register_api_function(L, context_state, "Unload", kne_lua_unload)
	register_api_function(L, context_state, "Reload", kne_lua_reload)
	register_api_function(L, context_state, "ApiVersion", kne_lua_api_version)

	vm.SetGlobalFromStack(vm_state, "KNE")
}
