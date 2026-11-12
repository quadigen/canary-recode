#ifndef KINE_SKIA_H
#define KINE_SKIA_H

#include "kine_skia_export.h"
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct KineSkiaSurface KineSkiaSurface;
typedef struct KineSkiaImage KineSkiaImage;
typedef struct KineSkiaVulkanContext KineSkiaVulkanContext;
typedef struct KineSkiaGLContext KineSkiaGLContext;
typedef struct KineSkiaRuntimeShader KineSkiaRuntimeShader;
typedef struct KineSkiaTypeface KineSkiaTypeface;

typedef struct KineSkiaVulkanBackend {
	void *instance;		  /* VkInstance */
	void *physicalDevice; /* VkPhysicalDevice */
	void *device;		  /* VkDevice */
	void *queue;		  /* VkQueue, must support graphics */
	uint32_t graphicsQueueFamilyIndex;
	uint32_t maxApiVersion;	   /* 0 = let Skia infer/default */
	void *getInstanceProcAddr; /* PFN_vkGetInstanceProcAddr */
	void *getDeviceProcAddr;   /* PFN_vkGetDeviceProcAddr, optional */
} KineSkiaVulkanBackend;

typedef struct KineSkiaVulkanImageInfo {
	void *image;				 /* VkImage owned by the engine */
	uint32_t format;			 /* VkFormat */
	uint32_t imageLayout;		 /* VkImageLayout at handoff to Skia */
	uint32_t imageTiling;		 /* VkImageTiling, usually VK_IMAGE_TILING_OPTIMAL */
	uint32_t imageUsageFlags;	 /* VkImageUsageFlags */
	uint32_t sampleCount;		 /* Vulkan sample count as integer, usually 1 */
	uint32_t levelCount;		 /* mip levels, usually 1 */
	uint32_t currentQueueFamily; /* queue family owning image, or VK_QUEUE_FAMILY_IGNORED */
} KineSkiaVulkanImageInfo;

/* A GL function loader of the form: void *(*)(void *context, const char *name).
   The returned pointer is a castable GL function address (GrGLFuncPtr). */
typedef void *(*KineSkiaGLGetProc)(void *context, const char *name);

typedef struct KineSkiaGLBackend {
	void *getProcAddr;	 /* KineSkiaGLGetProc loader, e.g. wglGetProcAddress + GetProcAddress */
	void *getProcContext;	 /* opaque context passed to getProcAddr; may be NULL */
} KineSkiaGLBackend;

typedef struct KineSkiaGLImageInfo {
	uint32_t framebufferId; /* GL FBO id owned by the engine */
	uint32_t format;	 /* GL sized internal format: GL_RGBA8=0x8058, GL_BGRA8=0x93A1,
				    GL_SRGB8_ALPHA8=0x8C43; 0 = GL_RGBA8 */
	uint32_t stencilBits;	 /* 0, 8 or 16; 0 acceptable */
	uint32_t sampleCount;	 /* MSAA samples, usually 1 */
	uint32_t origin;	 /* 0 = bottom-left (GL native), 1 = top-left */
} KineSkiaGLImageInfo;

/* ---------------- Version ---------------- */

KINE_SKIA_API const char *Kine_Skia_GetVersion(void);

/* ---------------- Vulkan GPU context ----------------
   These entry points are enabled when kine_skia is built with KINE_SKIA_BACKEND=VULKAN.
   Skia does not own the Vulkan instance/device/queue; the engine must keep them
   alive until all Vulkan-backed KineSkiaSurface objects and the context are destroyed. */

KINE_SKIA_API KineSkiaVulkanContext *Kine_Skia_Vulkan_CreateContext(
	const KineSkiaVulkanBackend *backend);
KINE_SKIA_API void Kine_Skia_Vulkan_DestroyContext(KineSkiaVulkanContext *context);
KINE_SKIA_API void Kine_Skia_Vulkan_PurgeResources(KineSkiaVulkanContext *context);

/* ---------------- OpenGL GPU context ----------------
   These entry points are enabled when kine_skia is built with KINE_SKIA_BACKEND=OPENGL.
   Skia does not own the GL context; the calling thread must make the desired GL
   context current before creating the context and before every draw/flush sequence.
   The caller keeps ownership of the GL context, FBOs and their textures. */

KINE_SKIA_API KineSkiaGLContext *Kine_Skia_GL_CreateContext(
	const KineSkiaGLBackend *backend);
KINE_SKIA_API void Kine_Skia_GL_DestroyContext(KineSkiaGLContext *context);
/* Invalidates Skia's cached GL state. Call this after any external code (for
   example another renderer sharing the same GL context) issues raw GL calls,
   so the next Skia flush re-synchronizes bound program/texture/FBO state. */
KINE_SKIA_API void Kine_Skia_GL_ResetContext(KineSkiaGLContext *context);

/* ---------------- Surface lifecycle ---------------- */

KINE_SKIA_API KineSkiaSurface *Kine_Skia_Surface_Create(int width, int height);

/* Display lists: BeginPicture routes later draw calls into a recorded list
   instead of the surface, EndPicture returns it, DrawPicture replays it. */
typedef struct KineSkiaPicture KineSkiaPicture;
KINE_SKIA_API int Kine_Skia_Surface_BeginPicture(KineSkiaSurface *surface);
KINE_SKIA_API KineSkiaPicture *Kine_Skia_Surface_EndPicture(KineSkiaSurface *surface);
KINE_SKIA_API void Kine_Skia_Picture_Destroy(KineSkiaPicture *picture);
KINE_SKIA_API void Kine_Skia_Surface_DrawPicture(
	KineSkiaSurface *surface,
	KineSkiaPicture *picture);
KINE_SKIA_API KineSkiaSurface *Kine_Skia_Surface_CreateVulkanRenderTarget(
	KineSkiaVulkanContext *context,
	int width,
	int height,
	const KineSkiaVulkanImageInfo *imageInfo);
KINE_SKIA_API KineSkiaSurface *Kine_Skia_Surface_CreateGLRenderTarget(
	KineSkiaGLContext *context,
	int width,
	int height,
	const KineSkiaGLImageInfo *imageInfo);
KINE_SKIA_API void Kine_Skia_Surface_Destroy(KineSkiaSurface *surface);

KINE_SKIA_API int Kine_Skia_Surface_GetWidth(const KineSkiaSurface *surface);
KINE_SKIA_API int Kine_Skia_Surface_GetHeight(const KineSkiaSurface *surface);
KINE_SKIA_API uint32_t Kine_Skia_Surface_GetRowBytes(const KineSkiaSurface *surface);
KINE_SKIA_API void *Kine_Skia_Surface_GetPixels(KineSkiaSurface *surface);
KINE_SKIA_API void Kine_Skia_Surface_Flush(KineSkiaSurface *surface);
KINE_SKIA_API void Kine_Skia_Surface_SetBackdropFromSurface(
	KineSkiaSurface *surface,
	KineSkiaSurface *backdrop);
KINE_SKIA_API void Kine_Skia_Surface_ClearBackdrop(KineSkiaSurface *surface);

/* Debug/readback helper: sample a single pixel back out of the surface */
KINE_SKIA_API void Kine_Skia_Surface_GetPixel(
	KineSkiaSurface *surface,
	int x, int y,
	uint8_t *outR, uint8_t *outG, uint8_t *outB, uint8_t *outA);

/* ---------------- Clear ---------------- */

KINE_SKIA_API void Kine_Skia_Surface_Clear(
	KineSkiaSurface *surface,
	uint8_t r, uint8_t g, uint8_t b, uint8_t a);

/* ---------------- Runtime SkSL shaders ---------------- */

KINE_SKIA_API KineSkiaRuntimeShader *Kine_Skia_RuntimeShader_Create(const char *sksl);
KINE_SKIA_API void Kine_Skia_RuntimeShader_Destroy(KineSkiaRuntimeShader *shader);
KINE_SKIA_API bool Kine_Skia_RuntimeShader_SetUniform(
	KineSkiaRuntimeShader *shader, const char *name, const float *values, int valueCount);
KINE_SKIA_API void Kine_Skia_Surface_DrawRuntimeShaderRect(
	KineSkiaSurface *surface, KineSkiaRuntimeShader *shader,
	float x, float y, float width, float height);
KINE_SKIA_API const char *Kine_Skia_RuntimeShader_GetLastError(void);

KINE_SKIA_API KineSkiaRuntimeShader *Kine_Skia_UIShader_Create(
	const char *sksl, bool *samplesContent);
KINE_SKIA_API bool Kine_Skia_Surface_DrawUIShader(
	KineSkiaSurface *surface, KineSkiaRuntimeShader *shader,
	float x, float y, float width, float height, const float *backgroundColor);
KINE_SKIA_API bool Kine_Skia_Surface_BeginUIShader(
	KineSkiaSurface *surface, KineSkiaRuntimeShader *shader,
	float x, float y, float width, float height, const float *backgroundColor,
	float sampleRadius);

/* ---------------- Shapes ----------------
   strokeWidth == 0 -> filled. strokeWidth > 0 -> stroked with that width. */

KINE_SKIA_API void Kine_Skia_Surface_DrawRect(
	KineSkiaSurface *surface,
	float x, float y, float width, float height,
	uint8_t r, uint8_t g, uint8_t b, uint8_t a,
	float strokeWidth);

KINE_SKIA_API void Kine_Skia_Surface_DrawRotatedRect(
	KineSkiaSurface *surface,
	float centerX, float centerY, float width, float height, float rotationDegrees,
	uint8_t r, uint8_t g, uint8_t b, uint8_t a,
	float strokeWidth);

KINE_SKIA_API void Kine_Skia_Surface_DrawRoundRect(
	KineSkiaSurface *surface,
	float x, float y, float width, float height,
	float radiusX, float radiusY,
	uint8_t r, uint8_t g, uint8_t b, uint8_t a,
	float strokeWidth);

KINE_SKIA_API void Kine_Skia_Surface_DrawSquircle(
	KineSkiaSurface *surface,
	float x, float y, float width, float height,
	float radius, float exponent,
	uint8_t r, uint8_t g, uint8_t b, uint8_t a,
	float strokeWidth);

KINE_SKIA_API void Kine_Skia_Surface_DrawSquircleCorners(
	KineSkiaSurface *surface,
	float x, float y, float width, float height,
	float radiusTL, float radiusTR, float radiusBR, float radiusBL,
	float exponent,
	uint8_t r, uint8_t g, uint8_t b, uint8_t a,
	float strokeWidth);

KINE_SKIA_API void Kine_Skia_Surface_DrawUIShadow(
	KineSkiaSurface *surface,
	float x, float y, float width, float height,
	float radius, float exponent,
	float offsetX, float offsetY,
	float blurSigma, float spread,
	uint8_t r, uint8_t g, uint8_t b, uint8_t a);

KINE_SKIA_API void Kine_Skia_Surface_DrawBackdropBlurRect(
	KineSkiaSurface *surface,
	float x, float y, float width, float height,
	float radiusX, float radiusY,
	float blurSigma,
	uint8_t alpha,
	uint8_t tintR, uint8_t tintG, uint8_t tintB, uint8_t tintA);

KINE_SKIA_API void Kine_Skia_Surface_DrawBackdropBlurSquircle(
	KineSkiaSurface *surface,
	float x, float y, float width, float height,
	float radius, float exponent,
	float blurSigma,
	uint8_t alpha,
	uint8_t tintR, uint8_t tintG, uint8_t tintB, uint8_t tintA);

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
	uint8_t tintR, uint8_t tintG, uint8_t tintB, uint8_t tintA);

/* Magnifier / loupe over the frozen frame.
     zoomAmount : magnification factor (1 disables the refraction)
     inset      : width of the fish-eye distortion band around the content */
KINE_SKIA_API void Kine_Skia_Surface_DrawMagnifierRect(
	KineSkiaSurface *surface,
	float x, float y, float width, float height,
	float zoomAmount, float inset,
	uint8_t alpha);

/* Directional motion blur applied to everything drawn between Begin and End.
   The blur runs along `angleDegrees` for `lengthPixels`. */
KINE_SKIA_API void Kine_Skia_Surface_BeginMotionBlur(
	KineSkiaSurface *surface,
	float x, float y, float width, float height,
	float angleDegrees, float lengthPixels);
KINE_SKIA_API void Kine_Skia_Surface_EndMotionBlur(KineSkiaSurface *surface);

KINE_SKIA_API void Kine_Skia_Surface_DrawCircle(
	KineSkiaSurface *surface,
	float cx, float cy, float radius,
	uint8_t r, uint8_t g, uint8_t b, uint8_t a,
	float strokeWidth);

KINE_SKIA_API void Kine_Skia_Surface_DrawOval(
	KineSkiaSurface *surface,
	float x, float y, float width, float height,
	uint8_t r, uint8_t g, uint8_t b, uint8_t a,
	float strokeWidth);

KINE_SKIA_API void Kine_Skia_Surface_DrawArc(
	KineSkiaSurface *surface,
	float x, float y, float width, float height,
	float startAngle, float sweepAngle, int useCenter,
	uint8_t r, uint8_t g, uint8_t b, uint8_t a,
	float strokeWidth);

KINE_SKIA_API void Kine_Skia_Surface_DrawLine(
	KineSkiaSurface *surface,
	float x0, float y0, float x1, float y1,
	float strokeWidth,
	uint8_t r, uint8_t g, uint8_t b, uint8_t a);

/* points: flat array [x0,y0,x1,y1,...], pointCount = number of (x,y) pairs */
KINE_SKIA_API void Kine_Skia_Surface_DrawPolygon(
	KineSkiaSurface *surface,
	const float *points, int pointCount,
	int closed,
	uint8_t r, uint8_t g, uint8_t b, uint8_t a,
	float strokeWidth);

/* ---------------- Transform stack ---------------- */

KINE_SKIA_API void Kine_Skia_Surface_Save(KineSkiaSurface *surface);
KINE_SKIA_API void Kine_Skia_Surface_SaveLayerAlpha(KineSkiaSurface *surface, float alpha);
KINE_SKIA_API void Kine_Skia_Surface_Restore(KineSkiaSurface *surface);
KINE_SKIA_API void Kine_Skia_Surface_Translate(KineSkiaSurface *surface, float dx, float dy);
KINE_SKIA_API void Kine_Skia_Surface_Rotate(KineSkiaSurface *surface, float degrees);
KINE_SKIA_API void Kine_Skia_Surface_Scale(KineSkiaSurface *surface, float sx, float sy);
KINE_SKIA_API void Kine_Skia_Surface_ClipRect(
	KineSkiaSurface *surface,
	float x, float y, float width, float height);

KINE_SKIA_API void Kine_Skia_Surface_ClipRoundRect(
	KineSkiaSurface *surface,
	float x, float y, float width, float height,
	float radiusX, float radiusY);

KINE_SKIA_API void Kine_Skia_Surface_ClipSquircle(
	KineSkiaSurface *surface,
	float x, float y, float width, float height,
	float radius, float exponent);

KINE_SKIA_API void Kine_Skia_Surface_ClipSquircleCorners(
	KineSkiaSurface *surface,
	float x, float y, float width, float height,
	float radiusTL, float radiusTR, float radiusBR, float radiusBL,
	float exponent);

KINE_SKIA_API void Kine_Skia_Surface_DrawImageSized(
	KineSkiaSurface *surface,
	KineSkiaImage *image,
	float x, float y,
	float width, float height,
	uint8_t alpha);

KINE_SKIA_API KineSkiaTypeface *
Kine_Skia_Typeface_LoadFromMemory(
	const uint8_t *data,
	size_t size);

KINE_SKIA_API float Kine_Skia_Typeface_MeasureText(
	KineSkiaTypeface *typeface,
	const char *text,
	float fontSize);

KINE_SKIA_API float Kine_Skia_Typeface_GetLineHeight(
	KineSkiaTypeface *typeface,
	float fontSize);

KINE_SKIA_API float Kine_Skia_Typeface_GetAscent(
	KineSkiaTypeface *typeface,
	float fontSize);

KINE_SKIA_API KineSkiaTypeface *
Kine_Skia_Typeface_LoadFromFile(
	const char *path);

KINE_SKIA_API void
Kine_Skia_Typeface_Destroy(
	KineSkiaTypeface *typeface);

KINE_SKIA_API void
Kine_Skia_Surface_DrawTextTypeface(
	KineSkiaSurface *surface,
	const char *text,
	float x,
	float y,
	float fontSize,
	KineSkiaTypeface *typeface,
	uint8_t r,
	uint8_t g,
	uint8_t b,
	uint8_t a);

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
	uint8_t a);

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
	uint8_t a);

KINE_SKIA_API void Kine_Skia_Surface_DrawImageBlurredSized(
	KineSkiaSurface *surface,
	KineSkiaImage *image,
	float x,
	float y,
	float width,
	float height,
	float blurSigma,
	uint8_t alpha);

KINE_SKIA_API void
Kine_Skia_Surface_DrawTextShadowTypeface(
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
	uint8_t shadowA);

KINE_SKIA_API void Kine_Skia_Surface_DrawPixels(
	KineSkiaSurface *surface,
	const void *pixels,
	int sourceWidth, int sourceHeight,
	uint32_t sourceRowBytes,
	float x, float y,
	float width, float height,
	bool flipY,
	uint8_t alpha);

KINE_SKIA_API void Kine_Skia_Surface_DrawImageOutlineSized(
	KineSkiaSurface *surface,
	KineSkiaImage *image,
	float x, float y,
	float width, float height,
	float thickness,
	uint8_t r, uint8_t g, uint8_t b, uint8_t a,
	uint8_t alpha);

KINE_SKIA_API void Kine_Skia_Surface_EndEdgeFade(
	KineSkiaSurface *surface,
	float x, float y, float width, float height,
	float fadeTop, float fadeBottom, float fadeLeft, float fadeRight);

KINE_SKIA_API void Kine_Skia_Surface_BeginEdgeFade(
	KineSkiaSurface *surface,
	float x, float y, float width, float height);

KINE_SKIA_API void Kine_Skia_Surface_DrawImageShadow(
	KineSkiaSurface *surface,
	KineSkiaImage *image,
	float x, float y,
	float width, float height,
	float offsetX, float offsetY,
	float blurSigma, float spread,
	uint8_t r, uint8_t g, uint8_t b, uint8_t a);

KINE_SKIA_API float Kine_Skia_Surface_GetFontAscent(float fontSize, const char *fontPath);

/* ---------------- Text ---------------- */

/* fontPath may be "" or NULL to use the default system font.
   x,y is the text BASELINE, not top-left. */
KINE_SKIA_API void Kine_Skia_Surface_DrawText(
	KineSkiaSurface *surface,
	const char *text,
	float x, float y,
	float fontSize,
	const char *fontPath,
	uint8_t r, uint8_t g, uint8_t b, uint8_t a);

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
	uint8_t shadowA);

KINE_SKIA_API float Kine_Skia_Surface_MeasureText(
	const char *text,
	float fontSize,
	const char *fontPath);

/* Approximate line height (ascent+descent+leading) for layout purposes */
KINE_SKIA_API float Kine_Skia_Surface_GetFontLineHeight(
	float fontSize,
	const char *fontPath);

/* ---------------- Images ---------------- */

KINE_SKIA_API KineSkiaImage *Kine_Skia_Image_LoadFromFile(const char *path);
KINE_SKIA_API KineSkiaImage *Kine_Skia_Image_LoadFromMemory(const uint8_t *data, size_t size);

// Wrap an engine-owned, shader-read-only atlas texture on the shared GPU.
KINE_SKIA_API KineSkiaImage *Kine_Skia_Image_WrapVulkan(KineSkiaVulkanContext *context,
    int width, int height, const KineSkiaVulkanImageInfo *info);
KINE_SKIA_API KineSkiaImage *Kine_Skia_Image_WrapGL(KineSkiaSurface *surface,
    uint32_t texture, int width, int height);

KINE_SKIA_API void Kine_Skia_Image_Destroy(KineSkiaImage *image);

KINE_SKIA_API int Kine_Skia_Image_GetWidth(const KineSkiaImage *image);
KINE_SKIA_API int Kine_Skia_Image_GetHeight(const KineSkiaImage *image);

/* Draw image at native size, top-left at (x,y) */
KINE_SKIA_API void Kine_Skia_Surface_DrawImage(
	KineSkiaSurface *surface,
	KineSkiaImage *image,
	float x, float y,
	uint8_t alpha);

/* Draw image scaled/cropped: src rect from the image -> dst rect on the surface */
KINE_SKIA_API void Kine_Skia_Surface_DrawImageRect(
	KineSkiaSurface *surface,
	KineSkiaImage *image,
	float srcX, float srcY, float srcWidth, float srcHeight,
	float dstX, float dstY, float dstWidth, float dstHeight,
	uint8_t alpha);

/* Draw an image with the GUI-facing ImageLabel feature set.
     srcX/srcY/srcWidth/srcHeight : sub-rect of the source, <= 0 falls back to the
                                    full image / remaining extent
     scaleType : 0 Stretch, 1 Slice, 2 Tile, 3 Fit, 4 Crop
     resample  : 0 Default (linear), 1 Linear, 2 Nearest
     tileSizeX/tileSizeY : resolved tile step in pixels for scaleType Tile
     r/g/b/colorA : ImageColor3 tint; colorA == 0 means no tint
     alpha : overall transparency, 0..255 */
KINE_SKIA_API void Kine_Skia_Surface_DrawImageScaled(
	KineSkiaSurface *surface,
	KineSkiaImage *image,
	float srcX, float srcY, float srcWidth, float srcHeight,
	float dstX, float dstY, float dstWidth, float dstHeight,
	float tileSizeX, float tileSizeY,
	int scaleType,
	int resample,
	uint8_t r, uint8_t g, uint8_t b, uint8_t colorA,
	uint8_t alpha);

#ifdef __cplusplus
}
#endif

#endif /* KINE_SKIA_H */
