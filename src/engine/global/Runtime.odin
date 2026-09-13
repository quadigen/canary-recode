package globals

import vm "../vm"

RUNTIME_NAME            :: "kinemium"
RUNTIME_VERSION_DISPLAY :: "1.19.0-dev"
RUNTIME_URL             :: "https://github.com/Qquaded/Kinemium-Engine"

RUNTIME_SEMANTIC_ENABLED    :: true
RUNTIME_SEMANTIC_MAJOR      :: 1
RUNTIME_SEMANTIC_MINOR      :: 19
RUNTIME_SEMANTIC_PATCH      :: 0
RUNTIME_SEMANTIC_PRERELEASE :: "dev"
RUNTIME_SEMANTIC_BUILD      :: ""

RUNTIME_GIT_ENABLED :: false
RUNTIME_GIT_URL     :: ""
RUNTIME_GIT_COMMIT  :: ""
RUNTIME_GIT_BRANCH  :: ""

LUAU_INFO_ENABLED    :: false
LUAU_VERSION_DISPLAY :: ""
LUAU_VERSION_MAJOR   :: 0
LUAU_VERSION_MINOR   :: 0
LUAU_URL             :: "https://github.com/luau-lang/luau"

runtime_set_optional_string :: proc(
	L: ^vm.State,
	table_index: int,
	name: string,
	value: string,
) {
	if len(value) == 0 {
		return
	}

	vm.PushString(L, value)
	vm.SetField(L, table_index, name)
}


runtime_push_semantic_version :: proc(L: ^vm.State) {
	vm.NewTable(L, 0, 5)

	vm.PushInteger(L, RUNTIME_SEMANTIC_MAJOR)
	vm.SetField(L, -2, "major")

	vm.PushInteger(L, RUNTIME_SEMANTIC_MINOR)
	vm.SetField(L, -2, "minor")

	vm.PushInteger(L, RUNTIME_SEMANTIC_PATCH)
	vm.SetField(L, -2, "patch")

	runtime_set_optional_string(
		L,
		-2,
		"prerelease",
		RUNTIME_SEMANTIC_PRERELEASE,
	)
	runtime_set_optional_string(
		L,
		-2,
		"build",
		RUNTIME_SEMANTIC_BUILD,
	)

	vm.SetReadOnly(L, -1)
}

runtime_push_git_version :: proc(L: ^vm.State) {
	vm.NewTable(L, 0, 3)

	runtime_set_optional_string(
		L,
		-2,
		"url",
		RUNTIME_GIT_URL,
	)

	vm.PushString(L, RUNTIME_GIT_COMMIT)
	vm.SetField(L, -2, "commit")

	runtime_set_optional_string(
		L,
		-2,
		"branch",
		RUNTIME_GIT_BRANCH,
	)

	vm.SetReadOnly(L, -1)
}

runtime_push_version :: proc(L: ^vm.State) {
	vm.NewTable(L, 0, 3)

	vm.PushString(L, RUNTIME_VERSION_DISPLAY)
	vm.SetField(L, -2, "display")

	if RUNTIME_SEMANTIC_ENABLED {
		runtime_push_semantic_version(L)
		vm.SetField(L, -2, "semantic")
	}

	if RUNTIME_GIT_ENABLED {
		assert(
			len(RUNTIME_GIT_COMMIT) > 0,
			"RUNTIME_GIT_COMMIT must be set when RUNTIME_GIT_ENABLED is true",
		)

		runtime_push_git_version(L)
		vm.SetField(L, -2, "git")
	}

	vm.SetReadOnly(L, -1)
}

runtime_install_runtime_global :: proc(vm_state: ^vm.VM) {
	assert(vm_state != nil)
	assert(vm_state.L != nil)

	L := vm_state.L

	vm.NewTable(L, 0, 4)

	vm.PushString(L, RUNTIME_NAME)
	vm.SetField(L, -2, "name")

	runtime_push_version(L)
	vm.SetField(L, -2, "version")

	runtime_set_optional_string(
		L,
		-2,
		"url",
		RUNTIME_URL,
	)

	vm.SetReadOnly(L, -1)
	vm.SetGlobalFromStack(vm_state, "_RUNTIME")
}


runtime_install_luau_global :: proc(vm_state: ^vm.VM) {
	if !LUAU_INFO_ENABLED {
		return
	}

	assert(vm_state != nil)
	assert(vm_state.L != nil)
	assert(
		len(LUAU_VERSION_DISPLAY) > 0,
		"LUAU_VERSION_DISPLAY must be set when LUAU_INFO_ENABLED is true",
	)

	L := vm_state.L

	vm.NewTable(L, 0, 2)
	vm.NewTable(L, 0, 3)

	vm.PushString(L, LUAU_VERSION_DISPLAY)
	vm.SetField(L, -2, "display")

	vm.PushInteger(L, LUAU_VERSION_MAJOR)
	vm.SetField(L, -2, "major")

	vm.PushInteger(L, LUAU_VERSION_MINOR)
	vm.SetField(L, -2, "minor")

	vm.SetReadOnly(L, -1)
	vm.SetField(L, -2, "version")

	runtime_set_optional_string(
		L,
		-2,
		"url",
		LUAU_URL,
	)

	vm.SetReadOnly(L, -1)
	vm.SetGlobalFromStack(vm_state, "_LUAU")
}


Install_Runtime_Globals :: proc(vm_state: ^vm.VM) {
	runtime_install_runtime_global(vm_state)
	runtime_install_luau_global(vm_state)
}
