package main

import k "../src/engine/bindings"
import sdl "vendor:sdl3"
import "core:fmt"

main :: proc() {
    assert(sdl.Init({.VIDEO}))
    defer sdl.Quit()
    window := sdl.CreateWindow("Large world gizmo regression", 640, 480, sdl.WINDOW_VULKAN | sdl.WINDOW_HIDDEN)
    assert(window != nil)
    defer sdl.DestroyWindow(window)
    ctx := k.Kine_Filament_CreateForVulkanCompositorWindow(window, 640, 480)
    assert(ctx != nil)
    defer k.Kine_Filament_Destroy(ctx)
    compositor := cast(^k.KineVulkanCompositor)k.Kine_Filament_GetVulkanCompositor(ctx)
    assert(compositor != nil)
    gizmo := k.Kine_Filament_CreateGizmo(ctx, k.KINE_GIZMO_MOVE)
    assert(gizmo != nil)
    defer k.Kine_Filament_DestroyGizmo(ctx, gizmo)
    k.Kine_Filament_SetCameraPerspective(ctx, 60, 640.0/480.0, 0.1, 10000)
    k.Kine_Filament_SetViewport(ctx, 0, 0, 640, 480)
    reference_axis: i32
    reference_delta: f32
    reference_plane: [2]f32
    for origin, i in ([3]f64{0, 1000000000.125, -1000000000.125}) {
        k.Kine_Filament_SetCameraPose(ctx, origin, origin, origin+10, 0, 0, -1, 0, 1, 0)
        model := [16]f64{1,0,0,origin,0,1,0,origin,0,0,1,origin,0,0,0,1}
        axis := k.Kine_Filament_PickGizmo(ctx,gizmo,&model[0], 380,240)
        assert(axis != k.KINE_GIZMO_AXIS_NONE, "visible gizmo X handle must be pickable")
        delta := k.Kine_Filament_GetGizmoDragDelta(ctx,gizmo,&model[0],k.KINE_GIZMO_AXIS_X,320,240,360,240)
        plane: [2]f32
        assert(k.Kine_Filament_GetGizmoPlaneDragDelta(ctx,gizmo,&model[0],k.KINE_GIZMO_AXIS_XY,320,240,360,220,&plane[0],&plane[1]) != 0)
        if i==0 {reference_axis, reference_delta, reference_plane = axis, delta, plane}
        else {assert(axis==reference_axis); assert(abs(delta-reference_delta)<0.0001); assert(abs(plane.x-reference_plane.x)<0.0001 && abs(plane.y-reference_plane.y)<0.0001)}
        base := cast(^k.KineSkiaSurface)k.Kine_VulkanCompositor_BeginFrame(compositor)
        assert(base != nil)
        k.Kine_Skia_Surface_Clear(base, 0, 0, 0, 255)
        k.Kine_Filament_DrawGizmo(ctx,gizmo,&model[0],axis,0)
        k.Kine_Filament_RenderFrame(ctx, 1.0/60)
        assert(k.Kine_VulkanCompositor_BeginOverlay(compositor) != nil)
        assert(k.Kine_VulkanCompositor_EndFrame(compositor) != 0)
    }
    fmt.println("LARGE_WORLD_GIZMO_SMOKE_PASSED")
}
