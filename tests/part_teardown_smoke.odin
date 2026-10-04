package main

// Regression test for a use-after-free that only appeared at scale.
//
// The physics service keeps its Part back-pointers in `Part::part_index`, and
// clearing one during service teardown looked harmless while there were a few
// Parts in the world. It is not harmless: at shutdown the Luau collector frees
// the Instance tree and the service objects in an unspecified order, so
// `physics_destroy` can run after the Parts have already gone through
// `part_destroy` and `free(part)`. The store into the back-pointer is then a
// write into freed memory.
//
// It does not fault at low counts, because the allocator has not yet reused the
// block, so a small test would pass while the bug was live. That is why this
// builds thousands of Parts: enough of them that the freed blocks are handed
// out again before teardown finishes.
//
// Before the fix this crashed with an access violation at 2601 Parts and passed
// at 1. It is a pass/fail test because the failure is a hard fault rather than a
// timing, so there is no noise to be tolerant of.

import "core:fmt"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"

PART_COUNT :: 2601

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)

	source := fmt.tprintf(
		"for i = 1, %d do local p = Instance.new('Part', workspace) p.Anchored = true end",
		PART_COUNT,
	)
	ok, err := vm.Run(&script_vm, source, "build")
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("failed to build parts")
	}

	// Enough frames that the bodies exist and the collector has been asked to do
	// a full cycle at least once.
	for _ in 0..<5 {
		engine_runtime.Environment_Update_Step(&environment, &script_vm, 1.0 / 60.0)
	}

	// Closing the VM is what runs the collector, and so what triggers the
	// write-after-free. Reaching the line below is the assertion: a fault during
	// Environment_Destroy never returns.
	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)

	fmt.printfln("PART_TEARDOWN_PASSED (%d parts)", PART_COUNT)
}