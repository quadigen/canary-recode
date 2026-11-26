package classes

import sdl3 "../platform"

import kineffi "../bindings"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:math"

Camera_Class := Class_Info {
	name   = "Camera",
	parent = &Instance_Class,
}

Camera :: struct {
	using object:      Object,
	CFrame:            datatypes.CFrame,
	Focus:             datatypes.CFrame,
	CameraSubject:     ^Object,
	CameraType:        enums.CameraType,
	yaw:               f32,
	pitch:             f32,
	move_speed:        f32,
	mouse_sensitivity: f32,
	mouse_captured:    bool,
	mouse_look_active: bool,
	input_enabled:     bool,
	scroll_step:       f32,
	pending_scroll:    f32,
	orbit_distance:    f32,
	field_of_view:     f32,
	viewport_width:    f32,
	viewport_height:   f32,
	velocity:          datatypes.Vector3,
	move_smoothing:    f32,
}

Camera_Init :: proc() -> Camera {
	cframe := datatypes.CFrame_New_XYZ(0, 4, 10)

	return Camera {
		object = Object_Init(&Camera_Class),
		CFrame = cframe,
		Focus = datatypes.CFrame_New_XYZ(0, 4, 0),
		CameraSubject = nil,
		CameraType = .Custom,
		yaw = 0,
		pitch = 0,
		field_of_view = 60,
		move_speed = 10,
		mouse_sensitivity = 0.003,
		mouse_captured = false,
		mouse_look_active = false,
		input_enabled = true,
		scroll_step = 5,
		pending_scroll = 0,
		orbit_distance = 12,
		velocity = datatypes.Vector3{},
		move_smoothing = 10,
	}
}

CAMERA_FIELD_OF_VIEW_DEGREES :: f32(60)

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


Camera_Projection_Scale :: proc(camera: ^Camera) -> (f32, f32) {
	width, height := Camera_Effective_Viewport(camera)
	tangent := f32(math.tan(math.to_radians(f64(camera.field_of_view)) * 0.5))
	return tangent, width / height
}

Camera_construct :: proc(renderer: ^Renderer_Object, data_Camera: rawptr) -> ^Object {
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

	camera.pitch = f32(math.asin(clamp(look.y, -1, 1)))
	camera.yaw = f32(math.atan2(-look.x, -look.z))
}

Camera_Release_Mouse :: proc(camera: ^Camera) {
	if camera == nil {
		return
	}

	camera.mouse_look_active = false
	if !camera.mouse_captured {
		return
	}

	window := sdl3.GetMouseFocus()
	if window != nil {
		_ = sdl3.SetWindowRelativeMouseMode(window, false)
	}

	camera.mouse_captured = false
}

Camera_Update_Mouse_Look :: proc(camera: ^Camera, focused: bool) -> bool {
	mouse_dx, mouse_dy: f32
	mouse_buttons := sdl3.GetRelativeMouseState(&mouse_dx, &mouse_dy)

	rotating := focused && .RIGHT in mouse_buttons

	if rotating {
		if !camera.mouse_look_active {
			camera.mouse_look_active = true

			window := sdl3.GetMouseFocus()

			if window != nil {
				camera.mouse_captured = sdl3.SetWindowRelativeMouseMode(window, true)
			}

			mouse_dx = 0
			mouse_dy = 0
		}

		camera.yaw -= mouse_dx * camera.mouse_sensitivity
		camera.pitch -= mouse_dy * camera.mouse_sensitivity

		max_pitch: f32 = 1.55334306

		camera.pitch = clamp(camera.pitch, -max_pitch, max_pitch)
	} else {
		Camera_Release_Mouse(camera)
	}

	return rotating
}


Camera_Add_Scroll :: proc(camera: ^Camera, steps: f32) {
	if camera == nil {
		return
	}

	camera.pending_scroll += steps
}

Camera_Find_Subject_Part :: proc(object: ^Object) -> ^Part {
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

Camera_Get_Subject_Position :: proc(camera: ^Camera) -> (position: datatypes.Vector3, ok: bool) {
	if camera == nil || camera.CameraSubject == nil || camera.CameraSubject.destroyed {
		return datatypes.Vector3{}, false
	}

	part := Camera_Find_Subject_Part(camera.CameraSubject)

	if part == nil {
		return datatypes.Vector3{}, false
	}

	return datatypes.CFrame_Position(part.cframe), true
}

Camera_Update_Focus :: proc(camera: ^Camera, position: datatypes.Vector3) {
	camera.Focus = datatypes.CFrame_New_Position(position)
}

Camera_Set_Position :: proc(camera: ^Camera, position: datatypes.Vector3) {
	camera.CFrame.x = position.x
	camera.CFrame.y = position.y
	camera.CFrame.z = position.z
}

Camera_Freecam_Step :: proc(camera: ^Camera, dt: f32, focused: bool, rotating: bool) {
	rotation := datatypes.CFrame_FromOrientation(f64(camera.pitch), f64(camera.yaw), 0)

	orientation := camera.CFrame
	if rotating {
		orientation = rotation
	}

	look := datatypes.CFrame_LookVector(orientation)
	right := datatypes.CFrame_RightVector(orientation)
	up := datatypes.CFrame_UpVector(orientation)

	keys := sdl3.GetKeyboardState(nil)
	mod := sdl3.GetModState()

	input_blocked := !focused || TEXTBOX_IS_USED == true || .LCTRL in mod

	movement := datatypes.Vector3{}

	if !input_blocked {
		if keys[int(sdl3.Scancode.W)] {
			movement.x += look.x; movement.y += look.y; movement.z += look.z
		}
		if keys[int(sdl3.Scancode.S)] {
			movement.x -= look.x; movement.y -= look.y; movement.z -= look.z
		}
		if keys[int(sdl3.Scancode.D)] {
			movement.x += right.x; movement.y += right.y; movement.z += right.z
		}
		if keys[int(sdl3.Scancode.A)] {
			movement.x -= right.x; movement.y -= right.y; movement.z -= right.z
		}
		if keys[int(sdl3.Scancode.E)] {
			movement.x += up.x; movement.y += up.y; movement.z += up.z
		}
		if keys[int(sdl3.Scancode.Q)] {
			movement.x -= up.x; movement.y -= up.y; movement.z -= up.z
		}
	}

	if focused && (keys[int(sdl3.Scancode.LSHIFT)] || keys[int(sdl3.Scancode.RSHIFT)]) {
		camera.move_speed = 5
	} else {
		camera.move_speed = 10
	}

	target := datatypes.Vector3{}
	length_squared := movement.x * movement.x + movement.y * movement.y + movement.z * movement.z
	if length_squared > 0 {
		scale := f64(camera.move_speed) / math.sqrt(length_squared)
		target = datatypes.Vector3{movement.x * scale, movement.y * scale, movement.z * scale}
	}

	alpha := 1 - math.exp(-camera.move_smoothing * dt)

	camera.velocity.x += (target.x - camera.velocity.x) * f64(alpha)
	camera.velocity.y += (target.y - camera.velocity.y) * f64(alpha)
	camera.velocity.z += (target.z - camera.velocity.z) * f64(alpha)

	speed_squared :=
		camera.velocity.x * camera.velocity.x +
		camera.velocity.y * camera.velocity.y +
		camera.velocity.z * camera.velocity.z
	if length_squared == 0 && speed_squared < 0.0001 {
		camera.velocity = datatypes.Vector3{}
	}

	position := datatypes.CFrame_Position(camera.CFrame)
	position.x += camera.velocity.x * f64(dt)
	position.y += camera.velocity.y * f64(dt)
	position.z += camera.velocity.z * f64(dt)

	if rotating && camera.pending_scroll != 0 {
		distance := camera.pending_scroll * camera.scroll_step

		position.x += look.x * f64(distance)
		position.y += look.y * f64(distance)
		position.z += look.z * f64(distance)
	}

	camera.pending_scroll = 0

	if rotating {
		camera.CFrame = rotation
	}

	Camera_Set_Position(camera, position)

	final_look := datatypes.CFrame_LookVector(camera.CFrame)

	Camera_Update_Focus(
		camera,
		datatypes.Vector3 {
			position.x + final_look.x * 10,
			position.y + final_look.y * 10,
			position.z + final_look.z * 10,
		},
	)
}

Camera_Consume_Orbit_Scroll :: proc(camera: ^Camera) {
	if camera.pending_scroll == 0 {
		return
	}

	camera.orbit_distance -= camera.pending_scroll * camera.scroll_step

	camera.orbit_distance = clamp(camera.orbit_distance, 1.0, 512.0)

	camera.pending_scroll = 0
}

Camera_Subject_Orbit_Step :: proc(
	camera: ^Camera,
	target: datatypes.Vector3,
	camera_type: enums.CameraType,
) {
	Camera_Consume_Orbit_Scroll(camera)

	rotation := datatypes.CFrame_FromOrientation(f64(camera.pitch), f64(camera.yaw), 0)

	look := datatypes.CFrame_LookVector(rotation)
	right := datatypes.CFrame_RightVector(rotation)
	up := datatypes.CFrame_UpVector(rotation)

	position := target

	#partial switch camera_type {
	case .FirstPerson:
		position.y += 2

		camera.CFrame = rotation
		Camera_Set_Position(camera, position)

	case .TopDown:
		position.y += f64(camera.orbit_distance)

		camera.CFrame = datatypes.CFrame_LookAt(position, target)

	case .Isometric:
		horizontal := camera.orbit_distance * 0.70710678

		position.x += f64(math.sin(camera.yaw) * horizontal)
		position.z += f64(math.cos(camera.yaw) * horizontal)
		position.y += f64(horizontal)

		camera.CFrame = datatypes.CFrame_LookAt(position, target)

	case .Shoulder:
		position.x -= look.x * f64(camera.orbit_distance)
		position.y -= look.y * f64(camera.orbit_distance)
		position.z -= look.z * f64(camera.orbit_distance)

		position.x += right.x * 2
		position.y += right.y * 2
		position.z += right.z * 2

		position.x += up.x * 1.5
		position.y += up.y * 1.5
		position.z += up.z * 1.5

		camera.CFrame = datatypes.CFrame_LookAt(position, target)

	case .Custom, .Orbital, .ThirdPerson, .Follow:
		position.x -= look.x * f64(camera.orbit_distance)
		position.y -= look.y * f64(camera.orbit_distance)
		position.z -= look.z * f64(camera.orbit_distance)

		camera.CFrame = datatypes.CFrame_LookAt(position, target)
	}

	Camera_Update_Focus(camera, target)
	Camera_Sync_Angles_From_CFrame(camera)
}

Camera_Update_World_To_View :: proc(camera: ^Camera, renderer: ^Renderer_Object) {
	if camera == nil || renderer == nil {
		return
	}

	if renderer.HasViewportRect && renderer.Filament != nil {
		rect := renderer.ViewportRect
		if rect[2] > 0 && rect[3] > 0 {
			kineffi.Kine_Filament_SetCameraPerspective(
				renderer.Filament,
				f64(camera.field_of_view),
				f64(rect[2]) / f64(rect[3]),
				0.1,
				1000,
			)
		}
	}
	view := datatypes.CFrame_Inverse(camera.CFrame)

	renderer.WorldToView = [12]f32 {
		f32(view.x),
		f32(view.y),
		f32(view.z),
		f32(view.r00),
		f32(view.r01),
		f32(view.r02),
		f32(view.r10),
		f32(view.r11),
		f32(view.r12),
		f32(view.r20),
		f32(view.r21),
		f32(view.r22),
	}

	renderer.HasWorldToView = true

	if renderer.Filament != nil {
		look := datatypes.CFrame_LookVector(camera.CFrame)
		up := datatypes.CFrame_UpVector(camera.CFrame)

		kineffi.Kine_Filament_SetCameraPose(
			renderer.Filament,
			f64(camera.CFrame.x),
			f64(camera.CFrame.y),
			f64(camera.CFrame.z),
			f64(look.x),
			f64(look.y),
			f64(look.z),
			f64(up.x),
			f64(up.y),
			f64(up.z),
		)
	}
}

camera_notify_step_changes :: proc(
	camera: ^Camera,
	previous_cframe, previous_focus: datatypes.CFrame,
	previous_viewport: datatypes.Vector2,
	L: ^vm.State,
) {
	if camera == nil || camera.destroyed {return}
	cframe_changed := camera.CFrame != previous_cframe
	focus_changed := camera.Focus != previous_focus
	viewport_changed :=
		previous_viewport != (datatypes.Vector2{camera.viewport_width, camera.viewport_height})
	if cframe_changed {
		Render_3D_Mark_Object_Dirty(&camera.object)
		Object_Fire_Property_Changed(&camera.object, "CFrame", L)
	}
	if focus_changed && !camera.destroyed {
		Object_Fire_Property_Changed(&camera.object, "Focus", L)
	}
	if viewport_changed && !camera.destroyed {
		Object_Fire_Property_Changed(&camera.object, "ViewportSize", L)
	}
}

Camera_Step :: proc(object: ^Object, ctx: ^Class_Step_Context) {
	camera := cast(^Camera)object

	if camera == nil || ctx == nil || ctx.renderer == nil || ctx.renderer.ActiveCamera != object {
		return
	}

	previous_cframe := camera.CFrame
	previous_focus := camera.Focus
	previous_viewport := datatypes.Vector2{camera.viewport_width, camera.viewport_height}
	defer camera_notify_step_changes(
		camera,
		previous_cframe,
		previous_focus,
		previous_viewport,
		ctx.L,
	)

	Camera_Sync_Viewport(camera, ctx.renderer)

	if ctx.renderer.Filament == nil {
		return
	}


	if camera.CameraType == .Scriptable || !camera.input_enabled {
		Camera_Release_Mouse(camera)
		camera.pending_scroll = 0

		Camera_Update_World_To_View(camera, ctx.renderer)

		return
	}

	focused := sdl3.GetKeyboardFocus() != nil

	rotating := Camera_Update_Mouse_Look(camera, focused)

	subject_position, has_subject := Camera_Get_Subject_Position(camera)


	if camera.CameraType == .Custom && !has_subject {
		Camera_Freecam_Step(camera, ctx.delta_time, focused, rotating)

		Camera_Update_World_To_View(camera, ctx.renderer)

		return
	}


	if !has_subject {
		Camera_Freecam_Step(camera, ctx.delta_time, focused, rotating)

		Camera_Update_World_To_View(camera, ctx.renderer)

		return
	}

	Camera_Subject_Orbit_Step(camera, subject_position, camera.CameraType)
	if registry := camera.signal_registry; registry != nil && registry.camera_obstruction != nil {
		position := registry.camera_obstruction(
			registry.network_ownership_ctx,
			camera,
			datatypes.CFrame_Position(camera.Focus),
			datatypes.CFrame_Position(camera.CFrame),
		)
		Camera_Set_Position(camera, position)
	}

	Camera_Update_World_To_View(camera, ctx.renderer)
}

Camera_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	camera := cast(^Camera)object

	Camera_Release_Mouse(camera)

	ViewportFrame_Camera_Destroyed(camera)
	camera.CameraSubject = nil

	Object_Destroy(object)
	free(camera)
}

Camera_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^Camera)source
	dst := cast(^Camera)destination

	dst.field_of_view = src.field_of_view
	dst.CFrame = src.CFrame
	dst.Focus = src.Focus

	dst.CameraSubject = src.CameraSubject
	dst.CameraType = src.CameraType

	dst.yaw = src.yaw
	dst.pitch = src.pitch

	dst.move_speed = src.move_speed
	dst.mouse_sensitivity = src.mouse_sensitivity

	dst.scroll_step = src.scroll_step
	dst.pending_scroll = 0

	dst.orbit_distance = src.orbit_distance


	dst.mouse_captured = false
	dst.mouse_look_active = false
	dst.input_enabled = src.input_enabled
}

Camera_Namecall :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method_name: string,
) -> (
	i32,
	bool,
) {
	switch method_name {
	case "GetRenderCFrame":
		datatypes.Push_CFrame(L, datatype_registry, (cast(^Camera)object).CFrame)
		return 1, true
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

camera_parallel_get :: proc(
	L: ^vm.State,
	object: ^Object,
	d: ^datatypes.Registry,
	e: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "FieldOfView",
	     "InputEnabled",
	     "Sensitivity",
	     "CFrame",
	     "Focus",
	     "CameraSubject",
	     "CameraType",
	     "Pitch",
	     "Yaw",
	     "ViewportSize",
	     "DiagonalFieldOfView",
	     "GetRenderCFrame",
	     "ScreenPointToRay",
	     "ViewportPointToRay",
	     "WorldToViewportPoint",
	     "WorldToScreenPoint":
		return Camera_Get(L, object, d, e, key)
	}
	return false
}

camera_parallel_namecall :: proc(
	L: ^vm.State,
	object: ^Object,
	d: ^datatypes.Registry,
	e: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	switch method {
	case "GetRenderCFrame",
	     "ScreenPointToRay",
	     "ViewportPointToRay",
	     "WorldToViewportPoint",
	     "WorldToScreenPoint":
		return Camera_Namecall(L, object, d, e, method)
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
		parallel_get = camera_parallel_get,
		set = Camera_Set,
		namecall = Camera_Namecall,
		parallel_namecall = camera_parallel_namecall,
		clone = Camera_clone,
		_step = Camera_Step,
		_step_phase = .Render_3D,
		properties = []string {
			"FieldOfView",
			"CFrame",
			"Focus",
			"CameraSubject",
			"CameraType",
			"Pitch",
			"Yaw",
			"Sensitivity",
			"InputEnabled",
			"ViewportSize",
			"DiagonalFieldOfView",
		},
		methods = []string {
			"ScreenPointToRay",
			"ViewportPointToRay",
			"WorldToViewportPoint",
			"WorldToScreenPoint",
			"GetRenderCFrame",
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
	case "FieldOfView":
		vm.PushNumber(L, f64(camera.field_of_view))
	case "DiagonalFieldOfView":
		width, height := Camera_Effective_Viewport(camera)
		tangent_v := math.tan(math.to_radians(f64(camera.field_of_view)) * 0.5)
		if width > 0 && height > 0 {
			tangent_h := tangent_v * f64(width) / f64(height)
			diagonal := 2 * math.atan(math.sqrt(tangent_v * tangent_v + tangent_h * tangent_h))
			vm.PushNumber(L, math.to_degrees(diagonal))
		} else {
			vm.PushNumber(L, f64(camera.field_of_view))
		}
	case "InputEnabled":
		vm.PushBoolean(L, camera.input_enabled)
	case "Sensitivity":
		vm.PushNumber(L, f64(camera.mouse_sensitivity))
	case "CFrame":
		if types == nil {
			return false
		}

		datatypes.Push_CFrame(L, types, camera.CFrame)

	case "Focus":
		if types == nil {
			return false
		}

		datatypes.Push_CFrame(L, types, camera.Focus)

	case "CameraSubject":
		Push_Object(L, camera.CameraSubject)

	case "CameraType":
		if enum_registry == nil {
			return false
		}

		_ = enums.Push_Item_By_Value(L, enum_registry, "CameraType", i64(camera.CameraType))

	case "Pitch":
		vm.PushNumber(L, f64(camera.pitch))

	case "Yaw":
		vm.PushNumber(L, f64(camera.yaw))

	case "ViewportSize":
		if types == nil {
			return false
		}

		width, height := Camera_Effective_Viewport(camera)
		datatypes.Push_Vector2(L, types, datatypes.Vector2{width, height})
		return true

	case "GetRenderCFrame",
	     "ScreenPointToRay",
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
) -> (
	i32,
	bool,
) {
	camera := cast(^Camera)object
	x := f32(vm.ArgNumber(L, 2))
	y := f32(vm.ArgNumber(L, 3))
	depth := f32(vm.ArgOptionalNumber(L, 4, 0))
	if method_name == "ScreenPointToRay" {
		x += sdl3.UI_Safe_Left / sdl3.UI_Scale
		y += sdl3.UI_Safe_Top / sdl3.UI_Scale
	}

	frame := camera.CFrame
	origin := datatypes.CFrame_Position(frame)

	tangent, aspect := Camera_Projection_Scale(camera)
	width, height := Camera_Effective_Viewport(camera)


	normalized_x := (x / width) * 2 - 1
	normalized_y := 1 - (y / height) * 2


	view := datatypes.Vector3 {
		f64(normalized_x * aspect * tangent),
		f64(normalized_y * tangent),
		-1,
	}

	direction := datatypes.Vec3_Unit(datatypes.CFrame_VectorToWorldSpace(frame, view))

	origin = datatypes.Vec3_Add(origin, datatypes.Vec3_Multiply(direction, f64(depth)))
	datatypes.Push_Ray(L, datatype_registry, datatypes.Ray{Origin = origin, Direction = direction})
	return 1, true
}

Camera_World_To_Viewport_Point :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	method_name: string,
) -> (
	i32,
	bool,
) {
	camera := cast(^Camera)object
	world := datatypes.Arg_Vector3(L, 2)
	frame := camera.CFrame
	delta := datatypes.Vec3_Subtract(world, datatypes.CFrame_Position(frame))

	tangent, aspect := Camera_Projection_Scale(camera)
	width, height := Camera_Effective_Viewport(camera)


	forward := datatypes.Vec3_Dot(delta, datatypes.CFrame_LookVector(frame))
	if forward <= 0 {
		datatypes.Push_Vector3(L, datatypes.Vector3{})
		vm.PushBoolean(L, false)
		return 2, true
	}


	normalized_x :=
		datatypes.Vec3_Dot(delta, datatypes.CFrame_RightVector(frame)) /
		(forward * f64(tangent) * f64(aspect))
	normalized_y :=
		datatypes.Vec3_Dot(delta, datatypes.CFrame_UpVector(frame)) / (forward * f64(tangent))

	on_screen := normalized_x >= -1 && normalized_x <= 1 && normalized_y >= -1 && normalized_y <= 1

	x := (normalized_x + 1) * f64(width) * 0.5
	y := (1 - normalized_y) * f64(height) * 0.5

	if method_name == "WorldToScreenPoint" {
		x -= f64(sdl3.UI_Safe_Left / sdl3.UI_Scale)
		y -= f64(sdl3.UI_Safe_Top / sdl3.UI_Scale)
	}
	datatypes.Push_Vector3(L, datatypes.Vector3{x, y, forward})
	vm.PushBoolean(L, on_screen)
	return 2, true
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
	case "FieldOfView":
		camera.field_of_view = clamp(f32(vm.ArgNumber(L, index)), 1, 120)
	case "CFrame":
		if types == nil {
			return false
		}

		camera.CFrame = datatypes.Arg_CFrame(L, index, types)

		Camera_Sync_Angles_From_CFrame(camera)
	case "InputEnabled":
		camera.input_enabled = vm.ArgBoolean(L, index)
	case "Sensitivity":
		camera.mouse_sensitivity = f32(vm.ArgNumber(L, index))

	case "Focus":
		if types == nil {
			return false
		}

		camera.Focus = datatypes.Arg_CFrame(L, index, types)

	case "CameraSubject":
		if vm.IsNil(L, index) {
			camera.CameraSubject = nil
			return true
		}

		subject := object_from_argument(L, index)

		if subject == nil {
			_ = vm.RaiseError(L, "CameraSubject must be an Instance or nil")

			return true
		}

		camera.CameraSubject = subject

	case "CameraType":
		if enum_registry == nil {
			return false
		}

		item := enums.Arg_Item(L, index, enum_registry, "CameraType")

		camera.CameraType = enums.CameraType(item.value)

		if camera.CameraType == .Scriptable {
			Camera_Release_Mouse(camera)
			camera.pending_scroll = 0
		}

	case "Pitch":
		camera.pitch = f32(vm.ArgNumber(L, index))

		max_pitch: f32 = 1.55334306

		camera.pitch = clamp(camera.pitch, -max_pitch, max_pitch)

	case "Yaw":
		camera.yaw = f32(vm.ArgNumber(L, index))

	case:
		return false
	}

	return true
}
