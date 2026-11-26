package main

import classes "../src/engine/classes"
import vm "../src/engine/vm"
import "core:fmt"
import "core:time"

reference :: proc(L: ^vm.State, object: ^classes.Object) -> bool {
	if object == nil {return false}
	for current := object; current != nil; current = current.parent {
		if !vm.ThreadMeetsSecurityRequirement(L, current.security_requirement) {return false}
	}
	return true
}

main :: proc() {
	v := vm.New()
	defer vm.Close(&v)
	nodes: [32]classes.Object
	for i in 1 ..< len(nodes) {nodes[i].parent = &nodes[i - 1]}
	low := vm.SecurityRequirementFromValue(3)
	high := vm.SecurityRequirementFromValue(119)
	both := vm.ThreadSecurityAddCapability(low.capabilities, 119)
	caps := [?]vm.Thread_Security_Capabilities {
		vm.THREAD_SECURITY_NONE,
		low.capabilities,
		high.capabilities,
		both,
		vm.THREAD_SECURITY_ALL,
	}
	for capability in caps {
		vm.SetThreadSecurityCapabilities(v.L, capability)
		for i in 0 ..< len(nodes) {
			nodes[i].security_requirement = low
			for j in 0 ..< len(nodes) {
				if i == j {continue}
				nodes[j].security_requirement = high
				for k in 0 ..< len(nodes) {
					assert(
						classes.Object_Is_Accessible(v.L, &nodes[k]) == reference(v.L, &nodes[k]),
					)
					assert(
						classes.Object_Is_Accessible(nil, &nodes[k]) == reference(nil, &nodes[k]),
					)
				}
				nodes[j].security_requirement = {}
			}
			nodes[i].security_requirement = {}
		}
	}
	assert(!classes.Object_Is_Accessible(v.L, nil))
	vm.SetThreadSecurityCapabilities(v.L, both)
	child := vm.NewThread(v.L)
	ref := vm.RetainValue(v.L)
	vm.Pop(v.L)
	defer vm.ReleaseValue(v.L, ref)
	nodes[0].security_requirement = high
	assert(classes.Object_Is_Accessible(child, &nodes[31]))
	vm.SetThreadSecurityCapabilities(v.L, vm.THREAD_SECURITY_NONE)
	assert(!classes.Object_Is_Accessible(v.L, &nodes[31]))
	assert(classes.Object_Is_Accessible(child, &nodes[31]))
	nodes[16].parent = nil
	assert(classes.Object_Is_Accessible(v.L, &nodes[31]))
	nodes[16].parent = &nodes[15]
	assert(!classes.Object_Is_Accessible(v.L, &nodes[31]))
	nodes[0].security_requirement = {}
	vm.SetThreadSecurityCapabilities(v.L, both)
	modes := [?]bool{false, true}
	for restricted in modes {
		if restricted {
			nodes[0].security_requirement = low
			nodes[15].security_requirement = high
		}
		for r in 0 ..< 5 {
			start := time.tick_now()
			count := 0
			for i in 0 ..< 1000000 {
				if classes.Object_Is_Accessible(v.L, &nodes[16 + i % 16]) {count += 1}
			}
			ms := time.duration_milliseconds(time.tick_since(start))
			assert(count == 1000000)
			fmt.printfln("ACCESS_BENCH_MS %v %d %.3f", restricted, r, ms)
		}
	}
	fmt.println("INSTANCE_ACCESS_PERF_SMOKE_PASSED")
}
