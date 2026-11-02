package kineffi

when ODIN_OS == .Windows {
	foreign import lib {"../../../vendor/build/lib/kine_vk.lib", "../../../vendor/build/lib/kine_vulkan_loader.lib"}
} else when #config(KINE_ANDROID, false) {
	foreign import lib "../../../build/android-native/lib/libkine_vulkan_compositor.a"
} else {
	foreign import lib "../../../vendor/build/lib/KinemiumLibs.a"
}

KineVulkanCompositor :: struct {}

KineVulkanCompositorInfo :: struct {
	instance:                 rawptr,
	surface:                  rawptr,
	physicalDevice:           rawptr,
	device:                   rawptr,
	graphicsQueue:            rawptr,
	swapchain:                rawptr,
	swapchainFormat:          u32,
	swapchainImageCount:      u32,
	graphicsQueueFamilyIndex: u32,
	graphicsQueueCount:       u32,
	width:                    u32,
	height:                   u32,
}

KineVulkanCompositorBackend :: struct {
	instance:                 rawptr,
	physicalDevice:           rawptr,
	device:                   rawptr,
	queue:                    rawptr,
	graphicsQueueFamilyIndex: u32,
	maxApiVersion:            u32,
	getInstanceProcAddr:      rawptr,
	getDeviceProcAddr:        rawptr,
}

@(default_calling_convention = "c")
foreign lib {
	Kine_VulkanCompositor_CreateForSDLWindow :: proc(sdlWindow: rawptr, width: i32, height: i32) -> ^KineVulkanCompositor ---
	Kine_VulkanCompositor_CreateForSDLWindowWithBackend :: proc(sdlWindow: rawptr, width: i32, height: i32, backend: ^KineVulkanCompositorBackend) -> ^KineVulkanCompositor ---
	Kine_VulkanCompositor_Destroy :: proc(compositor: ^KineVulkanCompositor) ---
	Kine_VulkanCompositor_Resize :: proc(compositor: ^KineVulkanCompositor, width: i32, height: i32) -> i32 ---
	Kine_VulkanCompositor_IsReady :: proc(compositor: ^KineVulkanCompositor) -> i32 ---
	Kine_VulkanCompositor_NeedsResize :: proc(compositor: ^KineVulkanCompositor) -> i32 ---
	Kine_VulkanCompositor_GetLastError :: proc(compositor: ^KineVulkanCompositor) -> cstring ---
	Kine_VulkanCompositor_GetInfo :: proc(compositor: ^KineVulkanCompositor, outInfo: ^KineVulkanCompositorInfo) -> i32 ---


	Kine_VulkanCompositor_MeshTerrainChunk :: proc(compositor: ^KineVulkanCompositor, occ: [^]f32, mat: [^]u32, originX, originY, originZ: i32, voxelSize, isoLevel: f32, outVertices: [^]f32, outWeights: [^]f32, outIndices: [^]u32, vertexCapacity, indexCapacity: u32, outVertexCount, outIndexCount: ^u32) -> i32 ---


	Kine_VulkanCompositor_GetSkiaContext :: proc(compositor: ^KineVulkanCompositor) -> rawptr ---
	Kine_VulkanCompositor_GetCurrentSkiaSurface :: proc(compositor: ^KineVulkanCompositor) -> rawptr ---
	Kine_VulkanCompositor_GetSwapchainImages :: proc(compositor: ^KineVulkanCompositor, outImages: ^rawptr, maxImages: u32) -> u32 ---
	Kine_VulkanCompositor_GetDepthAttachment :: proc(compositor: ^KineVulkanCompositor, outImage: ^rawptr, outFormat: ^u32) -> u32 ---


	Kine_VulkanCompositor_PrepareFilament :: proc(compositor: ^KineVulkanCompositor) -> i32 ---
	Kine_VulkanCompositor_FilamentAcquire :: proc(compositor: ^KineVulkanCompositor, outImageIndex: ^u32, outImageReadySemaphore: ^rawptr) -> u32 ---
	Kine_VulkanCompositor_FilamentPresent :: proc(compositor: ^KineVulkanCompositor, imageIndex: u32, finishedDrawingSemaphore: rawptr) -> u32 ---


	Kine_VulkanCompositor_BeginFrame :: proc(compositor: ^KineVulkanCompositor) -> rawptr ---


	Kine_VulkanCompositor_BeginOverlay :: proc(compositor: ^KineVulkanCompositor) -> rawptr ---


	Kine_VulkanCompositor_EndFrame :: proc(compositor: ^KineVulkanCompositor) -> i32 ---
}
