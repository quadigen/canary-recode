package services

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import sdl3 "../platform"
import signals "../signals"
import vm "../vm"
import "core:fmt"

user_input_key_code :: proc(scancode: sdl3.Scancode) -> enums.KeyCode {
	return enums.Key_Code_From_Scancode(scancode)
}

user_input_mouse_type :: proc(button: u8) -> enums.UserInputType {
	switch button {
	case sdl3.BUTTON_LEFT:
		return .MouseButton1
	case sdl3.BUTTON_RIGHT:
		return .MouseButton2
	case sdl3.BUTTON_MIDDLE:
		return .MouseButton3
	case:
		return .None
	}
}

user_input_mouse_index :: proc(input_type: enums.UserInputType) -> int {
	#partial switch input_type {
	case .MouseButton1:
		return 0
	case .MouseButton2:
		return 1
	case .MouseButton3:
		return 2
	case:
		return -1
	}
}

user_input_key_index :: proc(service: ^UserInputService, key_code: enums.KeyCode) -> int {
	for existing, i in service.keys_down {if existing == key_code {return i}}
	return -1
}

user_input_set_location :: proc(service: ^UserInputService, x, y: f32) {
	service.mouse_location = {x, y}
	Mouse_Set_Location(service.mouse, x, y)
}

user_input_point_in_viewport :: proc(service: ^UserInputService, x, y: f32) -> bool {
	if service.signal_registry == nil {
		return false
	}

	renderer := service.signal_registry.renderer
	if renderer == nil || !renderer.HasViewportRect {
		return false
	}

	scale := sdl3.UI_Scale > 1.0001 ? sdl3.UI_Scale : 1
	rect := renderer.ViewportRect
	vx := (f32(rect[0]) - sdl3.UI_Safe_Left) / scale
	vy := (f32(rect[1]) - sdl3.UI_Safe_Top) / scale
	vw := f32(rect[2]) / scale
	vh := f32(rect[3]) / scale

	return x >= vx && x < vx + vw && y >= vy && y < vy + vh
}

user_input_pointer_over_gui :: proc(
	service: ^UserInputService,
	value: classes.InputObject_Value,
) -> bool {
	#partial switch value.UserInputType {
	case .MouseButton1, .MouseButton2, .MouseButton3, .MouseMovement, .MouseWheel, .Touch:
		x := value.Position.x
		y := value.Position.y


		if classes.GuiObject_find_topmost(
			   service.signal_registry,
			   x,
			   y,
			   true,
			   user_input_point_in_viewport(service, x, y),
		   ) !=
		   nil {
			return true
		}

		if classes.GuiObject_surface_pointer_over(service.signal_registry, x, y, true) {
			return true
		}
	case:
	}
	return false
}

user_input_fire :: proc(
	L: ^vm.State,
	service: ^UserInputService,
	signal: ^signals.Signal,
	value: classes.InputObject_Value,
) {
	if signal == nil || service.signal_registry == nil {return}
	input := classes.Push_InputObject(L, service.signal_registry, value)
	if input == nil {return}
	vm.PushBoolean(L, user_input_pointer_over_gui(service, value))
	signals.Fire(L, signal, 2)
	vm.Pop(L, 2)

	classes.Destroy_Hierarchy(&input.object)
}

user_input_service_step :: proc(service: ^UserInputService, L: ^vm.State, event: sdl3.Event) {
	if service == nil || L == nil {return}
	#partial switch event.type {
	case .FINGER_DOWN, .FINGER_MOTION, .FINGER_UP, .FINGER_CANCELED:
		user_input_handle_finger(L, service, event)
	case .KEY_DOWN:
		if event.key.repeat {return}
		key_code := user_input_key_code(event.key.scancode)
		if user_input_key_index(service, key_code) < 0 {append(&service.keys_down, key_code)}
		service.last_input_type = .Keyboard
		Mouse_Handle_Key(L, service.mouse, key_code, true)
		user_input_fire(
			L,
			service,
			service.input_began,
			classes.InputObject_Value {
				UserInputType = .Keyboard,
				UserInputState = .Begin,
				KeyCode = key_code,
			},
		)
	case .KEY_UP:
		key_code := user_input_key_code(event.key.scancode)
		index := user_input_key_index(service, key_code)
		if index >= 0 {ordered_remove(&service.keys_down, index)}
		service.last_input_type = .Keyboard
		Mouse_Handle_Key(L, service.mouse, key_code, false)
		user_input_fire(
			L,
			service,
			service.input_ended,
			classes.InputObject_Value {
				UserInputType = .Keyboard,
				UserInputState = .End,
				KeyCode = key_code,
			},
		)
	case .MOUSE_BUTTON_DOWN, .MOUSE_BUTTON_UP:
		input_type := user_input_mouse_type(event.button.button)
		index := user_input_mouse_index(input_type)
		if index < 0 {return}
		is_down := event.type == .MOUSE_BUTTON_DOWN
		service.mouse_down[index] = is_down
		user_input_set_location(service, event.button.x, event.button.y)
		service.last_input_type = input_type
		Mouse_Handle_Button(L, service.mouse, input_type, is_down)
		user_input_fire(
			L,
			service,
			is_down ? service.input_began : service.input_ended,
			classes.InputObject_Value {
				UserInputType = input_type,
				UserInputState = is_down ? .Begin : .End,
				Position = {event.button.x, event.button.y, 0},
			},
		)
	case .MOUSE_MOTION:
		delta := datatypes.Vector2 {
			event.motion.xrel * service.mouse_delta_sensitivity,
			event.motion.yrel * service.mouse_delta_sensitivity,
		}
		user_input_set_location(service, event.motion.x, event.motion.y)
		service.pending_mouse_delta = datatypes.Vec2_Add(service.pending_mouse_delta, delta)
		service.last_input_type = .MouseMovement
		Mouse_Handle_Motion(L, service.mouse)
		user_input_fire(
			L,
			service,
			service.input_changed,
			classes.InputObject_Value {
				UserInputType = .MouseMovement,
				UserInputState = .Change,
				Position = {event.motion.x, event.motion.y, 0},
				Delta = {delta.X, delta.Y, 0},
			},
		)
	case .MOUSE_WHEEL:
		user_input_set_location(service, event.wheel.mouse_x, event.wheel.mouse_y)
		service.last_input_type = .MouseWheel
		wheel_steps := f32(event.wheel.y)
		when ODIN_OS != .JS {
			if event.wheel.direction == .FLIPPED {wheel_steps = -wheel_steps}
		}
		Mouse_Handle_Wheel(L, service.mouse, wheel_steps)
		user_input_fire(
			L,
			service,
			service.input_changed,
			classes.InputObject_Value {
				UserInputType = .MouseWheel,
				UserInputState = .Change,
				Position = {event.wheel.mouse_x, event.wheel.mouse_y, event.wheel.y},
				Delta = {event.wheel.x, 0, event.wheel.y},
			},
		)
	}
}

user_input_handle_finger :: proc(L: ^vm.State, service: ^UserInputService, event: sdl3.Event) {
	size := user_input_touch_size()
	if size.x <= 0 || size.y <= 0 {return}
	finger := event.tfinger
	x := finger.x * size.x
	y := finger.y * size.y


	{
		tscale := sdl3.UI_Scale > 1.0001 ? sdl3.UI_Scale : 1
		x -= sdl3.UI_Safe_Left / tscale
		y -= sdl3.UI_Safe_Top / tscale
	}
	#partial switch event.type {
	case .FINGER_DOWN:
		if user_input_touch_index(service, finger.fingerID) >= 0 {return}
		fmt.eprintf(
			"[finger] virtual=%.0f,%.0f physical=%.0f,%.0f\n",
			x,
			y,
			x * sdl3.UI_Scale,
			y * sdl3.UI_Scale,
		)
		value := classes.InputObject_Value {
			UserInputType  = .Touch,
			UserInputState = .Begin,
			Position       = {x, y, 0},
		}
		append(&service.touches, UserInputTouch{id = finger.fingerID, value = value})
		service.last_input_type = .Touch
		user_input_fire(L, service, service.input_began, value)
	case .FINGER_MOTION:
		index := user_input_touch_index(service, finger.fingerID)
		if index < 0 {
			value := classes.InputObject_Value {
				UserInputType  = .Touch,
				UserInputState = .Change,
				Position       = {x, y, 0},
			}
			append(&service.touches, UserInputTouch{id = finger.fingerID, value = value})
			service.last_input_type = .Touch
			user_input_fire(L, service, service.input_changed, value)
			return
		}
		value := service.touches[index].value
		value.UserInputState = .Change
		value.Position = {x, y, 0}
		value.Delta = {finger.dx * size.x, finger.dy * size.y, 0}
		service.touches[index].value = value
		service.last_input_type = .Touch
		user_input_fire(L, service, service.input_changed, value)
	case .FINGER_UP, .FINGER_CANCELED:
		index := user_input_touch_index(service, finger.fingerID)
		if index < 0 {return}
		value := service.touches[index].value
		value.UserInputState = .End
		value.Position = {x, y, 0}
		ordered_remove(&service.touches, index)
		service.last_input_type = .Touch
		user_input_fire(L, service, service.input_ended, value)
	}
}

user_input_touch_index :: proc(service: ^UserInputService, id: sdl3.FingerID) -> int {
	for entry, i in service.touches {if entry.id == id {return i}}
	return -1
}

user_input_touch_size :: proc() -> [2]f32 {
	window := sdl3.GetKeyboardFocus()
	if window == nil {window = sdl3.GetMouseFocus()}
	if window == nil {return {}}
	w, h: i32
	if !sdl3.GetWindowSize(window, &w, &h) {return {}}
	size := [2]f32{f32(w), f32(h)}
	scale := sdl3.UI_Scale
	if scale > 1.0001 {
		size.x /= scale
		size.y /= scale
	}
	return size
}

User_Input_Begin_Frame :: proc(service: ^UserInputService) {
	if service == nil {return}
	service.frame_mouse_delta = service.pending_mouse_delta
	service.pending_mouse_delta = datatypes.Vector2_Zero
}
