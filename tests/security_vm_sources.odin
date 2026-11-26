package main

import classes "../src/engine/classes"
import vm "../src/engine/vm"
import "core:fmt"

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
		panic("source access regression")
	}
}

main :: proc() {
	state := vm.New()
	registry := classes.Registry_Init()
	classes.Register_Default_Classes(&registry)
	classes.Install_Instance_Library(&registry, &state)

	run_ok(
		&state,
		`
script_instances = {Instance.new("Script"), Instance.new("LocalScript"), Instance.new("ModuleScript")}
for _, instance in script_instances do
    assert(not pcall(function() return instance.Source end))
    assert(not pcall(function() instance.Source = "return 1" end))
end
`,
		"untrusted-script-source-access",
	)

	run_ok(
		&state,
		`
for _, instance in script_instances do
    instance.Source = "return 7"
    assert(instance.Source == "return 7")
end
`,
		"trusted-script-source-access",
		true,
	)

	run_ok(
		&state,
		`
for _, instance in script_instances do
    assert(not pcall(function() return instance.Source end))
    assert(not pcall(function() instance.Source = "return 9" end))
end
`,
		"untrusted-source-after-trusted",
	)

	vm.Close(&state)
	classes.Registry_Destroy(&registry)
	fmt.println("SECURITY_VM_SOURCES_PASSED")
}
