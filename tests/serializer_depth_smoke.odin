package main

import classes "../src/engine/classes"
import engine_runtime "../src/engine/runtime"
import serializer "../src/engine/serializer"
import vm "../src/engine/vm"
import "core:fmt"
import "core:strings"

make_tree :: proc(environment: ^engine_runtime.Environment, state: ^vm.VM, depth: int) -> ^classes.Object {
    root: ^classes.Object
    parent: ^classes.Object
    for index in 0 ..< depth {
        object, ok := classes.Push_New(&environment.classes, state, "Folder")
        assert(ok && object != nil)
        vm.Pop(state.L)
        if parent != nil {classes.Set_Parent(object, parent)}
        if index == 0 {root = object}
        parent = object
    }
    return root
}

check_depth :: proc(environment: ^engine_runtime.Environment, state: ^vm.VM, depth: int, allowed: bool) {
    root := make_tree(environment, state, depth)
    data, encode_error := serializer.Serialize(&environment.classes, state.L, root)
    assert(serializer.Error_Is_None(encode_error), "could not construct deep KINE test stream")
    serializer.Error_Delete(&encode_error)
    assert(len(data) > 0)
    defer delete(data)

    before := vm.StackTop(state.L)
    loaded, decode_error := serializer.Deserialize(&environment.classes, state.L, nil, data)
    assert(vm.StackTop(state.L) == before, "deserialization leaked VM stack entries")
    if allowed {
        assert(serializer.Error_Is_None(decode_error), "in-range instance hierarchy failed to load")
        assert(loaded != nil)
        classes.Destroy_Hierarchy(loaded)
    } else {
        assert(loaded == nil, "over-depth instance hierarchy was accepted")
        assert(decode_error.kind == .Malformed_Record, "over-depth hierarchy failed without a format error")
        message := serializer.Error_String(decode_error)
        assert(strings.contains(message, "maximum depth of 256"), "depth error has no actionable message")
        delete(message)
    }
    serializer.Error_Delete(&decode_error)
    classes.Destroy_Hierarchy(root)
}

main :: proc() {
    state := vm.New()
    environment: engine_runtime.Environment
    engine_runtime.Environment_Init(&environment, &state)
    defer {engine_runtime.Environment_Destroy(&environment); vm.Close(&state)}

    check_depth(&environment, &state, 1, true)
    check_depth(&environment, &state, serializer.KINE_MAX_INSTANCE_DEPTH, true)
    check_depth(&environment, &state, serializer.KINE_MAX_INSTANCE_DEPTH + 1, false)

    fmt.println("SERIALIZER_DEPTH_SMOKE_PASSED")
}
