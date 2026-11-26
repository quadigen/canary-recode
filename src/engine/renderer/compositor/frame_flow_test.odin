package compositor

import "core:testing"

Flow_Test :: struct {
	steps: [8]Frame_Step,
	count: int,
	fail:  int,
}

flow_test_step :: proc "c" (user: rawptr, phase: u32) -> i32 {
	state := cast(^Flow_Test)user
	if state.count >= len(state.steps) {return 0}
	state.steps[state.count] = Frame_Step(phase)
	state.count += 1
	return i32(state.count != state.fail)
}

@(test)
frame_flow_orders_stages_and_stops_on_failure :: proc(t: ^testing.T) {
	state: Flow_Test
	testing.expect(t, frame_flow_callback(&state, flow_test_step, 0) == 1)
	testing.expect(t, state.count == 4)
	testing.expect(t, state.steps[0] == .Acquire && state.steps[3] == .Publish)
	testing.expect(t, frame_flow_callback(&state, flow_test_step, 1) == 1)
	testing.expect(t, state.count == 8)
	testing.expect(
		t,
		state.steps[4] == .Flush &&
		state.steps[5] == .Late_Acquire &&
		state.steps[6] == .Submit &&
		state.steps[7] == .Present,
	)
	state = {
		fail = 2,
	}
	testing.expect(t, frame_flow_callback(&state, flow_test_step, 0) == 0)
	testing.expect(t, state.count == 2 && state.steps[1] == .Claim)
	state = {
		fail = 3,
	}
	testing.expect(t, frame_flow_callback(&state, flow_test_step, 1) == 0)
	testing.expect(t, state.count == 3 && state.steps[2] == .Submit)
	testing.expect(t, frame_flow_callback(&state, flow_test_step, 2) == 0)
}
