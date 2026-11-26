#+build !js
package compositor

import "core:testing"
import vk "vendor:vulkan"

Mock_Present :: struct {
	calls:  int,
	job:    Present_Job,
	queue:  vk.Queue,
	result: vk.Result,
	valid:  bool,
}

mock_queue_present :: proc "system" (queue: vk.Queue, info: ^vk.PresentInfoKHR) -> vk.Result {
	mock_present := cast(^Mock_Present)queue
	mock_present.calls += 1
	mock_present.queue = queue
	mock_present.valid =
		info.sType == .PRESENT_INFO_KHR &&
		info.swapchainCount == 1 &&
		info.pSwapchains != nil &&
		info.pImageIndices != nil &&
		info.waitSemaphoreCount <= 1 &&
		(info.waitSemaphoreCount == 0 || info.pWaitSemaphores != nil)
	mock_present.job = {info.pSwapchains[0], 0, info.pImageIndices[0]}
	if info.waitSemaphoreCount == 1 {mock_present.job.semaphore = info.pWaitSemaphores[0]}
	return mock_present.result
}

@(test)
presentation_dispatch_preserves_job_and_result :: proc(t: ^testing.T) {
	mock_present := Mock_Present {
		result = .ERROR_OUT_OF_DATE_KHR,
	}
	queue := cast(vk.Queue)&mock_present
	job := Present_Job{vk.SwapchainKHR(11), vk.Semaphore(22), 3}
	state := Present_State {
		queue        = queue,
		present_proc = mock_queue_present,
	}
	testing.expect(t, present_start(&state, false))
	testing.expect(t, present_submit(&state, job) == .ERROR_OUT_OF_DATE_KHR)
	testing.expect(
		t,
		mock_present.calls == 1 &&
		mock_present.job == job &&
		mock_present.queue == queue &&
		mock_present.valid,
	)
	mock_present.result = .SUCCESS
	job.semaphore = 0
	testing.expect(t, present_submit(&state, job) == .SUCCESS)
	testing.expect(t, mock_present.job == job && mock_present.valid)
	wait_ns: u64 = 99
	testing.expect(t, present_drain(&state, &wait_ns) == .SUCCESS && wait_ns == 0)
}

@(test)
presentation_worker_preserves_order_and_errors :: proc(t: ^testing.T) {
	mock_present := Mock_Present {
		result = .ERROR_OUT_OF_DATE_KHR,
	}
	state := Present_State {
		queue        = cast(vk.Queue)&mock_present,
		present_proc = mock_queue_present,
	}
	if !present_start(&state, true) {
		testing.expect(t, false, "worker startup failed")
		return
	}
	defer present_stop(&state)
	job := Present_Job{vk.SwapchainKHR(33), vk.Semaphore(44), 1}
	testing.expect(t, present_submit(&state, job) == .SUCCESS)
	testing.expect(t, present_submit(&state, job) == .ERROR_INITIALIZATION_FAILED)
	testing.expect(t, present_drain(&state) == .ERROR_OUT_OF_DATE_KHR)
	testing.expect(t, mock_present.calls == 1 && mock_present.job == job && mock_present.valid)
	testing.expect(t, present_drain(&state) == .SUCCESS)
	mock_present.result = .SUCCESS
	for i in 0 ..< 64 {
		job.image = u32(i % 3)
		testing.expect(t, present_submit(&state, job) == .SUCCESS)
		testing.expect(t, present_drain(&state) == .SUCCESS)
		testing.expect(t, mock_present.job == job)
	}
	testing.expect(t, mock_present.calls == 65)
	present_stop(&state)
	testing.expect(t, state.worker == nil)
	testing.expect(t, present_start(&state, true))
	testing.expect(t, present_submit(&state, job) == .SUCCESS)
	present_stop(&state)
	testing.expect(t, mock_present.calls == 66 && state.worker == nil)
}
