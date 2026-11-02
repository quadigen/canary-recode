#include "kine_skia.h"

#include "include/core/SkBlendMode.h"
#include "include/core/SkBitmap.h"
#include "include/core/SkBlurTypes.h"
#include "include/core/SkCanvas.h"
#include "include/core/SkColor.h"
#include "include/core/SkColorFilter.h"
#include "include/core/SkColorSpace.h"
#include "include/core/SkData.h"
#include "include/core/SkFont.h"
#include "include/core/SkFontMetrics.h"
#include "include/core/SkFontMgr.h"
#include "include/core/SkFontScanner.h"
#include "include/core/SkImage.h"
#include "include/core/SkImageInfo.h"
#include "include/core/SkMaskFilter.h"
#include "include/core/SkPaint.h"
#include "include/core/SkPath.h"
#include "include/core/SkPathBuilder.h"
#include "include/core/SkPixmap.h"
#include "include/core/SkRRect.h"
#include "include/core/SkRect.h"
#include "include/core/SkSurface.h"
#include "include/core/SkTextBlob.h"
#include "include/core/SkTileMode.h"
#include "include/core/SkTypeface.h"
#include "include/effects/SkColorMatrix.h"
#if __has_include("include/effects/SkGradient.h")
#include "include/effects/SkGradient.h"
#else
#include "include/effects/SkGradientShader.h"
#endif
#include "include/effects/SkImageFilters.h"
#include "include/effects/SkRuntimeEffect.h"
#include "include/android/SkAnimatedImage.h"
#include "include/codec/SkAndroidCodec.h"
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <vector>
#include <type_traits>
#include <optional>

#if defined(_WIN32)
#include "include/ports/SkTypeface_win.h"
#elif defined(__ANDROID__)
#include "include/ports/SkFontMgr_android_ndk.h"
#include "include/ports/SkFontScanner_FreeType.h"
#elif defined(__APPLE__)
#include "include/ports/SkFontMgr_mac_ct.h"
#else
#include "include/ports/SkFontMgr_fontconfig.h"
#include "include/ports/SkFontScanner_FreeType.h"
#endif
#include "include/core/SkStream.h"
#include "modules/skshaper/include/SkShaper.h"
#include "modules/skshaper/include/SkShaper_harfbuzz.h"
#include "modules/skshaper/include/SkShaper_skunicode.h"
#include "modules/svg/include/SkSVGDOM.h"


#ifndef KINE_SKIA_BUILD_VULKAN
#define KINE_SKIA_BUILD_VULKAN 0
#endif

#ifndef KINE_SKIA_BUILD_GL
#define KINE_SKIA_BUILD_GL 0
#endif

#if KINE_SKIA_BUILD_VULKAN || KINE_SKIA_BUILD_GL
#include "include/gpu/ganesh/SkImageGanesh.h"
#endif
#if KINE_SKIA_BUILD_VULKAN
#include "include/gpu/ganesh/GrBackendSurface.h"
#include "include/gpu/ganesh/GrDirectContext.h"
#include "include/gpu/ganesh/SkSurfaceGanesh.h"
#include "include/gpu/ganesh/vk/GrVkBackendSurface.h"
#include "include/gpu/ganesh/vk/GrVkDirectContext.h"
#include "include/gpu/ganesh/vk/GrVkTypes.h"
#include "include/gpu/vk/VulkanBackendContext.h"
#include "include/gpu/vk/VulkanTypes.h"
#include "include/private/gpu/vk/SkiaVulkan.h"
#include "src/gpu/GpuTypesPriv.h"
#include "src/gpu/vk/vulkanmemoryallocator/VulkanMemoryAllocatorPriv.h"
#endif

#if KINE_SKIA_BUILD_GL
#include "include/gpu/ganesh/GrBackendSurface.h"
#include "include/gpu/ganesh/GrDirectContext.h"
#include "include/gpu/ganesh/SkSurfaceGanesh.h"
#include "include/gpu/ganesh/gl/GrGLAssembleInterface.h"
#include "include/gpu/ganesh/gl/GrGLBackendSurface.h"
#include "include/gpu/ganesh/gl/GrGLDirectContext.h"
#include "include/gpu/ganesh/gl/GrGLInterface.h"
#include "include/gpu/ganesh/gl/GrGLTypes.h"
#endif

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <memory>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>


struct KineSkiaSurface {
	sk_sp<SkSurface> surface;
	sk_sp<SkImage> backdrop;

	/* Cached lens normal map for the liquid-glass backdrop displacement. */
	sk_sp<SkImage> displacementMap;
	int displacementMapW = 0;
	int displacementMapH = 0;
	float displacementMapRadius = -1.0f;

	/* Number of canvas saves opened by BeginMotionBlur, closed by EndMotionBlur. */
	int motionBlurSaves = 0;
#if KINE_SKIA_BUILD_VULKAN
	sk_sp<GrDirectContext> vulkanContext;
	GrBackendRenderTarget vulkanRenderTarget;
#endif
#if KINE_SKIA_BUILD_GL
	sk_sp<GrDirectContext> glContext;
	GrBackendRenderTarget glRenderTarget;
#endif
};

struct KineSkiaImage {
    bool strictSourceRect = false;
	sk_sp<SkImage> image;
	sk_sp<SkSVGDOM> svg;
	sk_sp<SkAnimatedImage> animated;

	float width = 0.0f;
	float height = 0.0f;

	bool animationStarted = false;
	bool animationFinished = false;
	int animationFrameDurationMs = 0;
	std::chrono::steady_clock::time_point animationStartedAt;
};

struct KineSkiaVulkanContext {
#if KINE_SKIA_BUILD_VULKAN
	sk_sp<GrDirectContext> context;
	KineSkiaVulkanBackend backend;
#endif
};

struct KineSkiaGLContext {
#if KINE_SKIA_BUILD_GL
	sk_sp<GrDirectContext> context;
#endif
};

struct KineSkiaTypeface {
	sk_sp<SkTypeface> typeface;
};

struct KineSkiaRuntimeShader {
	sk_sp<SkRuntimeEffect> effect;
	std::unique_ptr<SkRuntimeShaderBuilder> builder;
};

static thread_local std::string kine_skia_shader_error;

/* ---------------- Paint helpers ---------------- */

static SkPaint kine_skia_paint(uint8_t r, uint8_t g, uint8_t b, uint8_t a, float strokeWidth) {
	SkPaint paint;
	paint.setAntiAlias(true);
	paint.setColor(SkColorSetARGB(a, r, g, b));
	if (strokeWidth > 0.0f) {
		paint.setStyle(SkPaint::kStroke_Style);
		paint.setStrokeWidth(strokeWidth);
	} else {
		paint.setStyle(SkPaint::kFill_Style);
	}
	return paint;
}

KINE_SKIA_API KineSkiaRuntimeShader *Kine_Skia_RuntimeShader_Create(const char *sksl) {
	kine_skia_shader_error.clear();
	if (!sksl || !*sksl) {
		kine_skia_shader_error = "SkSL source is empty";
		return nullptr;
	}
	auto result = SkRuntimeEffect::MakeForShader(SkString(sksl));
	if (!result.effect) {
		kine_skia_shader_error = result.errorText.c_str();
		return nullptr;
	}
	auto *shader = new KineSkiaRuntimeShader();
	shader->effect = std::move(result.effect);
	shader->builder = std::make_unique<SkRuntimeShaderBuilder>(shader->effect);
	return shader;
}

KINE_SKIA_API void Kine_Skia_RuntimeShader_Destroy(KineSkiaRuntimeShader *shader) {
	delete shader;
}

KINE_SKIA_API bool Kine_Skia_RuntimeShader_SetUniform(
	KineSkiaRuntimeShader *shader, const char *name, const float *values, int valueCount) {
	if (!shader || !shader->effect || !shader->builder || !name || !values || valueCount <= 0) {
		return false;
	}
	const SkRuntimeEffect::Uniform *uniform = shader->effect->findUniform(name);
	if (!uniform || uniform->sizeInBytes() != sizeof(float) * static_cast<size_t>(valueCount)) {
		return false;
	}

	using UniformType = SkRuntimeEffect::Uniform::Type;
	switch (uniform->type) {
	case UniformType::kInt:
	case UniformType::kInt2:
	case UniformType::kInt3:
	case UniformType::kInt4: {
		int32_t integerValues[4] = {};
		for (int index = 0; index < valueCount; ++index) {
			integerValues[index] = static_cast<int32_t>(values[index]);
		}
		return shader->builder->uniform(name).set(integerValues, valueCount);
	}
	default:
		return shader->builder->uniform(name).set(values, valueCount);
	}
}

KINE_SKIA_API void Kine_Skia_Surface_DrawRuntimeShaderRect(
	KineSkiaSurface *surface, KineSkiaRuntimeShader *shader,
	float x, float y, float width, float height) {
	if (!surface || !surface->surface || !shader || !shader->builder || width <= 0 || height <= 0) {
		return;
	}
	SkPaint paint;
	paint.setAntiAlias(true);
	paint.setShader(shader->builder->makeShader());
	surface->surface->getCanvas()->drawRect(SkRect::MakeXYWH(x, y, width, height), paint);
}

KINE_SKIA_API const char *Kine_Skia_RuntimeShader_GetLastError(void) {
	return kine_skia_shader_error.c_str();
}

static SkPath kine_skia_squircle_path_corners(
	float x, float y, float width, float height,
	float radiusTL, float radiusTR, float radiusBR, float radiusBL, float exponent) {
	const float w = std::max(0.0f, width);
	const float h = std::max(0.0f, height);
	const float cap = std::min(w, h) * 0.5f;
	const float tl = std::clamp(radiusTL, 0.0f, cap);
	const float tr = std::clamp(radiusTR, 0.0f, cap);
	const float br = std::clamp(radiusBR, 0.0f, cap);
	const float bl = std::clamp(radiusBL, 0.0f, cap);

	if (tl <= 0.0f && tr <= 0.0f && br <= 0.0f && bl <= 0.0f) {
		SkPathBuilder rectBuilder;
		rectBuilder.moveTo(x, y);
		rectBuilder.lineTo(x + w, y);
		rectBuilder.lineTo(x + w, y + h);
		rectBuilder.lineTo(x, y + h);
		rectBuilder.close();
		return rectBuilder.detach();
	}

	const float n = exponent > 0.0f ? std::max(2.0f, exponent) : 4.0f;
	const float power = 2.0f / n;

	SkPathBuilder builder;
	constexpr int kCornerSegments = 24;
	constexpr float kHalfPi = 1.57079632679f;

	auto cornerTo = [&](float cx, float cy, float r, float start, float end) {
		if (r <= 0.0f) {
			return;
		}
		for (int i = 1; i <= kCornerSegments; ++i) {
			const float t = start + (end - start) * (static_cast<float>(i) / kCornerSegments);
			const float c = std::cos(t);
			const float s = std::sin(t);
			const float px = cx + std::copysign(std::pow(std::abs(c), power) * r, c);
			const float py = cy + std::copysign(std::pow(std::abs(s), power) * r, s);
			builder.lineTo(px, py);
		}
	};

	builder.moveTo(x + tl, y);
	builder.lineTo(x + w - tr, y);
	cornerTo(x + w - tr, y + tr, tr, -kHalfPi, 0.0f);
	builder.lineTo(x + w, y + h - br);
	cornerTo(x + w - br, y + h - br, br, 0.0f, kHalfPi);
	builder.lineTo(x + bl, y + h);
	cornerTo(x + bl, y + h - bl, bl, kHalfPi, 2.0f * kHalfPi);
	builder.lineTo(x, y + tl);
	cornerTo(x + tl, y + tl, tl, 2.0f * kHalfPi, 3.0f * kHalfPi);
	builder.close();
	return builder.detach();
}

static SkPath kine_skia_squircle_path(
	float x, float y, float width, float height, float radius, float exponent) {
	return kine_skia_squircle_path_corners(
		x, y, width, height, radius, radius, radius, radius, exponent);
}

/* ---------------- Font/typeface cache ---------------- */

static std::unordered_map<std::string, sk_sp<SkTypeface>> &kine_skia_typeface_cache() {
	static std::unordered_map<std::string, sk_sp<SkTypeface>> cache;
	return cache;
}

/* In-memory font cache. Every load used to construct a fresh platform
 * font manager (a new DirectWrite factory on Windows); the manager and its
 * font collection retain OS-level state that is never fully released, so
 * each call leaked ~7MB of private memory. Fonts are keyed by content and
 * verified byte-for-byte on hit, so identical loads reuse one typeface. */
struct KineSkiaMemoryTypefaceEntry {
	std::vector<uint8_t> bytes;
	sk_sp<SkTypeface> typeface;
};

static std::unordered_map<size_t, KineSkiaMemoryTypefaceEntry> &kine_skia_memory_typeface_cache() {
	static std::unordered_map<size_t, KineSkiaMemoryTypefaceEntry> cache;
	return cache;
}

static size_t kine_skia_font_hash(const uint8_t *data, size_t size) {
	size_t hash = size * 31 + 1469598103934665603ull;
	for (size_t i = 0; i < size; i++) {
		hash = (hash ^ data[i]) * 1099511628211ull;
	}
	return hash;
}

static sk_sp<SkTypeface> kine_skia_get_typeface(const char *fontPath) {
	std::string key = (fontPath && fontPath[0] != '\0') ? fontPath : "__default__";

	auto &cache = kine_skia_typeface_cache();
	auto it = cache.find(key);
	if (it != cache.end()) {
		return it->second;
	}

#if defined(_WIN32)
	sk_sp<SkFontMgr> mgr = SkFontMgr_New_DirectWrite();
#elif defined(__ANDROID__)
	sk_sp<SkFontMgr> mgr = SkFontMgr_New_AndroidNDK(false, SkFontScanner_Make_FreeType());
#elif defined(__APPLE__)
	sk_sp<SkFontMgr> mgr = SkFontMgr_New_CoreText(nullptr);
#else
	sk_sp<SkFontMgr> mgr = SkFontMgr_New_FontConfig(nullptr, SkFontScanner_Make_FreeType());
#endif
	sk_sp<SkTypeface> tf;

	if (fontPath && fontPath[0] != '\0') {
		tf = mgr->makeFromFile(fontPath, 0);
		if (!tf) {
			fprintf(stderr, "kine_skia: failed to load font '%s', falling back to default\n", fontPath);
		}
	}

	if (!tf) {
		tf = mgr->legacyMakeTypeface(nullptr, SkFontStyle());
	}

	cache[key] = tf;
	return tf;
}

static sk_sp<SkSVGDOM> kine_skia_decode_svg(
	const sk_sp<SkData> &data,
	float *outWidth,
	float *outHeight) {
	if (!data || data->isEmpty()) {
		return nullptr;
	}

	SkMemoryStream stream(data);

	sk_sp<SkSVGDOM> svg = SkSVGDOM::MakeFromStream(stream);
	if (!svg) {
		return nullptr;
	}

	const SkSize size = svg->containerSize();

	float width = size.width();
	float height = size.height();

	if (width <= 0.0f && height <= 0.0f) {
		width = 100.0f;
		height = 100.0f;
	} else if (width <= 0.0f) {
		width = height;
	} else if (height <= 0.0f) {
		height = width;
	}

	if (outWidth) {
		*outWidth = width;
	}

	if (outHeight) {
		*outHeight = height;
	}

	return svg;
}

static void kine_skia_draw_svg(
	SkCanvas *canvas,
	KineSkiaImage *image,
	float x,
	float y,
	float width,
	float height,
	uint8_t alpha) {
	if (!canvas || !image || !image->svg ||
		width <= 0.0f || height <= 0.0f) {
		return;
	}

	const float sourceWidth =
		image->width > 0.0f ? image->width : width;

	const float sourceHeight =
		image->height > 0.0f ? image->height : height;

	const float scaleX = width / sourceWidth;
	const float scaleY = height / sourceHeight;

	SkAutoCanvasRestore restore(canvas, true);

	canvas->translate(x, y);

	// Clip in destination coordinates.
	canvas->clipRect(
		SkRect::MakeWH(width, height),
		SkClipOp::kIntersect,
		true);

	// pngtosvg emits fixed pixel coordinates without a viewBox,
	// so explicitly scale the original SVG coordinate space.
	canvas->scale(scaleX, scaleY);

	// Keep the DOM at its original/intrinsic size.
	image->svg->setContainerSize(
		SkSize::Make(sourceWidth, sourceHeight));

	if (alpha < 255) {
		SkPaint alphaPaint;
		alphaPaint.setAlphaf(alpha / 255.0f);

		const SkRect bounds =
			SkRect::MakeWH(sourceWidth, sourceHeight);

		canvas->saveLayer(&bounds, &alphaPaint);
		image->svg->render(canvas);
		canvas->restore();
	} else {
		image->svg->render(canvas);
	}
}

extern "C" {

/* ---------------- Version ---------------- */

KINE_SKIA_API const char *Kine_Skia_GetVersion(void) {
	return "kine_skia 0.2.0";
}

/* ---------------- Vulkan GPU context ---------------- */

KINE_SKIA_API KineSkiaVulkanContext *Kine_Skia_Vulkan_CreateContext(
	const KineSkiaVulkanBackend *backend) {
	if (!backend || !backend->instance || !backend->physicalDevice || !backend->device ||
		!backend->queue || !backend->getInstanceProcAddr) {
		return nullptr;
	}

#if KINE_SKIA_BUILD_VULKAN
	auto *wrapper = new KineSkiaVulkanContext();
	wrapper->backend = *backend;

	auto getInstanceProc = reinterpret_cast<PFN_vkGetInstanceProcAddr>(backend->getInstanceProcAddr);
	auto explicitGetDeviceProc = reinterpret_cast<PFN_vkGetDeviceProcAddr>(backend->getDeviceProcAddr);
	VkInstance backendInstance = reinterpret_cast<VkInstance>(backend->instance);

	skgpu::VulkanBackendContext vkContext;
	vkContext.fInstance = reinterpret_cast<VkInstance>(backend->instance);
	vkContext.fPhysicalDevice = reinterpret_cast<VkPhysicalDevice>(backend->physicalDevice);
	vkContext.fDevice = reinterpret_cast<VkDevice>(backend->device);
	vkContext.fQueue = reinterpret_cast<VkQueue>(backend->queue);
	vkContext.fGraphicsQueueIndex = backend->graphicsQueueFamilyIndex;
	vkContext.fMaxAPIVersion = backend->maxApiVersion;
	vkContext.fGetProc = [getInstanceProc, explicitGetDeviceProc, backendInstance](
							 const char *procName,
							 VkInstance instance,
							 VkDevice device) -> PFN_vkVoidFunction {
		if (!procName || !getInstanceProc) {
			return nullptr;
		}
		if (device != VK_NULL_HANDLE) {
			PFN_vkGetDeviceProcAddr getDeviceProc = explicitGetDeviceProc;
			if (!getDeviceProc) {
				getDeviceProc = reinterpret_cast<PFN_vkGetDeviceProcAddr>(
					getInstanceProc(backendInstance, "vkGetDeviceProcAddr"));
			}
			if (getDeviceProc) {
				if (PFN_vkVoidFunction proc = getDeviceProc(device, procName)) {
					return proc;
				}
			}
		}

		VkInstance lookupInstance = instance != VK_NULL_HANDLE ? instance : backendInstance;
		PFN_vkVoidFunction proc = getInstanceProc(lookupInstance, procName);
		if (!proc) {
			fprintf(stderr, "kine_skia: Vulkan procedure unavailable: %s\n", procName);
		}
		return proc;
	};

	// Released Skia builds may expose the allocator's optional block-size
	// argument while newer source builds provide the two-argument overload.
	vkContext.fMemoryAllocator = []<typename Factory>(
		Factory factory, const skgpu::VulkanBackendContext& context) {
		if constexpr (std::is_invocable_v<Factory,
			const skgpu::VulkanBackendContext&, skgpu::ThreadSafe>) {
			return factory(context, skgpu::ThreadSafe::kYes);
		} else {
			return factory(context, skgpu::ThreadSafe::kYes, std::nullopt);
		}
	}(skgpu::VulkanMemoryAllocators::Make, vkContext);
	if (!vkContext.fMemoryAllocator) {
		fprintf(stderr, "kine_skia: failed to create Skia Vulkan memory allocator\n");
		delete wrapper;
		return nullptr;
	}

	wrapper->context = GrDirectContexts::MakeVulkan(vkContext);
	if (!wrapper->context) {
		fprintf(stderr, "kine_skia: GrDirectContexts::MakeVulkan failed\n");
		delete wrapper;
		return nullptr;
	}

	return wrapper;
#else
	(void)backend;
	return nullptr;
#endif
}

KINE_SKIA_API void Kine_Skia_Vulkan_DestroyContext(KineSkiaVulkanContext *context) {
	if (!context) {
		return;
	}
#if KINE_SKIA_BUILD_VULKAN
	if (context->context) {
		context->context->flushAndSubmit();
		context->context->releaseResourcesAndAbandonContext();
		context->context.reset();
	}
#endif
	delete context;
}

/* ---------------- OpenGL GPU context ---------------- */

KINE_SKIA_API KineSkiaGLContext *Kine_Skia_GL_CreateContext(
	const KineSkiaGLBackend *backend) {
#if KINE_SKIA_BUILD_GL
	auto *wrapper = new KineSkiaGLContext();

	sk_sp<const GrGLInterface> glInterface;
	if (backend && backend->getProcAddr) {
		auto getProc = reinterpret_cast<GrGLGetProc>(backend->getProcAddr);
		// Pick the assembler that matches the standard Skia was built for. A
		// GLES build (SK_ASSUME_GL_ES) compiles the desktop GL assembler out to
		// a nullptr stub, so asking for it unconditionally fails on Android,
		// while a desktop build auto-detects from the GL version string.
		glInterface = GrGLMakeAssembledInterface(backend->getProcContext, getProc);
	} else {
		glInterface = GrGLMakeNativeInterface();
	}

	if (!glInterface) {
		fprintf(stderr, "kine_skia: failed to assemble GrGLInterface\n");
		delete wrapper;
		return nullptr;
	}

	wrapper->context = GrDirectContexts::MakeGL(std::move(glInterface));
	if (!wrapper->context) {
		fprintf(stderr, "kine_skia: GrDirectContexts::MakeGL failed\n");
		delete wrapper;
		return nullptr;
	}

	return wrapper;
#else
	(void)backend;
	return nullptr;
#endif
}

KINE_SKIA_API void Kine_Skia_GL_DestroyContext(KineSkiaGLContext *context) {
	if (!context) {
		return;
	}
#if KINE_SKIA_BUILD_GL
	if (context->context) {
		context->context->flushAndSubmit();
		context->context->releaseResourcesAndAbandonContext();
		context->context.reset();
	}
#endif
	delete context;
}

KINE_SKIA_API void Kine_Skia_GL_ResetContext(KineSkiaGLContext *context) {
	if (!context) {
		return;
	}
#if KINE_SKIA_BUILD_GL
	if (context->context) {
		context->context->resetContext();
	}
#endif
}

/* ---------------- Surface lifecycle ---------------- */

KINE_SKIA_API KineSkiaSurface *Kine_Skia_Surface_Create(int width, int height) {
	if (width <= 0 || height <= 0) {
		return nullptr;
	}

	SkImageInfo info = SkImageInfo::Make(
		width, height,
		kRGBA_8888_SkColorType,
		kPremul_SkAlphaType);

	sk_sp<SkSurface> surface = SkSurfaces::Raster(info);
	if (!surface) {
		return nullptr;
	}

	KineSkiaSurface *wrapper = new KineSkiaSurface();
	wrapper->surface = std::move(surface);
	wrapper->surface->getCanvas()->clear(SK_ColorTRANSPARENT);

	return wrapper;
}

KINE_SKIA_API KineSkiaSurface *Kine_Skia_Surface_CreateVulkanRenderTarget(
	KineSkiaVulkanContext *context,
	int width,
	int height,
	const KineSkiaVulkanImageInfo *imageInfo) {
	if (width <= 0 || height <= 0 || !context || !imageInfo || !imageInfo->image) {
		return nullptr;
	}

#if KINE_SKIA_BUILD_VULKAN
	if (!context->context) {
		return nullptr;
	}

	GrVkImageInfo vkImageInfo;
	vkImageInfo.fImage = reinterpret_cast<VkImage>(imageInfo->image);
	vkImageInfo.fImageTiling = imageInfo->imageTiling
								   ? static_cast<VkImageTiling>(imageInfo->imageTiling)
								   : VK_IMAGE_TILING_OPTIMAL;
	vkImageInfo.fImageLayout = static_cast<VkImageLayout>(imageInfo->imageLayout);
	vkImageInfo.fFormat = static_cast<VkFormat>(imageInfo->format);
	vkImageInfo.fImageUsageFlags = static_cast<VkImageUsageFlags>(imageInfo->imageUsageFlags);
	vkImageInfo.fSampleCount = imageInfo->sampleCount ? imageInfo->sampleCount : 1;
	vkImageInfo.fLevelCount = imageInfo->levelCount ? imageInfo->levelCount : 1;
	vkImageInfo.fCurrentQueueFamily = imageInfo->currentQueueFamily;

	SkColorType colorType;
	switch (vkImageInfo.fFormat) {
	case VK_FORMAT_B8G8R8A8_UNORM:
		colorType = kBGRA_8888_SkColorType;
		break;
	case VK_FORMAT_R8G8B8A8_UNORM:
		colorType = kRGBA_8888_SkColorType;
		break;
	case VK_FORMAT_R8G8B8A8_SRGB:
		colorType = kSRGBA_8888_SkColorType;
		break;
	default:
		fprintf(stderr, "kine_skia: unsupported Vulkan render target format=%u\n",
				static_cast<unsigned>(vkImageInfo.fFormat));
		return nullptr;
	}

	auto logImageInfo = [&]() {
		fprintf(stderr,
				"kine_skia: Vulkan target image=%p format=%u layout=%u usage=0x%x "
				"samples=%u levels=%u queueFamily=%u size=%dx%d\n",
				reinterpret_cast<void *>(vkImageInfo.fImage),
				static_cast<unsigned>(vkImageInfo.fFormat),
				static_cast<unsigned>(vkImageInfo.fImageLayout),
				static_cast<unsigned>(vkImageInfo.fImageUsageFlags),
				vkImageInfo.fSampleCount,
				vkImageInfo.fLevelCount,
				vkImageInfo.fCurrentQueueFamily,
				width, height);
	};

	GrBackendRenderTarget renderTarget = GrBackendRenderTargets::MakeVk(width, height, vkImageInfo);
	if (!renderTarget.isValid()) {
		fprintf(stderr, "kine_skia: Vulkan backend render target is invalid\n");
		logImageInfo();
		return nullptr;
	}

	sk_sp<SkSurface> surface = SkSurfaces::WrapBackendRenderTarget(
		context->context.get(),
		renderTarget,
		kTopLeft_GrSurfaceOrigin,
		colorType,
		nullptr,
		nullptr);

	if (!surface) {
		fprintf(stderr, "kine_skia: WrapBackendRenderTarget rejected format=%u colorType=%d\n",
				static_cast<unsigned>(vkImageInfo.fFormat), static_cast<int>(colorType));
		logImageInfo();
		return nullptr;
	}

	KineSkiaSurface *wrapper = new KineSkiaSurface();
	wrapper->surface = std::move(surface);
	wrapper->vulkanContext = context->context;
	wrapper->vulkanRenderTarget = renderTarget;
	return wrapper;
#else
	(void)context;
	(void)imageInfo;
	return nullptr;
#endif
}

KINE_SKIA_API KineSkiaSurface *Kine_Skia_Surface_CreateGLRenderTarget(
	KineSkiaGLContext *context,
	int width,
	int height,
	const KineSkiaGLImageInfo *imageInfo) {
	if (width <= 0 || height <= 0 || !context || !imageInfo) {
		return nullptr;
	}

#if KINE_SKIA_BUILD_GL
	if (!context->context) {
		return nullptr;
	}

	GrGLenum glFormat = imageInfo->format ? imageInfo->format : 0x8058 /* GL_RGBA8 */;

	SkColorType colorType;
	switch (glFormat) {
	case 0x8058 /* GL_RGBA8 */:
		colorType = kRGBA_8888_SkColorType;
		break;
	case 0x93A1 /* GL_BGRA8 */:
		colorType = kBGRA_8888_SkColorType;
		break;
	case 0x8C43 /* GL_SRGB8_ALPHA8 */:
		colorType = kSRGBA_8888_SkColorType;
		break;
	default:
		fprintf(stderr, "kine_skia: unsupported GL render target format=0x%x\n",
				static_cast<unsigned>(glFormat));
		return nullptr;
	}

	GrGLFramebufferInfo glInfo;
	glInfo.fFBOID = static_cast<GrGLuint>(imageInfo->framebufferId);
	glInfo.fFormat = glFormat;
	glInfo.fProtected = skgpu::Protected::kNo;

	const int sampleCount = imageInfo->sampleCount ? static_cast<int>(imageInfo->sampleCount) : 1;
	const int stencilBits = static_cast<int>(imageInfo->stencilBits);

	GrBackendRenderTarget renderTarget =
		GrBackendRenderTargets::MakeGL(width, height, sampleCount, stencilBits, glInfo);
	if (!renderTarget.isValid()) {
		fprintf(stderr,
				"kine_skia: GL backend render target is invalid fbo=%u format=0x%x "
				"samples=%d stencil=%d size=%dx%d\n",
				static_cast<unsigned>(glInfo.fFBOID),
				static_cast<unsigned>(glInfo.fFormat),
				sampleCount, stencilBits, width, height);
		return nullptr;
	}

	GrSurfaceOrigin origin = imageInfo->origin ? kTopLeft_GrSurfaceOrigin
											   : kBottomLeft_GrSurfaceOrigin;

	sk_sp<SkSurface> surface = SkSurfaces::WrapBackendRenderTarget(
		context->context.get(),
		renderTarget,
		origin,
		colorType,
		nullptr,
		nullptr);

	if (!surface) {
		fprintf(stderr,
				"kine_skia: WrapBackendRenderTarget rejected GL format=0x%x colorType=%d "
				"fbo=%u samples=%d stencil=%d\n",
				static_cast<unsigned>(glFormat), static_cast<int>(colorType),
				static_cast<unsigned>(glInfo.fFBOID), sampleCount, stencilBits);
		return nullptr;
	}

	KineSkiaSurface *wrapper = new KineSkiaSurface();
	wrapper->surface = std::move(surface);
	wrapper->glContext = context->context;
	wrapper->glRenderTarget = renderTarget;
	return wrapper;
#else
	(void)context;
	(void)imageInfo;
	return nullptr;
#endif
}

KINE_SKIA_API void Kine_Skia_Surface_Destroy(KineSkiaSurface *surface) {
	delete surface;
}

KINE_SKIA_API int Kine_Skia_Surface_GetWidth(const KineSkiaSurface *surface) {
	return surface && surface->surface ? surface->surface->width() : 0;
}

KINE_SKIA_API int Kine_Skia_Surface_GetHeight(const KineSkiaSurface *surface) {
	return surface && surface->surface ? surface->surface->height() : 0;
}

KINE_SKIA_API uint32_t Kine_Skia_Surface_GetRowBytes(const KineSkiaSurface *surface) {
	if (!surface || !surface->surface) {
		return 0;
	}

	SkPixmap pixmap;
	if (!surface->surface->peekPixels(&pixmap)) {
		return 0;
	}

	return static_cast<uint32_t>(pixmap.rowBytes());
}

KINE_SKIA_API void *Kine_Skia_Surface_GetPixels(KineSkiaSurface *surface) {
	if (!surface || !surface->surface) {
		return nullptr;
	}

	SkPixmap pixmap;
	if (!surface->surface->peekPixels(&pixmap)) {
		return nullptr;
	}

	return pixmap.writable_addr();
}

KINE_SKIA_API void Kine_Skia_Surface_Flush(KineSkiaSurface *surface) {
	if (!surface || !surface->surface) {
		return;
	}
#if KINE_SKIA_BUILD_VULKAN
	if (surface->vulkanContext) {
		skgpu::ganesh::FlushAndSubmit(surface->surface.get());
		surface->vulkanContext->flushAndSubmit();
	}
#endif
#if KINE_SKIA_BUILD_GL
	if (surface->glContext) {
		skgpu::ganesh::FlushAndSubmit(surface->surface.get());
		surface->glContext->flushAndSubmit();
	}
#endif
	/* Raster surfaces are synchronous. */
}

KINE_SKIA_API void Kine_Skia_Surface_SetBackdropFromSurface(
	KineSkiaSurface *surface,
	KineSkiaSurface *backdrop) {
	if (!surface) {
		return;
	}

	surface->backdrop.reset();
	if (!backdrop || !backdrop->surface) {
		return;
	}

	Kine_Skia_Surface_Flush(backdrop);
	surface->backdrop = backdrop->surface->makeImageSnapshot();
}

KINE_SKIA_API void Kine_Skia_Surface_ClearBackdrop(KineSkiaSurface *surface) {
	if (!surface) {
		return;
	}
	surface->backdrop.reset();
}

KINE_SKIA_API void Kine_Skia_Surface_GetPixel(
	KineSkiaSurface *surface,
	int x, int y,
	uint8_t *outR, uint8_t *outG, uint8_t *outB, uint8_t *outA) {
	if (outR)
		*outR = 0;
	if (outG)
		*outG = 0;
	if (outB)
		*outB = 0;
	if (outA)
		*outA = 0;

	if (!surface || !surface->surface) {
		return;
	}

	if (x < 0 || y < 0 || x >= surface->surface->width() || y >= surface->surface->height()) {
		return;
	}

	SkPixmap pixmap;
	SkColor c;
	if (surface->surface->peekPixels(&pixmap)) {
		c = pixmap.getColor(x, y);
	} else {
		// Vulkan surfaces are not CPU-addressable. Read a single pixel back
		// so this diagnostic API works for the actual compositor as well.
		uint8_t rgba[4];
		const auto info = SkImageInfo::Make(1, 1, kRGBA_8888_SkColorType, kUnpremul_SkAlphaType);
		if (!surface->surface->readPixels(info, rgba, sizeof(rgba), x, y))
			return;
		c = SkColorSetARGB(rgba[3], rgba[0], rgba[1], rgba[2]);
	}
	if (outR)
		*outR = SkColorGetR(c);
	if (outG)
		*outG = SkColorGetG(c);
	if (outB)
		*outB = SkColorGetB(c);
	if (outA)
		*outA = SkColorGetA(c);
}

/* ---------------- Clear ---------------- */

KINE_SKIA_API void Kine_Skia_Surface_Clear(
	KineSkiaSurface *surface,
	uint8_t r, uint8_t g, uint8_t b, uint8_t a) {
	if (!surface || !surface->surface) {
		return;
	}
	surface->surface->getCanvas()->clear(SkColorSetARGB(a, r, g, b));
}

/* ---------------- Shapes ---------------- */

KINE_SKIA_API void Kine_Skia_Surface_DrawRect(
	KineSkiaSurface *surface,
	float x, float y, float width, float height,
	uint8_t r, uint8_t g, uint8_t b, uint8_t a,
	float strokeWidth) {
	if (!surface || !surface->surface || width <= 0.0f || height <= 0.0f) {
		return;
	}

	SkPaint paint = kine_skia_paint(r, g, b, a, strokeWidth);
	surface->surface->getCanvas()->drawRect(SkRect::MakeXYWH(x, y, width, height), paint);
}

KINE_SKIA_API void Kine_Skia_Surface_DrawRotatedRect(
	KineSkiaSurface *surface,
	float centerX, float centerY, float width, float height, float rotationDegrees,
	uint8_t r, uint8_t g, uint8_t b, uint8_t a,
	float strokeWidth) {
	if (!surface || !surface->surface || width <= 0.0f || height <= 0.0f) {
		return;
	}

	SkCanvas *canvas = surface->surface->getCanvas();
	SkAutoCanvasRestore restore(canvas, true);
	canvas->rotate(rotationDegrees, centerX, centerY);
	canvas->drawRect(
		SkRect::MakeXYWH(centerX - width * 0.5f, centerY - height * 0.5f, width, height),
		kine_skia_paint(r, g, b, a, strokeWidth));
}

KINE_SKIA_API void Kine_Skia_Surface_BeginEdgeFade(
	KineSkiaSurface *surface,
	float x, float y, float width, float height) {
	if (!surface || !surface->surface || width <= 0.0f || height <= 0.0f)
		return;

	SkCanvas *canvas = surface->surface->getCanvas();
	const SkRect bounds = SkRect::MakeXYWH(x, y, width, height);

	canvas->save();
	canvas->clipRect(bounds, SkClipOp::kIntersect, true);
	canvas->saveLayer(&bounds, nullptr);
}

KINE_SKIA_API void Kine_Skia_Surface_EndEdgeFade(
	KineSkiaSurface *surface,
	float x, float y, float width, float height,
	float fadeTop, float fadeBottom, float fadeLeft, float fadeRight) {
	if (!surface || !surface->surface || width <= 0.0f || height <= 0.0f)
		return;

	SkCanvas *canvas = surface->surface->getCanvas();

	auto applyMask = [&](SkRect rect, SkPoint p0, SkPoint p1, SkColor from, SkColor to) {
		const SkPoint pts[2] = {p0, p1};
		const SkColor4f colors[2] = {SkColor4f::FromColor(from),
									  SkColor4f::FromColor(to)};

		SkPaint paint;
		paint.setBlendMode(SkBlendMode::kDstIn);
#if __has_include("include/effects/SkGradient.h")
		const SkGradient grad(
			SkGradient::Colors(SkSpan<const SkColor4f>(colors, 2),
							   SkSpan<const float>(), SkTileMode::kClamp),
			SkGradient::Interpolation{});

		paint.setShader(SkShaders::LinearGradient(pts, grad, nullptr));
#else
		paint.setShader(SkGradientShader::MakeLinear(
			pts, colors, nullptr, nullptr, 2, SkTileMode::kClamp));
#endif
		canvas->drawRect(rect, paint);
	};

	const SkColor kClear = SkColorSetARGB(0, 0, 0, 0);
	const SkColor kSolid = SkColorSetARGB(255, 0, 0, 0);

	if (fadeTop > 0.0f) {
		const float h = std::min(fadeTop, height);
		applyMask(SkRect::MakeXYWH(x, y, width, h),
				  {x, y}, {x, y + h}, kClear, kSolid);
	}
	if (fadeBottom > 0.0f) {
		const float h = std::min(fadeBottom, height);
		applyMask(SkRect::MakeXYWH(x, y + height - h, width, h),
				  {x, y + height - h}, {x, y + height}, kSolid, kClear);
	}
	if (fadeLeft > 0.0f) {
		const float w = std::min(fadeLeft, width);
		applyMask(SkRect::MakeXYWH(x, y, w, height),
				  {x, y}, {x + w, y}, kClear, kSolid);
	}
	if (fadeRight > 0.0f) {
		const float w = std::min(fadeRight, width);
		applyMask(SkRect::MakeXYWH(x + width - w, y, w, height),
				  {x + width - w, y}, {x + width, y}, kSolid, kClear);
	}

	canvas->restore(); // saveLayer, composites the masked layer
	canvas->restore(); // clip save
}

KINE_SKIA_API void Kine_Skia_Surface_DrawRoundRect(
	KineSkiaSurface *surface,
	float x, float y, float width, float height,
	float radiusX, float radiusY,
	uint8_t r, uint8_t g, uint8_t b, uint8_t a,
	float strokeWidth) {
	if (!surface || !surface->surface || width <= 0.0f || height <= 0.0f) {
		return;
	}

	SkPaint paint = kine_skia_paint(r, g, b, a, strokeWidth);
	surface->surface->getCanvas()->drawRRect(
		SkRRect::MakeRectXY(SkRect::MakeXYWH(x, y, width, height), radiusX, radiusY),
		paint);
}

KINE_SKIA_API void Kine_Skia_Surface_DrawSquircle(
	KineSkiaSurface *surface,
	float x, float y, float width, float height,
	float radius, float exponent,
	uint8_t r, uint8_t g, uint8_t b, uint8_t a,
	float strokeWidth) {
	if (!surface || !surface->surface || width <= 0.0f || height <= 0.0f) {
		return;
	}

	SkPaint paint = kine_skia_paint(r, g, b, a, strokeWidth);
	surface->surface->getCanvas()->drawPath(
		kine_skia_squircle_path(x, y, width, height, radius, exponent),
		paint);
}

KINE_SKIA_API void Kine_Skia_Surface_DrawSquircleCorners(
	KineSkiaSurface *surface,
	float x, float y, float width, float height,
	float radiusTL, float radiusTR, float radiusBR, float radiusBL,
	float exponent,
	uint8_t r, uint8_t g, uint8_t b, uint8_t a,
	float strokeWidth) {
	if (!surface || !surface->surface || width <= 0.0f || height <= 0.0f) {
		return;
	}

	SkPaint paint = kine_skia_paint(r, g, b, a, strokeWidth);
	surface->surface->getCanvas()->drawPath(
		kine_skia_squircle_path_corners(
			x, y, width, height, radiusTL, radiusTR, radiusBR, radiusBL, exponent),
		paint);
}

KINE_SKIA_API void Kine_Skia_Surface_DrawUIShadow(
	KineSkiaSurface *surface,
	float x, float y, float width, float height,
	float radius, float exponent,
	float offsetX, float offsetY,
	float blurSigma, float spread,
	uint8_t r, uint8_t g, uint8_t b, uint8_t a) {
	if (!surface || !surface->surface || width <= 0.0f || height <= 0.0f || a == 0) {
		return;
	}

	SkPaint paint;
	paint.setAntiAlias(true);
	paint.setStyle(SkPaint::kFill_Style);
	paint.setColor(SkColorSetARGB(a, r, g, b));
	if (blurSigma > 0.0f) {
		paint.setMaskFilter(SkMaskFilter::MakeBlur(kNormal_SkBlurStyle, blurSigma));
	}

	const float sx = x + offsetX - spread;
	const float sy = y + offsetY - spread;
	const float sw = width + spread * 2.0f;
	const float sh = height + spread * 2.0f;
	const float sr = std::max(0.0f, radius + spread);
	if (exponent > 2.0f && sr > 0.0f) {
		surface->surface->getCanvas()->drawPath(
			kine_skia_squircle_path(sx, sy, sw, sh, sr, exponent),
			paint);
	} else if (sr > 0.0f) {
		surface->surface->getCanvas()->drawRRect(
			SkRRect::MakeRectXY(SkRect::MakeXYWH(sx, sy, sw, sh), sr, sr),
			paint);
	} else {
		surface->surface->getCanvas()->drawRect(SkRect::MakeXYWH(sx, sy, sw, sh), paint);
	}
}

extern "C++" {

static SkColorMatrix kine_skia_color_matrix(
	float brightness,
	float contrast,
	float saturation,
	float hueDegrees) {
	SkColorMatrix matrix;
	matrix.setSaturation(std::max(0.0f, saturation));

	if (hueDegrees != 0.0f) {
		const float radians = hueDegrees *
			static_cast<float>(3.14159265358979323846) / 180.0f;
		const float c = std::cos(radians);
		const float s = std::sin(radians);

		SkColorMatrix hue(
			0.213f + c * 0.787f - s * 0.213f,
			0.715f - c * 0.715f - s * 0.715f,
			0.072f - c * 0.072f + s * 0.928f,
			0.0f, 0.0f,

			0.213f - c * 0.213f + s * 0.143f,
			0.715f + c * 0.285f + s * 0.140f,
			0.072f - c * 0.072f - s * 0.283f,
			0.0f, 0.0f,

			0.213f - c * 0.213f - s * 0.787f,
			0.715f - c * 0.715f + s * 0.715f,
			0.072f + c * 0.928f + s * 0.072f,
			0.0f, 0.0f,

			0.0f, 0.0f, 0.0f, 1.0f, 0.0f);

		matrix.postConcat(hue);
	}

	if (contrast != 1.0f) {
		SkColorMatrix contrastMatrix;
		contrastMatrix.setScale(contrast, contrast, contrast, 1.0f);
		const float t = 0.5f * (1.0f - contrast);
		contrastMatrix.postTranslate(t, t, t, 0.0f);
		matrix.postConcat(contrastMatrix);
	}

	if (brightness != 0.0f) {
		matrix.postTranslate(brightness, brightness, brightness, 0.0f);
	}

	return matrix;
}

static sk_sp<SkImage> kine_skia_make_lens_displacement_map(
	int width,
	int height) {
	if (width <= 0 || height <= 0) {
		return nullptr;
	}

	SkImageInfo info = SkImageInfo::MakeN32Premul(width, height);
	SkBitmap bitmap;
	if (!bitmap.tryAllocPixels(info)) {
		return nullptr;
	}

	const float cx = width * 0.5f;
	const float cy = height * 0.5f;
	const float invX = 1.0f / cx;
	const float invY = 1.0f / cy;

	for (int y = 0; y < height; ++y) {
		uint32_t *row = bitmap.getAddr32(0, y);
		const float v = (y + 0.5f - cy) * invY;
		const float av = std::min(1.0f, std::fabs(v));
		const float pv = std::pow(av, 3.0f);

		for (int x = 0; x < width; ++x) {
			const float u = (x + 0.5f - cx) * invX;
			const float au = std::min(1.0f, std::fabs(u));
			const float pu = std::pow(au, 3.0f);

			const float nx = (u < 0.0f ? -pu : pu) * (1.0f - pv * 0.5f);
			const float ny = (v < 0.0f ? -pv : pv) * (1.0f - pu * 0.5f);

			const uint8_t red = static_cast<uint8_t>(std::clamp(
				128.0f + nx * 127.0f, 0.0f, 255.0f));
			const uint8_t green = static_cast<uint8_t>(std::clamp(
				128.0f + ny * 127.0f, 0.0f, 255.0f));

			row[x] = SkColorSetARGB(255, red, green, 128);
		}
	}

	return bitmap.asImage();
}

static sk_sp<SkImage> kine_skia_surface_displacement_map(
	KineSkiaSurface *surface,
	float width,
	float height) {
	const float maxDim = 128.0f;
	const float scale = maxDim / std::max(width, height);

	int mapWidth = std::max(8, static_cast<int>(std::lround(width * scale)));
	int mapHeight = std::max(8, static_cast<int>(std::lround(height * scale)));

	if (surface->displacementMap &&
		surface->displacementMapW == mapWidth &&
		surface->displacementMapH == mapHeight) {
		return surface->displacementMap;
	}

	surface->displacementMap = kine_skia_make_lens_displacement_map(mapWidth, mapHeight);
	surface->displacementMapW = mapWidth;
	surface->displacementMapH = mapHeight;

	return surface->displacementMap;
}

} // extern "C++"

KINE_SKIA_API void Kine_Skia_Surface_DrawBackdropRect(
	KineSkiaSurface *surface,
	float x, float y, float width, float height,
	float radiusX, float radiusY,
	float exponent,
	float offsetX, float offsetY,
	float blurSigma,
	float brightness, float contrast, float saturation, float hueShift,
	float morphology,
	float displacement,
	float pixelate,
	float zoom,
	uint8_t alpha,
	uint8_t tintR, uint8_t tintG, uint8_t tintB, uint8_t tintA) {
	if (!surface || !surface->surface || !surface->backdrop ||
		width <= 0.0f || height <= 0.0f || (alpha == 0 && tintA == 0)) {
		return;
	}

	SkCanvas *canvas = surface->surface->getCanvas();
	const SkRect rect = SkRect::MakeXYWH(x, y, width, height);

	SkRect src = rect;
	src.offset(offsetX, offsetY);
	if (zoom > 0.0f && std::fabs(zoom - 1.0f) > 1e-4f) {
		const float nw = rect.width() / zoom;
		const float nh = rect.height() / zoom;
		const float centerX = src.centerX();
		const float centerY = src.centerY();
		src = SkRect::MakeLTRB(
			centerX - nw * 0.5f, centerY - nh * 0.5f,
			centerX + nw * 0.5f, centerY + nh * 0.5f);
	}

	canvas->save();
	if (exponent > 2.0f) {
		canvas->clipPath(
			kine_skia_squircle_path(
				x, y, width, height, std::max(radiusX, radiusY), exponent),
			true);
	} else if (radiusX > 0.0f || radiusY > 0.0f) {
		canvas->clipRRect(SkRRect::MakeRectXY(rect, radiusX, radiusY), true);
	} else {
		canvas->clipRect(rect, SkClipOp::kIntersect, true);
	}

	const bool graded =
		brightness != 0.0f || contrast != 1.0f ||
		saturation != 1.0f || hueShift != 0.0f;

	sk_sp<SkColorFilter> colorFilter;
	if (graded) {
		colorFilter = SkColorFilters::Matrix(
			kine_skia_color_matrix(brightness, contrast, saturation, hueShift));
	}

	if (pixelate > 0.0f) {
		const int pw = std::max(1, static_cast<int>(std::ceil(width / pixelate)));
		const int ph = std::max(1, static_cast<int>(std::ceil(height / pixelate)));

		sk_sp<SkSurface> small =
			surface->surface->makeSurface(SkImageInfo::MakeN32Premul(pw, ph));

		if (small) {
			const SkRect smallRect = SkRect::MakeWH(
				static_cast<float>(pw), static_cast<float>(ph));

			SkPaint downPaint;
			downPaint.setAntiAlias(true);
			if (colorFilter) {
				downPaint.setColorFilter(colorFilter);
			}

			small->getCanvas()->drawImageRect(
				surface->backdrop,
				src,
				smallRect,
				SkSamplingOptions(SkFilterMode::kLinear),
				&downPaint,
				SkCanvas::kFast_SrcRectConstraint);

			SkPaint upPaint;
			upPaint.setAntiAlias(true);
			upPaint.setAlphaf(alpha / 255.0f);

			canvas->drawImageRect(
				small->makeImageSnapshot(),
				smallRect,
				rect,
				SkSamplingOptions(SkFilterMode::kNearest),
				&upPaint,
				SkCanvas::kFast_SrcRectConstraint);
		}
	} else {
		sk_sp<SkImageFilter> filter;

		if (morphology > 0.0f) {
			filter = SkImageFilters::Dilate(morphology, morphology, std::move(filter));
		} else if (morphology < 0.0f) {
			filter = SkImageFilters::Erode(-morphology, -morphology, std::move(filter));
		}

		if (blurSigma > 0.0f) {
			filter = SkImageFilters::Blur(
				blurSigma, blurSigma, SkTileMode::kClamp, std::move(filter));
		}

		if (displacement > 0.0f) {
			sk_sp<SkImage> map =
				kine_skia_surface_displacement_map(surface, width, height);

			if (map) {
				sk_sp<SkImageFilter> mapFilter = SkImageFilters::Image(
					map,
					SkRect::MakeWH(
						static_cast<float>(map->width()),
						static_cast<float>(map->height())),
					rect,
					SkSamplingOptions(SkFilterMode::kLinear));

				filter = SkImageFilters::DisplacementMap(
					SkColorChannel::kR,
					SkColorChannel::kG,
					displacement,
					std::move(mapFilter),
					std::move(filter));
			}
		}

		SkPaint paint;
		paint.setAntiAlias(true);
		paint.setAlphaf(alpha / 255.0f);
		if (colorFilter) {
			paint.setColorFilter(colorFilter);
		}
		if (filter) {
			paint.setImageFilter(std::move(filter));
		}

		canvas->drawImageRect(
			surface->backdrop,
			src,
			rect,
			SkSamplingOptions(SkFilterMode::kLinear),
			&paint,
			SkCanvas::kFast_SrcRectConstraint);
	}

	if (tintA > 0) {
		SkPaint tintPaint;
		tintPaint.setAntiAlias(true);
		tintPaint.setStyle(SkPaint::kFill_Style);
		tintPaint.setColor(SkColorSetARGB(tintA, tintR, tintG, tintB));
		canvas->drawRect(rect, tintPaint);
	}

	canvas->restore();
}

KINE_SKIA_API void Kine_Skia_Surface_DrawMagnifierRect(
	KineSkiaSurface *surface,
	float x, float y, float width, float height,
	float zoomAmount, float inset,
	uint8_t alpha) {
	if (!surface || !surface->surface || !surface->backdrop ||
		width <= 0.0f || height <= 0.0f || alpha == 0 || zoomAmount <= 1.0f) {
		return;
	}

	SkCanvas *canvas = surface->surface->getCanvas();
	const SkRect rect = SkRect::MakeXYWH(x, y, width, height);
	const SkSamplingOptions sampling(SkFilterMode::kLinear);
	const SkRect backdropBounds = SkRect::Make(surface->backdrop->bounds());

	sk_sp<SkImageFilter> input = SkImageFilters::Image(
		surface->backdrop, backdropBounds, backdropBounds, sampling);

	const float insetClamped = std::clamp(
		inset, 0.0f, std::min(width, height) * 0.5f);

	sk_sp<SkImageFilter> magnifier = SkImageFilters::Magnifier(
		rect, zoomAmount, insetClamped, sampling, std::move(input));

	SkPaint paint;
	paint.setAntiAlias(true);
	paint.setAlphaf(alpha / 255.0f);
	paint.setImageFilter(std::move(magnifier));

	canvas->save();
	canvas->clipRect(rect, SkClipOp::kIntersect, true);
	canvas->drawRect(rect, paint);
	canvas->restore();
}

KINE_SKIA_API void Kine_Skia_Surface_BeginMotionBlur(
	KineSkiaSurface *surface,
	float x, float y, float width, float height,
	float angleDegrees, float lengthPixels) {
	if (!surface || !surface->surface) {
		return;
	}

	SkCanvas *canvas = surface->surface->getCanvas();
	canvas->save();
	surface->motionBlurSaves = 1;

	const SkRect bounds = SkRect::MakeXYWH(x, y, width, height);

	if (lengthPixels <= 0.5f || width <= 0.0f || height <= 0.0f) {
		return;
	}

	int radius = static_cast<int>(std::ceil(lengthPixels));
	radius = std::max(3, radius | 1);
	radius = std::min(radius, 63);

	std::vector<SkScalar> kernel(
		static_cast<size_t>(radius) * static_cast<size_t>(radius), 0.0f);

	const float radians = angleDegrees *
		static_cast<float>(3.14159265358979323846) / 180.0f;
	const float dirX = std::cos(radians);
	const float dirY = std::sin(radians);
	const float half = (radius - 1) * 0.5f;

	int hits = 0;
	const int steps = std::max(1, static_cast<int>(std::ceil(lengthPixels)));
	for (int i = 0; i <= steps; ++i) {
		const float t = static_cast<float>(i) / static_cast<float>(steps) - 0.5f;
		const int ix = static_cast<int>(std::lround(half + dirX * t * lengthPixels));
		const int iy = static_cast<int>(std::lround(half + dirY * t * lengthPixels));

		if (ix >= 0 && ix < radius && iy >= 0 && iy < radius) {
			kernel[static_cast<size_t>(iy) * radius + ix] += 1.0f;
			++hits;
		}
	}

	if (hits == 0) {
		return;
	}

	const float gain = 1.0f / static_cast<float>(hits);
	const SkIPoint offset = SkIPoint::Make(radius / 2, radius / 2);

	sk_sp<SkImageFilter> filter = SkImageFilters::MatrixConvolution(
		SkISize::Make(radius, radius),
		kernel.data(),
		gain,
		0.0f,
		offset,
		SkTileMode::kClamp,
		true,
		nullptr);

	SkRect layerBounds = bounds;
	layerBounds.outset(lengthPixels + 2.0f, lengthPixels + 2.0f);

	SkPaint paint;
	paint.setAntiAlias(true);
	paint.setImageFilter(std::move(filter));

	canvas->saveLayer(&layerBounds, &paint);
	surface->motionBlurSaves = 2;
}

KINE_SKIA_API void Kine_Skia_Surface_EndMotionBlur(KineSkiaSurface *surface) {
	if (!surface || !surface->surface) {
		return;
	}

	SkCanvas *canvas = surface->surface->getCanvas();
	for (int i = 0; i < surface->motionBlurSaves; ++i) {
		canvas->restore();
	}
	surface->motionBlurSaves = 0;
}

KINE_SKIA_API void Kine_Skia_Surface_DrawBackdropBlurRect(
	KineSkiaSurface *surface,
	float x, float y, float width, float height,
	float radiusX, float radiusY,
	float blurSigma,
	uint8_t alpha,
	uint8_t tintR, uint8_t tintG, uint8_t tintB, uint8_t tintA) {
	if (!surface || !surface->surface || !surface->backdrop ||
		width <= 0.0f || height <= 0.0f || (alpha == 0 && tintA == 0)) {
		return;
	}

	SkCanvas *canvas = surface->surface->getCanvas();
	SkRect rect = SkRect::MakeXYWH(x, y, width, height);
	canvas->save();
	if (radiusX > 0.0f || radiusY > 0.0f) {
		canvas->clipRRect(SkRRect::MakeRectXY(rect, radiusX, radiusY), true);
	} else {
		canvas->clipRect(rect, SkClipOp::kIntersect, true);
	}

	SkPaint paint;
	paint.setAntiAlias(true);
	paint.setAlphaf(alpha / 255.0f);
	if (blurSigma > 0.0f) {
		paint.setImageFilter(SkImageFilters::Blur(
			blurSigma, blurSigma, SkTileMode::kClamp, nullptr));
	}
	canvas->drawImageRect(
		surface->backdrop,
		rect,
		rect,
		SkSamplingOptions(SkFilterMode::kLinear),
		&paint,
		SkCanvas::kStrict_SrcRectConstraint);
	if (tintA > 0) {
		SkPaint tintPaint;
		tintPaint.setAntiAlias(true);
		tintPaint.setStyle(SkPaint::kFill_Style);
		tintPaint.setColor(SkColorSetARGB(tintA, tintR, tintG, tintB));
		canvas->drawRect(rect, tintPaint);
	}
	canvas->restore();
}

KINE_SKIA_API void Kine_Skia_Surface_DrawBackdropBlurSquircle(
	KineSkiaSurface *surface,
	float x, float y, float width, float height,
	float radius, float exponent,
	float blurSigma,
	uint8_t alpha,
	uint8_t tintR, uint8_t tintG, uint8_t tintB, uint8_t tintA) {
	if (!surface || !surface->surface || !surface->backdrop ||
		width <= 0.0f || height <= 0.0f || (alpha == 0 && tintA == 0)) {
		return;
	}

	SkCanvas *canvas = surface->surface->getCanvas();
	SkRect rect = SkRect::MakeXYWH(x, y, width, height);
	canvas->save();
	canvas->clipPath(kine_skia_squircle_path(x, y, width, height, radius, exponent), true);

	SkPaint paint;
	paint.setAntiAlias(true);
	paint.setAlphaf(alpha / 255.0f);
	if (blurSigma > 0.0f) {
		paint.setImageFilter(SkImageFilters::Blur(
			blurSigma, blurSigma, SkTileMode::kClamp, nullptr));
	}
	canvas->drawImageRect(
		surface->backdrop,
		rect,
		rect,
		SkSamplingOptions(SkFilterMode::kLinear),
		&paint,
		SkCanvas::kStrict_SrcRectConstraint);
	if (tintA > 0) {
		SkPaint tintPaint;
		tintPaint.setAntiAlias(true);
		tintPaint.setStyle(SkPaint::kFill_Style);
		tintPaint.setColor(SkColorSetARGB(tintA, tintR, tintG, tintB));
		canvas->drawRect(rect, tintPaint);
	}
	canvas->restore();
}

KINE_SKIA_API void Kine_Skia_Surface_DrawCircle(
	KineSkiaSurface *surface,
	float cx, float cy, float radius,
	uint8_t r, uint8_t g, uint8_t b, uint8_t a,
	float strokeWidth) {
	if (!surface || !surface->surface || radius <= 0.0f) {
		return;
	}

	SkPaint paint = kine_skia_paint(r, g, b, a, strokeWidth);
	surface->surface->getCanvas()->drawCircle(cx, cy, radius, paint);
}

KINE_SKIA_API void Kine_Skia_Surface_DrawOval(
	KineSkiaSurface *surface,
	float x, float y, float width, float height,
	uint8_t r, uint8_t g, uint8_t b, uint8_t a,
	float strokeWidth) {
	if (!surface || !surface->surface || width <= 0.0f || height <= 0.0f) {
		return;
	}

	SkPaint paint = kine_skia_paint(r, g, b, a, strokeWidth);
	surface->surface->getCanvas()->drawOval(SkRect::MakeXYWH(x, y, width, height), paint);
}

KINE_SKIA_API void Kine_Skia_Surface_DrawArc(
	KineSkiaSurface *surface,
	float x, float y, float width, float height,
	float startAngle, float sweepAngle, int useCenter,
	uint8_t r, uint8_t g, uint8_t b, uint8_t a,
	float strokeWidth) {
	if (!surface || !surface->surface || width <= 0.0f || height <= 0.0f) {
		return;
	}

	SkPaint paint = kine_skia_paint(r, g, b, a, strokeWidth);
	surface->surface->getCanvas()->drawArc(
		SkRect::MakeXYWH(x, y, width, height),
		startAngle, sweepAngle, useCenter != 0, paint);
}

KINE_SKIA_API void Kine_Skia_Surface_DrawLine(
	KineSkiaSurface *surface,
	float x0, float y0, float x1, float y1,
	float strokeWidth,
	uint8_t r, uint8_t g, uint8_t b, uint8_t a) {
	if (!surface || !surface->surface || strokeWidth <= 0.0f) {
		return;
	}

	SkPaint paint;
	paint.setAntiAlias(true);
	paint.setColor(SkColorSetARGB(a, r, g, b));
	paint.setStyle(SkPaint::kStroke_Style);
	paint.setStrokeWidth(strokeWidth);

	surface->surface->getCanvas()->drawLine(x0, y0, x1, y1, paint);
}

KINE_SKIA_API void Kine_Skia_Surface_DrawPolygon(
	KineSkiaSurface *surface,
	const float *points, int pointCount,
	int closed,
	uint8_t r, uint8_t g, uint8_t b, uint8_t a,
	float strokeWidth) {
	if (!surface || !surface->surface || !points || pointCount < 2) {
		return;
	}

	SkPathBuilder builder;
	builder.moveTo(points[0], points[1]);
	for (int i = 1; i < pointCount; ++i) {
		builder.lineTo(points[i * 2], points[i * 2 + 1]);
	}
	if (closed) {
		builder.close();
	}
	SkPath path = builder.detach();

	SkPaint paint = kine_skia_paint(r, g, b, a, strokeWidth);
	surface->surface->getCanvas()->drawPath(path, paint);
}

/* ---------------- Transform stack ---------------- */

KINE_SKIA_API void Kine_Skia_Surface_Save(KineSkiaSurface *surface) {
	if (!surface || !surface->surface)
		return;
	surface->surface->getCanvas()->save();
}

KINE_SKIA_API void Kine_Skia_Surface_Restore(KineSkiaSurface *surface) {
	if (!surface || !surface->surface)
		return;
	surface->surface->getCanvas()->restore();
}

KINE_SKIA_API void Kine_Skia_Surface_Translate(KineSkiaSurface *surface, float dx, float dy) {
	if (!surface || !surface->surface)
		return;
	surface->surface->getCanvas()->translate(dx, dy);
}

KINE_SKIA_API void Kine_Skia_Surface_Rotate(KineSkiaSurface *surface, float degrees) {
	if (!surface || !surface->surface)
		return;
	surface->surface->getCanvas()->rotate(degrees);
}

KINE_SKIA_API void Kine_Skia_Surface_Scale(KineSkiaSurface *surface, float sx, float sy) {
	if (!surface || !surface->surface)
		return;
	surface->surface->getCanvas()->scale(sx, sy);
}

KINE_SKIA_API void Kine_Skia_Surface_ClipRect(
	KineSkiaSurface *surface,
	float x, float y, float width, float height) {
	if (!surface || !surface->surface)
		return;
	surface->surface->getCanvas()->clipRect(SkRect::MakeXYWH(x, y, width, height));
}

KINE_SKIA_API void Kine_Skia_Surface_ClipRoundRect(
	KineSkiaSurface *surface,
	float x, float y, float width, float height,
	float radiusX, float radiusY) {
	if (!surface || !surface->surface || width <= 0.0f || height <= 0.0f)
		return;

	SkRRect rrect = SkRRect::MakeRectXY(
		SkRect::MakeXYWH(x, y, width, height), radiusX, radiusY);

	surface->surface->getCanvas()->clipRRect(rrect, /*doAntiAlias=*/true);
}

KINE_SKIA_API void Kine_Skia_Surface_ClipSquircle(
	KineSkiaSurface *surface,
	float x, float y, float width, float height,
	float radius, float exponent) {
	if (!surface || !surface->surface || width <= 0.0f || height <= 0.0f)
		return;

	surface->surface->getCanvas()->clipPath(
		kine_skia_squircle_path(x, y, width, height, radius, exponent),
		/*doAntiAlias=*/true);
}

KINE_SKIA_API void Kine_Skia_Surface_ClipSquircleCorners(
	KineSkiaSurface *surface,
	float x, float y, float width, float height,
	float radiusTL, float radiusTR, float radiusBR, float radiusBL,
	float exponent) {
	if (!surface || !surface->surface || width <= 0.0f || height <= 0.0f)
		return;

	surface->surface->getCanvas()->clipPath(
		kine_skia_squircle_path_corners(
			x, y, width, height, radiusTL, radiusTR, radiusBR, radiusBL, exponent),
		/*doAntiAlias=*/true);
}

/* ---------------- Text ---------------- */

KINE_SKIA_API void Kine_Skia_Surface_DrawText(
	KineSkiaSurface *surface,
	const char *text,
	float x, float y,
	float fontSize,
	const char *fontPath,
	uint8_t r, uint8_t g, uint8_t b, uint8_t a) {
	if (!surface || !surface->surface || !text || !text[0]) {
		return;
	}

	sk_sp<SkTypeface> typeface = kine_skia_get_typeface(fontPath);
	if (!typeface) {
		return;
	}

	SkFont font(typeface, fontSize);
	font.setEdging(SkFont::Edging::kAntiAlias);

	sk_sp<SkTextBlob> blob = SkTextBlob::MakeFromText(
		text, strlen(text), font, SkTextEncoding::kUTF8);
	if (!blob) {
		return;
	}

	SkPaint paint;
	paint.setAntiAlias(true);
	paint.setColor(SkColorSetARGB(a, r, g, b));

	surface->surface->getCanvas()->drawTextBlob(blob, x, y, paint);
}

KINE_SKIA_API void Kine_Skia_Surface_DrawTextShadow(
	KineSkiaSurface *surface,
	const char *text,
	float x, float y,
	float fontSize,
	const char *fontPath,

	float offsetX,
	float offsetY,
	float blurSigma,
	float spread,

	uint8_t shadowR,
	uint8_t shadowG,
	uint8_t shadowB,
	uint8_t shadowA) {
	if (!surface || !surface->surface || !text || !text[0] ||
		fontSize <= 0.0f || shadowA == 0) {
		return;
	}

	sk_sp<SkTypeface> typeface = kine_skia_get_typeface(fontPath);

	if (!typeface) {
		return;
	}

	SkFont font(typeface, fontSize);
	font.setEdging(SkFont::Edging::kAntiAlias);

	sk_sp<SkTextBlob> blob = SkTextBlob::MakeFromText(
		text,
		strlen(text),
		font,
		SkTextEncoding::kUTF8);

	if (!blob) {
		return;
	}

	SkPaint shadowPaint;
	shadowPaint.setAntiAlias(true);
	shadowPaint.setColor(
		SkColorSetARGB(
			shadowA,
			shadowR,
			shadowG,
			shadowB));

	if (spread > 0.0f) {
		shadowPaint.setStyle(SkPaint::kStrokeAndFill_Style);
		shadowPaint.setStrokeWidth(spread * 2.0f);
		shadowPaint.setStrokeJoin(SkPaint::kRound_Join);
	} else {
		shadowPaint.setStyle(SkPaint::kFill_Style);
	}

	if (blurSigma > 0.0f) {
		shadowPaint.setMaskFilter(
			SkMaskFilter::MakeBlur(
				kNormal_SkBlurStyle,
				blurSigma));
	}

	surface->surface->getCanvas()->drawTextBlob(
		blob,
		x + offsetX,
		y + offsetY,
		shadowPaint);
}

KINE_SKIA_API KineSkiaTypeface *Kine_Skia_Typeface_LoadFromMemory(
	const uint8_t *data,
	size_t size) {
	if (!data || size == 0) {
		return nullptr;
	}

	auto &cache = kine_skia_memory_typeface_cache();
	const size_t key = kine_skia_font_hash(data, size);

	auto it = cache.find(key);
	if (it != cache.end()) {
		const KineSkiaMemoryTypefaceEntry &entry = it->second;
		if (entry.bytes.size() == size &&
			memcmp(entry.bytes.data(), data, size) == 0 &&
			entry.typeface) {
			auto *wrapper = new KineSkiaTypeface();
			wrapper->typeface = entry.typeface;
			return wrapper;
		}
	}

#if defined(_WIN32)
	sk_sp<SkFontMgr> mgr = SkFontMgr_New_DirectWrite();
#elif defined(__ANDROID__)
	sk_sp<SkFontMgr> mgr = SkFontMgr_New_AndroidNDK(false, SkFontScanner_Make_FreeType());
#elif defined(__APPLE__)
	sk_sp<SkFontMgr> mgr = SkFontMgr_New_CoreText(nullptr);
#else
	sk_sp<SkFontMgr> mgr =
		SkFontMgr_New_FontConfig(
			nullptr,
			SkFontScanner_Make_FreeType());
#endif

	if (!mgr) {
		return nullptr;
	}

	sk_sp<SkData> fontData =
		SkData::MakeWithCopy(data, size);

	if (!fontData) {
		return nullptr;
	}

	sk_sp<SkTypeface> typeface =
		mgr->makeFromData(
			fontData,
			0);

	if (!typeface) {
		return nullptr;
	}

	KineSkiaMemoryTypefaceEntry entry;
	entry.bytes.assign(data, data + size);
	entry.typeface = typeface;
	cache[key] = std::move(entry);

	auto *wrapper = new KineSkiaTypeface();
	wrapper->typeface = std::move(typeface);

	return wrapper;
}

KINE_SKIA_API KineSkiaTypeface *Kine_Skia_Typeface_LoadFromFile(
	const char *path) {
	if (!path || !path[0]) {
		return nullptr;
	}

	sk_sp<SkTypeface> typeface =
		kine_skia_get_typeface(path);

	if (!typeface) {
		return nullptr;
	}

	auto *wrapper = new KineSkiaTypeface();
	wrapper->typeface = std::move(typeface);

	return wrapper;
}

KINE_SKIA_API void Kine_Skia_Typeface_Destroy(
	KineSkiaTypeface *typeface) {
	delete typeface;
}

KINE_SKIA_API void Kine_Skia_Surface_DrawTextTypeface(
	KineSkiaSurface *surface,
	const char *text,
	float x,
	float y,
	float fontSize,
	KineSkiaTypeface *typeface,
	uint8_t r,
	uint8_t g,
	uint8_t b,
	uint8_t a) {
	if (!surface ||
		!surface->surface ||
		!text ||
		!text[0] ||
		!typeface ||
		!typeface->typeface) {
		return;
	}

	SkFont font(
		typeface->typeface,
		fontSize);

	font.setEdging(
		SkFont::Edging::kAntiAlias);

	sk_sp<SkTextBlob> blob =
		SkTextBlob::MakeFromText(
			text,
			strlen(text),
			font,
			SkTextEncoding::kUTF8);

	if (!blob) {
		return;
	}

	SkPaint paint;
	paint.setAntiAlias(true);
	paint.setColor(
		SkColorSetARGB(
			a,
			r,
			g,
			b));

	surface->surface
		->getCanvas()
		->drawTextBlob(
			blob,
			x,
			y,
			paint);
}

KINE_SKIA_API void Kine_Skia_Surface_DrawTextShadowTypeface(
	KineSkiaSurface *surface,
	const char *text,
	float x,
	float y,
	float fontSize,
	KineSkiaTypeface *typeface,

	float offsetX,
	float offsetY,
	float blurSigma,
	float spread,

	uint8_t shadowR,
	uint8_t shadowG,
	uint8_t shadowB,
	uint8_t shadowA) {
	if (!surface ||
		!surface->surface ||
		!text ||
		!text[0] ||
		!typeface ||
		!typeface->typeface ||
		shadowA == 0) {
		return;
	}

	SkFont font(
		typeface->typeface,
		fontSize);

	font.setEdging(
		SkFont::Edging::kAntiAlias);

	sk_sp<SkTextBlob> blob =
		SkTextBlob::MakeFromText(
			text,
			strlen(text),
			font,
			SkTextEncoding::kUTF8);

	if (!blob) {
		return;
	}

	SkPaint paint;

	paint.setAntiAlias(true);

	paint.setColor(
		SkColorSetARGB(
			shadowA,
			shadowR,
			shadowG,
			shadowB));

	if (spread > 0.0f) {
		paint.setStyle(
			SkPaint::kStrokeAndFill_Style);

		paint.setStrokeWidth(
			spread * 2.0f);

		paint.setStrokeJoin(
			SkPaint::kRound_Join);
	}

	if (blurSigma > 0.0f) {
		paint.setMaskFilter(
			SkMaskFilter::MakeBlur(
				kNormal_SkBlurStyle,
				blurSigma));
	}

	surface->surface
		->getCanvas()
		->drawTextBlob(
			blob,
			x + offsetX,
			y + offsetY,
			paint);
}

KINE_SKIA_API float Kine_Skia_Typeface_MeasureText(
	KineSkiaTypeface *typeface,
	const char *text,
	float fontSize) {
	if (!typeface ||
		!typeface->typeface ||
		!text ||
		fontSize <= 0.0f) {
		return 0.0f;
	}

	SkFont font(typeface->typeface, fontSize);

	return font.measureText(
		text,
		strlen(text),
		SkTextEncoding::kUTF8);
}

KINE_SKIA_API float Kine_Skia_Typeface_GetLineHeight(
	KineSkiaTypeface *typeface,
	float fontSize) {
	if (!typeface ||
		!typeface->typeface ||
		fontSize <= 0.0f) {
		return 0.0f;
	}

	SkFont font(typeface->typeface, fontSize);

	SkFontMetrics metrics;
	font.getMetrics(&metrics);

	return (-metrics.fAscent) +
		   metrics.fDescent +
		   metrics.fLeading;
}

KINE_SKIA_API float Kine_Skia_Typeface_GetAscent(
	KineSkiaTypeface *typeface,
	float fontSize) {
	if (!typeface ||
		!typeface->typeface ||
		fontSize <= 0.0f) {
		return 0.0f;
	}

	SkFont font(typeface->typeface, fontSize);

	SkFontMetrics metrics;
	font.getMetrics(&metrics);

	return -metrics.fAscent;
}

KINE_SKIA_API float Kine_Skia_Surface_MeasureText(
	const char *text,
	float fontSize,
	const char *fontPath) {
	if (!text || fontSize <= 0.0f) {
		return 0.0f;
	}

	sk_sp<SkTypeface> tf = kine_skia_get_typeface(fontPath);
	SkFont font(tf, fontSize);
	return font.measureText(text, strlen(text), SkTextEncoding::kUTF8);
}

KINE_SKIA_API float Kine_Skia_Surface_GetFontLineHeight(
	float fontSize,
	const char *fontPath) {
	if (fontSize <= 0.0f) {
		return 0.0f;
	}

	sk_sp<SkTypeface> tf = kine_skia_get_typeface(fontPath);
	SkFont font(tf, fontSize);

	SkFontMetrics metrics;
	font.getMetrics(&metrics);

	return (-metrics.fAscent) + metrics.fDescent + metrics.fLeading;
}

/* ---------------- Images ---------------- */

static constexpr int kine_skia_min_frame_duration_ms = 10;

static bool kine_skia_data_is_gif(const sk_sp<SkData> &data) {
	if (!data || data->size() < 6) {
		return false;
	}

	const char *bytes = static_cast<const char *>(data->data());

	return std::memcmp(bytes, "GIF87a", 6) == 0 ||
		   std::memcmp(bytes, "GIF89a", 6) == 0;
}

static int kine_skia_frame_duration(int durationMs) {
	return durationMs > kine_skia_min_frame_duration_ms
		? durationMs
		: kine_skia_min_frame_duration_ms;
}

/*
 * GIFs need SkAnimatedImage rather than a plain SkImage so that all of the
 * existing draw entry points keep working: the current frame is mirrored into
 * KineSkiaImage::image, and every draw call advances the animation first.
 */
static KineSkiaImage *kine_skia_load_animated_gif(
	const sk_sp<SkData> &data) {
	if (!kine_skia_data_is_gif(data)) {
		return nullptr;
	}

	std::unique_ptr<SkAndroidCodec> codec =
		SkAndroidCodec::MakeFromData(data);

	if (!codec) {
		return nullptr;
	}

	sk_sp<SkAnimatedImage> animated =
		SkAnimatedImage::Make(std::move(codec));

	if (!animated) {
		return nullptr;
	}

	sk_sp<SkImage> frame = animated->getCurrentFrame();

	if (!frame) {
		return nullptr;
	}

	auto *wrapper = new KineSkiaImage();

	wrapper->width = static_cast<float>(frame->width());
	wrapper->height = static_cast<float>(frame->height());
	wrapper->image = std::move(frame);
	wrapper->animated = std::move(animated);
	wrapper->animationFrameDurationMs = kine_skia_frame_duration(
		wrapper->animated->currentFrameDuration());

	return wrapper;
}

static void kine_skia_image_advance_animation(KineSkiaImage *image) {
	if (!image || !image->animated || image->animationFinished) {
		return;
	}

	const auto now = std::chrono::steady_clock::now();

	if (!image->animationStarted) {
		image->animationStarted = true;
		image->animationStartedAt = now;
		return;
	}

	const int minDuration = kine_skia_min_frame_duration_ms;

	/*
	 * Catch up after a stall without letting a very old image decode an
	 * unbounded number of frames in a single draw.
	 */
	for (int step = 0; step < 120; step++) {
		const int duration = kine_skia_frame_duration(
			image->animationFrameDurationMs);

		const auto elapsed =
			std::chrono::duration_cast<std::chrono::milliseconds>(
				now - image->animationStartedAt).count();

		if (elapsed < duration) {
			break;
		}

		const auto nextStart =
			image->animationStartedAt + std::chrono::milliseconds(duration);

		const int nextDuration = image->animated->decodeNextFrame();

		image->animationStartedAt = nextStart;

		sk_sp<SkImage> frame = image->animated->getCurrentFrame();

		if (frame) {
			image->image = std::move(frame);
		}

		if (nextDuration == SkAnimatedImage::kFinished) {
			image->animationFinished = true;
			break;
		}

		image->animationFrameDurationMs = nextDuration > 0
			? std::max(nextDuration, minDuration)
			: minDuration;
	}
}

KINE_SKIA_API KineSkiaImage *Kine_Skia_Image_LoadFromFile(const char *path) {
	if (!path || path[0] == '\0') {
		return nullptr;
	}

	sk_sp<SkData> data = SkData::MakeFromFileName(path);
	if (!data) {
		fprintf(stderr, "kine_skia: failed to read image file '%s'\n", path);
		return nullptr;
	}

	if (KineSkiaImage *animated = kine_skia_load_animated_gif(data)) {
		return animated;
	}

	sk_sp<SkImage> raster = SkImages::DeferredFromEncodedData(data);

	if (raster) {
		auto *wrapper = new KineSkiaImage();

		wrapper->width = static_cast<float>(raster->width());
		wrapper->height = static_cast<float>(raster->height());
		wrapper->image = std::move(raster);

		return wrapper;
	}

	float width = 0.0f;
	float height = 0.0f;

	sk_sp<SkSVGDOM> svg = kine_skia_decode_svg(
		data,
		&width,
		&height);

	if (svg) {
		auto *wrapper = new KineSkiaImage();

		wrapper->svg = std::move(svg);
		wrapper->width = width;
		wrapper->height = height;

		return wrapper;
	}

	fprintf(
		stderr,
		"kine_skia: failed to decode raster or SVG image '%s'\n",
		path);

	return nullptr;
}

KINE_SKIA_API KineSkiaImage *Kine_Skia_Image_LoadFromMemory(
	const uint8_t *data,
	size_t size) {
	if (!data || size == 0) {
		return nullptr;
	}

	sk_sp<SkData> skData = SkData::MakeWithCopy(data, size);

	if (KineSkiaImage *animated = kine_skia_load_animated_gif(skData)) {
		return animated;
	}

	sk_sp<SkImage> raster =
		SkImages::DeferredFromEncodedData(skData);

	if (raster) {
		auto *wrapper = new KineSkiaImage();

		wrapper->width = static_cast<float>(raster->width());
		wrapper->height = static_cast<float>(raster->height());
		wrapper->image = std::move(raster);

		return wrapper;
	}

	float width = 0.0f;
	float height = 0.0f;

	sk_sp<SkSVGDOM> svg = kine_skia_decode_svg(
		skData,
		&width,
		&height);

	if (svg) {
		auto *wrapper = new KineSkiaImage();

		wrapper->svg = std::move(svg);
		wrapper->width = width;
		wrapper->height = height;

		return wrapper;
	}

	fprintf(
		stderr,
		"kine_skia: failed to decode raster or SVG image from memory buffer\n");

	return nullptr;
}

KINE_SKIA_API KineSkiaImage *Kine_Skia_Image_WrapVulkan(KineSkiaVulkanContext *context,
        int width, int height, const KineSkiaVulkanImageInfo *info) {
#if KINE_SKIA_BUILD_VULKAN
    if (!context || !context->context || !info || !info->image || width <= 0 || height <= 0) return nullptr;
    GrVkImageInfo vk{};
    vk.fImage = reinterpret_cast<VkImage>(info->image);
    vk.fImageLayout = static_cast<VkImageLayout>(info->imageLayout);
    vk.fImageTiling = VK_IMAGE_TILING_OPTIMAL;
    vk.fFormat = static_cast<VkFormat>(info->format);
    vk.fImageUsageFlags = info->imageUsageFlags;
    vk.fSampleCount = 1; vk.fLevelCount = 1;
    vk.fCurrentQueueFamily = VK_QUEUE_FAMILY_IGNORED;
    auto backend = GrBackendTextures::MakeVk(width, height, vk);
    auto image = SkImages::BorrowTextureFrom(context->context.get(), backend,
        kTopLeft_GrSurfaceOrigin, kRGBA_8888_SkColorType, kPremul_SkAlphaType, nullptr);
    if (!image) return nullptr;
    auto *result = new KineSkiaImage();
    result->strictSourceRect = true; result->image = std::move(image); result->width = float(width); result->height = float(height);
    return result;
#else
    (void)context; (void)width; (void)height; (void)info; return nullptr;
#endif
}
KINE_SKIA_API KineSkiaImage *Kine_Skia_Image_WrapGL(KineSkiaSurface *surface,
        uint32_t texture, int width, int height) {
#if KINE_SKIA_BUILD_GL
    if (!surface || !surface->glContext || !texture) return nullptr;
    GrGLTextureInfo info{};
    info.fTarget = 0x0DE1; info.fID = texture; info.fFormat = 0x8058;
    auto backend = GrBackendTextures::MakeGL(width, height, skgpu::Mipmapped::kNo, info);
    auto image = SkImages::BorrowTextureFrom(surface->glContext.get(), backend,
        kBottomLeft_GrSurfaceOrigin, kRGBA_8888_SkColorType, kPremul_SkAlphaType, nullptr);
    if (!image) return nullptr;
    auto *result = new KineSkiaImage();
    result->strictSourceRect = true; result->image = std::move(image); result->width = float(width); result->height = float(height);
    return result;
#else
    (void)surface; (void)texture; (void)width; (void)height; return nullptr;
#endif
}

KINE_SKIA_API void Kine_Skia_Image_Destroy(KineSkiaImage *image) {
	delete image;
}

KINE_SKIA_API int Kine_Skia_Image_GetWidth(const KineSkiaImage *image) {
	if (!image) {
		return 0;
	}

	return static_cast<int>(std::round(image->width));
}

KINE_SKIA_API int Kine_Skia_Image_GetHeight(const KineSkiaImage *image) {
	if (!image) {
		return 0;
	}

	return static_cast<int>(std::round(image->height));
}

KINE_SKIA_API void Kine_Skia_Surface_DrawImage(
	KineSkiaSurface *surface,
	KineSkiaImage *image,
	float x,
	float y,
	uint8_t alpha) {
	if (!surface || !surface->surface || !image) {
		return;
	}

	kine_skia_image_advance_animation(image);

	if (image->svg) {
		kine_skia_draw_svg(
			surface->surface->getCanvas(),
			image,
			x,
			y,
			image->width,
			image->height,
			alpha);

		return;
	}

	if (!image->image) {
		return;
	}

	SkPaint paint;
	paint.setAntiAlias(true);

	if (alpha < 255) {
		paint.setAlphaf(alpha / 255.0f);
	}

	surface->surface->getCanvas()->drawImage(
		image->image,
		x,
		y,
		SkSamplingOptions(),
		&paint);
}

KINE_SKIA_API void Kine_Skia_Surface_DrawImageSized(
	KineSkiaSurface *surface,
	KineSkiaImage *image,
	float x,
	float y,
	float width,
	float height,
	uint8_t alpha) {
	if (!surface || !surface->surface || !image) {
		return;
	}

	if (width <= 0.0f || height <= 0.0f) {
		return;
	}

	kine_skia_image_advance_animation(image);

	if (image->svg) {
		kine_skia_draw_svg(
			surface->surface->getCanvas(),
			image,
			x,
			y,
			width,
			height,
			alpha);

		return;
	}

	if (!image->image) {
		return;
	}

	SkPaint paint;
	paint.setAntiAlias(true);

	if (alpha < 255) {
		paint.setAlphaf(alpha / 255.0f);
	}

	const SkRect dst =
		SkRect::MakeXYWH(x, y, width, height);

	surface->surface->getCanvas()->drawImageRect(
		image->image,
		dst,
		SkSamplingOptions(SkFilterMode::kLinear),
		&paint);
}

KINE_SKIA_API void Kine_Skia_Surface_DrawPixels(
	KineSkiaSurface *surface,
	const void *pixels,
	int sourceWidth, int sourceHeight,
	uint32_t sourceRowBytes,
	float x, float y,
	float width, float height,
	bool flipY,
	uint8_t alpha) {
	if (!surface || !surface->surface || !pixels ||
		sourceWidth <= 0 || sourceHeight <= 0 || sourceRowBytes == 0 ||
		width <= 0.0f || height <= 0.0f) {
		return;
	}

	SkImageInfo info = SkImageInfo::Make(
		sourceWidth,
		sourceHeight,
		kRGBA_8888_SkColorType,
		kPremul_SkAlphaType);
	SkPixmap pixmap(info, pixels, sourceRowBytes);
	sk_sp<SkImage> image = SkImages::RasterFromPixmapCopy(pixmap);
	if (!image)
		return;

	SkPaint paint;
	paint.setAntiAlias(true);
	if (alpha < 255)
		paint.setAlphaf(alpha / 255.0f);

	SkCanvas *canvas = surface->surface->getCanvas();
	canvas->save();
	if (flipY) {
		canvas->translate(x, y + height);
		canvas->scale(1.0f, -1.0f);
		x = 0.0f;
		y = 0.0f;
	}
	canvas->drawImageRect(
		image,
		SkRect::MakeXYWH(x, y, width, height),
		SkSamplingOptions(SkFilterMode::kLinear),
		&paint);
	canvas->restore();
}

KINE_SKIA_API void Kine_Skia_Surface_DrawImageOutlineSized(
	KineSkiaSurface *surface,
	KineSkiaImage *image,
	float x, float y,
	float width, float height,
	float thickness,
	uint8_t r, uint8_t g, uint8_t b, uint8_t a,
	uint8_t alpha) {
	if (!surface || !surface->surface || !image ||
		width <= 0.0f || height <= 0.0f || thickness <= 0.0f || a == 0) {
		return;
	}

	kine_skia_image_advance_animation(image);

	if (!image->image) {
		return;
	}

	SkRect dst = SkRect::MakeXYWH(x, y, width, height);
	SkRect layerBounds = dst;
	layerBounds.outset(thickness, thickness);
	SkCanvas *canvas = surface->surface->getCanvas();

	SkPaint outlinePaint;
	outlinePaint.setAntiAlias(true);
	outlinePaint.setImageFilter(SkImageFilters::Dilate(thickness, thickness, nullptr));

	canvas->saveLayer(&layerBounds, nullptr);
	canvas->drawImageRect(
		image->image,
		dst,
		SkSamplingOptions(SkFilterMode::kLinear),
		&outlinePaint);

	SkPaint tintPaint;
	tintPaint.setAntiAlias(true);
	tintPaint.setStyle(SkPaint::kFill_Style);
	tintPaint.setColor(SkColorSetARGB(a, r, g, b));
	tintPaint.setBlendMode(SkBlendMode::kSrcIn);
	canvas->drawRect(layerBounds, tintPaint);
	canvas->restore();

	SkPaint imagePaint;
	imagePaint.setAntiAlias(true);
	if (alpha < 255) {
		imagePaint.setAlphaf(alpha / 255.0f);
	}
	canvas->drawImageRect(
		image->image,
		dst,
		SkSamplingOptions(SkFilterMode::kLinear),
		&imagePaint);
}

KINE_SKIA_API void Kine_Skia_Surface_DrawImageShadow(
	KineSkiaSurface *surface,
	KineSkiaImage *image,
	float x, float y,
	float width, float height,
	float offsetX, float offsetY,
	float blurSigma, float spread,
	uint8_t r, uint8_t g, uint8_t b, uint8_t a) {
	if (!surface || !surface->surface || !image ||
		width <= 0.0f || height <= 0.0f || a == 0) {
		return;
	}

	kine_skia_image_advance_animation(image);

	if (!image->image && !image->svg) {
		return;
	}

	SkCanvas *canvas = surface->surface->getCanvas();

	const SkRect srcRect =
		SkRect::MakeXYWH(x, y, width, height);

	sk_sp<SkImageFilter> inputFilter = nullptr;

	// Spread should expand the alpha silhouette, not resize the image.
	if (spread > 0.0f) {
		inputFilter = SkImageFilters::Dilate(
			spread,
			spread,
			nullptr);
	}

	sk_sp<SkImageFilter> shadowFilter =
		SkImageFilters::DropShadowOnly(
			offsetX,
			offsetY,
			std::max(0.0f, blurSigma),
			std::max(0.0f, blurSigma),
			SkColorSetARGB(a, r, g, b),
			std::move(inputFilter));

	SkPaint layerPaint;
	layerPaint.setAntiAlias(true);
	layerPaint.setImageFilter(std::move(shadowFilter));

	// Blur normally needs significantly more room than one sigma.
	const float blurPadding =
		std::max(0.0f, blurSigma) * 3.0f;

	const float padding =
		std::max(0.0f, spread) + blurPadding;

	SkRect layerBounds = srcRect;
	layerBounds.outset(
		padding + std::abs(offsetX),
		padding + std::abs(offsetY));

	canvas->saveLayer(&layerBounds, &layerPaint);

	if (image->svg) {
		kine_skia_draw_svg(
			canvas,
			image,
			x,
			y,
			width,
			height,
			255);
	} else {
		SkPaint imagePaint;
		imagePaint.setAntiAlias(true);

		canvas->drawImageRect(
			image->image,
			srcRect,
			SkSamplingOptions(SkFilterMode::kLinear),
			&imagePaint);
	}

	canvas->restore();
}

KINE_SKIA_API float Kine_Skia_Surface_GetFontAscent(
	float fontSize,
	const char *fontPath) {
	if (fontSize <= 0.0f) {
		return 0.0f;
	}

	sk_sp<SkTypeface> tf = kine_skia_get_typeface(fontPath);
	SkFont font(tf, fontSize);

	SkFontMetrics metrics;
	font.getMetrics(&metrics);

	return -metrics.fAscent;
}

KINE_SKIA_API void Kine_Skia_Surface_DrawTextBlurred(
	KineSkiaSurface *surface,
	const char *text,
	float x,
	float y,
	float fontSize,
	const char *fontPath,
	float blurSigma,
	uint8_t r,
	uint8_t g,
	uint8_t b,
	uint8_t a) {
	if (!surface ||
		!surface->surface ||
		!text ||
		!text[0] ||
		fontSize <= 0.0f ||
		a == 0) {
		return;
	}

	sk_sp<SkTypeface> typeface =
		kine_skia_get_typeface(fontPath);

	if (!typeface) {
		return;
	}

	SkFont font(typeface, fontSize);
	font.setEdging(SkFont::Edging::kAntiAlias);

	sk_sp<SkTextBlob> blob = SkTextBlob::MakeFromText(
		text,
		strlen(text),
		font,
		SkTextEncoding::kUTF8);

	if (!blob) {
		return;
	}

	SkPaint paint;
	paint.setAntiAlias(true);
	paint.setColor(SkColorSetARGB(a, r, g, b));

	if (blurSigma > 0.0f) {
		paint.setMaskFilter(
			SkMaskFilter::MakeBlur(
				kNormal_SkBlurStyle,
				blurSigma));
	}

	surface->surface
		->getCanvas()
		->drawTextBlob(
			blob,
			x,
			y,
			paint);
}

KINE_SKIA_API void Kine_Skia_Surface_DrawTextBlurredTypeface(
	KineSkiaSurface *surface,
	const char *text,
	float x,
	float y,
	float fontSize,
	KineSkiaTypeface *typeface,
	float blurSigma,
	uint8_t r,
	uint8_t g,
	uint8_t b,
	uint8_t a) {
	if (!surface ||
		!surface->surface ||
		!text ||
		!text[0] ||
		!typeface ||
		!typeface->typeface ||
		fontSize <= 0.0f ||
		a == 0) {
		return;
	}

	SkFont font(typeface->typeface, fontSize);
	font.setEdging(SkFont::Edging::kAntiAlias);

	sk_sp<SkTextBlob> blob = SkTextBlob::MakeFromText(
		text,
		strlen(text),
		font,
		SkTextEncoding::kUTF8);

	if (!blob) {
		return;
	}

	SkPaint paint;
	paint.setAntiAlias(true);
	paint.setColor(SkColorSetARGB(a, r, g, b));

	if (blurSigma > 0.0f) {
		paint.setMaskFilter(
			SkMaskFilter::MakeBlur(
				kNormal_SkBlurStyle,
				blurSigma));
	}

	surface->surface
		->getCanvas()
		->drawTextBlob(
			blob,
			x,
			y,
			paint);
}

KINE_SKIA_API void Kine_Skia_Surface_DrawImageBlurredSized(
	KineSkiaSurface *surface,
	KineSkiaImage *image,
	float x,
	float y,
	float width,
	float height,
	float blurSigma,
	uint8_t alpha) {
	if (!surface ||
		!surface->surface ||
		!image ||
		width <= 0.0f ||
		height <= 0.0f ||
		alpha == 0) {
		return;
	}

	kine_skia_image_advance_animation(image);

	if (!image->image && !image->svg) {
		return;
	}

	if (blurSigma <= 0.0f) {
		Kine_Skia_Surface_DrawImageSized(
			surface,
			image,
			x,
			y,
			width,
			height,
			alpha);
		return;
	}

	SkCanvas *canvas =
		surface->surface->getCanvas();

	const SkRect dst =
		SkRect::MakeXYWH(
			x,
			y,
			width,
			height);

	const float padding =
		std::max(0.0f, blurSigma) * 3.0f;

	SkRect layerBounds = dst;
	layerBounds.outset(
		padding,
		padding);

	SkPaint blurPaint;
	blurPaint.setAntiAlias(true);
	blurPaint.setImageFilter(
		SkImageFilters::Blur(
			blurSigma,
			blurSigma,
			SkTileMode::kDecal,
			nullptr));

	canvas->saveLayer(
		&layerBounds,
		&blurPaint);

	if (image->svg) {
		kine_skia_draw_svg(
			canvas,
			image,
			x,
			y,
			width,
			height,
			alpha);
	} else {
		SkPaint imagePaint;
		imagePaint.setAntiAlias(true);

		if (alpha < 255) {
			imagePaint.setAlphaf(
				alpha / 255.0f);
		}

		canvas->drawImageRect(
			image->image,
			dst,
			SkSamplingOptions(
				SkFilterMode::kLinear),
			&imagePaint);
	}

	canvas->restore();
}

KINE_SKIA_API void Kine_Skia_Surface_DrawImageRect(
	KineSkiaSurface *surface,
	KineSkiaImage *image,
	float srcX, float srcY, float srcWidth, float srcHeight,
	float dstX, float dstY, float dstWidth, float dstHeight,
	uint8_t alpha) {
	if (!surface || !surface->surface || !image) {
		return;
	}
	if (srcWidth <= 0.0f || srcHeight <= 0.0f || dstWidth <= 0.0f || dstHeight <= 0.0f) {
		return;
	}

	kine_skia_image_advance_animation(image);

	if (!image->image) {
		return;
	}

	SkPaint paint;
	paint.setAntiAlias(true);
	if (alpha < 255) {
		paint.setAlphaf(alpha / 255.0f);
	}

	SkRect src = SkRect::MakeXYWH(srcX, srcY, srcWidth, srcHeight);
	SkRect dst = SkRect::MakeXYWH(dstX, dstY, dstWidth, dstHeight);

	surface->surface->getCanvas()->drawImageRect(
		image->image, src, dst,
		SkSamplingOptions(SkFilterMode::kLinear),
		&paint,
		SkCanvas::kStrict_SrcRectConstraint);
}

KINE_SKIA_API void Kine_Skia_Surface_DrawImageScaled(
	KineSkiaSurface *surface,
	KineSkiaImage *image,
	float srcX, float srcY, float srcWidth, float srcHeight,
	float dstX, float dstY, float dstWidth, float dstHeight,
	float tileSizeX, float tileSizeY,
	int scaleType,
	int resample,
	uint8_t r, uint8_t g, uint8_t b, uint8_t colorA,
	uint8_t alpha) {
	if (!surface || !surface->surface || !image ||
		dstWidth <= 0.0f || dstHeight <= 0.0f || alpha == 0) {
		return;
	}

	kine_skia_image_advance_animation(image);

	SkCanvas *canvas = surface->surface->getCanvas();
	const SkRect dst = SkRect::MakeXYWH(dstX, dstY, dstWidth, dstHeight);

	const bool hasTint = colorA > 0 && !(r == 255 && g == 255 && b == 255);
	sk_sp<SkColorFilter> tintFilter;
	if (hasTint) {
		tintFilter = SkColorFilters::Blend(
			SkColorSetARGB(255, r, g, b), SkBlendMode::kModulate);
	}

	if (image->svg) {
		if (hasTint) {
			SkPaint layerPaint;
			layerPaint.setColorFilter(tintFilter);
			canvas->saveLayer(&dst, &layerPaint);
			kine_skia_draw_svg(canvas, image, dstX, dstY, dstWidth, dstHeight, alpha);
			canvas->restore();
		} else {
			kine_skia_draw_svg(canvas, image, dstX, dstY, dstWidth, dstHeight, alpha);
		}
		return;
	}

	if (!image->image) {
		return;
	}

	const float imageWidth = image->width;
	const float imageHeight = image->height;

	float sx = srcX;
	float sy = srcY;
	float sw = srcWidth;
	float sh = srcHeight;

	if (sw <= 0.0f) {
		sw = imageWidth - sx;
	}
	if (sh <= 0.0f) {
		sh = imageHeight - sy;
	}
	if (sw <= 0.0f || sh <= 0.0f) {
		sx = 0.0f;
		sy = 0.0f;
		sw = imageWidth;
		sh = imageHeight;
	}

	sx = std::clamp(sx, 0.0f, std::max(0.0f, imageWidth - 1.0f));
	sy = std::clamp(sy, 0.0f, std::max(0.0f, imageHeight - 1.0f));
	sw = std::min(sw, imageWidth - sx);
	sh = std::min(sh, imageHeight - sy);

	if (sw <= 0.0f || sh <= 0.0f) {
		return;
	}

	const SkRect src = SkRect::MakeXYWH(sx, sy, sw, sh);
	const SkSamplingOptions sampling = resample == 2
		? SkSamplingOptions(SkFilterMode::kNearest)
		: SkSamplingOptions(SkFilterMode::kLinear);

	const auto sourceConstraint = image->strictSourceRect ? SkCanvas::kStrict_SrcRectConstraint : SkCanvas::kFast_SrcRectConstraint;
	SkPaint paint;
	paint.setAntiAlias(true);
	paint.setAlphaf(alpha / 255.0f);
	if (tintFilter) {
		paint.setColorFilter(tintFilter);
	}

	if (scaleType == 2) {
		const float stepX = tileSizeX > 0.0f ? tileSizeX : sw;
		const float stepY = tileSizeY > 0.0f ? tileSizeY : sh;
		if (stepX <= 0.0f || stepY <= 0.0f) {
			return;
		}

		canvas->save();
		canvas->clipRect(dst, SkClipOp::kIntersect, true);
		for (float ty = dstY; ty < dstY + dstHeight; ty += stepY) {
			for (float tx = dstX; tx < dstX + dstWidth; tx += stepX) {
				SkRect tile = SkRect::MakeXYWH(tx, ty, stepX, stepY);
				canvas->drawImageRect(
					image->image, src, tile, sampling,
					&paint, sourceConstraint);
			}
		}
		canvas->restore();
		return;
	}

	if (scaleType == 3) {
		const float scale = std::min(dstWidth / sw, dstHeight / sh);
		const float w = sw * scale;
		const float h = sh * scale;
		SkRect fitted = SkRect::MakeXYWH(
			dstX + (dstWidth - w) * 0.5f,
			dstY + (dstHeight - h) * 0.5f,
			w, h);
		canvas->drawImageRect(
			image->image, src, fitted, sampling,
			&paint, sourceConstraint);
		return;
	}

	if (scaleType == 4) {
		const float scale = std::max(dstWidth / sw, dstHeight / sh);
		const float w = sw * scale;
		const float h = sh * scale;
		canvas->save();
		canvas->clipRect(dst, SkClipOp::kIntersect, true);
		SkRect covered = SkRect::MakeXYWH(
			dstX + (dstWidth - w) * 0.5f,
			dstY + (dstHeight - h) * 0.5f,
			w, h);
		canvas->drawImageRect(
			image->image, src, covered, sampling,
			&paint, sourceConstraint);
		canvas->restore();
		return;
	}

	canvas->drawImageRect(
		image->image, src, dst, sampling,
		&paint, sourceConstraint);
}
}
