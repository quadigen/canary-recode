#+build !js
package compositor

import kineffi "../../bindings"
import "core:testing"

@(test)
registry_rejects_incomplete_backends :: proc(t: ^testing.T) {
	id := u32(0xC0FFEE01)
	incomplete: kineffi.KineVulkanSwapchainBackend
	testing.expect(t, Kine_VulkanCompositor_RegisterSwapchainBackend(0, nil) == 0)
	testing.expect(t, Kine_VulkanCompositor_RegisterSwapchainBackend(id, &incomplete) == 0)
	backend: kineffi.KineVulkanSwapchainBackend
	testing.expect(t, Kine_OdinCompositor_CopySwapchainBackend(id, &backend) == 0)
}

@(test)
registry_retains_backends_until_explicit_unregistration :: proc(t: ^testing.T) {
	id := u32(0xC0FFEE02)
	testing.expect(t, register_swapchain(id))
	backend: kineffi.KineVulkanSwapchainBackend
	testing.expect(t, Kine_OdinCompositor_CopySwapchainBackend(id, &backend) == 1)
	testing.expect(t, valid_backend(&backend))
	unregister_swapchain(id)
	backend = {}
	testing.expect(t, Kine_OdinCompositor_CopySwapchainBackend(id, &backend) == 0)
	testing.expect(t, backend.create == nil)
}
