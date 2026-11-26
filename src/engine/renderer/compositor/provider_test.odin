#+build !js
package compositor

import "core:testing"
import "core:thread"
import "core:time"

@(test)
provider_frame_lifecycle :: proc(t: ^testing.T) {
	state: Provider_State
	index: u32
	semaphore: u64
	testing.expect(t, provider_action(&state, .Acquire, out_image = &index) == 0)
	testing.expect(t, provider_action(&state, .Begin, 2) == 1)
	testing.expect(t, provider_action(&state, .Begin, 3) == 0)
	testing.expect(t, provider_action(&state, .Check_Prepare) == 1)
	testing.expect(t, provider_action(&state, .Prepare) == 1)
	testing.expect(t, provider_action(&state, .Check_Prepare) == 2)
	testing.expect(t, provider_action(&state, .Acquire, out_image = &index) == 1 && index == 2)
	testing.expect(t, provider_action(&state, .Present, 3, 42) == 0)
	testing.expect(t, provider_action(&state, .Present, 2, 42) == 1)
	testing.expect(t, provider_action(&state, .Present, 2, 43) == 0)
	testing.expect(
		t,
		provider_action(&state, .Wait_Overlay, out_semaphore = &semaphore) == 1 && semaphore == 42,
	)
	testing.expect(t, provider_action(&state, .Overlay) == 1)
	testing.expect(
		t,
		provider_action(&state, .Wait_End, out_semaphore = &semaphore) == 2 && semaphore == 0,
	)
	testing.expect(t, provider_action(&state, .XR_Ready) == 1)
	testing.expect(t, provider_action(&state, .Reset) == 1)
	testing.expect(t, provider_action(&state, .Active) == 0)
	testing.expect(t, provider_action(&state, .Begin, 1) == 1)
	testing.expect(t, provider_action(&state, .Wait_Overlay) == 2)
	testing.expect(t, provider_action(&state, .Overlay) == 1)
	testing.expect(t, provider_action(&state, .Wait_End) == 2)
}

provider_publish :: proc(t: ^thread.Thread) {
	state := cast(^Provider_State)t.data
	time.sleep(2 * time.Millisecond)
	_ = provider_action(state, .Present, 1, 99)
}

@(test)
provider_waits_for_backend_and_times_out :: proc(t: ^testing.T) {
	state: Provider_State
	testing.expect(t, provider_action(&state, .Begin, 1) == 1)
	testing.expect(t, provider_action(&state, .Prepare) == 1)
	testing.expect(t, provider_action(&state, .Wait_End, timeout = time.Millisecond) == -1)
	worker := thread.create(provider_publish)
	testing.expect(t, worker != nil)
	if worker == nil {return}
	worker.data = &state
	thread.start(worker)
	semaphore: u64
	testing.expect(
		t,
		provider_action(&state, .Wait_End, out_semaphore = &semaphore, timeout = time.Second) == 1,
	)
	testing.expect(t, semaphore == 99)
	thread.join(worker)
	thread.destroy(worker)
}
