package compositor

import kineffi "../../bindings"
import "base:runtime"
import "core:sync"

Registry :: struct {
	mutex:    sync.Mutex,
	backends: map[u32]kineffi.KineVulkanSwapchainBackend,
}

registry: Registry

valid_backend :: proc(backend: ^kineffi.KineVulkanSwapchainBackend) -> bool {
	return backend != nil &&
		backend.create != nil &&
		backend.destroy != nil &&
		backend.create_frame != nil &&
		backend.destroy_frame != nil &&
		backend.record_transition != nil &&
		backend.submit != nil &&
		backend.wrap_surface != nil &&
		backend.next_slot != nil &&
		backend.create_root != nil &&
		backend.destroy_root != nil &&
		backend.create_sync != nil &&
		backend.destroy_sync != nil &&
		backend.create_color != nil &&
		backend.destroy_color != nil &&
		backend.copy_color != nil &&
		backend.release_surface != nil &&
		backend.flush_surface != nil &&
		backend.wait_surface != nil &&
		backend.retire_fence != nil &&
		backend.create_depth != nil &&
		backend.create_surface != nil &&
		backend.destroy_surface != nil &&
		backend.destroy_device != nil &&
		backend.destroy_instance != nil &&
		backend.select_ready != nil &&
		backend.submit_copy != nil &&
		backend.create_provider != nil &&
		backend.destroy_provider != nil &&
		backend.provider_action != nil &&
		backend.frame_flow != nil
}

@(export)
Kine_VulkanCompositor_RegisterSwapchainBackend :: proc "c" (
	window_id: u32,
	backend: ^kineffi.KineVulkanSwapchainBackend,
) -> i32 {
	context = runtime.default_context()
	if window_id == 0 || (backend != nil && !valid_backend(backend)) {return 0}
	sync.mutex_lock(&registry.mutex)
	defer sync.mutex_unlock(&registry.mutex)
	if backend == nil {
		if registry.backends != nil {delete_key(&registry.backends, window_id)}
		return 1
	}
	if registry.backends == nil {
		registry.backends = make(map[u32]kineffi.KineVulkanSwapchainBackend)
	}
	registry.backends[window_id] = backend^
	return 1
}

@(export)
Kine_OdinCompositor_CopySwapchainBackend :: proc "c" (
	window_id: u32,
	output: ^kineffi.KineVulkanSwapchainBackend,
) -> i32 {
	context = runtime.default_context()
	if output == nil || window_id == 0 {return 0}
	output^ = {}
	sync.mutex_lock(&registry.mutex)
	defer sync.mutex_unlock(&registry.mutex)
	if registry.backends == nil {return 0}
	backend, ok := registry.backends[window_id]
	if !ok {return 0}
	output^ = backend
	return 1
}
