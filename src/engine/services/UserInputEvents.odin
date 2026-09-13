package services

import sdl3 "../platform"
import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import signals "../signals"
import vm "../vm"

user_input_key_code :: proc(scancode: sdl3.Scancode) -> enums.KeyCode {
	if scancode >= .A && scancode <= .Z {
		return enums.KeyCode(i64(enums.KeyCode.A)+i64(scancode)-i64(sdl3.Scancode.A))
	}
	if scancode >= .F1 && scancode <= .F12 {
		return enums.KeyCode(i64(enums.KeyCode.F1)+i64(scancode)-i64(sdl3.Scancode.F1))
	}
	#partial switch scancode {
	case ._0: return .Zero
	case ._1: return .One
	case ._2: return .Two
	case ._3: return .Three
	case ._4: return .Four
	case ._5: return .Five
	case ._6: return .Six
	case ._7: return .Seven
	case ._8: return .Eight
	case ._9: return .Nine
	case .SPACE: return .Space
	case .APOSTROPHE: return .Quote
	case .COMMA: return .Comma
	case .MINUS: return .Minus
	case .PERIOD: return .Period
	case .SLASH: return .Slash
	case .SEMICOLON: return .Semicolon
	case .EQUALS: return .Equals
	case .LEFTBRACKET: return .LeftBracket
	case .BACKSLASH: return .Backslash
	case .RIGHTBRACKET: return .RightBracket
	case .GRAVE: return .Grave
	case .ESCAPE: return .Escape
	case .RETURN: return .Return
	case .TAB: return .Tab
	case .BACKSPACE: return .Backspace
	case .INSERT: return .Insert
	case .DELETE: return .Delete
	case .RIGHT: return .Right
	case .LEFT: return .Left
	case .DOWN: return .Down
	case .UP: return .Up
	case .PAGEUP: return .PageUp
	case .PAGEDOWN: return .PageDown
	case .HOME: return .Home
	case .END: return .End
	case .CAPSLOCK: return .CapsLock
	case .SCROLLLOCK: return .ScrollLock
	case .NUMLOCKCLEAR: return .NumLock
	case .PRINTSCREEN: return .PrintScreen
	case .PAUSE: return .Pause
	case .KP_0: return .ZeroPad
	case .KP_1: return .OnePad
	case .KP_2: return .TwoPad
	case .KP_3: return .ThreePad
	case .KP_4: return .FourPad
	case .KP_5: return .FivePad
	case .KP_6: return .SixPad
	case .KP_7: return .SevenPad
	case .KP_8: return .EightPad
	case .KP_9: return .NinePad
	case .KP_PERIOD: return .Decimal
	case .KP_DIVIDE: return .Divide
	case .KP_MULTIPLY: return .Multiply
	case .KP_MINUS: return .Subtract
	case .KP_PLUS: return .Add
	case .KP_ENTER: return .KeypadEnter
	case .KP_EQUALS: return .KeypadEquals
	case .LSHIFT: return .LeftShift
	case .LCTRL: return .LeftControl
	case .LALT: return .LeftAlt
	case .LGUI: return .LeftSuper
	case .RSHIFT: return .RightShift
	case .RCTRL: return .RightControl
	case .RALT: return .RightAlt
	case .RGUI: return .RightSuper
	case .APPLICATION: return .Apps
	case .VOLUMEUP: return .VolumeUp
	case .VOLUMEDOWN: return .VolumeDown
	case: return .None
	}
}

user_input_mouse_type :: proc(button: u8) -> enums.UserInputType {
	switch button {
	case sdl3.BUTTON_LEFT: return .MouseButton1
	case sdl3.BUTTON_RIGHT: return .MouseButton2
	case sdl3.BUTTON_MIDDLE: return .MouseButton3
	case: return .None
	}
}

user_input_mouse_index :: proc(input_type: enums.UserInputType) -> int {
	#partial switch input_type {
	case .MouseButton1: return 0
	case .MouseButton2: return 1
	case .MouseButton3: return 2
	case: return -1
	}
}

user_input_key_index :: proc(service: ^UserInputService, key_code: enums.KeyCode) -> int {
	for existing, i in service.keys_down { if existing == key_code { return i } }
	return -1
}

user_input_fire :: proc(L: ^vm.State, service: ^UserInputService, signal: ^signals.Signal, value: classes.InputObject_Value) {
	if signal == nil || service.class_registry == nil { return }
	if classes.Push_InputObject(L, service.class_registry, value) == nil { return }
	vm.PushBoolean(L, false)
	signals.Fire(L, signal, 2)
	vm.Pop(L, 2)
}

user_input_service_step :: proc(service: ^UserInputService, L: ^vm.State, event: sdl3.Event) {
	if service == nil || L == nil { return }
	#partial switch event.type {
	case .KEY_DOWN:
		if event.key.repeat { return }
		key_code := user_input_key_code(event.key.scancode)
		if user_input_key_index(service, key_code) < 0 { append(&service.keys_down, key_code) }
		service.last_input_type = .Keyboard
		user_input_fire(L, service, service.input_began, classes.InputObject_Value{
			UserInputType = .Keyboard,
			UserInputState = .Begin,
			KeyCode = key_code,
		})
	case .KEY_UP:
		key_code := user_input_key_code(event.key.scancode)
		index := user_input_key_index(service, key_code)
		if index >= 0 { ordered_remove(&service.keys_down, index) }
		service.last_input_type = .Keyboard
		user_input_fire(L, service, service.input_ended, classes.InputObject_Value{
			UserInputType = .Keyboard,
			UserInputState = .End,
			KeyCode = key_code,
		})
	case .MOUSE_BUTTON_DOWN, .MOUSE_BUTTON_UP:
		input_type := user_input_mouse_type(event.button.button)
		index := user_input_mouse_index(input_type)
		if index < 0 { return }
		is_down := event.type == .MOUSE_BUTTON_DOWN
		service.mouse_down[index] = is_down
		service.mouse_location = {event.button.x, event.button.y}
		service.last_input_type = input_type
		user_input_fire(L, service, is_down ? service.input_began : service.input_ended, classes.InputObject_Value{
			UserInputType = input_type,
			UserInputState = is_down ? .Begin : .End,
			Position = {event.button.x, event.button.y, 0},
		})
	case .MOUSE_MOTION:
		delta := datatypes.Vector2{event.motion.xrel*service.mouse_delta_sensitivity, event.motion.yrel*service.mouse_delta_sensitivity}
		service.mouse_location = {event.motion.x, event.motion.y}
		service.pending_mouse_delta = datatypes.Vec2_Add(service.pending_mouse_delta, delta)
		service.last_input_type = .MouseMovement
		user_input_fire(L, service, service.input_changed, classes.InputObject_Value{
			UserInputType = .MouseMovement,
			UserInputState = .Change,
			Position = {event.motion.x, event.motion.y, 0},
			Delta = {delta.X, delta.Y, 0},
		})
	case .MOUSE_WHEEL:
		service.mouse_location = {event.wheel.mouse_x, event.wheel.mouse_y}
		service.last_input_type = .MouseWheel
		user_input_fire(L, service, service.input_changed, classes.InputObject_Value{
			UserInputType = .MouseWheel,
			UserInputState = .Change,
			Position = {event.wheel.mouse_x, event.wheel.mouse_y, event.wheel.y},
			Delta = {event.wheel.x, 0, event.wheel.y},
		})
	}
}

User_Input_Begin_Frame :: proc(service: ^UserInputService) {
	if service == nil { return }
	service.frame_mouse_delta = service.pending_mouse_delta
	service.pending_mouse_delta = datatypes.Vector2_Zero
}
