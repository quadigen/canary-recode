package services

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import sdl3 "../platform"
import signals "../signals"
import vm "../vm"

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

user_input_fire :: proc(
	L: ^vm.State,
	service: ^UserInputService,
	signal: ^signals.Signal,
	value: classes.InputObject_Value,
) {
	if signal == nil || service.signal_registry == nil {return}
	if classes.Push_InputObject(L, service.signal_registry, value) == nil {return}
	vm.PushBoolean(L, false)
	signals.Fire(L, signal, 2)
	vm.Pop(L, 2)
}

user_input_service_step :: proc(service: ^UserInputService, L: ^vm.State, event: sdl3.Event) {
	if service == nil || L == nil {return}
	#partial switch event.type {
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

User_Input_Begin_Frame :: proc(service: ^UserInputService) {
	if service == nil {return}
	service.frame_mouse_delta = service.pending_mouse_delta
	service.pending_mouse_delta = datatypes.Vector2_Zero
}
