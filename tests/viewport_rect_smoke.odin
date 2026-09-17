package main

import "core:fmt"
import kineffi "../src/engine/bindings"
import classes "../src/engine/classes"
import renderer "../src/engine/renderer"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import sdl3 "vendor:sdl3"

expect_pixel :: proc(surface: ^kineffi.KineSkiaSurface, x, y: i32, outside: bool) {
    r, g, b, a: u8
    kineffi.Kine_Skia_Surface_GetPixel(surface, x, y, &r, &g, &b, &a)
    is_base := r == 255 && g == 0 && b == 255 && a == 255
    assert(a == 255 && is_base == outside)
}

main :: proc() {
    // Instance names must outlive the Lua string storage they came from.
    object := classes.Object_Init()
    name := []u8{'S', 't', 'u', 'd', 'i', 'o'}
    classes.Set_Name(&object, string(name))
    name[0] = 'X'
    assert(object.name == "Studio")
    classes.Set_Name(&object, object.name)
    assert(object.name == "Studio")
    classes.Object_Destroy(&object)

    script_vm := vm.New()
    renderer_object: renderer.RendererObject
    environment: engine_runtime.Environment
    engine_runtime.Environment_Init(&environment, &script_vm, &renderer_object)
    defer {
        vm.Close(&script_vm)
        engine_runtime.Environment_Destroy(&environment)
    }
    ok, err := vm.RunInternal(&script_vm, `
local screen = Instance.new("ScreenGui", game.CoreGui)
screen.Name = "Studio"
local frame = Instance.new("Frame", game.CoreGui:FindFirstChild("Studio"))
frame.Position = UDim2.fromOffset(60, 30)
frame.Size = UDim2.new(0.5, 0, 0, 100)
frame.BackgroundTransparency = 1
layout_checks = 0
-- Absolute rects are resolved by Update_GUI_Layout after the "2d" pool
-- phase, so the "2da" phase observes them fresh (see viewport.luau).
renderer.Pool.new("2da", function()
    assert(frame.AbsolutePosition == Vector2.new(60, 30))
    assert(frame.AbsoluteSize == Vector2.new(renderer.Width * 0.5, 100))
    layout_checks += 1
end)
-- Configure once, before there is a native renderer, then retain across resize.
renderer:Set3DTexProps(60, 30, 160, 100)
assert(renderer.tex3d_rect.width == 160)
assert(not pcall(function() renderer:Set3DTexProps(0, 0, 0, -35) end))
`, "viewport_rect_smoke")
    if !ok { fmt.eprintln(err); delete(err); panic("viewport setup failed") }
    assert(renderer_object.HasViewportRect)

    assert(sdl3.Init({.VIDEO}))
    defer sdl3.Quit()
    window := sdl3.CreateWindow("Viewport regression", 320, 240,
        sdl3.WINDOW_VULKAN | sdl3.WINDOW_HIDDEN | sdl3.WINDOW_RESIZABLE)
    assert(window != nil)
    defer sdl3.DestroyWindow(window)
    filament := kineffi.Kine_Filament_CreateForVulkanCompositorWindow(window, 320, 240)
    assert(filament != nil)
    renderer_object.Filament = filament
    defer { renderer_object.Filament = nil; kineffi.Kine_Filament_Destroy(filament) }
    compositor := cast(^kineffi.KineVulkanCompositor)kineffi.Kine_Filament_GetVulkanCompositor(filament)

    sizes := [][2]i32{{320, 240}, {480, 360}, {320, 240}}
    for size in sizes {
        assert(sdl3.SetWindowSize(window, size[0], size[1]))
        sdl3.PumpEvents()
        width, height: i32
        assert(sdl3.GetWindowSizeInPixels(window, &width, &height))
        kineffi.Kine_Filament_Resize(filament, width, height)
        for _ in 0..<3 {
            surface := cast(^kineffi.KineSkiaSurface)kineffi.Kine_VulkanCompositor_BeginFrame(compositor)
            assert(surface != nil)
            kineffi.Kine_Skia_Surface_Clear(surface, 255, 0, 255, 255)
            engine_runtime.Environment_Render_2D(&environment, &script_vm, surface, width, height, 1.0/60.0)
            renderer.apply_viewport_rect(&renderer_object)
            kineffi.Kine_Filament_RenderFrame(filament, 1.0/60.0)
            overlay := cast(^kineffi.KineSkiaSurface)kineffi.Kine_VulkanCompositor_BeginOverlay(compositor)
            assert(overlay != nil)
            // Check all four edges in top-left UI coordinates, plus interior.
            expect_pixel(overlay, 59, 80, true)
            expect_pixel(overlay, 220, 80, true)
            expect_pixel(overlay, 120, 29, true)
            expect_pixel(overlay, 120, 130, true)
            expect_pixel(overlay, 120, 80, false)
            expect_pixel(overlay, width-1, height-1, true)
            assert(kineffi.Kine_VulkanCompositor_EndFrame(compositor) != 0)
        }
        fmt.printf("VIEWPORT_RECT_PASSED %dx%d\n", width, height)
    }
    ok, err = vm.RunInternal(&script_vm, "assert(layout_checks == 9)", "viewport_layout_checks")
    if !ok { fmt.eprintln(err); delete(err); panic("viewport layout callbacks failed") }
}
