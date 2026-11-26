package compositor

import "core:sync"
import "core:thread"
import "core:time"
import vk "vendor:vulkan"

Present_Job :: struct {
	swapchain: vk.SwapchainKHR,
	semaphore: vk.Semaphore,
	image:     u32,
}

Present_State :: struct {
	queue:        vk.Queue,
	present_proc: vk.ProcQueuePresentKHR,
	worker:       ^thread.Thread,
	mutex:        sync.Mutex,
	condition:    sync.Cond,
	job:          Present_Job,
	pending:      bool,
	outstanding:  bool,
	stopping:     bool,
	result:       vk.Result,
	last_call_ns: u64,
	completed:    u64,
}

present_call :: proc(state: ^Present_State, value: Present_Job) -> vk.Result {
	job := value
	info := vk.PresentInfoKHR {
		sType          = .PRESENT_INFO_KHR,
		swapchainCount = 1,
		pSwapchains    = &job.swapchain,
		pImageIndices  = &job.image,
	}
	if job.semaphore != 0 {
		info.waitSemaphoreCount = 1
		info.pWaitSemaphores = &job.semaphore
	}
	return state.present_proc(state.queue, &info)
}

present_worker :: proc(t: ^thread.Thread) {
	state := cast(^Present_State)t.data
	sync.mutex_lock(&state.mutex)
	defer sync.mutex_unlock(&state.mutex)
	for {
		for !state.pending && !state.stopping {
			sync.cond_wait(&state.condition, &state.mutex)
		}
		if !state.pending && state.stopping {return}
		job := state.job
		sync.mutex_unlock(&state.mutex)
		started := time.tick_now()
		result := present_call(state, job)
		elapsed := u64(max(0, time.duration_nanoseconds(time.tick_since(started))))
		sync.mutex_lock(&state.mutex)
		state.result = result
		state.last_call_ns = elapsed
		state.completed += 1
		state.pending = false
		sync.cond_broadcast(&state.condition)
	}
}

present_start :: proc(state: ^Present_State, asynchronous: bool) -> bool {
	if state == nil || state.present_proc == nil || state.queue == nil {return false}
	if state.worker != nil {return false}
	state.stopping = false
	state.pending = false
	state.outstanding = false
	state.result = .SUCCESS
	if !asynchronous {return true}
	state.worker = thread.create(present_worker, name = "KinePresent")
	if state.worker == nil {return false}
	state.worker.data = state
	thread.start(state.worker)
	return true
}

present_submit :: proc(state: ^Present_State, job: Present_Job) -> vk.Result {
	if state == nil || state.present_proc == nil {return .ERROR_INITIALIZATION_FAILED}
	if state.worker == nil {
		started := time.tick_now()
		result := present_call(state, job)
		state.last_call_ns = u64(max(0, time.duration_nanoseconds(time.tick_since(started))))
		state.completed += 1
		return result
	}
	sync.mutex_lock(&state.mutex)
	defer sync.mutex_unlock(&state.mutex)
	if state.outstanding || state.stopping {return .ERROR_INITIALIZATION_FAILED}
	state.job = job
	state.pending = true
	state.outstanding = true
	sync.cond_signal(&state.condition)
	return .SUCCESS
}

present_drain :: proc(state: ^Present_State, wait_ns: ^u64 = nil) -> vk.Result {
	if wait_ns != nil {wait_ns^ = 0}
	if state == nil {return .ERROR_INITIALIZATION_FAILED}
	if state.worker == nil {return .SUCCESS}
	started := time.tick_now()
	sync.mutex_lock(&state.mutex)
	defer sync.mutex_unlock(&state.mutex)
	for state.pending {
		sync.cond_wait(&state.condition, &state.mutex)
	}
	result := state.result
	state.result = .SUCCESS
	state.outstanding = false
	if wait_ns != nil {
		wait_ns^ = u64(max(0, time.duration_nanoseconds(time.tick_since(started))))
	}
	return result
}

present_latest :: proc(state: ^Present_State) -> (completed, call_ns: u64) {
	if state == nil {return 0, 0}
	if state.worker != nil {
		sync.mutex_lock(&state.mutex)
		defer sync.mutex_unlock(&state.mutex)
		return state.completed, state.last_call_ns
	}
	return state.completed, state.last_call_ns
}

present_stop :: proc(state: ^Present_State) {
	if state == nil || state.worker == nil {return}
	sync.mutex_lock(&state.mutex)
	state.stopping = true
	sync.cond_broadcast(&state.condition)
	sync.mutex_unlock(&state.mutex)
	thread.join(state.worker)
	thread.destroy(state.worker)
	state.worker = nil
}
