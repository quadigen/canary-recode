package services

import "core:sync"
import "core:thread"

when ODIN_OS == .JS {
	Cloth_Physics_Workers :: struct {}
	physics_run_cloth_jobs :: proc(service: ^Physics) {
		for job in service.cloth_jobs {physics_step_cloth(job)}
	}
	physics_stop_cloth_workers :: proc(service: ^Physics) {}
} else {
	Cloth_Physics_Workers :: struct {
		worker: ^thread.Thread,
		ready, finished: sync.Sema,
		stopping: bool,
	}

	physics_cloth_worker :: proc(data: rawptr) {
		service := cast(^Physics)data
		state := &service.cloth_workers
		for {
			sync.wait(&state.ready)
			if state.stopping {return}
			for i := 1; i < len(service.cloth_jobs); i += 2 {
				physics_step_cloth(service.cloth_jobs[i])
			}
			sync.post(&state.finished, 1)
		}
	}

	physics_run_cloth_jobs :: proc(service: ^Physics) {
		if len(service.cloth_jobs) < 2 {
			for job in service.cloth_jobs {physics_step_cloth(job)}
			return
		}
		state := &service.cloth_workers
		if state.worker == nil {
			state.worker = thread.create_and_start_with_data(service, physics_cloth_worker)
		}
		if state.worker == nil {
			for job in service.cloth_jobs {physics_step_cloth(job)}
			return
		}
		// Attachment transforms and rigid contacts stay on the physics thread.
		// These jobs only read/write their own prepared cloth buffers.
		sync.post(&state.ready, 1)
		for i := 0; i < len(service.cloth_jobs); i += 2 {
			physics_step_cloth(service.cloth_jobs[i])
		}
		sync.wait(&state.finished)
	}

	physics_stop_cloth_workers :: proc(service: ^Physics) {
		state := &service.cloth_workers
		if state.worker == nil {return}
		state.stopping = true
		sync.post(&state.ready, 1)
		thread.join(state.worker)
		thread.destroy(state.worker)
	}
}
