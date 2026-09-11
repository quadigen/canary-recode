package classes

import "vendor:sdl3"
import datatypes "../datatypes"
import kineffi "../bindings"
import "core:math"
import vm "../vm"
import enums "../enum"

Camera_Class := Class_Info{
    name   = "Camera",
    parent = &Instance_Class,
}

Camera :: struct {
    using object: Object,

    CFrame: datatypes.CFrame,

    yaw:               f32,
    pitch:             f32,
    move_speed:        f32,
    mouse_sensitivity: f32,
    mouse_captured:    bool,
}

Camera_Init :: proc() -> Camera {
    return Camera{
        object = Object_Init(&Camera_Class),

        CFrame = datatypes.CFrame_New_XYZ(0, 4, 10),

        yaw               = 0,
        pitch             = 0,
        move_speed        = 10,
        mouse_sensitivity = 0.003,
        mouse_captured    = false,
    }
}

Camera_construct :: proc(renderer: ^Renderer_Object, data_Camera: rawptr) -> ^Object {
    corner := new(Camera)
    corner^ = Camera_Init()
    corner.name = "Camera"

    return &corner.object
}

Camera_Update_World_To_View :: proc(camera: ^Camera, renderer: ^Renderer_Object) {
    if camera == nil || renderer == nil { return }
    view := datatypes.CFrame_Inverse(camera.CFrame)
    renderer.WorldToView = [12]f32{
        view.x, view.y, view.z,
        view.r00, view.r01, view.r02,
        view.r10, view.r11, view.r12,
        view.r20, view.r21, view.r22,
    }
    renderer.HasWorldToView = true
    if renderer.Filament != nil {
        look := datatypes.CFrame_LookVector(camera.CFrame)
        up := datatypes.CFrame_UpVector(camera.CFrame)
        kineffi.Kine_Filament_SetCameraLookAt(renderer.Filament,
            camera.CFrame.x, camera.CFrame.y, camera.CFrame.z,
            camera.CFrame.x + look.x, camera.CFrame.y + look.y, camera.CFrame.z + look.z,
            up.x, up.y, up.z)
    }
}

Camera_Step :: proc(
    object: ^Object,
    ctx: ^Class_Step_Context,
) {
    camera := cast(^Camera)object

    if camera == nil || ctx == nil || ctx.renderer == nil || ctx.renderer.ActiveCamera != object {
        return
    }

    if ctx.renderer.Filament == nil {
        return
    }

    dt := ctx.delta_time

    mouse_dx, mouse_dy: f32
    mouse_buttons := sdl3.GetRelativeMouseState(&mouse_dx, &mouse_dy)

    focused := sdl3.GetKeyboardFocus() != nil
    rotating := focused && .RIGHT in mouse_buttons

    if rotating {
        if !camera.mouse_captured {
            window := sdl3.GetMouseFocus()

            if window != nil {
                if sdl3.SetWindowRelativeMouseMode(window, true) {
                    camera.mouse_captured = true
                }
            }

            mouse_dx = 0
            mouse_dy = 0
        }

        camera.yaw   -= mouse_dx * camera.mouse_sensitivity
        camera.pitch -= mouse_dy * camera.mouse_sensitivity

        max_pitch: f32 = 1.55334306 // 89 degrees

        if camera.pitch > max_pitch {
            camera.pitch = max_pitch
        }

        if camera.pitch < -max_pitch {
            camera.pitch = -max_pitch
        }
    } else if camera.mouse_captured {
        window := sdl3.GetMouseFocus()

        if window != nil {
            _ = sdl3.SetWindowRelativeMouseMode(window, false)
        }

        camera.mouse_captured = false
    }

    rotation := datatypes.CFrame_FromOrientation(
        camera.pitch,
        camera.yaw,
        0,
    )

    orientation := rotating ? rotation : camera.CFrame
    look  := datatypes.CFrame_LookVector(orientation)
    right := datatypes.CFrame_RightVector(orientation)

    keys := sdl3.GetKeyboardState(nil)

    movement := datatypes.Vector3{}

    if focused && keys[int(sdl3.Scancode.W)] {
        movement.x += look.x
        movement.y += look.y
        movement.z += look.z
    }

    if focused && keys[int(sdl3.Scancode.S)] {
        movement.x -= look.x
        movement.y -= look.y
        movement.z -= look.z
    }

    if focused && keys[int(sdl3.Scancode.D)] {
        movement.x += right.x
        movement.y += right.y
        movement.z += right.z
    }

    if focused && keys[int(sdl3.Scancode.A)] {
        movement.x -= right.x
        movement.y -= right.y
        movement.z -= right.z
    }

    if focused && keys[int(sdl3.Scancode.E)] {
        movement.y += 1
    }

    if focused && keys[int(sdl3.Scancode.Q)] {
        movement.y -= 1
    }

    length_squared :=
        movement.x * movement.x +
        movement.y * movement.y +
        movement.z * movement.z

    position := datatypes.CFrame_Position(camera.CFrame)

    if length_squared > 0 {
        length := math.sqrt(length_squared)
        scale := camera.move_speed * dt / length

        position.x += movement.x * scale
        position.y += movement.y * scale
        position.z += movement.z * scale
    }

    if rotating { camera.CFrame = rotation }
    camera.CFrame.x = position.x
    camera.CFrame.y = position.y
    camera.CFrame.z = position.z

    Camera_Update_World_To_View(camera, ctx.renderer)
}

Camera_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
    camera := cast(^Camera)object

    if camera.mouse_captured {
        window := sdl3.GetMouseFocus()

        if window != nil {
            _ = sdl3.SetWindowRelativeMouseMode(window, false)
        }
    }

    Object_Destroy(object)
    free(camera)
}

Camera_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^Camera)source
	dst := cast(^Camera)destination

	dst.CFrame = src.CFrame
	dst.yaw = src.yaw
	dst.pitch = src.pitch
	dst.move_speed = src.move_speed
	dst.mouse_sensitivity = src.mouse_sensitivity
	// mouse_captured intentionally not copied.
}

Register_Camera :: proc(registry: ^Registry) {
    Register_Class(
        registry,
        &Camera_Class,
        Camera_construct,
        Camera_destroy,
        get = Camera_Get,
        set = Camera_Set,
        clone = Camera_clone,
        _step = Camera_Step,
		_step_phase = .Render_3D,
    )
}

Camera_Get :: proc(L: ^vm.State, object: ^Object, types: ^datatypes.Registry, enums: ^enums.Registry, key: string) -> bool {
    if key != "CFrame" || types == nil { return false }
    camera := cast(^Camera)object
    datatypes.Push_CFrame(L, types, camera.CFrame)
    return true
}

Camera_Set :: proc(L: ^vm.State, object: ^Object, types: ^datatypes.Registry, enums: ^enums.Registry, key: string, index: int) -> bool {
    if key != "CFrame" || types == nil { return false }
    camera := cast(^Camera)object
    camera.CFrame = datatypes.Arg_CFrame(L, index, types)
    look := datatypes.CFrame_LookVector(camera.CFrame)
    camera.pitch = math.asin(clamp(look.y, -1, 1))
    camera.yaw = math.atan2(-look.x, -look.z)
    return true
}
