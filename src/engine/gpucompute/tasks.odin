#+build linux, windows
package gpucompute

import vk "vendor:vulkan"


Task_Access_History :: struct {
	reads, writes: [MAX_COMPUTE_QUEUES]u64,
}
Task_Resource :: struct {
	id:    u32,
	write: bool,
}
Task_Resources :: struct {
	items: [MAX_CUSTOM_BUFFERS + MAX_CUSTOM_TEXTURES]Task_Resource,
	count: int,
}
Parallel_Task :: struct {
	id:         u32,
	lane:       u32,
	command:    vk.CommandBuffer,
	fence:      vk.Fence,
	pools:      [MAX_BATCH_DISPATCHES]vk.DescriptorPool,
	pool_count: u32,
	resources:  Task_Resources,
}
Parallel_State :: struct {
	queues:                    [MAX_COMPUTE_QUEUES]vk.Queue,
	timelines:                 [MAX_COMPUTE_QUEUES]vk.Semaphore,
	values:                    [MAX_COMPUTE_QUEUES]u64,
	loads:                     [MAX_COMPUTE_QUEUES]u32,
	tasks:                     [MAX_PARALLEL_TASKS]Parallel_Task,
	count, next_id, next_lane: u32,
	base:                      u64,
	join_pending:              bool,
}

parallel_init :: proc(device: ^Device) -> string {
	t := &device.parallel
	d := &device.procs
	type_info := vk.SemaphoreTypeCreateInfo {
		sType         = .SEMAPHORE_TYPE_CREATE_INFO,
		semaphoreType = .TIMELINE,
	}
	info := vk.SemaphoreCreateInfo {
		sType = .SEMAPHORE_CREATE_INFO,
		pNext = &type_info,
	}
	for i in 0 ..< device.capabilities.compute_queues {
		if d.CreateSemaphore(device.handle, &info, nil, &t.timelines[i]) != .SUCCESS {
			return "could not create GPUCompute timeline semaphores"
		}
	}
	return ""
}

parallel_cpu_idle :: proc(device: ^Device) -> string {
	if device.custom.recording {return "GPUCompute commands are recording; submit or cancel first"}
	return custom_bind_idle(device)
}

task_add_resource :: proc(resources: ^Task_Resources, id: u32, write: bool) {
	for &r in resources.items[:resources.count] {
		if r.id == id {r.write = r.write || write; return}
	}

	assert(resources.count < len(resources.items))
	resources.items[resources.count] = {id, write}
	resources.count += 1
}

task_resource_busy :: proc(device: ^Device, id: u32) -> bool {
	for &task in device.parallel.tasks {
		if task.id == 0 {continue}
		for r in task.resources.items[:task.resources.count] {
			if r.id == id {return true}
		}
	}
	return false
}

task_history :: proc(device: ^Device, id: u32) -> ^Task_Access_History {
	if b := custom_get_buffer(device, id); b != nil {return &b.history}
	if t := texture_find(device, id); t != nil {return &t.history}
	return nil
}

task_free :: proc(device: ^Device, task: ^Parallel_Task) {
	d := &device.procs
	h := device.handle
	if task.command != nil {d.FreeCommandBuffers(h, device.commands, 1, &task.command)}
	for pool in task.pools[:task.pool_count] {if pool != 0 {d.DestroyDescriptorPool(h, pool, nil)}}
	if task.fence != 0 {d.DestroyFence(h, task.fence, nil)}
	task^ = {}
}

parallel_close :: proc(device: ^Device) {
	p := &device.parallel

	if p.count != 0 ||
	   p.base != 0 ||
	   p.join_pending {_ = device.procs.DeviceWaitIdle(device.handle)}
	for &task in p.tasks {if task.id != 0 {task_free(device, &task)}}
	for semaphore in p.timelines {if semaphore != 0 {device.procs.DestroySemaphore(device.handle, semaphore, nil)}}
	p^ = {}
}

pending_task_count :: proc(device: ^Device) -> u32 {return device.parallel.count}

begin_task :: proc(device: ^Device) -> string {
	if reason := custom_bind_idle(device); reason != "" {return reason}
	c := &device.custom
	if c.recording {return "GPUCompute commands are already recording"}
	if device.parallel.count >=
	   MAX_PARALLEL_TASKS {return "GPUCompute task limit reached; poll completed tasks"}
	if reason := open(device); reason != "" {return reason}
	if reason := command_begin(device); reason != "" {custom_clear_job(device); return reason}
	c.recording = true
	c.parallel_recording = true
	c.task_resources = {}
	return ""
}

submit_task :: proc(device: ^Device, x, y, z: u32) -> (u32, string) {
	if reason := begin_task(device); reason != "" {return 0, reason}
	if reason := dispatch_shader(device, x, y, z);
	   reason != "" {custom_clear_job(device); return 0, reason}
	id, reason := submit_task_batch(device)
	if reason != "" && device.custom.parallel_recording {custom_clear_job(device)}
	return id, reason
}


parallel_begin_epoch :: proc(device: ^Device) -> string {
	p := &device.parallel
	if device.capabilities.compute_queues <= 1 || p.base != 0 {return ""}
	if p.values[0] == max(u64) {return "GPUCompute timeline exhausted"}
	value := p.values[0] + 1
	timeline := vk.TimelineSemaphoreSubmitInfo {
		sType                     = .TIMELINE_SEMAPHORE_SUBMIT_INFO,
		signalSemaphoreValueCount = 1,
		pSignalSemaphoreValues    = &value,
	}
	submit := vk.SubmitInfo {
		sType                = .SUBMIT_INFO,
		pNext                = &timeline,
		signalSemaphoreCount = 1,
		pSignalSemaphores    = &p.timelines[0],
	}
	if device.procs.QueueSubmit(device.queue, 1, &submit, 0) !=
	   .SUCCESS {return "could not start GPUCompute task epoch"}
	p.values[0], p.base = value, value
	return ""
}


parallel_end_epoch :: proc(device: ^Device) -> string {
	p := &device.parallel
	if p.base != 0 {
		semaphores: [MAX_COMPUTE_QUEUES]vk.Semaphore
		values: [MAX_COMPUTE_QUEUES]u64
		stages: [MAX_COMPUTE_QUEUES]vk.PipelineStageFlags
		n: u32
		for i in 0 ..< device.capabilities.compute_queues {
			if p.values[i] == 0 {continue}
			semaphores[n], values[n], stages[n] = p.timelines[i], p.values[i], {.ALL_COMMANDS}
			n += 1
		}
		t := vk.TimelineSemaphoreSubmitInfo {
			sType                   = .TIMELINE_SEMAPHORE_SUBMIT_INFO,
			waitSemaphoreValueCount = n,
			pWaitSemaphoreValues    = &values[0],
		}
		info := vk.SubmitInfo {
			sType              = .SUBMIT_INFO,
			pNext              = &t,
			waitSemaphoreCount = n,
			pWaitSemaphores    = &semaphores[0],
			pWaitDstStageMask  = &stages[0],
		}
		if device.procs.QueueSubmit(device.queue, 1, &info, 0) !=
		   .SUCCESS {return "could not join GPUCompute queues"}
		p.join_pending = true
		p.base = 0
	}
	for &b in device.custom.buffers {b.history = {}}
	for &t in device.custom.textures {t.history = {}}
	return ""
}

task_pick_lane :: proc(device: ^Device) -> u32 {
	p := &device.parallel
	n := device.capabilities.compute_queues
	best := p.next_lane % n
	for i in 1 ..< n {
		lane := (p.next_lane + i) % n
		if p.loads[lane] < p.loads[best] {best = lane}
	}
	p.next_lane = (best + 1) % n
	return best
}

submit_task_batch :: proc(device: ^Device) -> (id: u32, err: string) {
	p := &device.parallel
	c := &device.custom
	if !c.parallel_recording {return 0, "no GPUCompute task batch; call BeginTask"}
	if c.batch_count == 0 {return 0, "GPUCompute task batch is empty"}
	if p.count >= MAX_PARALLEL_TASKS ||
	   p.next_id == max(u32) {return 0, "GPUCompute task limit reached"}
	slot: ^Parallel_Task
	for &task in p.tasks {if task.id == 0 {slot = &task; break}}
	if slot == nil {return 0, "GPUCompute task slots exhausted"}

	d := &device.procs
	h := device.handle
	lane := task_pick_lane(device)
	after := vk.MemoryBarrier {
		sType         = .MEMORY_BARRIER,
		srcAccessMask = {.SHADER_WRITE},
		dstAccessMask = {.HOST_READ},
	}
	d.CmdPipelineBarrier(c.command, {.COMPUTE_SHADER}, {.HOST}, {}, 1, &after, 0, nil, 0, nil)

	if d.EndCommandBuffer(c.command) !=
	   .SUCCESS {custom_clear_job(device); return 0, "could not end GPUCompute task"}
	fi := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
	}
	if d.CreateFence(h, &fi, nil, &c.fence) !=
	   .SUCCESS {custom_clear_job(device); return 0, "could not create GPUCompute task fence"}

	submit := vk.SubmitInfo {
		sType              = .SUBMIT_INFO,
		commandBufferCount = 1,
		pCommandBuffers    = &c.command,
	}
	timeline: vk.TimelineSemaphoreSubmitInfo
	semaphores: [MAX_COMPUTE_QUEUES]vk.Semaphore
	stages: [MAX_COMPUTE_QUEUES]vk.PipelineStageFlags
	wait_values: [MAX_COMPUTE_QUEUES]u64
	deps: [MAX_COMPUTE_QUEUES]u64
	signal: u64
	if device.capabilities.compute_queues > 1 {
		if reason := parallel_begin_epoch(device);
		   reason != "" {custom_clear_job(device); return 0, reason}


		deps[0] = p.base
		for r in c.task_resources.items[:c.task_resources.count] {
			hist := task_history(device, r.id)
			assert(hist != nil)
			for i in 0 ..< device.capabilities.compute_queues {
				deps[i] = max(deps[i], hist.writes[i])
				if r.write {deps[i] = max(deps[i], hist.reads[i])}
			}
		}
		n: u32
		for value, i in deps {
			if value == 0 {continue}
			semaphores[n], stages[n], wait_values[n] = p.timelines[i], {.ALL_COMMANDS}, value
			n += 1
		}
		if p.values[lane] == max(u64) {
			custom_clear_job(device)
			if p.count == 0 {
				if reason := parallel_end_epoch(device);
				   reason != "" {close(device); return 0, TASK_DEVICE_LOST}
			}
			return 0, "GPUCompute timeline exhausted"
		}
		signal = p.values[lane] + 1
		timeline = {
			sType                     = .TIMELINE_SEMAPHORE_SUBMIT_INFO,
			waitSemaphoreValueCount   = n,
			pWaitSemaphoreValues      = &wait_values[0],
			signalSemaphoreValueCount = 1,
			pSignalSemaphoreValues    = &signal,
		}
		submit.pNext = &timeline
		submit.waitSemaphoreCount = n
		submit.pWaitSemaphores = &semaphores[0]
		submit.pWaitDstStageMask = &stages[0]
		submit.signalSemaphoreCount = 1
		submit.pSignalSemaphores = &p.timelines[lane]
	}
	if d.QueueSubmit(p.queues[lane], 1, &submit, c.fence) != .SUCCESS {
		custom_clear_job(device)
		if p.count == 0 {
			if reason := parallel_end_epoch(device); reason != "" {
				close(device)
				return 0, TASK_DEVICE_LOST
			}
		}
		return 0, "could not submit GPUCompute task"
	}
	if signal != 0 {
		p.values[lane] = signal
		for r in c.task_resources.items[:c.task_resources.count] {
			hist := task_history(device, r.id)
			if r.write {
				hist.reads = {}
				hist.writes = {}
				hist.writes[lane] = signal
			} else {hist.reads[lane] = signal}
		}
	}
	p.next_id += 1
	slot^ = {
		id         = p.next_id,
		lane       = lane,
		command    = c.command,
		fence      = c.fence,
		pools      = c.batch_pools,
		pool_count = c.batch_count,
		resources  = c.task_resources,
	}
	p.count += 1
	p.loads[lane] += 1
	c.command = nil
	c.fence = 0
	c.batch_pools = {}
	c.batch_count = 0
	c.task_resources = {}
	c.recording = false
	c.parallel_recording = false
	return slot.id, ""
}

poll_task :: proc(device: ^Device, id: u32) -> (bool, string) {
	p := &device.parallel
	for &task in p.tasks {
		if task.id != id || id == 0 {continue}
		#partial switch device.procs.GetFenceStatus(device.handle, task.fence) {
		case .NOT_READY:
			return false, ""
		case .SUCCESS:
			p.loads[task.lane] -= 1
			p.count -= 1
			task_free(device, &task)
			if p.count == 0 {
				if reason := parallel_end_epoch(device); reason != "" {
					close(device)
					return false, TASK_DEVICE_LOST
				}
			}
			return true, ""
		case:
			close(device)
			return false, TASK_DEVICE_LOST
		}
	}
	return false, "unknown or already collected GPUCompute task"
}


get_task_info :: proc(device: ^Device, id: u32) -> (Task_Info, string) {
	if id == 0 {return {}, "invalid GPUCompute task ID"}
	for &task in device.parallel.tasks {
		if task.id != id {continue}
		#partial switch device.procs.GetFenceStatus(device.handle, task.fence) {
		case .SUCCESS:
			return {task.lane, task.pool_count, true}, ""
		case .NOT_READY:
			return {task.lane, task.pool_count, false}, ""
		case:
			return {}, "GPUCompute task fence failed; collect it with PollTask"
		}
	}
	return {}, "unknown or already collected GPUCompute task"
}
