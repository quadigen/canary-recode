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

	viewport_width:  f32,
	viewport_height: f32,
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

// The vertical field of view the renderer builds its perspective with, in
// degrees. set_viewport_rect in src/engine/renderer/main.odin passes this to
// Kine_Filament_SetCameraPerspective, and Mouse.odin mirrors it as
// MOUSE_FIELD_OF_VIEW. Every screen<->world projection has to agree with it, so
// the value lives here and the other two sites are expected to match.
CAMERA_FIELD_OF_VIEW_DEGREES :: f32(60)

// Copies the renderer's live viewport into the camera. The projection helpers
// are pure functions of these two fields, so keeping them current is what makes
// ScreenPointToRay and WorldToViewportPoint agree with the rendered frame after
// a window resize.
Camera_Sync_Viewport :: proc(camera: ^Camera, renderer: ^Renderer_Object) {
	if camera == nil || renderer == nil || !renderer.HasViewportRect {
		return
	}

	rect := renderer.ViewportRect
	if rect[2] <= 0 || rect[3] <= 0 {
		return
	}

	camera.viewport_width = f32(rect[2])
	camera.viewport_height = f32(rect[3])
}

// The viewport a projection should actually use. A camera that has not been
// stepped yet, or a renderer that never published a rect, still has to produce
// usable rays instead of dividing by zero, so fall back to a single pixel.
Camera_Effective_Viewport :: proc(camera: ^Camera) -> (f32, f32) {
	width := camera.viewport_width
	height := camera.viewport_height
	if width <= 0 {
		width = 1
	}
	if height <= 0 {
		height = 1
	}
	return width, height
}

// The half-extent of the view frustum at unit distance: the tangent of the
// vertical half field of view, and the aspect-widened horizontal one.
Camera_Projection_Scale :: proc(camera: ^Camera) -> (f32, f32) {
	width, height := Camera_Effective_Viewport(camera)
	tangent := f32(math.tan(math.to_radians(f64(CAMERA_FIELD_OF_VIEW_DEGREES)) * 0.5))
	return tangent, width / height
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

	// Track the live render viewport before anything else. The projection
	// helpers divide by these dimensions, so they have to follow a resize even
	// when there is no Filament context to draw into. This has to happen before
	// the context check below: a headless or not-yet-initialized renderer still
	// reports a usable ViewportRect.
	Camera_Sync_Viewport(camera, ctx.renderer)

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

Camera_Namecall :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method_name: string,
) -> (i32, bool) {
	switch method_name {
	case "ScreenPointToRay", "ViewportPointToRay":
		return Camera_Screen_Point_To_Ray(L, object, datatype_registry, method_name)
	case "WorldToViewportPoint", "WorldToScreenPoint":
		return Camera_World_To_Viewport_Point(L, object, datatype_registry, method_name)
	case "ProjectLocalPosition":
		datatypes.Push_Vector3(L, datatypes.Vector3{})
		return 1, true
	case "GetLargestCutoffDistance":
		vm.PushNumber(L, 0)
		return 1, true
	case "FrustumExtentsSize":
		camera := cast(^Camera)object
		datatypes.Push_Vector2(
			L,
			datatype_registry,
			datatypes.Vector2{camera.viewport_width, camera.viewport_height},
		)
		return 1, true
	case "FrustumExtentsNearPlaneDistance", "FrustumExtentsFarPlaneDistance":
		vm.PushNumber(L, 0)
		return 1, true
	case "GetFocusedPart":
		Push_Object(L, nil)
		return 1, true
	}
	return 0, false
}

Register_Camera :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&Camera_Class,
		Camera_construct,
		Camera_destroy,

		get = Camera_Get,
		set = Camera_Set,

		namecall = Camera_Namecall,

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

	case "ViewportSize":
		if types == nil {
			return false
		}

		width, height := Camera_Effective_Viewport(camera)
		datatypes.Push_Vector2(
			L,
			types,
			datatypes.Vector2{width, height},
		)
		return true

	case "ScreenPointToRay",
	     "ViewportPointToRay",
	     "WorldToViewportPoint",
	     "WorldToScreenPoint",
	     "ProjectLocalPosition",
	     "GetLargestCutoffDistance",
	     "FrustumExtentsSize",
	     "FrustumExtentsNearPlaneDistance",
	     "FrustumExtentsFarPlaneDistance",
	     "FocusedPart",
	     "GetFocusedPart":
		vm.PushUserdataMethod(L, key)

	case:
		return false
	}

	return true
}

Camera_Screen_Point_To_Ray :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	method_name: string,
) -> (i32, bool) {
	camera := cast(^Camera)object
	x := f32(vm.ArgNumber(L, 2))
	y := f32(vm.ArgNumber(L, 3))

	frame := camera.CFrame
	origin := datatypes.CFrame_Position(frame)

	tangent, aspect := Camera_Projection_Scale(camera)
	width, height := Camera_Effective_Viewport(camera)

	// Screen space is pixel-based with the origin at the top left, while the
	// renderer projects onto normalized device coordinates centered on the
	// viewport.
	normalized_x := (x / width) * 2 - 1
	normalized_y := 1 - (y / height) * 2

	// Camera space is -Z forward, matching CFrame_VectorToWorldSpace and the
	// perspective the renderer built. The horizontal extent is widened by the
	// aspect ratio so a wide viewport does not stretch the vertical field of
	// view sideways.
	view := datatypes.Vector3{
		normalized_x * aspect * tangent,
		normalized_y * tangent,
		-1,
	}

	direction := datatypes.Vec3_Unit(
		datatypes.CFrame_VectorToWorldSpace(frame, view),
	)

	datatypes.Push_Ray(
		L,
		datatype_registry,
		datatypes.Ray{Origin = origin, Direction = direction},
	)
	return 1, true
}

Camera_World_To_Viewport_Point :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	method_name: string,
) -> (i32, bool) {
	camera := cast(^Camera)object
	world := datatypes.Arg_Vector3(L, 2)
	frame := camera.CFrame
	delta := datatypes.Vec3_Subtract(world, datatypes.CFrame_Position(frame))

	tangent, aspect := Camera_Projection_Scale(camera)
	width, height := Camera_Effective_Viewport(camera)

	// Only points in front of the camera can project.
	forward := datatypes.Vec3_Dot(delta, datatypes.CFrame_LookVector(frame))
	if forward <= 0 {
		vm.PushBoolean(L, false)
		return 1, true
	}

	// Inverse of the camera-space ray built in Camera_Screen_Point_To_Ray: undo
	// the perspective divide, then the aspect and tangent scaling.
	normalized_x :=
		datatypes.Vec3_Dot(delta, datatypes.CFrame_RightVector(frame)) /
		(forward * tangent * aspect)
	normalized_y :=
		datatypes.Vec3_Dot(delta, datatypes.CFrame_UpVector(frame)) /
		(forward * tangent)

	on_screen :=
		normalized_x >= -1 &&
		normalized_x <= 1 &&
		normalized_y >= -1 &&
		normalized_y <= 1

	x := (normalized_x + 1) * width * 0.5
	y := (1 - normalized_y) * height * 0.5

	vm.PushBoolean(L, on_screen)
	vm.PushNumber(L, f64(x))
	vm.PushNumber(L, f64(y))
	return 3, true
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