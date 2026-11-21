package main

import classes "../src/engine/classes"
import engine_runtime "../src/engine/runtime"
import serializer "../src/engine/serializer"
import vm "../src/engine/vm"
import "core:fmt"

check_error :: proc(err: serializer.Error, label: string) {
	if serializer.Error_Is_None(err) {return}
	serializer.Error_Print(err, label)
	panic(label)
}

main :: proc() {
	script_vm := vm.New()
	env: engine_runtime.Environment
	engine_runtime.Environment_Init(&env, &script_vm)

	ok, script_err := vm.Run(&script_vm, `
local root = Instance.new("Model")
root.Name = "LargeRepeatedWorld"
for i = 1, 750 do
    local node = Instance.new("Folder", root)
    node.Name = "IdenticalName"
    node:SetAttribute("Index", i)
    node:SetAttribute("SameAttribute", "same value")
end
KineStressRoot = root
`, "kine_scale")
	if !ok {
		fmt.eprintln(script_err)
		panic("could not create large repeated scene")
	}
	delete(script_err)
	vm.GetGlobal(script_vm.L, "KineStressRoot")
	root := cast(^classes.Object)vm.UserdataValue(script_vm.L, -1)
	vm.Pop(script_vm.L)
	assert(root != nil)

	current, err := serializer.Serialize(&env.classes, script_vm.L, root)
	check_error(err, "serialize v11")
	defer delete(current)
	previous, previous_err := serializer.Serialize(
		&env.classes, script_vm.L, root, format_version = serializer.KINE_TERRAIN_RAYMARCH_VERSION,
	)
	check_error(previous_err, "serialize v10")
	defer delete(previous)
	assert(current[4] == u8(serializer.KINE_VERSION))
	assert(previous[4] == u8(serializer.KINE_TERRAIN_RAYMARCH_VERSION))
	fmt.printf("v10: %d bytes; v11: %d bytes; reduction: %.1f%%\n",
		len(previous), len(current),
		100.0 * (1.0 - f64(len(current)) / f64(len(previous))))
	assert(len(current) < len(previous) * 9 / 10)
	current_packed, current_pack_err := serializer.Repack_File_Data(current, 3)
	check_error(current_pack_err, "compress v11")
	defer delete(current_packed)
	previous_packed, previous_pack_err := serializer.Repack_File_Data(previous, 3)
	check_error(previous_pack_err, "compress v10")
	defer delete(previous_packed)
	fmt.printf("zstd v10: %d bytes; v11: %d bytes\n", len(previous_packed), len(current_packed))

	versions := [2][]u8{current, previous}
	for data, variant in versions {
		loaded, load_err := serializer.Deserialize(&env.classes, script_vm.L, nil, data)
		check_error(load_err, "deserialize")
		assert(loaded != nil)
		vm.PushRegistryReference(script_vm.L, loaded.lua_ref)
		vm.SetGlobalFromStack(&script_vm, "LoadedRoot")
		valid, verify_err := vm.Run(&script_vm, `
assert(LoadedRoot.Name == "LargeRepeatedWorld")
local children = LoadedRoot:GetChildren()
assert(#children == 750)
for _, child in ipairs(children) do
    assert(child.ClassName == "Folder")
    assert(child.Name == "IdenticalName")
    assert(type(child:GetAttribute("Index")) == "number")
    assert(child:GetAttribute("SameAttribute") == "same value")
end
`, "kine_verify")
		if !valid {
			fmt.eprintln("variant:", variant, verify_err)
			panic("KINE failed round trip")
		}
		delete(verify_err)
	}

	// The first v11 tree symbol is the root class, directly after the
	// 5-byte header and the 4-byte empty asset count.
	assert(current[5] == 0 && current[6] == 0 &&
		current[7] == 0 && current[8] == 0)
	malformed := make([]u8, len(current))
	copy(malformed, current)
	malformed[9] = 1 // forward reference to symbol 0, not yet defined
	corrupt_root, corrupt_err := serializer.Deserialize(
		&env.classes, script_vm.L, nil, malformed,
	)
	assert(corrupt_root == nil)
	assert(corrupt_err.kind == .Malformed_Record)
	serializer.Error_Delete(&corrupt_err)
	delete(malformed)

	// The former total-stream ceiling was 512 MiB of assets + 64 MiB
	// of headroom. With assets near their limit, a 72 MiB tree would
	// exceed that ceiling. Verify the new 1 GiB budget and exercise the
	// compressed-data path with a payload larger than the old headroom.
	assert(serializer.KINE_MAX_STREAM_BYTES >= 1024 * 1024 * 1024)
	large := make([]u8, 72 * 1024 * 1024)
	packed, pack_err := serializer.Repack_File_Data(large, 3)
	check_error(pack_err, "compress 72MiB")
	assert(len(packed) < len(large))
	unpacked, unpack_err := serializer.Repack_File_Data(packed, 0)
	check_error(unpack_err, "decompress 72MiB")
	assert(len(unpacked) == len(large))
	assert(unpacked[0] == 0 && unpacked[len(unpacked)-1] == 0)
	delete(unpacked)
	delete(packed)
	delete(large)

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&env)
	fmt.println("KINE_FORMAT_SCALE_SMOKE_PASSED")
}
