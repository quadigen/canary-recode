package main

import k "../src/engine/bindings"
import classes "../src/engine/classes"
import renderer "../src/engine/renderer"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import sdl "vendor:sdl3"
import "core:fmt"
import "core:time"

WIDTH :: 96
HEIGHT :: 64

RED_SHADER :: `material {
    name : "ChainRed",
    shadingModel : unlit,
    requires : [uv0],
    depthWrite : false,
    depthCulling : false,
    culling : none,
    parameters : [{type : sampler2d, name : inputTexture}]
}
fragment {
    void material(inout MaterialInputs material) {
        prepareMaterial(material);
        material.baseColor = vec4(1.0, 0.0, 0.0, 1.0);
    }
}`

SWAP_RG_SHADER :: `material {
    name : "ChainSwapRG",
    shadingModel : unlit,
    requires : [uv0],
    depthWrite : false,
    depthCulling : false,
    culling : none,
    parameters : [{type : sampler2d, name : inputTexture}]
}
fragment {
    void material(inout MaterialInputs material) {
        prepareMaterial(material);
        vec3 color = texture(materialParams_inputTexture, getUV0()).rgb;
        material.baseColor = vec4(color.g, color.r, color.b, 1.0);
    }
}`

SWAP_GB_SHADER :: `material {
    name : "ChainSwapGB",
    shadingModel : unlit,
    requires : [uv0],
    depthWrite : false,
    depthCulling : false,
    culling : none,
    parameters : [{type : sampler2d, name : inputTexture}]
}
fragment {
    void material(inout MaterialInputs material) {
        prepareMaterial(material);
        vec3 color = texture(materialParams_inputTexture, getUV0()).rgb;
        material.baseColor = vec4(color.r, color.b, color.g, 1.0);
    }
}`

assert_chain :: proc(ctx: ^k.KineFilamentContext, shaders: []^k.KineFilamentShader) {
    if len(shaders) == 0 {
        assert(k.Kine_Filament_SetPostProcessChain(ctx, nil, 0))
        return
    }
    assert(k.Kine_Filament_SetPostProcessChain(ctx, &shaders[0], i32(len(shaders))), string(k.Kine_Filament_Shader_GetLastError()))
}

capture :: proc(ctx: ^k.KineFilamentContext, expected_passes: u32) -> [4]u8 {
    pixels: [WIDTH * HEIGHT * 4]u8
    offset :: ((HEIGHT / 2) * WIDTH + WIDTH / 2) * 4
    rendered := 0
    for frame in 0 ..< 150 {
        k.Kine_Filament_RenderFrame(ctx, 1.0 / 60.0)
        stats: k.KineFilamentPassStats
        k.Kine_Filament_GetPassStats(ctx, &stats)
        if stats.world > 0 {
            assert(stats.customPost == expected_passes, "Incorrect GPU post-process pass count")
            rendered += 1
        }
        for &pixel in pixels {pixel = 0}
        _ = k.Kine_Filament_ReadPixels(ctx, &pixels[0])
        if rendered >= 3 && pixels[offset + 3] != 0 {
            result: [4]u8
            copy(result[:], pixels[offset:offset + 4])
            return result
        }
        if frame % 20 == 0 {
            fmt.println("Headless frame", frame, "rendered", rendered, "post passes", stats.customPost)
        }
        time.sleep(5 * time.Millisecond)
    }
    panic("No offscreen pixels returned; enable KINE_FILAMENT_VULKAN_READBACK in the native build")
}

run_luau :: proc(state: ^vm.VM, source: string) {
    ok, err := vm.Run(state, source, "postprocess_chain_headless_smoke")
    assert(ok, err)
}

prepare_luau_chain :: proc(env: ^engine_runtime.Environment, state: ^vm.VM, expected: int) {
    ready := 0
    for _ in 0 ..< 5000 {
        classes.Step(&env.classes, state.L, 0, phase = .Render_3D)
        ready = 0
        for object in classes.Find_Class(&env.classes, "PostProcess").instances {
            if object == nil || object.destroyed || object.parent == nil {continue}
            if (cast(^classes.PostProcess)object).filament_shader != nil {ready += 1}
        }
        if ready >= expected {return}
        time.sleep(time.Millisecond)
    }
    panic("PostProcess instances did not compile before the headless GPU test")
}

expect_dominant :: proc(color: [4]u8, dominant: int, label: string) {
    for channel in 0 ..< 3 {
        if channel != dominant {
            assert(i32(color[dominant]) > i32(color[channel]) + 60, label)
        }
    }
    fmt.println(label, color)
}

main :: proc() {
    ctx := k.Kine_Filament_Create(WIDTH, HEIGHT)
    assert(ctx != nil, "Could not create an offscreen Filament renderer")
    defer k.Kine_Filament_Destroy(ctx)

    _ = sdl.GetVersion()
    renderer_object := renderer.RendererObject{Filament = ctx}
    script_vm := vm.New()
    env: engine_runtime.Environment
    engine_runtime.Environment_Init(&env, &script_vm, &renderer_object)
    defer {vm.Close(&script_vm); engine_runtime.Environment_Destroy(&env)}

    red := k.Kine_Filament_Shader_Create(ctx, RED_SHADER)
    assert(red != nil, string(k.Kine_Filament_Shader_GetLastError()))
    defer k.Kine_Filament_Shader_Destroy(red)

    swap_rg := k.Kine_Filament_Shader_Create(ctx, SWAP_RG_SHADER)
    assert(swap_rg != nil, string(k.Kine_Filament_Shader_GetLastError()))
    defer k.Kine_Filament_Shader_Destroy(swap_rg)

    swap_gb := k.Kine_Filament_Shader_Create(ctx, SWAP_GB_SHADER)
    assert(swap_gb != nil, string(k.Kine_Filament_Shader_GetLastError()))
    defer k.Kine_Filament_Shader_Destroy(swap_gb)

    defer _ = k.Kine_Filament_SetPostProcessChain(ctx, nil, 0)

    assert_chain(ctx, {red})
    expect_dominant(capture(ctx, 1), 0, "One pass: red")

    assert_chain(ctx, {red, swap_rg})
    expect_dominant(capture(ctx, 2), 1, "Two passes: green")

    assert_chain(ctx, {red, swap_rg, swap_gb})
    expect_dominant(capture(ctx, 3), 2, "Three passes: blue")

    assert_chain(ctx, {red, swap_gb, swap_rg})
    expect_dominant(capture(ctx, 3), 1, "Reordered passes: green")

    assert_chain(ctx, {red})
    expect_dominant(capture(ctx, 1), 0, "Removed passes: red")

    assert_chain(ctx, {})
    vm.PushString(script_vm.L, RED_SHADER)
    vm.SetGlobalFromStack(&script_vm, "redSource")
    vm.PushString(script_vm.L, SWAP_RG_SHADER)
    vm.SetGlobalFromStack(&script_vm, "swapRgSource")
    vm.PushString(script_vm.L, SWAP_GB_SHADER)
    vm.SetGlobalFromStack(&script_vm, "swapGbSource")
    run_luau(&script_vm, `
first = Instance.new("PostProcess", workspace)
first.Priority = 0
first.Source = redSource
second = Instance.new("PostProcess", workspace)
second.Priority = 10
second.Source = swapRgSource
third = Instance.new("PostProcess", workspace)
third.Priority = 20
third.Source = swapGbSource
`)
    prepare_luau_chain(&env, &script_vm, 3)
    expect_dominant(capture(ctx, 3), 2, "Luau instances: blue")

    run_luau(&script_vm, "third.Priority = 5")
    classes.Step(&env.classes, script_vm.L, 0, phase = .Render_3D)
    expect_dominant(capture(ctx, 3), 1, "Luau reordered instances: green")

    run_luau(&script_vm, "second.Enabled = false")
    classes.Step(&env.classes, script_vm.L, 0, phase = .Render_3D)
    expect_dominant(capture(ctx, 2), 0, "Luau disabled pass: red")

    run_luau(&script_vm, "first:Destroy(); second:Destroy(); third:Destroy()")
    classes.Step(&env.classes, script_vm.L, 0, phase = .Render_3D)

    fmt.println("POSTPROCESS_CHAIN_HEADLESS_PASSED")
}
