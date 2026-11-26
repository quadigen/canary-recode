package main

import classes "../src/engine/classes"
import native_api "../src/engine/native_api"
import engine_runtime "../src/engine/runtime"
import serializer "../src/engine/serializer"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"

run :: proc(state: ^vm.VM, source, name: string) {
	ok, err := vm.RunInternal(state, source, name)
	if !ok {
		fmt.eprintln(err)
		panic(name)
	}
}

main :: proc() {
	state := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &state)
	defer {
		engine_runtime.Environment_Destroy(&environment)
		vm.Close(&state)
	}

	ctx := &environment.extensions.native_context
	plugin: u64
	assert(
		native_api.Kinemium_PluginLoad(
			ctx,
			cstring("build/native-plugins/native.example"),
			&plugin,
		),
	)
	assert(plugin != 0)

	run(
		&state,
		"local saved = Instance.new(\"Folder\"); " +
		"saved.Name = \"NativeSDKPersistence\"; " +
		"saved:SetAttribute(\"CustomDamage\", NativeDamageInfo.new(17.5, true)); " +
		"saved.Parent = workspace; " +
		"nativeDamage = NativeDamageInfo.new(23.5, false)",
		"native_datatype_seed",
	)

	workspace := services.Ensure_Service(&environment.services, "Workspace")
	saved := classes.Find_First_Child(workspace, "NativeSDKPersistence")
	assert(saved != nil)
	bytes, save_error := serializer.Serialize(&environment.classes, state.L, saved)
	defer delete(bytes)
	serializer.Error_Print(save_error, "Native SDK save: ")
	assert(serializer.Error_Is_None(save_error))
	defer serializer.Error_Delete(&save_error)

	loaded, load_error := serializer.Deserialize(&environment.classes, state.L, nil, bytes)
	serializer.Error_Print(load_error, "Native SDK load: ")
	assert(serializer.Error_Is_None(load_error))
	defer serializer.Error_Delete(&load_error)
	classes.Push_Object(state.L, loaded)
	vm.SetGlobalFromStack(&state, "nativeLoaded")

	run(
		&state,
		"local d = nativeLoaded:GetAttribute(\"CustomDamage\"); " +
		"assert(typeof(d) == \"NativeDamageInfo\"); " +
		"assert(d.Amount == 17.5 and d.Critical == true)",
		"native_datatype_persistence",
	)

	vm.GetGlobal(state.L, "nativeDamage")
	wire: [dynamic]u8
	assert(services.replication_encode_value(state.L, -1, &wire, 0))
	vm.Pop(state.L)
	reader := services.Replication_Reader {
		data  = wire[:],
		valid = true,
	}
	services.replication_decode_value(state.L, &reader, &environment.datatypes, 0)
	assert(reader.valid && reader.offset == len(wire))
	vm.SetGlobalFromStack(&state, "nativeReplicated")

	run(
		&state,
		"assert(typeof(nativeReplicated) == \"NativeDamageInfo\"); " +
		"assert(nativeReplicated.Amount == 23.5 and not nativeReplicated.Critical)",
		"native_datatype_replication",
	)

	codec_version := environment.datatypes.extension_codecs[0].wire_version
	environment.datatypes.extension_codecs[0].wire_version += 1
	missing, missing_error := serializer.Deserialize(&environment.classes, state.L, nil, bytes)
	assert(serializer.Error_Is_None(missing_error) && missing != nil)
	classes.Push_Object(state.L, missing)
	vm.SetGlobalFromStack(&state, "nativeMissing")
	run(
		&state,
		"assert(nativeMissing:GetAttribute(\"CustomDamage\") == nil)",
		"native_datatype_missing_codec",
	)
	environment.datatypes.extension_codecs[0].wire_version = codec_version
	serializer.Error_Delete(&missing_error)

	delete(wire)
	assert(native_api.Kinemium_PluginUnload(ctx, plugin))
	run(&state, "assert(NativeDamageInfo == nil)", "native_datatype_unload")
	fmt.println("PASS unified SDK native datatype persistence and replication")
}
