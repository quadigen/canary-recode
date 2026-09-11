package luau

import "base:runtime"
import luauh "luauh"

Thread_Security_Capabilities :: struct {
	bits_low:  u64,
	bits_high: u64,
}

Security_Requirement :: struct {
	capabilities: Thread_Security_Capabilities,
}

THREAD_SECURITY_NONE :: Thread_Security_Capabilities{}
THREAD_SECURITY_ALL  :: Thread_Security_Capabilities{~u64(0), ~u64(0)}
SECURITY_REQUIREMENT_NONE :: Security_Requirement{}

SecurityRequirementFromCapabilities :: proc(capabilities: Thread_Security_Capabilities) -> Security_Requirement {
	return Security_Requirement{capabilities = capabilities}
}

SecurityRequirementFromValue :: proc(capability: i64) -> Security_Requirement {
	result := SECURITY_REQUIREMENT_NONE
	if capability < 0 || capability > 127 {
		return result
	}
	if capability < 64 {
		result.capabilities.bits_low = u64(1) << u64(capability)
	} else {
		result.capabilities.bits_high = u64(1) << u64(capability-64)
	}
	return result
}

SecurityRequirementIsNone :: proc(requirement: Security_Requirement) -> bool {
	return requirement.capabilities.bits_low == 0 && requirement.capabilities.bits_high == 0
}

ThreadSecurityAddCapability :: proc(capabilities: Thread_Security_Capabilities, capability: i64) -> Thread_Security_Capabilities {
	result := capabilities
	if capability < 0 || capability > 127 {
		return result
	}
	if capability < 64 {
		result.bits_low |= u64(1) << u64(capability)
	} else {
		result.bits_high |= u64(1) << u64(capability-64)
	}
	return result
}

ThreadHasSecurityCapabilities :: proc(L: ^State, required: Thread_Security_Capabilities) -> bool {
	current := GetThreadSecurityCapabilities(L)
	return current.bits_low & required.bits_low == required.bits_low &&
	       current.bits_high & required.bits_high == required.bits_high
}

ThreadMeetsSecurityRequirement :: proc(L: ^State, requirement: Security_Requirement) -> bool {
	return ThreadHasSecurityCapabilities(L, requirement.capabilities)
}

thread_security_context :: proc(L: ^State) -> ^Thread_Security_Capabilities {
	if L == nil {
		return nil
	}
	return cast(^Thread_Security_Capabilities)luauh.lua_getthreaddata(L)
}

GetThreadSecurityCapabilities :: proc(L: ^State) -> Thread_Security_Capabilities {
	security := thread_security_context(L)
	if security == nil {
		return THREAD_SECURITY_NONE
	}
	return security^
}

SetThreadSecurityCapabilities :: proc(L: ^State, capabilities: Thread_Security_Capabilities) {
	if L == nil {
		return
	}

	security := thread_security_context(L)
	if security == nil {
		security = new(Thread_Security_Capabilities)
		luauh.lua_setthreaddata(L, security)
	}
	security^ = capabilities
}

ThreadHasSecurityCapability :: proc(L: ^State, capability: i64) -> bool {
	if capability < 0 || capability > 127 {
		return false
	}

	capabilities := GetThreadSecurityCapabilities(L)
	if capability < 64 {
		return capabilities.bits_low & (u64(1) << u64(capability)) != 0
	}
	return capabilities.bits_high & (u64(1) << u64(capability-64)) != 0
}

thread_security_userthread :: proc "c" (parent, thread: ^State) {
	context = runtime.default_context()
	if thread == nil {
		return
	}

	if parent == nil {
		security := thread_security_context(thread)
		if security != nil {
			luauh.lua_setthreaddata(thread, nil)
			free(security)
		}
		return
	}

	SetThreadSecurityCapabilities(thread, GetThreadSecurityCapabilities(parent))
}

InitializeThreadSecurity :: proc(L: ^State) {
	if L == nil {
		return
	}
	luauh.lua_setuserthreadcallback(L, thread_security_userthread)
	SetThreadSecurityCapabilities(L, THREAD_SECURITY_NONE)
}

ShutdownThreadSecurity :: proc(L: ^State) {
	if L == nil {
		return
	}
	security := thread_security_context(L)
	if security != nil {
		luauh.lua_setthreaddata(L, nil)
		free(security)
	}
}

RunWithSecurityCapabilities :: proc(
	vm: ^VM,
	source: string,
	capabilities: Thread_Security_Capabilities,
	chunk_name: string = "Kinemium",
) -> (ok: bool, err: string) {
	assert_open(vm)
	previous := GetThreadSecurityCapabilities(vm.L)
	SetThreadSecurityCapabilities(vm.L, capabilities)
	defer SetThreadSecurityCapabilities(vm.L, previous)
	return Run(vm, source, chunk_name)
}

RunInternal :: proc(
	vm: ^VM,
	source: string,
	chunk_name: string = "KinemiumInternal",
) -> (ok: bool, err: string) {
	return RunWithSecurityCapabilities(vm, source, THREAD_SECURITY_ALL, chunk_name)
}
