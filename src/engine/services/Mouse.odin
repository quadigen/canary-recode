package services

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import signals "../signals"
import vm "../vm"
import "core:math"
import "core:strings"

Mouse_Class := classes.Class_Info {
	name   = "Mouse",
	parent = &classes.Instance_Class,
}

MOUSE_FIELD_OF_VIEW :: f32(60)
MOUSE_IDLE_INTERVAL :: f32(1)
MOUSE_MISS_DISTANCE :: f32(1000)

MOUSE_PROPERTIES := []string {
	"Hit",
	"hit",
	"Icon",
	"IconContent",
	"Origin",
	"Target",
	"target",
	"TargetFilter",
	"TargetSurface",
	"UnitRay",
	"ViewSizeX",
	"ViewSizeY",
	"X",
	"Y",
}

MOUSE_EVENTS := []string {
	"Button1Down",
	"Button1Up",
	"Button2Down",
	"Button2Up",
	"Idle",
	"KeyDown",
	"keyDown",
	"KeyUp",
	"keyUp",
	"Move",
	"WheelBackward",
	"WheelForward",
}

Mouse :: struct {
	using object:     classes.Object,
	x:                f32,
	y:                f32,
	// The cursor position exactly as SDL delivered it, in window/logical units.
	// x and y hold the same position converted to render pixels, which is the
	// space ViewSizeX/ViewSizeY and the render target are measured in.
	logical_x:        f32,
	logical_y:        f32,
	view_size_x:      f32,
	view_size_y:      f32,
	icon:             string,
	icon_content:     datatypes.Content,
	target_filter:    ^classes.Object,
	filtered_against: ^classes.Object,
	params:           datatypes.RaycastParams,
	unit_ray:         datatypes.Ray,
	hit:              datatypes.CFrame,
	target:           ^classes.Object,
	target_surface:   enums.NormalId,
	idle_elapsed:     f32,
	button1_down:     ^signals.Signal,
	button1_up:       ^signals.Signal,
	button2_down:     ^signals.Signal,
	button2_up:       ^signals.Signal,
	idle:             ^signals.Signal,
	key_down:         ^signals.Signal,
	key_up:           ^signals.Signal,
	move:             ^signals.Signal,
	wheel_backward:   ^signals.Signal,
	wheel_forward:    ^signals.Signal,
}

mouse_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	mouse := new(Mouse)
	mouse.object = classes.Object_Init(&Mouse_Class, "Mouse")
	mouse.params = datatypes.RaycastParams_New()
	mouse.hit = datatypes.CFrame_New_Empty()
	mouse.unit_ray = datatypes.Ray {
		Origin    = {},
		Direction = {0, 0, -1},
	}
	return &mouse.object
}

mouse_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	mouse := cast(^Mouse)object
	if mouse.button1_down != nil {signals.Destroy(mouse.button1_down)}
	if mouse.button1_up != nil {signals.Destroy(mouse.button1_up)}
	if mouse.button2_down != nil {signals.Destroy(mouse.button2_down)}
	if mouse.button2_up != nil {signals.Destroy(mouse.button2_up)}
	if mouse.idle != nil {signals.Destroy(mouse.idle)}
	if mouse.key_down != nil {signals.Destroy(mouse.key_down)}
	if mouse.key_up != nil {signals.Destroy(mouse.key_up)}
	if mouse.move != nil {signals.Destroy(mouse.move)}
	if mouse.wheel_backward != nil {signals.Destroy(mouse.wheel_backward)}
	if mouse.wheel_forward != nil {signals.Destroy(mouse.wheel_forward)}
	delete(mouse.params.ExcludeInstances)
	delete(mouse.icon)
	delete(mouse.icon_content.uri)
	mouse.target_filter = nil
	mouse.filtered_against = nil
	mouse.target = nil
	classes.Object_Destroy(object)
	free(mouse)
}

Mouse_Signal :: proc(mouse: ^Mouse, name: string) -> ^signals.Signal {
	if mouse == nil || mouse.signal_registry == nil {return nil}
	registry := mouse.signal_registry.signal_registry
	if registry == nil {return nil}
	switch name {
	case "Button1Down":
		if mouse.button1_down == nil {mouse.button1_down = signals.Create(registry)}
		return mouse.button1_down
	case "Button1Up":
		if mouse.button1_up == nil {mouse.button1_up = signals.Create(registry)}
		return mouse.button1_up
	case "Button2Down":
		if mouse.button2_down == nil {mouse.button2_down = signals.Create(registry)}
		return mouse.button2_down
	case "Button2Up":
		if mouse.button2_up == nil {mouse.button2_up = signals.Create(registry)}
		return mouse.button2_up
	case "Idle":
		if mouse.idle == nil {mouse.idle = signals.Create(registry)}
		return mouse.idle
	case "KeyDown", "keyDown":
		if mouse.key_down == nil {mouse.key_down = signals.Create(registry)}
		return mouse.key_down
	case "KeyUp", "keyUp":
		if mouse.key_up == nil {mouse.key_up = signals.Create(registry)}
		return mouse.key_up
	case "Move":
		if mouse.move == nil {mouse.move = signals.Create(registry)}
		return mouse.move
	case "WheelBackward":
		if mouse.wheel_backward == nil {mouse.wheel_backward = signals.Create(registry)}
		return mouse.wheel_backward
	case "WheelForward":
		if mouse.wheel_forward == nil {mouse.wheel_forward = signals.Create(registry)}
		return mouse.wheel_forward
	}
	return nil
}

Mouse_Fire :: proc(L: ^vm.State, mouse: ^Mouse, name: string) {
	if L == nil || mouse == nil || mouse.destroyed {return}
	signal := Mouse_Signal(mouse, name)
	if signal == nil {return}
	signals.Fire(L, signal, 0)
}

Mouse_Key_Name :: proc(mouse: ^Mouse, key_code: enums.KeyCode) -> string {
	if mouse.signal_registry == nil || mouse.signal_registry.enums == nil {return ""}
	item := enums.Enum_Item_By_Value(mouse.signal_registry.enums, "KeyCode", i64(key_code))
	if item == nil {return ""}
	return enums.Item_Name(item)
}

Mouse_Fire_Key :: proc(L: ^vm.State, mouse: ^Mouse, name: string, key_code: enums.KeyCode) {
	if L == nil || mouse == nil || mouse.destroyed {return}
	signal := Mouse_Signal(mouse, name)
	if signal == nil {return}
	vm.PushString(L, Mouse_Key_Name(mouse, key_code))
	signals.Fire(L, signal, 1)
	vm.Pop(L, 1)
}

Mouse_Workspace :: proc(mouse: ^Mouse) -> ^Workspace {
	if mouse == nil || mouse.signal_registry == nil {return nil}
	model := cast(^DataModel)mouse.signal_registry.data_model
	if model == nil {return nil}
	object := DataModel_Get_Service(model, "Workspace")
	if object == nil {return nil}
	return cast(^Workspace)object
}

// The render viewport is a sub-rectangle of the window rather than the whole
// thing: an editor hosting this engine draws it inside a panel, so its origin is
// generally non-zero. The origin matters as much as the size, because the ray
// normalizes the cursor against the size and Mouse_Viewport only reports size.
Mouse_Viewport_Rect :: proc(mouse: ^Mouse) -> (x, y, width, height: f32) {
	if mouse == nil || mouse.signal_registry == nil {return 0, 0, 0, 0}
	renderer := mouse.signal_registry.renderer
	if renderer == nil || !renderer.HasViewportRect {return 0, 0, 0, 0}
	rect := renderer.ViewportRect
	return f32(rect[0]), f32(rect[1]), f32(rect[2]), f32(rect[3])
}

Mouse_Viewport :: proc(mouse: ^Mouse) -> (f32, f32) {
	_, _, width, height := Mouse_Viewport_Rect(mouse)
	return width, height
}

// Converts the raw SDL cursor position into viewport-local render pixels. Two
// corrections are needed and they are not interchangeable:
//
//   - SDL reports the cursor in window/logical units, while the render target
//     and the published viewport rect are physical pixels. On a scaled display
//     those differ, and dividing one by the other skews every ray toward the
//     top-left of the screen.
//   - the viewport sits at an offset inside the window, so window pixels must
//     have the viewport origin removed before they are normalized by the
//     viewport size. Skipping this leaves normalized_x proportional to the
//     panel offset, which is why picking only worked for a full-window viewport.
Mouse_Sync_Position :: proc(mouse: ^Mouse) {
	if mouse == nil {return}

	scale := [2]f32{1, 1}
	origin_x, origin_y := f32(0), f32(0)
	if mouse.signal_registry != nil {
		if renderer := mouse.signal_registry.renderer; renderer != nil {
			scale = renderer.MouseScale
		}
		origin_x, origin_y, _, _ = Mouse_Viewport_Rect(mouse)
	}

	// RendererObject is used zero-initialized in tests and before the first
	// frame publishes a density, so an unset component has to mean "unscaled"
	// rather than collapse the cursor to the origin.
	x_scale := scale[0] > 0 ? scale[0] : 1
	y_scale := scale[1] > 0 ? scale[1] : 1

	mouse.x = mouse.logical_x * x_scale - origin_x
	mouse.y = mouse.logical_y * y_scale - origin_y
}

Mouse_Direction :: proc(mouse: ^Mouse, camera: ^classes.Camera) -> datatypes.Vector3 {
	forward := datatypes.Vector3{0, 0, -1}
	if camera == nil {return forward}
	if mouse.view_size_x <= 0 || mouse.view_size_y <= 0 {return forward}
	normalized_x := (mouse.x / mouse.view_size_x) * 2 - 1
	normalized_y := 1 - (mouse.y / mouse.view_size_y) * 2
	tangent := math.tan(math.to_radians(MOUSE_FIELD_OF_VIEW) * 0.5)
	aspect := mouse.view_size_x / mouse.view_size_y
	view := datatypes.Vector3{normalized_x * aspect * tangent, normalized_y * tangent, -1}
	return datatypes.Vec3_Unit(datatypes.CFrame_VectorToWorldSpace(camera.CFrame, view))
}

Mouse_Surface :: proc(normal: datatypes.Vector3) -> enums.NormalId {
	absolute := datatypes.Vec3_Abs(normal)
	if absolute.x >= absolute.y && absolute.x >= absolute.z {
		return .Left if normal.x < 0 else .Right
	}
	if absolute.y >= absolute.z {
		return .Bottom if normal.y < 0 else .Top
	}
	return .Back if normal.z > 0 else .Front
}

Mouse_Sync_Filter :: proc(mouse: ^Mouse) {
	if mouse == nil || mouse.filtered_against == mouse.target_filter {return}
	delete(mouse.params.ExcludeInstances)
	mouse.params.ExcludeInstances = nil
	mouse.params.ExcludeFilterSet = false
	if mouse.target_filter != nil && !mouse.target_filter.destroyed {
		append(
			&mouse.params.ExcludeInstances,
			datatypes.Raycast_Instance_Reference {
				object = mouse.target_filter,
				lua_ref = mouse.target_filter.lua_ref,
			},
		)
		mouse.params.ExcludeFilterSet = true
	}
	mouse.filtered_against = mouse.target_filter
}

Mouse_Miss_Hit :: proc(origin, direction: datatypes.Vector3) -> datatypes.CFrame {
	return datatypes.CFrame_LookAt(
		datatypes.Vec3_Add(origin, datatypes.Vec3_Multiply(direction, MOUSE_MISS_DISTANCE)),
		origin,
	)
}

Mouse_Begin_Frame :: proc(mouse: ^Mouse, L: ^vm.State, delta_time: f32) {
	if mouse == nil || mouse.destroyed {return}

	mouse.view_size_x, mouse.view_size_y = Mouse_Viewport(mouse)

	// The window's pixel density can change when it moves between monitors, so
	// re-derive the pixel position every frame rather than only on motion.
	Mouse_Sync_Position(mouse)

	workspace := Mouse_Workspace(mouse)
	camera: ^classes.Camera
	physics: ^Physics
	if workspace != nil {
		camera = workspace.current_camera
		physics = workspace_physics(workspace)
	}

	origin := datatypes.Vector3{}
	if camera != nil && !camera.destroyed {
		origin = datatypes.CFrame_Position(camera.CFrame)
	}

	direction := Mouse_Direction(mouse, camera)

	mouse.unit_ray = datatypes.Ray {
		Origin    = origin,
		Direction = direction,
	}
	mouse.hit = Mouse_Miss_Hit(origin, direction)
	mouse.target = nil
	mouse.target_surface = .Front

	if physics != nil &&
	   camera != nil &&
	   !camera.destroyed &&
	   mouse.view_size_x > 0 &&
	   mouse.view_size_y > 0 {
		Mouse_Sync_Filter(mouse)
		extent := datatypes.Vec3_Multiply(direction, MOUSE_MISS_DISTANCE)
		result, hit := Physics_Raycast(physics, &workspace.object, origin, extent, &mouse.params)
		if hit {
			mouse.hit = datatypes.CFrame_LookAt(result.Position, origin)
			mouse.target_surface = Mouse_Surface(result.Normal)
			target := cast(^classes.Object)result.ObjectRef
			if target != nil && !target.destroyed {mouse.target = target}
		}
	}

	mouse.idle_elapsed += delta_time
	if mouse.idle_elapsed >= MOUSE_IDLE_INTERVAL {
		mouse.idle_elapsed = 0
		Mouse_Fire(L, mouse, "Idle")
	}
}

Mouse_Set_Location :: proc(mouse: ^Mouse, x, y: f32) {
	if mouse == nil || mouse.destroyed {return}
	mouse.logical_x = x
	mouse.logical_y = y
	// Convert straight away so a script reading Mouse.X in the same tick sees
	// pixels rather than the unscaled SDL value.
	Mouse_Sync_Position(mouse)
	mouse.idle_elapsed = 0
}

Mouse_Handle_Motion :: proc(L: ^vm.State, mouse: ^Mouse) {
	if mouse == nil || mouse.destroyed {return}
	mouse.idle_elapsed = 0
	Mouse_Fire(L, mouse, "Move")
}

Mouse_Handle_Button :: proc(
	L: ^vm.State,
	mouse: ^Mouse,
	input_type: enums.UserInputType,
	pressed: bool,
) {
	if mouse == nil || mouse.destroyed {return}
	mouse.idle_elapsed = 0
	#partial switch input_type {
	case .MouseButton1:
		Mouse_Fire(L, mouse, pressed ? "Button1Down" : "Button1Up")
	case .MouseButton2:
		Mouse_Fire(L, mouse, pressed ? "Button2Down" : "Button2Up")
	case:
	}
}

Mouse_Handle_Wheel :: proc(L: ^vm.State, mouse: ^Mouse, steps: f32) {
	if mouse == nil || mouse.destroyed {return}
	mouse.idle_elapsed = 0
	if steps > 0 {
		Mouse_Fire(L, mouse, "WheelForward")
	} else if steps < 0 {
		Mouse_Fire(L, mouse, "WheelBackward")
	}
}

Mouse_Handle_Key :: proc(L: ^vm.State, mouse: ^Mouse, key_code: enums.KeyCode, pressed: bool) {
	if mouse == nil || mouse.destroyed {return}
	mouse.idle_elapsed = 0
	Mouse_Fire_Key(L, mouse, pressed ? "KeyDown" : "KeyUp", key_code)
}

Mouse_Origin_CFrame :: proc(mouse: ^Mouse) -> datatypes.CFrame {
	return datatypes.CFrame_LookAt(
		mouse.unit_ray.Origin,
		datatypes.Vec3_Add(mouse.unit_ray.Origin, mouse.unit_ray.Direction),
	)
}

Mouse_Push :: proc(L: ^vm.State, mouse: ^Mouse) {
	if mouse == nil || mouse.destroyed {vm.PushNil(L); return}
	classes.Push_Object(L, &mouse.object)
}

Mouse_Set_Icon :: proc(mouse: ^Mouse, uri: string, content: datatypes.Content) {
	if mouse == nil {return}
	delete(mouse.icon)
	delete(mouse.icon_content.uri)
	mouse.icon = strings.clone(uri)
	mouse.icon_content = datatypes.Content_Clone(content)
}

mouse_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	mouse := cast(^Mouse)object
	switch key {
	case "Hit", "hit":
		if datatype_registry == nil {return false}
		datatypes.Push_CFrame(L, datatype_registry, mouse.hit)
	case "Icon":
		vm.PushString(L, mouse.icon)
	case "IconContent":
		if datatype_registry == nil {return false}
		datatypes.Push_Content(L, datatype_registry, datatypes.Content_Clone(mouse.icon_content))
	case "Origin":
		if datatype_registry == nil {return false}
		datatypes.Push_CFrame(L, datatype_registry, Mouse_Origin_CFrame(mouse))
	case "Target", "target":
		if mouse.target == nil ||
		   mouse.target.destroyed {vm.PushNil(L)} else {classes.Push_Object(L, mouse.target)}
	case "TargetFilter":
		classes.Push_Object(L, mouse.target_filter)
	case "TargetSurface":
		if enum_registry == nil {return false}
		_ = enums.Push_Item_By_Value(L, enum_registry, "NormalId", i64(mouse.target_surface))
	case "UnitRay":
		if datatype_registry == nil {return false}
		datatypes.Push_Ray(L, datatype_registry, mouse.unit_ray)
	case "ViewSizeX":
		vm.PushNumber(L, f64(mouse.view_size_x))
	case "ViewSizeY":
		vm.PushNumber(L, f64(mouse.view_size_y))
	case "X":
		vm.PushNumber(L, f64(mouse.x))
	case "Y":
		vm.PushNumber(L, f64(mouse.y))
	case "Button1Down",
	     "Button1Up",
	     "Button2Down",
	     "Button2Up",
	     "Idle",
	     "KeyDown",
	     "keyDown",
	     "KeyUp",
	     "keyUp",
	     "Move",
	     "WheelBackward",
	     "WheelForward":
		signals.Push(L, Mouse_Signal(mouse, key))
	case:
		return false
	}
	return true
}

mouse_set :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	mouse := cast(^Mouse)object
	switch key {
	case "Icon":
		uri := vm.ArgString(L, value_index)
		Mouse_Set_Icon(mouse, uri, datatypes.Content_From_URI(uri))
	case "IconContent":
		if datatype_registry == nil {return false}
		content := datatypes.Arg_Content(L, value_index, datatype_registry)
		Mouse_Set_Icon(mouse, content.uri, content)
	case "TargetFilter":
		mouse.target_filter = classes.object_from_argument(L, value_index)
		if mouse.target_filter == mouse.filtered_against {mouse.filtered_against = nil}
	case:
		return false
	}
	return true
}

Register_Mouse_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&Mouse_Class,
		mouse_construct,
		mouse_destroy,
		creatable = false,
		get = mouse_get,
		set = mouse_set,
		properties = MOUSE_PROPERTIES,
		events = MOUSE_EVENTS,
	)
}
