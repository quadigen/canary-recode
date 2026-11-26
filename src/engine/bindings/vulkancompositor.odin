package kineffi

when ODIN_OS == .Windows {
	foreign import lib {"../../../vendor/build/lib/kine_vk.lib", "../../../vendor/build/lib/kine_vulkan_loader.lib"}
} else when #config(KINE_ANDROID, false) {
	foreign import lib "../../../build/android-native/lib/libkine_vulkan_compositor.a"
} else {
	foreign import lib "../../../vendor/build/lib/KinemiumLibs.a"
}

KineVulkanCompositor :: struct {}

KineVulkanSwapchainDispatch :: struct {
	physical_device:   rawptr,
	device:            rawptr,
	get_capabilities:  rawptr,
	get_formats:       rawptr,
	get_present_modes: rawptr,
	create:            rawptr,
	surface:           u64,
	width:             u32,
	height:            u32,
	mode_policy:       u32,
	image_override:    u32,
}

KineVulkanSwapchainResult :: struct {
	swapchain:        u64,
	width:            u32,
	height:           u32,
	format:           u32,
	color_space:      u32,
	usage:            u32,
	present_mode:     u32,
	requested_images: u32,
}

KineVulkanFrameResources :: struct {
	commands:     [5]rawptr,
	fence, query: u64,
}

KineVulkanFrameDispatch :: struct {
	device, get_device_proc:   rawptr,
	command_pool:              u64,
	timing, detail, offscreen: u32,
}

KineVulkanTransition :: struct {
	command:                          rawptr,
	image, query:                     u64,
	old_layout, new_layout, reusable: u32,
}

KineVulkanSwapchainBackend :: struct {
	create:            proc "c" (
		dispatch: ^KineVulkanSwapchainDispatch,
		result: ^KineVulkanSwapchainResult,
	) -> i32,
	destroy:           proc "c" (device, destroy_proc: rawptr, swapchain: u64),
	mode_policy:       u32,
	image_override:    u32,
	create_frame:      proc "c" (_: ^KineVulkanFrameDispatch, _: ^KineVulkanFrameResources) -> i32,
	destroy_frame:     proc "c" (_: ^KineVulkanFrameDispatch, _: ^KineVulkanFrameResources),
	record_transition: proc "c" (_: ^KineVulkanFrameDispatch, _: ^KineVulkanTransition) -> i32,
	submit:            proc "c" (
		_: ^KineVulkanFrameDispatch,
		_: rawptr,
		_: rawptr,
		_: u64,
		_: u64,
		_: u64,
	) -> i32,
	wrap_surface:      proc "c" (_: rawptr, _: rawptr, _: u32, _: u32, _: u32, _: u32) -> rawptr,
	next_slot:         proc "c" (_: u32, _: u32, _: ^u32) -> u32,
	create_root:       proc "c" (_: ^KineVulkanFrameDispatch, _: u32, _: ^u64, _: ^u64) -> i32,
	destroy_root:      proc "c" (_: ^KineVulkanFrameDispatch, _: u64, _: u64),
	create_sync:       proc "c" (_: ^KineVulkanFrameDispatch, _: ^u64, _: ^u64, _: ^u64) -> i32,
	destroy_sync:      proc "c" (_: ^KineVulkanFrameDispatch, _: u64, _: u64, _: u64),
	create_color:      proc "c" (
		_: ^KineVulkanFrameDispatch,
		_: rawptr,
		_: rawptr,
		_: rawptr,
		_: u32,
		_: u32,
		_: u32,
		_: ^u64,
		_: ^u64,
	) -> i32,
	destroy_color:     proc "c" (_: ^KineVulkanFrameDispatch, _: u64, _: u64),
	copy_color:        proc "c" (
		_: ^KineVulkanFrameDispatch,
		_: rawptr,
		_: u64,
		_: u64,
		_: u32,
		_: u32,
		_: u32,
		_: u32,
		_: u64,
	) -> i32,
	offscreen:         u32,
	release_surface:   proc "c" (_: rawptr),
	flush_surface:     proc "c" (_: rawptr) -> i32,
	wait_surface:      proc "c" (_: rawptr, _: rawptr) -> i32,
	retire_fence:      proc "c" (_: ^KineVulkanFrameDispatch, _: u64, _: u32) -> i32,
	create_depth:      proc "c" (
		_: ^KineVulkanFrameDispatch,
		_: rawptr,
		_: rawptr,
		_: rawptr,
		_: u32,
		_: u32,
		_: ^u64,
		_: ^u64,
		_: ^u32,
	) -> i32,
	create_surface:    proc "c" (_: rawptr, _: rawptr, _: ^u64) -> i32,
	destroy_surface:   proc "c" (_: rawptr, _: u64),
	destroy_device:    proc "c" (_: ^KineVulkanFrameDispatch),
	destroy_instance:  proc "c" (_: rawptr, _: rawptr),
	select_ready:      proc "c" (_: u32, _: u32, _: u32, _: ^u32) -> u32,
	submit_copy:       proc "c" (
		_: ^KineVulkanFrameDispatch,
		_: rawptr,
		_: rawptr,
		_: rawptr,
		_: rawptr,
		_: u64,
		_: u64,
		_: u64,
		_: u64,
		_: u64,
	) -> i32,
	create_provider:   proc "c" () -> rawptr,
	destroy_provider:  proc "c" (_: rawptr),
	provider_action:   proc "c" (_: rawptr, _: u32, _: u32, _: u64, _: ^u32, _: ^u64) -> i32,
	frame_flow:        proc "c" (_: rawptr, _: proc "c" (_: rawptr, _: u32) -> i32, _: u32) -> i32,
}

KineVulkanWsiDispatch :: struct {
	device:          rawptr,
	queue:           rawptr,
	acquire:         rawptr,
	present:         rawptr,
	dedicated_queue: u32,
}

KineVulkanWsiBackend :: struct {
	user:         rawptr,
	acquire:      proc "c" (
		user: rawptr,
		swapchain, timeout, semaphore, fence: u64,
		image: ^u32,
	) -> i32,
	present:      proc "c" (user: rawptr, swapchain, semaphore: u64, image: u32) -> i32,
	drain:        proc "c" (user: rawptr, wait_ns: ^u64) -> i32,
	asynchronous: u32,
}

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
	Kine_VulkanCompositor_RegisterSwapchainBackend :: proc(window_id: u32, backend: ^KineVulkanSwapchainBackend) -> i32 ---
	Kine_VulkanCompositor_IsOffscreen :: proc(compositor: ^KineVulkanCompositor) -> i32 ---
	Kine_VulkanCompositor_GetWsiDispatch :: proc(compositor: ^KineVulkanCompositor, out: ^KineVulkanWsiDispatch) -> i32 ---
	Kine_VulkanCompositor_SetWsiBackend :: proc(compositor: ^KineVulkanCompositor, backend: ^KineVulkanWsiBackend) -> i32 ---
	Kine_VulkanCompositor_CreateForSDLWindow :: proc(sdlWindow: rawptr, width: i32, height: i32) -> ^KineVulkanCompositor ---
	Kine_VulkanCompositor_CreateForSDLWindowWithBackend :: proc(sdlWindow: rawptr, width: i32, height: i32, backend: ^KineVulkanCompositorBackend) -> ^KineVulkanCompositor ---
	Kine_VulkanCompositor_Destroy :: proc(compositor: ^KineVulkanCompositor) ---
	Kine_VulkanCompositor_Resize :: proc(compositor: ^KineVulkanCompositor, width: i32, height: i32) -> i32 ---
	Kine_VulkanCompositor_IsReady :: proc(compositor: ^KineVulkanCompositor) -> i32 ---
	Kine_VulkanCompositor_UsesOdinBackend :: proc(compositor: ^KineVulkanCompositor) -> i32 ---
	Kine_VulkanCompositor_IsDeviceLost :: proc(compositor: ^KineVulkanCompositor) -> i32 ---
	Kine_VulkanCompositor_NeedsResize :: proc(compositor: ^KineVulkanCompositor) -> i32 ---
	Kine_VulkanCompositor_GetLastError :: proc(compositor: ^KineVulkanCompositor) -> cstring ---
	Kine_VulkanCompositor_WaitForQueueIdle :: proc(compositor: ^KineVulkanCompositor) -> i32 ---
	Kine_VulkanCompositor_GetInfo :: proc(compositor: ^KineVulkanCompositor, outInfo: ^KineVulkanCompositorInfo) -> i32 ---


	Kine_VulkanCompositor_MeshTerrainChunk :: proc(compositor: ^KineVulkanCompositor, occ: [^]f32, mat: [^]u32, originX, originY, originZ: i32, voxelSize, isoLevel: f32, outVertices: [^]f32, outWeights: [^]f32, outIndices: [^]u32, vertexCapacity, indexCapacity: u32, outVertexCount, outIndexCount: ^u32) -> i32 ---


	Kine_VulkanCompositor_GetSkiaContext :: proc(compositor: ^KineVulkanCompositor) -> rawptr ---
	Kine_VulkanCompositor_GetCurrentSkiaSurface :: proc(compositor: ^KineVulkanCompositor) -> rawptr ---
	Kine_VulkanCompositor_GetSwapchainImages :: proc(compositor: ^KineVulkanCompositor, outImages: ^rawptr, maxImages: u32) -> u32 ---
	Kine_VulkanCompositor_GetDepthAttachment :: proc(compositor: ^KineVulkanCompositor, outImage: ^rawptr, outFormat: ^u32) -> u32 ---


	Kine_VulkanCompositor_PrepareFilament :: proc(compositor: ^KineVulkanCompositor) -> i32 ---
	Kine_VulkanCompositor_FilamentAcquire :: proc(compositor: ^KineVulkanCompositor, outImageIndex: ^u32, outImageReadySemaphore: ^rawptr) -> u32 ---
	Kine_VulkanCompositor_FilamentPresent :: proc(compositor: ^KineVulkanCompositor, imageIndex: u32, finishedDrawingSemaphore: rawptr) -> u32 ---


	Kine_VulkanCompositor_SetFrameProfileCallback :: proc(compositor: ^KineVulkanCompositor, callback: proc "c" (user: rawptr, phase: cstring, begin: bool), user: rawptr) ---
	Kine_VulkanCompositor_BeginFrame :: proc(compositor: ^KineVulkanCompositor) -> rawptr ---


	Kine_VulkanCompositor_BeginOverlay :: proc(compositor: ^KineVulkanCompositor) -> rawptr ---


	Kine_VulkanCompositor_GetLatestQueueDetail :: proc(compositor: ^KineVulkanCompositor, serial, filament, overlay: ^u64) -> i32 ---
	Kine_VulkanCompositor_GetLatestQueueStages :: proc(compositor: ^KineVulkanCompositor, serial, base, render: ^u64) -> i32 ---
	Kine_VulkanCompositor_GetLatestQueueTiming :: proc(compositor: ^KineVulkanCompositor, serial, ns: ^u64) -> i32 ---
	Kine_VulkanCompositor_GetPrefetchStats :: proc(compositor: ^KineVulkanCompositor, hits, misses: ^u64) ---
	Kine_VulkanCompositor_GetPresentWaitNs :: proc(compositor: ^KineVulkanCompositor) -> u64 ---
	Kine_VulkanCompositor_EndFrame :: proc(compositor: ^KineVulkanCompositor) -> i32 ---
}
