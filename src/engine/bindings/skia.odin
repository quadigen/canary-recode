package kineffi

when ODIN_OS == .JS {
	foreign import kine_skia "kinemium_skia"
} else when ODIN_OS == .Windows {
	foreign import kine_skia {
		"../../../vendor/build/lib/kine_skia.lib",
		"../../../vendor/build/lib/kine_skia_skiacore.lib",
		"../../../vendor/build/lib/kine_skia_svg.lib",
		"../../../vendor/build/lib/kine_skia_skshaper.lib",
		"../../../vendor/build/lib/kine_skia_skunicode_core.lib",
		"../../../vendor/build/lib/kine_skia_skunicode_icu.lib",
		"../../../vendor/build/lib/kine_vulkan_loader.lib",
		"system:advapi32.lib",
		"system:d2d1.lib",
		"system:dwrite.lib",
		"system:dxgi.lib",
		"system:gdi32.lib",
		"system:ole32.lib",
		"system:user32.lib",
	}
} else when #config(KINE_ANDROID, false) {
	foreign import kine_skia "../../../build/android-native/lib/kine_skia_component.a"
} else {
	foreign import kine_skia "../../../vendor/build/lib/KinemiumLibs.a"
}

KineSkiaSurface       :: struct {}
KineSkiaImage         :: struct {}
KineSkiaVulkanContext :: struct {}
KineSkiaRuntimeShader :: struct {}
KineSkiaTypeface :: struct {}

KineSkiaVulkanBackend :: struct {
	instance:                 rawptr, /* VkInstance */
	physicalDevice:           rawptr, /* VkPhysicalDevice */
	device:                   rawptr, /* VkDevice */
	queue:                    rawptr, /* VkQueue, must support graphics */
	graphicsQueueFamilyIndex: u32,
	maxApiVersion:            u32,    /* 0 = let Skia infer/default */
	getInstanceProcAddr:      rawptr, /* PFN_vkGetInstanceProcAddr */
	getDeviceProcAddr:        rawptr, /* PFN_vkGetDeviceProcAddr, optional */
}

KineSkiaVulkanImageInfo :: struct {
	image:              rawptr, /* VkImage owned by the engine */
	format:             u32,    /* VkFormat */
	imageLayout:        u32,    /* VkImageLayout at handoff to Skia */
	imageTiling:        u32,    /* VkImageTiling, usually VK_IMAGE_TILING_OPTIMAL */
	imageUsageFlags:    u32,    /* VkImageUsageFlags */
	sampleCount:        u32,    /* Vulkan sample count as integer, usually 1 */
	levelCount:         u32,    /* mip levels, usually 1 */
	currentQueueFamily: u32,    /* queue family owning image, or VK_QUEUE_FAMILY_IGNORED */
}

@(default_calling_convention="c")
foreign kine_skia {
	/* ---------------- Version ---------------- */
	Kine_Skia_GetVersion :: proc() -> cstring ---

	/* ---------------- Vulkan GPU context ----------------
	These entry points are enabled when kine_skia is built with KINE_SKIA_BACKEND=VULKAN.
	Skia does not own the Vulkan instance/device/queue; the engine must keep them
	alive until all Vulkan-backed KineSkiaSurface objects and the context are destroyed. */
	Kine_Skia_Vulkan_CreateContext  :: proc(backend: ^KineSkiaVulkanBackend) -> ^KineSkiaVulkanContext ---
	Kine_Skia_Vulkan_DestroyContext :: proc(_context: ^KineSkiaVulkanContext) ---

	/* ---------------- Surface lifecycle ---------------- */
	Kine_Skia_Surface_Create                   :: proc(width: i32, height: i32) -> ^KineSkiaSurface ---
	Kine_Skia_Surface_CreateVulkanRenderTarget :: proc(_context: ^KineSkiaVulkanContext, width: i32, height: i32, imageInfo: ^KineSkiaVulkanImageInfo) -> ^KineSkiaSurface ---
	Kine_Skia_Surface_Destroy                  :: proc(surface: ^KineSkiaSurface) ---
	Kine_Skia_Surface_GetWidth                 :: proc(surface: ^KineSkiaSurface) -> i32 ---
	Kine_Skia_Surface_GetHeight                :: proc(surface: ^KineSkiaSurface) -> i32 ---
	Kine_Skia_Surface_GetRowBytes              :: proc(surface: ^KineSkiaSurface) -> u32 ---
	Kine_Skia_Surface_GetPixels                :: proc(surface: ^KineSkiaSurface) -> rawptr ---
	Kine_Skia_Surface_Flush                    :: proc(surface: ^KineSkiaSurface) ---
	Kine_Skia_Surface_SetBackdropFromSurface   :: proc(surface: ^KineSkiaSurface, backdrop: ^KineSkiaSurface) ---
	Kine_Skia_Surface_ClearBackdrop            :: proc(surface: ^KineSkiaSurface) ---
	Kine_Skia_Typeface_LoadFromMemory :: proc(
		data: ^u8,
		size: uintptr,
	) -> ^KineSkiaTypeface ---

	Kine_Skia_Surface_DrawImageBlurredSized :: proc(
		surface: ^KineSkiaSurface,
		image: ^KineSkiaImage,
		x, y: f32,
		width, height: f32,
		blurSigma: f32,
		alpha: u8,
	) ---

	Kine_Skia_Surface_DrawTextBlurred :: proc(
		surface: ^KineSkiaSurface,
		text: cstring,
		x, y: f32,
		fontSize: f32,
		fontPath: cstring,
		blurSigma: f32,
		r, g, b, a: u8,
	) ---

	Kine_Skia_Surface_DrawTextBlurredTypeface :: proc(
		surface: ^KineSkiaSurface,
		text: cstring,
		x, y: f32,
		fontSize: f32,
		typeface: ^KineSkiaTypeface,
		blurSigma: f32,
		r, g, b, a: u8,
	) ---

	Kine_Skia_Typeface_LoadFromFile :: proc(
		path: cstring,
	) -> ^KineSkiaTypeface ---

	Kine_Skia_Typeface_Destroy :: proc(
		typeface: ^KineSkiaTypeface,
	) ---

	Kine_Skia_Surface_DrawTextTypeface :: proc(
		surface: ^KineSkiaSurface,
		text: cstring,
		x, y: f32,
		fontSize: f32,
		typeface: ^KineSkiaTypeface,
		r, g, b, a: u8,
	) ---

	Kine_Skia_Surface_DrawTextShadowTypeface :: proc(
		surface: ^KineSkiaSurface,
		text: cstring,
		x, y: f32,
		fontSize: f32,
		typeface: ^KineSkiaTypeface,

		offsetX: f32,
		offsetY: f32,
		blurSigma: f32,
		spread: f32,

		shadowR: u8,
		shadowG: u8,
		shadowB: u8,
		shadowA: u8,
	) ---

	Kine_Skia_Typeface_MeasureText :: proc(
		typeface: ^KineSkiaTypeface,
		text: cstring,
		fontSize: f32,
	) -> f32 ---

	Kine_Skia_Typeface_GetLineHeight :: proc(
		typeface: ^KineSkiaTypeface,
		fontSize: f32,
	) -> f32 ---

	Kine_Skia_Typeface_GetAscent :: proc(
		typeface: ^KineSkiaTypeface,
		fontSize: f32,
	) -> f32 ---

	/* Debug/readback helper: sample a single pixel back out of the surface */
	Kine_Skia_Surface_GetPixel :: proc(surface: ^KineSkiaSurface, x: i32, y: i32, outR: ^u8, outG: ^u8, outB: ^u8, outA: ^u8) ---

	/* ---------------- Clear ---------------- */
	Kine_Skia_Surface_Clear :: proc(surface: ^KineSkiaSurface, r: u8, g: u8, b: u8, a: u8) ---

	/* ---------------- Runtime SkSL shaders ---------------- */
	Kine_Skia_RuntimeShader_Create          :: proc(sksl: cstring) -> ^KineSkiaRuntimeShader ---
	Kine_Skia_RuntimeShader_Destroy         :: proc(shader: ^KineSkiaRuntimeShader) ---
	Kine_Skia_RuntimeShader_SetUniform      :: proc(shader: ^KineSkiaRuntimeShader, name: cstring, values: ^f32, valueCount: i32) -> i32 ---
	Kine_Skia_Surface_DrawRuntimeShaderRect :: proc(surface: ^KineSkiaSurface, shader: ^KineSkiaRuntimeShader, x: f32, y: f32, width: f32, height: f32) ---
	Kine_Skia_RuntimeShader_GetLastError    :: proc() -> cstring ---

	/* ---------------- Shapes ----------------
	strokeWidth == 0 -> filled. strokeWidth > 0 -> stroked with that width. */
	Kine_Skia_Surface_DrawRect                 :: proc(surface: ^KineSkiaSurface, x: f32, y: f32, width: f32, height: f32, r: u8, g: u8, b: u8, a: u8, strokeWidth: f32) ---
	Kine_Skia_Surface_DrawRotatedRect          :: proc(surface: ^KineSkiaSurface, centerX: f32, centerY: f32, width: f32, height: f32, rotationDegrees: f32, r: u8, g: u8, b: u8, a: u8, strokeWidth: f32) ---
	Kine_Skia_Surface_DrawRoundRect            :: proc(surface: ^KineSkiaSurface, x: f32, y: f32, width: f32, height: f32, radiusX: f32, radiusY: f32, r: u8, g: u8, b: u8, a: u8, strokeWidth: f32) ---
	Kine_Skia_Surface_DrawSquircle             :: proc(surface: ^KineSkiaSurface, x: f32, y: f32, width: f32, height: f32, radius: f32, exponent: f32, r: u8, g: u8, b: u8, a: u8, strokeWidth: f32) ---
	Kine_Skia_Surface_DrawUIShadow             :: proc(surface: ^KineSkiaSurface, x: f32, y: f32, width: f32, height: f32, radius: f32, exponent: f32, offsetX: f32, offsetY: f32, blurSigma: f32, spread: f32, r: u8, g: u8, b: u8, a: u8) ---
	Kine_Skia_Surface_DrawBackdropBlurRect     :: proc(surface: ^KineSkiaSurface, x: f32, y: f32, width: f32, height: f32, radiusX: f32, radiusY: f32, blurSigma: f32, alpha: u8, tintR: u8, tintG: u8, tintB: u8, tintA: u8) ---
	Kine_Skia_Surface_DrawBackdropBlurSquircle :: proc(surface: ^KineSkiaSurface, x: f32, y: f32, width: f32, height: f32, radius: f32, exponent: f32, blurSigma: f32, alpha: u8, tintR: u8, tintG: u8, tintB: u8, tintA: u8) ---
	Kine_Skia_Surface_DrawCircle               :: proc(surface: ^KineSkiaSurface, cx: f32, cy: f32, radius: f32, r: u8, g: u8, b: u8, a: u8, strokeWidth: f32) ---
	Kine_Skia_Surface_DrawOval                 :: proc(surface: ^KineSkiaSurface, x: f32, y: f32, width: f32, height: f32, r: u8, g: u8, b: u8, a: u8, strokeWidth: f32) ---
	Kine_Skia_Surface_DrawArc                  :: proc(surface: ^KineSkiaSurface, x: f32, y: f32, width: f32, height: f32, startAngle: f32, sweepAngle: f32, useCenter: i32, r: u8, g: u8, b: u8, a: u8, strokeWidth: f32) ---
	Kine_Skia_Surface_DrawLine                 :: proc(surface: ^KineSkiaSurface, x0: f32, y0: f32, x1: f32, y1: f32, strokeWidth: f32, r: u8, g: u8, b: u8, a: u8) ---

	/* points: flat array [x0,y0,x1,y1,...], pointCount = number of (x,y) pairs */
	Kine_Skia_Surface_DrawPolygon :: proc(surface: ^KineSkiaSurface, points: ^f32, pointCount: i32, closed: i32, r: u8, g: u8, b: u8, a: u8, strokeWidth: f32) ---

	/* ---------------- Transform stack ---------------- */
	Kine_Skia_Surface_Save                  :: proc(surface: ^KineSkiaSurface) ---
	Kine_Skia_Surface_Restore               :: proc(surface: ^KineSkiaSurface) ---
	Kine_Skia_Surface_Translate             :: proc(surface: ^KineSkiaSurface, dx: f32, dy: f32) ---
	Kine_Skia_Surface_Rotate                :: proc(surface: ^KineSkiaSurface, degrees: f32) ---
	Kine_Skia_Surface_Scale                 :: proc(surface: ^KineSkiaSurface, sx: f32, sy: f32) ---
	Kine_Skia_Surface_ClipRect              :: proc(surface: ^KineSkiaSurface, x: f32, y: f32, width: f32, height: f32) ---
	Kine_Skia_Surface_ClipRoundRect         :: proc(surface: ^KineSkiaSurface, x: f32, y: f32, width: f32, height: f32, radiusX: f32, radiusY: f32) ---
	Kine_Skia_Surface_ClipSquircle          :: proc(surface: ^KineSkiaSurface, x: f32, y: f32, width: f32, height: f32, radius: f32, exponent: f32) ---
	Kine_Skia_Surface_DrawImageSized        :: proc(surface: ^KineSkiaSurface, image: ^KineSkiaImage, x: f32, y: f32, width: f32, height: f32, alpha: u8) ---
	Kine_Skia_Surface_DrawPixels            :: proc(surface: ^KineSkiaSurface, pixels: rawptr, sourceWidth: i32, sourceHeight: i32, sourceRowBytes: u32, x: f32, y: f32, width: f32, height: f32, flipY: i32, alpha: u8) ---
	Kine_Skia_Surface_DrawImageOutlineSized :: proc(surface: ^KineSkiaSurface, image: ^KineSkiaImage, x: f32, y: f32, width: f32, height: f32, thickness: f32, r: u8, g: u8, b: u8, a: u8, alpha: u8) ---
	Kine_Skia_Surface_DrawImageShadow      :: proc(surface: ^KineSkiaSurface, image: ^KineSkiaImage, x: f32, y: f32, width: f32, height: f32, offsetX: f32, offsetY: f32, blurSigma: f32, spread: f32, r: u8, g: u8, b: u8, a: u8) ---
	Kine_Skia_Surface_GetFontAscent         :: proc(fontSize: f32, fontPath: cstring) -> f32 ---

	/* fontPath may be "" or NULL to use the default system font.
	x,y is the text BASELINE, not top-left. */
	Kine_Skia_Surface_DrawText       :: proc(surface: ^KineSkiaSurface, text: cstring, x: f32, y: f32, fontSize: f32, fontPath: cstring, r: u8, g: u8, b: u8, a: u8) ---
	Kine_Skia_Surface_DrawTextShadow :: proc(surface: ^KineSkiaSurface, text: cstring, x: f32, y: f32, fontSize: f32, fontPath: cstring, offsetX: f32, offsetY: f32, blurSigma: f32, spread: f32, shadowR: u8, shadowG: u8, shadowB: u8, shadowA: u8) ---
	Kine_Skia_Surface_MeasureText    :: proc(text: cstring, fontSize: f32, fontPath: cstring) -> f32 ---

	/* Approximate line height (ascent+descent+leading) for layout purposes */
	Kine_Skia_Surface_GetFontLineHeight :: proc(fontSize: f32, fontPath: cstring) -> f32 ---

	/* ---------------- Images ---------------- */
	Kine_Skia_Image_LoadFromFile   :: proc(path: cstring) -> ^KineSkiaImage ---
	Kine_Skia_Image_LoadFromMemory :: proc(data: ^u8, size: uintptr) -> ^KineSkiaImage ---
	Kine_Skia_Image_Destroy        :: proc(image: ^KineSkiaImage) ---
	Kine_Skia_Image_GetWidth       :: proc(image: ^KineSkiaImage) -> i32 ---
	Kine_Skia_Image_GetHeight      :: proc(image: ^KineSkiaImage) -> i32 ---

	/* Draw image at native size, top-left at (x,y) */
	Kine_Skia_Surface_DrawImage :: proc(surface: ^KineSkiaSurface, image: ^KineSkiaImage, x: f32, y: f32, alpha: u8) ---

	/* Draw image scaled/cropped: src rect from the image -> dst rect on the surface */
	Kine_Skia_Surface_DrawImageRect :: proc(surface: ^KineSkiaSurface, image: ^KineSkiaImage, srcX: f32, srcY: f32, srcWidth: f32, srcHeight: f32, dstX: f32, dstY: f32, dstWidth: f32, dstHeight: f32, alpha: u8) ---
}
