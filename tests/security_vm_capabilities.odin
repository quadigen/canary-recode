package main

import packages "../src/engine/packages"
import tracy "../src/engine/util/odin-tracy"
import vm "../src/engine/vm"
import "core:fmt"

expect :: proc(ok: bool, description: string) {
	if !ok {panic(description)}
}

probe_resolve :: proc "c" (L: ^vm.State) -> i32 {
	context = tracy.DefaultContext()
	registry := cast(^packages.Registry)vm.UpvaluePointer(L)
	if packages.Resolve(L, vm.ArgString(L, 1), registry) {
		return 1
	}
	return vm.RaiseError(L, "test package not found")
}

run_ok :: proc(state: ^vm.VM, source, label: string, internal := false) {
	ok, err := false, ""
	if internal {
		ok, err = vm.RunInternal(state, source, label)
	} else {
		ok, err = vm.Run(state, source, label)
	}
	if !ok {
		fmt.eprintf("%s: %s\n", label, err)
		delete(err)
		panic("security VM Lua regression")
	}
}

main :: proc() {
	state := vm.New()
	defer vm.Close(&state)

	expect(
		!vm.ThreadMeetsSecurityRequirement(state.L, vm.SecurityRequirementFromValue(-1)),
		"invalid negative capability grants access",
	)
	expect(
		!vm.ThreadMeetsSecurityRequirement(state.L, vm.SecurityRequirementFromValue(128)),
		"invalid oversized capability grants access",
	)

	privilege := vm.ThreadSecurityAddCapability(vm.THREAD_SECURITY_NONE, 122)
	vm.SetThreadSecurityCapabilities(state.L, privilege)
	child := vm.NewThread(state.L)
	child_ref := vm.RetainValue(state.L)
	vm.Pop(state.L)
	expect(vm.ThreadHasSecurityCapability(child, 122), "child did not inherit capability")
	vm.SetThreadSecurityCapabilities(state.L, vm.THREAD_SECURITY_NONE)
	expect(
		vm.ThreadHasSecurityCapability(child, 122),
		"parent privilege change unexpectedly changed child",
	)
	expect(!vm.ThreadHasSecurityCapability(state.L, 122), "parent still privileged")
	vm.ReleaseValue(state.L, child_ref)

	registry := packages.Registry {
		vm_state = &state,
	}
	append(
		&registry.internal_modules,
		packages.Internal_Module {
			name = "security_internal_probe",
			source = "return 947",
			reference = -1,
		},
	)
	append(
		&registry.startup_modules,
		packages.Internal_Module {
			name = "security_startup_probe",
			source = "return 848",
			reference = -1,
		},
	)
	defer {
		for module in registry.internal_modules {
			if module.reference > 0 {vm.ReleaseValue(state.L, module.reference)}
		}
		for module in registry.startup_modules {
			if module.reference > 0 {vm.ReleaseValue(state.L, module.reference)}
		}
		delete(registry.internal_modules)
		delete(registry.startup_modules)
	}

	vm.PushLightUserdata(state.L, &registry)
	vm.PushFunction(state.L, "probeResolve", probe_resolve, 1)
	vm.SetGlobalFromStack(&state, "probeResolve")

	run_ok(
		&state,
		`assert(probeResolve("@internal/security_internal_probe") == 947)
assert(probeResolve("@startup/security_startup_probe") == 848)`,
		"trusted-embedded-modules",
		true,
	)

	run_ok(
		&state,
		`
local paths = {
	"@internal/security_internal_probe",
	"internal/security_internal_probe",
	"@startup/security_startup_probe",
	"startup/security_startup_probe",
	"./security_internal_probe",
}
for _, path in paths do
	local ok = pcall(probeResolve, path)
	assert(not ok, "untrusted access to restricted module: " .. path)
end
`,
		"untrusted-embedded-modules",
	)

	fmt.println("SECURITY_VM_CAPABILITIES_PASSED")
}
