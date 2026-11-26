package services

import classes "../classes"
import enums "../enum"
import sdl3 "../platform"
import signals "../signals"
import vm "../vm"

when ODIN_OS != .JS {
	gamepad_slot :: proc(service: ^UserInputService, id: u32, create: bool = false) -> int {
		if id == 0 {return -1}
		for existing, i in service.gamepad_ids {if existing == id {return i}}
		if create {
			for existing, i in service.gamepad_ids {
				if existing ==
				   0 {service.gamepad_ids[i] = id; service.gamepad_enabled = true; return i}
			}
		}
		return -1
	}

	gamepad_button_key :: proc(button: u8) -> enums.KeyCode {
		switch button {
		case 0:
			return .ButtonA
		case 1:
			return .ButtonB
		case 2:
			return .ButtonX
		case 3:
			return .ButtonY
		case 4:
			return .ButtonSelect
		case 6:
			return .ButtonStart
		case 7:
			return .ButtonL3
		case 8:
			return .ButtonR3
		case 9:
			return .ButtonL1
		case 10:
			return .ButtonR1
		case 11:
			return .DPadUp
		case 12:
			return .DPadDown
		case 13:
			return .DPadLeft
		case 14:
			return .DPadRight
		}
		return .None
	}

	gamepad_handle_event :: proc(
		service: ^UserInputService,
		L: ^vm.State,
		event: sdl3.Event,
	) -> bool {
		registry := service.signal_registry
		#partial switch event.type {
		case .GAMEPAD_ADDED:
			slot := gamepad_slot(service, u32(event.gdevice.which), true)
			if slot >= 0 &&
			   service.gamepad_connected != nil &&
			   registry != nil &&
			   registry.enums != nil {
				_ = enums.Push_Item_By_Value(
					L,
					registry.enums,
					"UserInputType",
					i64(enums.UserInputType.Gamepad1) + i64(slot),
				)
				signals.Fire(L, service.gamepad_connected, 1)
				vm.Pop(L)
			}
			return true
		case .GAMEPAD_REMOVED:
			id := u32(event.gdevice.which)
			slot := gamepad_slot(service, id)
			if slot >= 0 &&
			   service.gamepad_disconnected != nil &&
			   registry != nil &&
			   registry.enums != nil {
				_ = enums.Push_Item_By_Value(
					L,
					registry.enums,
					"UserInputType",
					i64(enums.UserInputType.Gamepad1) + i64(slot),
				)
				signals.Fire(L, service.gamepad_disconnected, 1)
				vm.Pop(L)
			}
			if slot >= 0 {
				service.gamepad_ids[slot] = 0
				service.gamepad_axes[slot] = {}
				service.gamepad_buttons[slot] = {}
				service.gamepad_direction[slot] = {}
			}
			classes.Gui_Gamepad_Disconnect(registry, id)
			service.gamepad_enabled = false
			for existing in service.gamepad_ids {if existing != 0 {service.gamepad_enabled = true; break}}
			if !service.gamepad_enabled {_ = classes.Gui_Set_Selected(registry, nil)}
			return true
		case .GAMEPAD_BUTTON_DOWN, .GAMEPAD_BUTTON_UP:
			id := u32(event.gbutton.which)
			slot := gamepad_slot(service, id, true)
			if slot < 0 {return true}
			input_type := enums.UserInputType(i64(enums.UserInputType.Gamepad1) + i64(slot))
			key := gamepad_button_key(event.gbutton.button)
			down := event.type == .GAMEPAD_BUTTON_DOWN
			button := int(event.gbutton.button)
			if button <
			   len(service.gamepad_buttons[slot]) {service.gamepad_buttons[slot][button] = down}
			service.last_input_type = input_type
			processed := false
			if !service.navigation_disabled[slot] && key == .ButtonA {
				processed = classes.Gui_Gamepad_Confirm(registry, L, id, input_type, down)
			} else if down && !service.navigation_disabled[slot] {
				#partial switch key {
				case .DPadUp:
					processed = classes.Gui_Navigate(registry, 0, -1)
				case .DPadDown:
					processed = classes.Gui_Navigate(registry, 0, 1)
				case .DPadLeft:
					processed = classes.Gui_Navigate(registry, -1, 0)
				case .DPadRight:
					processed = classes.Gui_Navigate(registry, 1, 0)
				case .ButtonB:
					processed = classes.Gui_Get_Selected(registry) != nil
					_ = classes.Gui_Set_Selected(registry, nil)
				}
			}
			if key != .None {
				user_input_fire(
					L,
					service,
					down ? service.input_began : service.input_ended,
					classes.InputObject_Value {
						UserInputType = input_type,
						KeyCode = key,
						UserInputState = down ? .Begin : .End,
					},
					processed,
				)
			}
			return true
		case .GAMEPAD_AXIS_MOTION:
			slot := gamepad_slot(service, u32(event.gaxis.which), true)
			axis := int(event.gaxis.axis)
			if slot < 0 || axis < 0 || axis >= 6 {return true}
			axes := &service.gamepad_axes[slot]
			old := axes[axis]
			axes[axis] = clamp(f32(event.gaxis.value) / 32767.0, -1, 1)
			input_type := enums.UserInputType(i64(enums.UserInputType.Gamepad1) + i64(slot))
			processed := false
			if axis < 2 && !service.navigation_disabled[slot] {
				x, y := axes[0], axes[1]
				direction: [2]i32
				if max(abs(x), abs(y)) >= 0.60 {
					if abs(x) >=
					   abs(
						   y,
					   ) {direction[0] = 1 if x > 0 else -1} else {direction[1] = 1 if y > 0 else -1}
				} else if max(abs(x), abs(y)) > 0.35 {
					direction = service.gamepad_direction[slot]
				}
				if direction != service.gamepad_direction[slot] {
					service.gamepad_direction[slot] = direction
					if direction[0] != 0 || direction[1] != 0 {
						processed = classes.Gui_Navigate(registry, direction[0], direction[1])
					}
				}
			}
			key: enums.KeyCode
			value := classes.InputObject_Value {
				UserInputType  = input_type,
				UserInputState = .Change,
			}
			switch axis {
			case 0, 1:
				key = .Thumbstick1; value.Position = {f64(axes[0]), f64(-axes[1]), 0}
			case 2, 3:
				key = .Thumbstick2; value.Position = {f64(axes[2]), f64(-axes[3]), 0}
			case 4, 5:
				key = .ButtonL2 if axis == 4 else .ButtonR2
				value.Position = {0, 0, f64(max(0, axes[axis]))}
			}
			value.KeyCode = key
			if axis <
			   4 {if axis % 2 == 0 {value.Delta.x = f64(axes[axis] - old)} else {value.Delta.y = f64(old - axes[axis])}} else {value.Delta.z = f64(axes[axis] - old)}
			if abs(axes[axis]) > 0.2 {service.last_input_type = input_type}
			user_input_fire(L, service, service.input_changed, value, processed)
			return true
		}
		return false
	}
}
