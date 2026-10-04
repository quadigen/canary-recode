package globals

import "core:time"
import "base:runtime"
import vm "../vm"

RUNTIME_NAME            :: "kinemium"
RUNTIME_VERSION_DISPLAY := string(#config(RUNTIME_VERSION_DISPLAY, "1.19.0-dev"))
RUNTIME_URL             := string(#config(RUNTIME_URL, "https://github.com/quadigen/canary-recode"))

// The update manifest for the engine self-update flow. Release builds are
// stamped (see justfile / CI) with everything except this constant; the
// self-update system is disabled unless RUNTIME_GIT_COMMIT is non-empty.
RUNTIME_UPDATE_URL := string(#config(RUNTIME_UPDATE_URL, "https://api.github.com/repos/quadigen/canary-recode/releases/latest"))

RUNTIME_SEMANTIC_ENABLED    := bool(#config(RUNTIME_SEMANTIC_ENABLED, true))
RUNTIME_SEMANTIC_MAJOR      := int(#config(RUNTIME_SEMANTIC_MAJOR, 1))
RUNTIME_SEMANTIC_MINOR      := int(#config(RUNTIME_SEMANTIC_MINOR, 19))
RUNTIME_SEMANTIC_PATCH      := int(#config(RUNTIME_SEMANTIC_PATCH, 0))
RUNTIME_SEMANTIC_PRERELEASE := string(#config(RUNTIME_SEMANTIC_PRERELEASE, "dev"))
RUNTIME_SEMANTIC_BUILD      := string(#config(RUNTIME_SEMANTIC_BUILD, ""))

RUNTIME_GIT_ENABLED := bool(#config(RUNTIME_GIT_ENABLED, false))
RUNTIME_GIT_URL     := string(#config(RUNTIME_GIT_URL, "https://github.com/quadigen/canary-recode"))
RUNTIME_GIT_COMMIT  := string(#config(RUNTIME_GIT_COMMIT, ""))
RUNTIME_GIT_BRANCH  := string(#config(RUNTIME_GIT_BRANCH, ""))

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

	vm.PushInteger(L, i64(RUNTIME_SEMANTIC_MAJOR))
	vm.SetField(L, -2, "major")

	vm.PushInteger(L, i64(RUNTIME_SEMANTIC_MINOR))
	vm.SetField(L, -2, "minor")

	vm.PushInteger(L, i64(RUNTIME_SEMANTIC_PATCH))
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


runtime_global_tick :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	vm.PushNumber(L, f64(time.to_unix_nanoseconds(time.now())) / 1e9)
	return 1
}

runtime_global_time :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	vm.PushNumber(L, f64(time.to_unix_nanoseconds(time.now())) / 1e9)
	return 1
}

runtime_civil_from_days :: proc(days: i64) -> (year, month, day: i64) {
	z := days + 719468
	if z < 0 {
		z = z - 146096
	}
	era := z / 146097
	doe := z - era * 146097
	yoe := (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
	y := yoe + era * 400
	doy := doe - (365 * yoe + yoe / 4 - yoe / 100)
	mp := (5 * doy + 2) / 153
	d := doy - (153 * mp + 2) / 5 + 1
	m := mp + 3
	if mp >= 10 {
		m = mp - 9
	}
	if m <= 2 {
		y += 1
	}
	return y, m, d
}

runtime_global_date :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	seconds := i64(time.to_unix_seconds(time.now()))
	days := seconds / 86400
	remainder := seconds % 86400
	if remainder < 0 {
		remainder += 86400
		days -= 1
	}
	hour := remainder / 3600
	minute := (remainder % 3600) / 60
	second := remainder % 60
	year, month, day := runtime_civil_from_days(days)

	vm.NewTable(L, 0, 9)
	vm.PushInteger(L, year)
	vm.SetField(L, -2, "year")
	vm.PushInteger(L, month)
	vm.SetField(L, -2, "month")
	vm.PushInteger(L, day)
	vm.SetField(L, -2, "day")
	vm.PushInteger(L, hour)
	vm.SetField(L, -2, "hour")
	vm.PushInteger(L, minute)
	vm.SetField(L, -2, "min")
	vm.PushInteger(L, second)
	vm.SetField(L, -2, "sec")
	vm.PushInteger(L, (days + 4) % 7 + 1)
	vm.SetField(L, -2, "wday")
	vm.PushInteger(L, 0)
	vm.SetField(L, -2, "yday")
	vm.PushBoolean(L, false)
	vm.SetField(L, -2, "isdst")
	return 1
}

runtime_global_collectgarbage :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	option := "collect"
	if vm.StackTop(L) >= 1 {
		option = vm.ArgString(L, 1)
	}
	if option == "count" {
		vm.PushNumber(L, f64(0))
		return 1
	}
	if option == "collect" {
		vm.PushNumber(L, f64(0))
		return 1
	}
	vm.PushNil(L)
	return 1
}

runtime_global_settings :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	vm.NewTable(L, 0, 2)
	vm.PushBoolean(L, settings_studio)
	vm.SetField(L, -2, "Studio")
	vm.PushBoolean(L, false)
	vm.SetField(L, -2, "DeviceCamera")
	return 1
}

settings_studio: bool

runtime_install_time_global :: proc(vm_state: ^vm.VM) {
	assert(vm_state != nil)
	assert(vm_state.L != nil)

	L := vm_state.L

	vm.PushFunction(L, "tick", runtime_global_tick, 0)
	vm.SetGlobalFromStack(vm_state, "tick")

	vm.PushFunction(L, "time", runtime_global_time, 0)
	vm.SetGlobalFromStack(vm_state, "time")

	vm.NewTable(L, 0, 3)
	vm.PushFunction(L, "clock", runtime_global_tick, 0)
	vm.SetField(L, -2, "clock")
	vm.PushFunction(L, "time", runtime_global_time, 0)
	vm.SetField(L, -2, "time")
	vm.PushFunction(L, "date", runtime_global_date, 0)
	vm.SetField(L, -2, "date")
	vm.SetReadOnly(L, -1)
	vm.SetGlobalFromStack(vm_state, "os")

	vm.NewTable(L, 0, 0)
	vm.SetGlobalFromStack(vm_state, "shared")

	vm.PushFunction(L, "collectgarbage", runtime_global_collectgarbage, 0)
	vm.SetGlobalFromStack(vm_state, "collectgarbage")

	vm.PushFunction(L, "settings", runtime_global_settings, 0)
	vm.SetGlobalFromStack(vm_state, "settings")
}
Install_Runtime_Globals :: proc(vm_state: ^vm.VM) {
	runtime_install_runtime_global(vm_state)
	runtime_install_luau_global(vm_state)
	runtime_install_time_global(vm_state)
}
