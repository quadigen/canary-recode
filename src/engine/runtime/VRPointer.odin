package engine_runtime

import kineffi "../bindings"
import sdl3 "../platform"
import vm "../vm"

Environment_Update_VR_Pointer :: proc(
	environment: ^Environment,
	state: ^vm.VM,
	width, height: i32,
	active: bool,
) {
	when ODIN_OS == .Linux && !#config(KINE_ANDROID, false) {
		if environment == nil || state == nil || environment.renderer == nil {return}
		u, v, trigger: f32
		hand := environment.vr_pointer_hand if environment.vr_pointer_down else 1
		hit := false
		if active {
			hit = kineffi.Kine_Filament_XR_GetUIPointer(
				environment.renderer.Filament,
				hand,
				&u,
				&v,
				&trigger,
			)
			if !hit && !environment.vr_pointer_down {
				hand = 0
				hit = kineffi.Kine_Filament_XR_GetUIPointer(
					environment.renderer.Filament,
					hand,
					&u,
					&v,
					&trigger,
				)
			}
		}
		was_valid := environment.vr_pointer_valid
		environment.vr_pointer_valid = hit
		x := u * f32(width) if hit else -10000
		y := v * f32(height) if hit else -10000
		if hit || was_valid {
			event: sdl3.Event
			event.type = .MOUSE_MOTION
			event.motion.x = x
			event.motion.y = y
			if hit && was_valid {
				event.motion.xrel = x - environment.vr_pointer_x
				event.motion.yrel = y - environment.vr_pointer_y
			}
			Environment_SetEvent(environment, state, event)
		}
		environment.vr_pointer_x = x
		environment.vr_pointer_y = y
		if trigger < 0.35 && hit {environment.vr_pointer_latched = false}
		if !hit && environment.vr_pointer_down {environment.vr_pointer_latched = true}
		down := hit && (trigger >= (0.35 if environment.vr_pointer_down else 0.65))
		if !environment.vr_pointer_down && environment.vr_pointer_latched {down = false}
		if down != environment.vr_pointer_down {
			environment.vr_pointer_down = down
			environment.vr_pointer_hand = hand
			event: sdl3.Event
			event.type = .MOUSE_BUTTON_DOWN if down else .MOUSE_BUTTON_UP
			event.button.button = sdl3.BUTTON_LEFT
			event.button.clicks = 1
			event.button.x = x
			event.button.y = y
			Environment_SetEvent(environment, state, event)
		}
	}
}
