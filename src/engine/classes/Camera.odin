package classes

import sdl3 "../platform"

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
	Focus:  datatypes.CFrame,

	CameraSubject: ^Object,
	CameraType:    enums.CameraType,

	yaw:   f32,
	pitch: f32,

	move_speed:        f32,
	mouse_sensitivity: f32,
	mouse_captured:    bool,

	scroll_step:    f32,
	pending_scroll: f32,

	orbit_distance: f32,
}

Camera_Init :: proc() -> Camera {
	cframe := datatypes.CFrame_New_XYZ(0, 4, 10)

	return Camera{
		object = Object_Init(&Camera_Class),

		CFrame = cframe,
		Focus  = datatypes.CFrame_New_XYZ(0, 4, 0),

		CameraSubject = nil,
		CameraType    = .Custom,

		yaw   = 0,
		pitch = 0,

		move_speed        = 10,
		mouse_sensitivity = 0.003,
		mouse_captured    = false,

		scroll_step    = 5,
		pending_scroll = 0,

		orbit_distance = 12,
	}
}

Camera_construct :: proc(
	renderer: ^Renderer_Object,
	data_Camera: rawptr,
) -> ^Object {
	camera := new(Camera)
	camera^ = Camera_Init()
	camera.name = "Camera"

	return &camera.object
}

Camera_Sync_Angles_From_CFrame :: proc(camera: ^Camera) {
	if camera == nil {
		return
	}

	look := datatypes.CFrame_LookVector(camera.CFrame)

	camera.pitch = math.asin(clamp(look.y, -1, 1))
	camera.yaw   = math.atan2(-look.x, -look.z)
}

Camera_Release_Mouse :: proc(camera: ^Camera) {
	if camera == nil || !camera.mouse_captured {
		return
	}

	window := sdl3.GetMouseFocus()
	if window != nil {
		_ = sdl3.SetWindowRelativeMouseMode(window, false)
	}

	camera.mouse_captured = false
}

Camera_Update_Mouse_Look :: proc(
	camera: ^Camera,
	focused: bool,
) -> bool {
	mouse_dx, mouse_dy: f32
	mouse_buttons := sdl3.GetRelativeMouseState(
		&mouse_dx,
		&mouse_dy,
	)

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

		camera.pitch = clamp(
			camera.pitch,
			-max_pitch,
			max_pitch,
		)
	} else {
		Camera_Release_Mouse(camera)
	}

	return rotating
}

// Called by the SDL event path.
// Positive = wheel forward/up.
// Negative = wheel backward/down.
Camera_Add_Scroll :: proc(
	camera: ^Camera,
	steps: f32,
) {
	if camera == nil {
		return
	}

	camera.pending_scroll += steps
}

Camera_Find_Subject_Part :: proc(
	object: ^Object,
) -> ^Part {
	if object == nil || object.destroyed {
		return nil
	}

	if Is_A(object, "Part") {
		return cast(^Part)object
	}

	for child in object.children {
		part := Camera_Find_Subject_Part(child)

		if part != nil {
			return part
		}
	}

	return nil
}

Camera_Get_Subject_Position :: proc(
	camera: ^Camera,
) -> (
	position: datatypes.Vector3,
	ok: bool,
) {
	if camera == nil ||
	   camera.CameraSubject == nil ||
	   camera.CameraSubject.destroyed {
		return datatypes.Vector3{}, false
	}

	part := Camera_Find_Subject_Part(camera.CameraSubject)

	if part == nil {
		return datatypes.Vector3{}, false
	}

	return datatypes.CFrame_Position(part.cframe), true
}

Camera_Update_Focus :: proc(
	camera: ^Camera,
	position: datatypes.Vector3,
) {
	camera.Focus = datatypes.CFrame_New_Position(position)
}

Camera_Set_Position :: proc(
	camera: ^Camera,
	position: datatypes.Vector3,
) {
	camera.CFrame.x = position.x
	camera.CFrame.y = position.y
	camera.CFrame.z = position.z
}

Camera_Freecam_Step :: proc(
	camera: ^Camera,
	dt: f32,
	focused: bool,
	rotating: bool,
) {
	rotation := datatypes.CFrame_FromOrientation(
		camera.pitch,
		camera.yaw,
		0,
	)

	orientation := camera.CFrame

	if rotating {
		orientation = rotation
	}

	look  := datatypes.CFrame_LookVector(orientation)
	right := datatypes.CFrame_RightVector(orientation)
	up    := datatypes.CFrame_UpVector(orientation)

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
		movement.x += up.x
		movement.y += up.y
		movement.z += up.z
	}

	if focused && keys[int(sdl3.Scancode.Q)] {
		movement.x -= up.x
		movement.y -= up.y
		movement.z -= up.z
	}

	if focused && keys[int(sdl3.Scancode.LSHIFT)] || keys[int(sdl3.Scancode.RSHIFT)] {
		camera.move_speed = 5 
	} else {
		camera.move_speed = 10
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

	if rotating == true && camera.pending_scroll != 0 {
		scroll_look := datatypes.CFrame_LookVector(orientation)
		distance := camera.pending_scroll * camera.scroll_step

		position.x += scroll_look.x * distance
		position.y += scroll_look.y * distance
		position.z += scroll_look.z * distance
	}

	camera.pending_scroll = 0
	
	if rotating {
		camera.CFrame = rotation
	}

	Camera_Set_Position(camera, position)

	look = datatypes.CFrame_LookVector(camera.CFrame)

	focus_position := datatypes.Vector3{
		position.x + look.x * 10,
		position.y + look.y * 10,
		position.z + look.z * 10,
	}

	Camera_Update_Focus(camera, focus_position)
}

Camera_Consume_Orbit_Scroll :: proc(camera: ^Camera) {
	if camera.pending_scroll == 0 {
		return
	}

	camera.orbit_distance -=
		camera.pending_scroll * camera.scroll_step

	camera.orbit_distance = clamp(
		camera.orbit_distance,
		1.0,
		512.0,
	)

	camera.pending_scroll = 0
}

Camera_Subject_Orbit_Step :: proc(
	camera: ^Camera,
	target: datatypes.Vector3,
	camera_type: enums.CameraType,
) {
	Camera_Consume_Orbit_Scroll(camera)

	rotation := datatypes.CFrame_FromOrientation(
		camera.pitch,
		camera.yaw,
		0,
	)

	look  := datatypes.CFrame_LookVector(rotation)
	right := datatypes.CFrame_RightVector(rotation)
	up    := datatypes.CFrame_UpVector(rotation)

	position := target

	#partial switch camera_type {
	case .FirstPerson:
		position.y += 2

		camera.CFrame = rotation
		Camera_Set_Position(camera, position)

	case .TopDown:
		position.y += camera.orbit_distance

		camera.CFrame = datatypes.CFrame_LookAt(
			position,
			target,
		)

	case .Isometric:
		horizontal :=
			camera.orbit_distance * 0.70710678

		position.x += math.sin(camera.yaw) * horizontal
		position.z += math.cos(camera.yaw) * horizontal
		position.y += horizontal

		camera.CFrame = datatypes.CFrame_LookAt(
			position,
			target,
		)

	case .Shoulder:
		position.x -= look.x * camera.orbit_distance
		position.y -= look.y * camera.orbit_distance
		position.z -= look.z * camera.orbit_distance

		position.x += right.x * 2
		position.y += right.y * 2
		position.z += right.z * 2

		position.x += up.x * 1.5
		position.y += up.y * 1.5
		position.z += up.z * 1.5

		camera.CFrame = datatypes.CFrame_LookAt(
			position,
			target,
		)

	case .Custom,
	     .Orbital,
	     .ThirdPerson,
	     .Follow:
		position.x -= look.x * camera.orbit_distance
		position.y -= look.y * camera.orbit_distance
		position.z -= look.z * camera.orbit_distance

		camera.CFrame = datatypes.CFrame_LookAt(
			position,
			target,
		)
	}

	Camera_Update_Focus(camera, target)
	Camera_Sync_Angles_From_CFrame(camera)
}

Camera_Update_World_To_View :: proc(
	camera: ^Camera,
	renderer: ^Renderer_Object,
) {
	if camera == nil || renderer == nil {
		return
	}

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
		up   := datatypes.CFrame_UpVector(camera.CFrame)

		kineffi.Kine_Filament_SetCameraLookAt(
			renderer.Filament,

			camera.CFrame.x,
			camera.CFrame.y,
			camera.CFrame.z,

			camera.CFrame.x + look.x,
			camera.CFrame.y + look.y,
			camera.CFrame.z + look.z,

			up.x,
			up.y,
			up.z,
		)
	}
}

Camera_Step :: proc(
	object: ^Object,
	ctx: ^Class_Step_Context,
) {
	camera := cast(^Camera)object

	if camera == nil ||
	   ctx == nil ||
	   ctx.renderer == nil ||
	   ctx.renderer.ActiveCamera != object {
		return
	}

	if ctx.renderer.Filament == nil {
		return
	}

	// Scriptable means Kinemium does not alter the camera at all.
	// Luau owns CFrame and Focus.
	if camera.CameraType == .Scriptable {
		Camera_Release_Mouse(camera)
		camera.pending_scroll = 0

		Camera_Update_World_To_View(
			camera,
			ctx.renderer,
		)

		return
	}

	focused := sdl3.GetKeyboardFocus() != nil

	rotating := Camera_Update_Mouse_Look(
		camera,
		focused,
	)

	subject_position, has_subject :=
		Camera_Get_Subject_Position(camera)

	// Custom without a subject remains the editor/freecam mode.
	if camera.CameraType == .Custom && !has_subject {
		Camera_Freecam_Step(
			camera,
			ctx.delta_time,
			focused,
			rotating,
		)

		Camera_Update_World_To_View(
			camera,
			ctx.renderer,
		)

		return
	}

	// Subject camera modes need a valid subject.
	// If none exists, fall back to normal freecam instead of freezing.
	if !has_subject {
		Camera_Freecam_Step(
			camera,
			ctx.delta_time,
			focused,
			rotating,
		)

		Camera_Update_World_To_View(
			camera,
			ctx.renderer,
		)

		return
	}

	Camera_Subject_Orbit_Step(
		camera,
		subject_position,
		camera.CameraType,
	)

	Camera_Update_World_To_View(
		camera,
		ctx.renderer,
	)
}

Camera_destroy :: proc(
	object: ^Object,
	renderer: ^Renderer_Object,
) {
	camera := cast(^Camera)object

	Camera_Release_Mouse(camera)

	camera.CameraSubject = nil

	Object_Destroy(object)
	free(camera)
}

Camera_clone :: proc(
	source: ^Object,
	destination: ^Object,
) {
	src := cast(^Camera)source
	dst := cast(^Camera)destination

	dst.CFrame = src.CFrame
	dst.Focus  = src.Focus

	dst.CameraSubject = src.CameraSubject
	dst.CameraType    = src.CameraType

	dst.yaw   = src.yaw
	dst.pitch = src.pitch

	dst.move_speed        = src.move_speed
	dst.mouse_sensitivity = src.mouse_sensitivity

	dst.scroll_step    = src.scroll_step
	dst.pending_scroll = 0

	dst.orbit_distance = src.orbit_distance

	// Never clone active OS mouse capture.
	dst.mouse_captured = false
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

		properties = []string{
			"CFrame",
			"Focus",
			"CameraSubject",
			"CameraType",
			"Pitch",
			"Yaw",
		},
	)
}

Camera_Get :: proc(
	L: ^vm.State,
	object: ^Object,
	types: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	camera := cast(^Camera)object

	switch key {
	case "CFrame":
		if types == nil {
			return false
		}

		datatypes.Push_CFrame(
			L,
			types,
			camera.CFrame,
		)

	case "Focus":
		if types == nil {
			return false
		}

		datatypes.Push_CFrame(
			L,
			types,
			camera.Focus,
		)

	case "CameraSubject":
		Push_Object(
			L,
			camera.CameraSubject,
		)

	case "CameraType":
		if enum_registry == nil {
			return false
		}

		_ = enums.Push_Item_By_Value(
			L,
			enum_registry,
			"CameraType",
			i64(camera.CameraType),
		)

	case "Pitch":
		vm.PushNumber(
			L,
			f64(camera.pitch),
		)

	case "Yaw":
		vm.PushNumber(
			L,
			f64(camera.yaw),
		)

	case:
		return false
	}

	return true
}

Camera_Set :: proc(
	L: ^vm.State,
	object: ^Object,
	types: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	index: int,
) -> bool {
	camera := cast(^Camera)object

	switch key {
	case "CFrame":
		if types == nil {
			return false
		}

		camera.CFrame = datatypes.Arg_CFrame(
			L,
			index,
			types,
		)

		Camera_Sync_Angles_From_CFrame(camera)

	case "Focus":
		if types == nil {
			return false
		}

		camera.Focus = datatypes.Arg_CFrame(
			L,
			index,
			types,
		)

	case "CameraSubject":
		if vm.IsNil(L, index) {
			camera.CameraSubject = nil
			return true
		}

		subject := object_from_argument(
			L,
			index,
		)

		if subject == nil {
			_ = vm.RaiseError(
				L,
				"CameraSubject must be an Instance or nil",
			)

			return true
		}

		camera.CameraSubject = subject

	case "CameraType":
		if enum_registry == nil {
			return false
		}

		item := enums.Arg_Item(
			L,
			index,
			enum_registry,
			"CameraType",
		)

		camera.CameraType =
			enums.CameraType(item.value)

		if camera.CameraType == .Scriptable {
			Camera_Release_Mouse(camera)
			camera.pending_scroll = 0
		}

	case "Pitch":
		camera.pitch = f32(
			vm.ArgNumber(L, index),
		)

		max_pitch: f32 = 1.55334306

		camera.pitch = clamp(
			camera.pitch,
			-max_pitch,
			max_pitch,
		)

	case "Yaw":
		camera.yaw = f32(
			vm.ArgNumber(L, index),
		)

	case:
		return false
	}

	return true
}