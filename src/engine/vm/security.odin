package luau

import "base:runtime"
import luauh "luauh"

Thread_Security_Capabilities :: struct {
	bits_low:  u64,
	bits_high: u64,
}

THREAD_SECURITY_NONE :: Thread_Security_Capabilities{}
THREAD_SECURITY_ALL  :: Thread_Security_Capabilities{~u64(0), ~u64(0)}

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
