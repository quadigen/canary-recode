package services

import sdl3 "../platform"
import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import signals "../signals"
import vm "../vm"

UserInputService_Class := classes.Class_Info{name = "UserInputService", parent = &Service_Class}

UserInputService :: struct {
	using service: Service,
	accelerometer_enabled: bool,
	keyboard_enabled:      bool,
	mouse_enabled:         bool,
	touch_enabled:         bool,
	gamepad_enabled:       bool,
	mouse_icon_enabled:    bool,
	mouse_behavior:        enums.MouseBehavior,
	mouse_delta_sensitivity: f32,
	last_input_type:       enums.UserInputType,
	keys_down:             [dynamic]enums.KeyCode,
	mouse_down:            [3]bool,
	mouse_location:        datatypes.Vector2,
	pending_mouse_delta:   datatypes.Vector2,
	frame_mouse_delta:     datatypes.Vector2,
	input_began:           ^signals.Signal,
	input_changed:         ^signals.Signal,
	input_ended:           ^signals.Signal,
	object_runtime:        ^classes.Registry,
}

user_input_service_construct :: proc(renderer: ^classes.Renderer_Object, data_model: rawptr) -> ^classes.Object {
	service := new(UserInputService)
	service.service = Service_Init(&UserInputService_Class, "UserInputService", data_model)
	service.keyboard_enabled = true
	service.mouse_enabled = true
	service.mouse_icon_enabled = true
	service.mouse_delta_sensitivity = 1
	model := cast(^DataModel)data_model
	if model != nil && model.registry != nil {
		service.signal_registry = model.registry.classes
		if model.registry.signal_registry != nil && model.registry.vm_state != nil {
			service.input_began = signals.Create(model.registry.signal_registry, model.registry.vm_state.L)
			service.input_changed = signals.Create(model.registry.signal_registry, model.registry.vm_state.L)
			service.input_ended = signals.Create(model.registry.signal_registry, model.registry.vm_state.L)
		}
	}
	return &service.object
}

user_input_service_get :: proc(L: ^vm.State, object: ^classes.Object, datatype_registry: ^datatypes.Registry, enum_registry: ^enums.Registry, key: string) -> bool {
	service := cast(^UserInputService)object
	switch key {
	case "AccelerometerEnabled": vm.PushBoolean(L, service.accelerometer_enabled)
	case "KeyboardEnabled": vm.PushBoolean(L, service.keyboard_enabled)
	case "MouseEnabled": vm.PushBoolean(L, service.mouse_enabled)
	case "TouchEnabled", "TouchScreenEnabled": vm.PushBoolean(L, service.touch_enabled)
	case "GamepadEnabled": vm.PushBoolean(L, service.gamepad_enabled)
	case "GyroscopeEnabled", "VREnabled", "OnScreenKeyboardVisible": vm.PushBoolean(L, false)
	case "MouseIconEnabled": vm.PushBoolean(L, service.mouse_icon_enabled)
	case "MouseDeltaSensitivity": vm.PushNumber(L, f64(service.mouse_delta_sensitivity))
	case "MouseBehavior":
		if enum_registry == nil { return false }
		_ = enums.Push_Item_By_Value(L, enum_registry, "MouseBehavior", i64(service.mouse_behavior))
	case "InputBegan": signals.Push(L, service.input_began)
	case "InputChanged": signals.Push(L, service.input_changed)
	case "InputEnded": signals.Push(L, service.input_ended)
	case "GetMouseLocation", "GetMouseDelta", "GetLastInputType", "IsKeyDown", "IsMouseButtonPressed", "GetKeysPressed", "GetMouseButtonsPressed":
		vm.PushUserdataMethod(L, key)
	case: return false
	}
	return true
}

user_input_service_set :: proc(L: ^vm.State, object: ^classes.Object, datatype_registry: ^datatypes.Registry, enum_registry: ^enums.Registry, key: string, value_index: int) -> bool {
	service := cast(^UserInputService)object
	switch key {
	case "MouseIconEnabled":
		service.mouse_icon_enabled = vm.ArgBoolean(L, value_index)
		if service.mouse_icon_enabled {
			_ = sdl3.ShowCursor()
		} else {
			_ = sdl3.HideCursor()
		}
	case "MouseDeltaSensitivity": service.mouse_delta_sensitivity = clamp(f32(vm.ArgNumber(L, value_index)), 0, 10)
	case "MouseBehavior":
		if enum_registry == nil { return false }
		item := enums.Arg_Item(L, value_index, enum_registry, "MouseBehavior")
		service.mouse_behavior = enums.MouseBehavior(item.value)
		window := sdl3.GetKeyboardFocus()
		if window != nil {
			_ = sdl3.SetWindowRelativeMouseMode(window, service.mouse_behavior != .Default)
		}
	case: return false
	}
	return true
}

user_input_push_key :: proc(L: ^vm.State, service: ^UserInputService, key_code: enums.KeyCode) {
	_ = classes.Push_InputObject(L, service.signal_registry, classes.InputObject_Value{
		UserInputType = .Keyboard,
		UserInputState = .Begin,
		KeyCode = key_code,
	})
}

user_input_push_mouse_button :: proc(L: ^vm.State, service: ^UserInputService, input_type: enums.UserInputType) {
	_ = classes.Push_InputObject(L, service.signal_registry, classes.InputObject_Value{
		UserInputType = input_type,
		UserInputState = .Begin,
		Position = {service.mouse_location.X, service.mouse_location.Y, 0},
	})
}

user_input_service_namecall :: proc(L: ^vm.State, object: ^classes.Object, datatype_registry: ^datatypes.Registry, enum_registry: ^enums.Registry, method: string) -> (i32, bool) {
	service := cast(^UserInputService)object
	switch method {
	case "GetMouseLocation":
		datatypes.Push_Vector2(L, datatype_registry, service.mouse_location)
		return 1, true
	case "GetMouseDelta":
		datatypes.Push_Vector2(L, datatype_registry, service.frame_mouse_delta)
		return 1, true
	case "GetLastInputType":
		_ = enums.Push_Item_By_Value(L, enum_registry, "UserInputType", i64(service.last_input_type))
		return 1, true
	case "IsKeyDown":
		item := enums.Arg_Item(L, 2, enum_registry, "KeyCode")
		down := false
		for key_code in service.keys_down { if key_code == enums.KeyCode(item.value) { down = true; break } }
		vm.PushBoolean(L, down)
		return 1, true
	case "IsMouseButtonPressed":
		item := enums.Arg_Item(L, 2, enum_registry, "UserInputType")
		index := user_input_mouse_index(enums.UserInputType(item.value))
		vm.PushBoolean(L, index >= 0 && service.mouse_down[index])
		return 1, true
	case "GetKeysPressed":
		vm.NewTable(L, len(service.keys_down), 0)
		for key_code, i in service.keys_down {
			user_input_push_key(L, service, key_code)
			vm.SetArrayValue(L, -2, i+1)
		}
		return 1, true
	case "GetMouseButtonsPressed":
		vm.NewTable(L, 3, 0)
		count := 0
		button_types := [3]enums.UserInputType{.MouseButton1, .MouseButton2, .MouseButton3}
		for input_type, i in button_types {
			if !service.mouse_down[i] { continue }
			user_input_push_mouse_button(L, service, input_type)
			count += 1
			vm.SetArrayValue(L, -2, count)
		}
		return 1, true
	}
	return 0, false
}

user_input_service_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	classes.Object_Destroy(object)
	service := cast(^UserInputService)object
	delete(service.keys_down)
	free(service)
}

Register_UserInputService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&UserInputService_Class,
		user_input_service_construct,
		user_input_service_destroy,
		creatable = false,
		get = user_input_service_get,
		set = user_input_service_set,
		namecall = user_input_service_namecall,
	)
}
