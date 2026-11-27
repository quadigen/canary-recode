package main

import vm "../src/engine/vm"
import "core:fmt"

run_on_thread :: proc(state: ^vm.VM, source, label: string) -> bool {
	thread := vm.NewThread(state.L)
	ref := vm.RetainValue(state.L)
	vm.Pop(state.L)
	defer vm.ReleaseValue(state.L, ref)

	ok, load_error := vm.LoadSource(state, thread, source, label)
	if !ok {
		fmt.eprintln("compilation failed: ", label, ": ", load_error)
		if load_error != "" {delete(load_error)}
		return false
	}
	finished, yielded, runtime_error := vm.ResumeThread(thread, state.L)
	if runtime_error != "" {
		fmt.eprintln("execution failed: ", label, ": ", runtime_error)
		delete(runtime_error)
		return false
	}
	return finished && !yielded
}

main :: proc() {
	state := vm.New()
	defer vm.Close(&state)


	vm.PushNumber(state.L, 42)
	vm.SetGlobalFromStack(&state, "HostGlobal")

	assert(
		run_on_thread(
			&state,
			`assert(HostGlobal == 42)
        _G.network_security_test_marker = "POISONED"
        assert(_G.network_security_test_marker == "POISONED")
        local coroutine_ok, coroutine_error = coroutine.resume(coroutine.create(function()
            assert(_G.network_security_test_marker == "POISONED")
            _G.child_scope_marker = "VISIBLE_TO_PARENT"
        end))
        assert(coroutine_ok, coroutine_error)
        assert(_G.child_scope_marker == "VISIBLE_TO_PARENT",
               "coroutines within a script must retain its globals")
        local ok = pcall(function() math.sqrt = function() return -1 end end)
        assert(not ok, "builtin math library must not be mutable")
        assert(type(getfenv) == "function" and type(setfenv) == "function")
        local scoped = function() return sandbox_marker end
        local newEnvironment = setmetatable({sandbox_marker = 12345}, {__index = _G})
        assert(setfenv(scoped, newEnvironment) == scoped)
        assert(getfenv(scoped) == newEnvironment)
        assert(scoped() == 12345)
        getfenv(print).native_environment_marker = "POISONED"
        getfenv(math.sqrt).builtin_environment_marker = "POISONED"
        local strmt = getmetatable("")
        if strmt then
            local ok_mt = pcall(function() strmt.__index = {} end)
            assert(not ok_mt, "string metatable must not be mutable")
        end
        `,
			"sandbox_writer",
		),
	)

	assert(
		run_on_thread(
			&state,
			`assert(HostGlobal == 42)
        assert(_G.network_security_test_marker == nil,
               "untrusted scripts share a mutable _G")
        assert(math.sqrt(16) == 4)
        assert(_G.native_environment_marker == nil, "builtin function leaked shared global scope")
        assert(_G.builtin_environment_marker == nil, "native closure exposed shared global scope")
        `,
			"sandbox_reader",
		),
	)


	vm.PushNumber(state.L, 84)
	vm.SetGlobalFromStack(&state, "HostGlobalAfterCreation")
	assert(run_on_thread(&state, `assert(HostGlobalAfterCreation == 84)`, "late_registration"))
	fmt.println("SECURITY_SANDBOX_VM_PASSED")
}
