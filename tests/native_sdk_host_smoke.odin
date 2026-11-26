package main

import classes "../src/engine/classes"
import extensions "../src/engine/extensions"
import engine_runtime "../src/engine/runtime"
import serializer "../src/engine/serializer"
import services "../src/engine/services"
import target "../src/engine/target"
import vm "../src/engine/vm"
import "core:fmt"

check :: proc(success: bool, detail: string) {
	if !success {panic(detail)}
}

execute :: proc(state: ^vm.VM, source, title: string) {
	ok, err := vm.RunInternal(state, source, title)
	if !ok {
		fmt.eprintln(err)
		panic(title)
	}
}

main :: proc() {
	target.set_mode(.Editor)
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm, nil, .Editor)

	record, err := extensions.Load_Directory(
		&environment.extensions,
		"build/native-plugins/native.example",
	)
	if err != "" {fmt.eprintln(err)}
	check(
		err == "" && record != nil && record.native_desc != nil,
		"native plugin did not attach to engine",
	)
	check(len(environment.datatypes.extension_codecs) == 1, "native datatype codec missing")

	execute(
		&script_vm,
		`
assert(NativePluginSum(4,7) == 11)
local counter = Instance.new("NativeCounter")
assert(counter.Value == 10)
assert(counter:Increment(7) == 17)
local service = game:GetService("NativeWeatherService")
assert(service.Temperature == 26)
service.Temperature = 22
assert(game:GetService("NativeWeatherService").Temperature == 22)
local info = NativeDamageInfo.new(7,true)
assert(info:Double() == 14)
local other = NativeDamageInfo.new(3,false)
assert((info + other).Amount == 10)
assert((-info).Amount == -7)
local f = Instance.new("Folder")
f.Name = "NativeSDKPersistence"
f:SetAttribute("CustomDamage", info)
f.Parent = workspace
nativeSaved = f
nativeInfo = info
nativeSavedConstructor = NativeDamageInfo.new
`,
		"native_sdk_engine",
	)

	workspace := services.Ensure_Service(&environment.services, "Workspace")
	object := classes.Find_First_Child(workspace, "NativeSDKPersistence")
	check(object != nil, "serialization fixture missing")

	bytes, save_err := serializer.Serialize(&environment.classes, script_vm.L, object)
	check(serializer.Error_Is_None(save_err), "native datatype serialization failed")
	restored, load_err := serializer.Deserialize(&environment.classes, script_vm.L, nil, bytes)
	check(
		serializer.Error_Is_None(load_err) && restored != nil,
		"native datatype deserialization failed",
	)
	classes.Push_Object(script_vm.L, restored)
	vm.SetGlobalFromStack(&script_vm, "nativeRestored")

	execute(
		&script_vm,
		`local x=nativeRestored:GetAttribute("CustomDamage"); assert(x.Amount==7 and x.Critical)`,
		"native_sdk_serialize_roundtrip",
	)

	vm.GetGlobal(script_vm.L, "nativeInfo")
	wire: [dynamic]u8
	check(
		services.replication_encode_value(script_vm.L, -1, &wire, 0),
		"native datatype replication encode failed",
	)
	vm.Pop(script_vm.L)

	reader := services.Replication_Reader {
		data  = wire[:],
		valid = true,
	}
	services.replication_decode_value(script_vm.L, &reader, &environment.datatypes, 0)
	check(reader.valid && reader.offset == len(wire), "native datatype replication decode failed")
	vm.SetGlobalFromStack(&script_vm, "nativeReplicated")
	execute(
		&script_vm,
		`assert(nativeReplicated.Amount == 7 and nativeReplicated.Critical)`,
		"native_sdk_replication_roundtrip",
	)

	old_version := environment.datatypes.extension_codecs[0].wire_version
	environment.datatypes.extension_codecs[0].wire_version += 1
	mismatch := services.Replication_Reader {
		data  = wire[:],
		valid = true,
	}
	services.replication_decode_value(script_vm.L, &mismatch, &environment.datatypes, 0)
	check(
		mismatch.valid && vm.IsNil(script_vm.L, -1),
		"native datatype codec mismatch not rejected",
	)
	vm.Pop(script_vm.L)
	environment.datatypes.extension_codecs[0].wire_version = old_version

	truncated := services.Replication_Reader {
		data  = wire[:len(wire) - 1],
		valid = true,
	}
	services.replication_decode_value(script_vm.L, &truncated, &environment.datatypes, 0)
	check(!truncated.valid, "truncated native datatype accepted")
	vm.Pop(script_vm.L)

	unload_error := extensions.Unload(&environment.extensions, "native.example")
	check(unload_error == "", "native plugin unload failed")
	check(len(environment.datatypes.extension_codecs) == 0, "native datatype codec leaked")
	execute(
		&script_vm,
		`assert(NativePluginSum == nil and NativeDamageInfo == nil and NativePluginStopped == true)
assert(nativeSavedConstructor(5,false)==nil)
assert(not pcall(function() return nativeInfo.Amount end))`,
		"native_sdk_unloaded",
	)

	delete(wire)
	delete(bytes)
	serializer.Error_Delete(&save_err)
	serializer.Error_Delete(&load_err)
	engine_runtime.Environment_Destroy(&environment)
	vm.Close(&script_vm)

	fmt.println("NATIVE_SDK_HOST_SMOKE_PASSED")
}
