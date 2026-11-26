package compositor

import "base:runtime"
import "core:sync"
import "core:time"

Provider_Action :: enum u32 {
	Active,
	Begin,
	Reset,
	Check_Prepare,
	Prepare,
	Acquire,
	Present,
	Wait_Overlay,
	Overlay,
	Wait_End,
	XR_Ready,
}

Provider_Phase :: enum u8 {
	Idle,
	Base,
	Prepared,
	Presented,
	Overlay,
}

Provider_State :: struct {
	mutex:      sync.Mutex,
	condition:  sync.Cond,
	phase:      Provider_Phase,
	image:      u32,
	semaphore:  u64,
	generation: u64,
}

create_provider_callback :: proc "c" () -> rawptr {
	context = runtime.default_context()
	state := new(Provider_State)
	if state != nil {state.image = max(u32)}
	return state
}

destroy_provider_callback :: proc "c" (user: rawptr) {
	context = runtime.default_context()
	if user != nil {free(cast(^Provider_State)user)}
}

provider_action_callback :: proc "c" (
	user: rawptr,
	action, image: u32,
	semaphore: u64,
	out_image: ^u32,
	out_semaphore: ^u64,
) -> i32 {
	context = runtime.default_context()
	if user == nil || action > u32(Provider_Action.XR_Ready) {return 0}
	return provider_action(
		cast(^Provider_State)user,
		Provider_Action(action),
		image,
		semaphore,
		out_image,
		out_semaphore,
	)
}

provider_action :: proc(
	state: ^Provider_State,
	action: Provider_Action,
	image := max(u32),
	semaphore: u64 = 0,
	out_image: ^u32 = nil,
	out_semaphore: ^u64 = nil,
	timeout := 5 * time.Second,
) -> i32 {
	if state == nil {return 0}
	sync.mutex_lock(&state.mutex)
	defer sync.mutex_unlock(&state.mutex)
	if out_semaphore != nil {out_semaphore^ = 0}
	switch action {
	case .Active:
		return i32(state.phase != .Idle)
	case .Begin:
		if state.phase != .Idle || image == max(u32) {return 0}
		state.generation += 1
		state.phase = .Base
		state.image = image
		state.semaphore = 0
	case .Reset:
		state.phase = .Idle
		state.image = max(u32)
		state.semaphore = 0
		state.generation += 1
		sync.cond_broadcast(&state.condition)
	case .Check_Prepare:
		if state.phase == .Idle {return 0}
		return 1 if state.phase == .Base else 2
	case .Prepare:
		if state.phase != .Base {return 0}
		state.phase = .Prepared
	case .Acquire:
		if state.phase != .Prepared {return 0}
		if out_image != nil {out_image^ = state.image}
	case .Present:
		if state.phase != .Prepared || image != state.image {return 0}
		state.semaphore = semaphore
		state.phase = .Presented
		sync.cond_broadcast(&state.condition)
	case .Wait_Overlay, .Wait_End:
		if state.phase == .Idle {return 0}
		if state.phase == .Base || state.phase == .Overlay {return 2}
		generation := state.generation
		started := time.tick_now()
		for state.phase == .Prepared && state.generation == generation {
			remaining := timeout - time.tick_since(started)
			if remaining <= 0 {return -1}
			if !sync.cond_wait_with_timeout(&state.condition, &state.mutex, remaining) &&
			   state.phase == .Prepared {return -1}
		}
		if state.generation != generation || state.phase != .Presented {return 0}
		if out_semaphore != nil {out_semaphore^ = state.semaphore}
	case .Overlay:
		if state.phase != .Base && state.phase != .Presented && state.phase != .Overlay {return 0}
		state.phase = .Overlay
		state.semaphore = 0
	case .XR_Ready:
		return i32(state.phase == .Base || state.phase == .Overlay)
	}
	return 1
}
