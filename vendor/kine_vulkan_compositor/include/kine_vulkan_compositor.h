#ifndef KINE_VULKAN_COMPOSITOR_H
#define KINE_VULKAN_COMPOSITOR_H

#include <stdint.h>
#ifndef __cplusplus
#include <stdbool.h>
#endif

#if defined(_WIN32) && (defined(KINE_BUILD_SHARED) || defined(KINE_VULKAN_COMPOSITOR_BUILD_SHARED))
  #if defined(KINE_VULKAN_COMPOSITOR_BUILD_EXPORTS)
    #define KINE_VULKAN_COMPOSITOR_API __declspec(dllexport)
  #else
    #define KINE_VULKAN_COMPOSITOR_API __declspec(dllimport)
  #endif
#elif defined(__GNUC__) && (defined(KINE_BUILD_SHARED) || defined(KINE_VULKAN_COMPOSITOR_BUILD_SHARED))
  #define KINE_VULKAN_COMPOSITOR_API __attribute__((visibility("default")))
#else
  #define KINE_VULKAN_COMPOSITOR_API
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct KineVulkanCompositor KineVulkanCompositor;
KINE_VULKAN_COMPOSITOR_API uint32_t Kine_VulkanCompositor_GetSDLWindowId(const KineVulkanCompositor* compositor);

typedef void (*KineVulkanCompositorProfileCallback)(void* user, const char* phase, bool begin);
KINE_VULKAN_COMPOSITOR_API void Kine_VulkanCompositor_SetFrameProfileCallback(
    KineVulkanCompositor* compositor, KineVulkanCompositorProfileCallback callback, void* user);


typedef struct KineVulkanSwapchainDispatch {
    void* physicalDevice;
    void* device;
    void* getCapabilities;
    void* getFormats;
    void* getPresentModes;
    void* create;
    uint64_t surface;
    uint32_t width;
    uint32_t height;
    uint32_t modePolicy;
    uint32_t imageOverride;
} KineVulkanSwapchainDispatch;

typedef struct KineVulkanSwapchainResult {
    uint64_t swapchain;
    uint32_t width;
    uint32_t height;
    uint32_t format;
    uint32_t colorSpace;
    uint32_t usage;
    uint32_t presentMode;
    uint32_t requestedImages;
} KineVulkanSwapchainResult;

typedef struct KineVulkanFrameResources {
    void* commands[5];
    uint64_t fence;
    uint64_t query;
} KineVulkanFrameResources;

typedef struct KineVulkanFrameDispatch {
    void* device;
    void* getDeviceProcAddr;
    uint64_t commandPool;
    uint32_t timing;
    uint32_t detail;
    uint32_t offscreen;
} KineVulkanFrameDispatch;

typedef struct KineVulkanTransition {
    void* command;
    uint64_t image;
    uint64_t query;
    uint32_t oldLayout;
    uint32_t newLayout;
    uint32_t reusable;
} KineVulkanTransition;

typedef enum KineProviderAction {
    KINE_PROVIDER_ACTIVE = 0,
    KINE_PROVIDER_BEGIN,
    KINE_PROVIDER_RESET,
    KINE_PROVIDER_CHECK_PREPARE,
    KINE_PROVIDER_PREPARE,
    KINE_PROVIDER_ACQUIRE,
    KINE_PROVIDER_PRESENT,
    KINE_PROVIDER_WAIT_OVERLAY,
    KINE_PROVIDER_OVERLAY,
    KINE_PROVIDER_WAIT_END,
    KINE_PROVIDER_XR_READY
} KineProviderAction;

typedef enum KineFrameStep {
    KINE_FRAME_ACQUIRE = 0,
    KINE_FRAME_CLAIM,
    KINE_FRAME_CANVAS,
    KINE_FRAME_PUBLISH,
    KINE_FRAME_FLUSH,
    KINE_FRAME_LATE_ACQUIRE,
    KINE_FRAME_SUBMIT,
    KINE_FRAME_PRESENT
} KineFrameStep;

typedef int32_t (*KineFrameStepFn)(void*, uint32_t);

typedef struct KineVulkanSwapchainBackend {
    int32_t (*create)(const KineVulkanSwapchainDispatch* dispatch, KineVulkanSwapchainResult* result);
    void (*destroy)(void* device, void* destroyProc, uint64_t swapchain);
    uint32_t modePolicy;
    uint32_t imageOverride;
    int32_t (*createFrame)(const KineVulkanFrameDispatch*, KineVulkanFrameResources*);
    void (*destroyFrame)(const KineVulkanFrameDispatch*, KineVulkanFrameResources*);
    int32_t (*recordTransition)(const KineVulkanFrameDispatch*, const KineVulkanTransition*);
    int32_t (*submit)(const KineVulkanFrameDispatch*, void* queue, void* command, uint64_t wait, uint64_t signal, uint64_t fence);
    void* (*wrapSurface)(void* skiaContext, void* image, uint32_t width, uint32_t height, uint32_t format, uint32_t usage);
    uint32_t (*nextSlot)(uint32_t next, uint32_t count, uint32_t* following);
    int32_t (*createRoot)(const KineVulkanFrameDispatch*, uint32_t family, uint64_t* pool, uint64_t* fence);
    void (*destroyRoot)(const KineVulkanFrameDispatch*, uint64_t pool, uint64_t fence);
    int32_t (*createSync)(const KineVulkanFrameDispatch*, uint64_t* semaphore, uint64_t* consumed, uint64_t* prefetched);
    void (*destroySync)(const KineVulkanFrameDispatch*, uint64_t semaphore, uint64_t consumed, uint64_t prefetched);
    int32_t (*createColor)(const KineVulkanFrameDispatch*, void* instance, void* physical, void* getInstanceProc, uint32_t width, uint32_t height, uint32_t format, uint64_t* image, uint64_t* memory);
    void (*destroyColor)(const KineVulkanFrameDispatch*, uint64_t image, uint64_t memory);
    int32_t (*copyColor)(const KineVulkanFrameDispatch*, void* command, uint64_t source, uint64_t destination, uint32_t width, uint32_t height, uint32_t format, uint32_t destinationLayout, uint64_t query);
    uint32_t offscreen;
    void (*releaseSurface)(void* surface);
    int32_t (*flushSurface)(void* surface);
    int32_t (*waitSurface)(void* surface, void* semaphore);
    int32_t (*retireFence)(const KineVulkanFrameDispatch*, uint64_t fence, uint32_t wait);
    int32_t (*createDepth)(const KineVulkanFrameDispatch*, void* instance, void* physical, void* getInstanceProc, uint32_t width, uint32_t height, uint64_t* image, uint64_t* memory, uint32_t* format);
    int32_t (*createSurface)(void* window, void* instance, uint64_t* surface);
    void (*destroySurface)(void* instance, uint64_t surface);
    void (*destroyDevice)(const KineVulkanFrameDispatch*);
    void (*destroyInstance)(void* instance, void* getInstanceProc);
    uint32_t (*selectReady)(uint32_t next, uint32_t count, uint32_t readyMask, uint32_t* following);
    int32_t (*submitCopy)(const KineVulkanFrameDispatch*, void* graphics, void* copyQueue, void* marker, void* command, uint64_t ready, uint64_t acquired, uint64_t present, uint64_t returned, uint64_t fence);
    void* (*createProvider)(void);
    void (*destroyProvider)(void*);
    int32_t (*providerAction)(void*, uint32_t action, uint32_t image, uint64_t semaphore, uint32_t* outImage, uint64_t* outSemaphore);
    int32_t (*frameFlow)(void*, KineFrameStepFn, uint32_t ending);


} KineVulkanSwapchainBackend;

KINE_VULKAN_COMPOSITOR_API int Kine_VulkanCompositor_RegisterSwapchainBackend(
    uint32_t windowId, const KineVulkanSwapchainBackend* backend);
KINE_VULKAN_COMPOSITOR_API int Kine_OdinCompositor_CopySwapchainBackend(
    uint32_t windowId, KineVulkanSwapchainBackend* output);

typedef struct KineVulkanWsiDispatch {
    void* device;
    void* queue;
    void* acquire;
    void* present;
    uint32_t dedicatedQueue;
} KineVulkanWsiDispatch;

typedef struct KineVulkanWsiBackend {
    void* user;
    int32_t (*acquire)(void* user, uint64_t swapchain, uint64_t timeout,
        uint64_t semaphore, uint64_t fence, uint32_t* image);
    int32_t (*present)(void* user, uint64_t swapchain, uint64_t semaphore, uint32_t image);
    int32_t (*drain)(void* user, uint64_t* waitNs);
    uint32_t asynchronous;
} KineVulkanWsiBackend;

KINE_VULKAN_COMPOSITOR_API void Kine_VulkanCompositor_EnableCopyQueue(KineVulkanCompositor* compositor, uint32_t family);
KINE_VULKAN_COMPOSITOR_API int Kine_VulkanCompositor_IsOffscreen(const KineVulkanCompositor* compositor);
KINE_VULKAN_COMPOSITOR_API int Kine_VulkanCompositor_GetWsiDispatch(
    KineVulkanCompositor* compositor, KineVulkanWsiDispatch* out);
KINE_VULKAN_COMPOSITOR_API int Kine_VulkanCompositor_SetWsiBackend(
    KineVulkanCompositor* compositor, const KineVulkanWsiBackend* backend);

typedef struct KineVulkanCompositorInfo {
    void* instance;
    void* surface;
    void* physicalDevice;
    void* device;
    void* graphicsQueue;
    void* swapchain;
    uint32_t swapchainFormat;
    uint32_t swapchainImageCount;
    uint32_t graphicsQueueFamilyIndex;
    uint32_t graphicsQueueCount;
    uint32_t width;
    uint32_t height;
} KineVulkanCompositorInfo;

typedef struct KineVulkanCompositorBackend {
    void* instance;
    void* physicalDevice;
    void* device;
    void* queue;
    uint32_t graphicsQueueFamilyIndex;
    uint32_t maxApiVersion;
    void* getInstanceProcAddr;
    void* getDeviceProcAddr;
} KineVulkanCompositorBackend;

KINE_VULKAN_COMPOSITOR_API KineVulkanCompositor*
Kine_VulkanCompositor_CreateForSDLWindow(void* sdlWindow, int width, int height);

KINE_VULKAN_COMPOSITOR_API KineVulkanCompositor*
Kine_VulkanCompositor_CreateForSDLWindowWithBackend(
    void* sdlWindow,
    int width,
    int height,
    const KineVulkanCompositorBackend* backend);

KINE_VULKAN_COMPOSITOR_API void
Kine_VulkanCompositor_Destroy(KineVulkanCompositor* compositor);

KINE_VULKAN_COMPOSITOR_API int
Kine_VulkanCompositor_WaitForQueueIdle(KineVulkanCompositor* compositor);

KINE_VULKAN_COMPOSITOR_API int
Kine_VulkanCompositor_Resize(
    KineVulkanCompositor* compositor,
    int width,
    int height);

KINE_VULKAN_COMPOSITOR_API int
Kine_VulkanCompositor_IsReady(const KineVulkanCompositor* compositor);

KINE_VULKAN_COMPOSITOR_API int
Kine_VulkanCompositor_UsesOdinBackend(const KineVulkanCompositor* compositor);

KINE_VULKAN_COMPOSITOR_API int
Kine_VulkanCompositor_IsDeviceLost(const KineVulkanCompositor* compositor);

KINE_VULKAN_COMPOSITOR_API int
Kine_VulkanCompositor_NeedsResize(const KineVulkanCompositor* compositor);

KINE_VULKAN_COMPOSITOR_API const char*
Kine_VulkanCompositor_GetLastError(const KineVulkanCompositor* compositor);

KINE_VULKAN_COMPOSITOR_API int
Kine_VulkanCompositor_GetInfo(
    const KineVulkanCompositor* compositor,
    KineVulkanCompositorInfo* outInfo);


KINE_VULKAN_COMPOSITOR_API int
Kine_VulkanCompositor_MeshTerrainChunk(
    KineVulkanCompositor* compositor,
    const float* occ,
    const uint32_t* mat,
    int originX,
    int originY,
    int originZ,
    float voxelSize,
    float isoLevel,
    float* outVertices,
    float* outWeights,
    uint32_t* outIndices,
    uint32_t vertexCapacity,
    uint32_t indexCapacity,
    uint32_t* outVertexCount,
    uint32_t* outIndexCount);


KINE_VULKAN_COMPOSITOR_API void*
Kine_VulkanCompositor_GetSkiaContext(KineVulkanCompositor* compositor);

KINE_VULKAN_COMPOSITOR_API void*
Kine_VulkanCompositor_GetCurrentSkiaSurface(KineVulkanCompositor* compositor);


KINE_VULKAN_COMPOSITOR_API int
Kine_VulkanCompositor_GetXRPanelSource(KineVulkanCompositor* compositor, void** image,
    uint32_t* width, uint32_t* height, uint32_t* format);

KINE_VULKAN_COMPOSITOR_API uint32_t
Kine_VulkanCompositor_GetSwapchainImages(
    KineVulkanCompositor* compositor,
    void** outImages,
    uint32_t maxImages);

KINE_VULKAN_COMPOSITOR_API uint32_t
Kine_VulkanCompositor_GetDepthAttachment(
    KineVulkanCompositor* compositor,
    void** outImage,
    uint32_t* outFormat);


KINE_VULKAN_COMPOSITOR_API int
Kine_VulkanCompositor_PrepareFilament(KineVulkanCompositor* compositor);

KINE_VULKAN_COMPOSITOR_API uint32_t
Kine_VulkanCompositor_FilamentAcquire(
    KineVulkanCompositor* compositor,
    uint32_t* outImageIndex,
    void** outImageReadySemaphore);

KINE_VULKAN_COMPOSITOR_API uint32_t
Kine_VulkanCompositor_FilamentPresent(
    KineVulkanCompositor* compositor,
    uint32_t imageIndex,
    void* finishedDrawingSemaphore);


KINE_VULKAN_COMPOSITOR_API void*
Kine_VulkanCompositor_BeginFrame(KineVulkanCompositor* compositor);


KINE_VULKAN_COMPOSITOR_API void*
Kine_VulkanCompositor_BeginOverlay(KineVulkanCompositor* compositor);


KINE_VULKAN_COMPOSITOR_API void Kine_VulkanCompositor_GetPrefetchStats(
    const KineVulkanCompositor* compositor, uint64_t* hits, uint64_t* misses);
KINE_VULKAN_COMPOSITOR_API uint64_t Kine_VulkanCompositor_GetPresentWaitNs(const KineVulkanCompositor* compositor);

KINE_VULKAN_COMPOSITOR_API void Kine_VulkanCompositor_SetPresentQueue(KineVulkanCompositor* compositor, void* queue);

KINE_VULKAN_COMPOSITOR_API int Kine_VulkanCompositor_GetLatestQueueDetail(KineVulkanCompositor* compositor, uint64_t* serial, uint64_t* filament, uint64_t* overlay);
KINE_VULKAN_COMPOSITOR_API int Kine_VulkanCompositor_GetLatestQueueStages(KineVulkanCompositor* compositor, uint64_t* serial, uint64_t* base, uint64_t* render);
KINE_VULKAN_COMPOSITOR_API int Kine_VulkanCompositor_GetLatestQueueTiming(KineVulkanCompositor* compositor, uint64_t* serial, uint64_t* ns);

KINE_VULKAN_COMPOSITOR_API int
Kine_VulkanCompositor_EndFrame(KineVulkanCompositor* compositor);

#ifdef __cplusplus
}
#endif

#endif
