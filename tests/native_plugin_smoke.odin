package main

import native_api "../src/engine/native_api"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

main :: proc() {
	state := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &state)
	defer {
		engine_runtime.Environment_Destroy(&environment)
		vm.Close(&state)
	}

	ctx := &environment.extensions.native_context
	assert(ctx.active && ctx.root == ctx)
	assert(ctx.script_vm == &state)
	assert(ctx.classes == &environment.classes)
	assert(ctx.services == &environment.services)
	assert(!native_api.Kinemium_ContextIsBorrowed(ctx))

	plugin: u64
	if !native_api.Kinemium_PluginLoad(
		ctx,
		cstring("build/native-plugins/native.example"),
		&plugin,
	) {
		fmt.eprintln(ctx.last_error)
		panic("native plugin failed to load into existing engine")
	}
	assert(plugin != 0)

	assert(
		native_api.Kinemium_RunLuau(
			ctx,
			cstring(
				"assert(NativePluginSum(4,5)==9); local d=NativeDamageInfo.new(20,true); assert(d:Double()==40)",
			),
		),
	)
	assert(
		native_api.Kinemium_RunLuau(
			ctx,
			cstring("local c=Instance.new('NativeCounter'); assert(c:Increment(2)==12)"),
		),
	)

	for _ in 0 ..< 5 {
		engine_runtime.Environment_Update_Step(&environment, &state, f32(1.0 / 60.0))
	}

	assert(native_api.Kinemium_PluginUnload(ctx, plugin))
	assert(
		native_api.Kinemium_RunLuau(
			ctx,
			cstring(
				"assert(NativePluginSum==nil and NativeDamageInfo==nil and NativeCounter==nil)",
			),
		),
	)
	fmt.println("PASS engine-hosted plugin uses the existing VM and registry")
}
