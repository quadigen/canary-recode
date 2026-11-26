#include "kine_vulkan_compositor.h"

#include "kine_skia.h"

#include "kine_terrain_mc.h"

#include <SDL3/SDL_vulkan.h>

#include <vulkan/vulkan.h>

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

struct KineVulkanFrameSlot {


    VkCommandBuffer acquire = VK_NULL_HANDLE;
    VkCommandBuffer handoff = VK_NULL_HANDLE;
    VkCommandBuffer present = VK_NULL_HANDLE;
    VkCommandBuffer overlayTiming = VK_NULL_HANDLE;
    VkCommandBuffer renderComplete = VK_NULL_HANDLE;
    VkFence finished = VK_NULL_HANDLE;
    VkSemaphore lateAcquire = VK_NULL_HANDLE;
    VkSemaphore copyReady = VK_NULL_HANDLE;
    VkSemaphore copyReturned = VK_NULL_HANDLE;
    bool copyReturnPending = false;
    VkFence lateAcquireFence = VK_NULL_HANDLE;
    bool lateAcquirePending = false;
    bool inFlight = false;
    VkQueryPool timing = VK_NULL_HANDLE;
    uint64_t timingSerial = 0;
    bool timingHandoff = false;
    bool timingOverlay = false;
    VkImageLayout acquireRecordedLayout = VK_IMAGE_LAYOUT_MAX_ENUM;
    bool presentRecorded = false;
};

struct KineVulkanAcquireSlot {


    VkSemaphore ready = VK_NULL_HANDLE;
    VkFence consumed = VK_NULL_HANDLE;
    VkFence prefetched = VK_NULL_HANDLE;
    bool prefetchPending = false;
    bool inFlight = false;
};

struct KineVulkanFrame {


    static constexpr uint32_t SlotCount = 2;
    KineVulkanFrameSlot slots[SlotCount];
    uint32_t nextSlot = 0;
    KineSkiaSurface* base = nullptr;
    KineSkiaSurface* overlay = nullptr;
};

struct KinePresentJob {
    VkSwapchainKHR swapchain = VK_NULL_HANDLE;
    VkSemaphore semaphore = VK_NULL_HANDLE;
    uint32_t image = UINT32_MAX;
};

struct KineVulkanCompositor {
    PFN_vkGetInstanceProcAddr getInstanceProcAddr = nullptr;
    PFN_vkGetDeviceProcAddr getDeviceProcAddr = nullptr;

    SDL_WindowID windowId = 0;
    VkInstance instance = VK_NULL_HANDLE;
    VkSurfaceKHR surface = VK_NULL_HANDLE;
    VkPhysicalDevice physicalDevice = VK_NULL_HANDLE;
    VkDevice device = VK_NULL_HANDLE;
    VkQueue graphicsQueue = VK_NULL_HANDLE;
    VkQueue presentQueue = VK_NULL_HANDLE;
    bool sameFamilyCopyQueue = false;
    KineVulkanWsiBackend wsiBackend{};
    KineVulkanSwapchainBackend swapchainBackend{};
    bool nativeSwapchain = false;
    bool offscreen = false;
    uint32_t nextRenderImage = 0;
    std::vector<VkImage> renderImages;
    std::vector<VkDeviceMemory> renderMemory;
    std::vector<VkImageLayout> renderLayouts;
    bool prefetchEnabled = false;
    bool overlapPresent = false;
    uint32_t minimumImageCount = UINT32_MAX;
    uint32_t prefetchedImage = UINT32_MAX;
    uint32_t prefetchedSlot = UINT32_MAX;
    uint64_t prefetchHits = 0;
    uint64_t prefetchMisses = 0;
    uint64_t presentWaitNs = 0;
    uint32_t graphicsQueueFamilyIndex = UINT32_MAX;
    uint32_t graphicsQueueCount = 0;
    VkSwapchainKHR swapchain = VK_NULL_HANDLE;
    VkFormat swapchainFormat = VK_FORMAT_UNDEFINED;
    VkImageUsageFlags swapchainUsage = 0;
    VkPresentModeKHR presentMode = VK_PRESENT_MODE_FIFO_KHR;
    VkExtent2D swapchainExtent = {};
    std::vector<VkImage> swapchainImages;
    std::vector<VkImageLayout> swapchainImageLayouts;
    VkImage depthImage = VK_NULL_HANDLE;
    VkDeviceMemory depthImageMemory = VK_NULL_HANDLE;
    VkFormat depthFormat = VK_FORMAT_UNDEFINED;
    VkCommandPool commandPool = VK_NULL_HANDLE;
    VkFence acquireFence = VK_NULL_HANDLE;
    std::vector<KineVulkanAcquireSlot> acquireSlots;
    uint32_t nextAcquireSlot = 0;
    bool gpuAcquire = true;
    std::vector<KineVulkanFrame> frames;
    KineVulkanFrameSlot* activeSlot = nullptr;
    uint32_t timestampBits = 0;
    double timestampPeriod = 0;
    uint64_t timingSerial = 0;
    uint64_t latestTimingSerial = 0;
    uint64_t latestTimingNs = 0;
    uint64_t latestBaseNs = 0;
    uint64_t latestRenderNs = 0;
    bool latestStageValid = false;
    bool detailedTiming = false;
    bool latestOverlayValid = false;
    uint64_t latestFilamentNs = 0;
    uint64_t latestOverlayNs = 0;
    std::vector<VkSemaphore> renderFinishedSemaphores;
    uint32_t currentImageIndex = UINT32_MAX;
    KineSkiaSurface* currentSkiaSurface = nullptr;
    KineSkiaSurface* overlaySkiaSurface = nullptr;
    void* nativeProvider = nullptr;
    bool needsResize = false;
    bool device_lost = false;
    uint32_t width = 0;
    uint32_t height = 0;
    uint32_t apiVersion = VK_API_VERSION_1_0;

    KineSkiaVulkanContext* skiaContext = nullptr;
    KineTerrainMc* terrainMc = nullptr;
    std::string lastError;
    bool ownsInstance = true;
    bool ownsDevice = true;
    KineVulkanCompositorProfileCallback frameProfile = nullptr;
    void* frameProfileUser = nullptr;
};

static int32_t kine_vk_provider_action(KineVulkanCompositor* c, KineProviderAction action,
    uint32_t image = UINT32_MAX, VkSemaphore semaphore = VK_NULL_HANDLE,
    uint32_t* outImage = nullptr, uint64_t* outSemaphore = nullptr)
{
    if (!c || !c->nativeProvider || !c->swapchainBackend.providerAction) return 0;
    return c->swapchainBackend.providerAction(c->nativeProvider,
        uint32_t(action), image, (uint64_t)semaphore, outImage, outSemaphore);
}

static bool kine_vk_frame_active(KineVulkanCompositor* c)
{
    return kine_vk_provider_action(c, KINE_PROVIDER_ACTIVE) == 1;
}

static KineVulkanSwapchainBackend kine_vk_window_swapchain_backend(uint32_t windowId)
{
    KineVulkanSwapchainBackend backend{};
    Kine_OdinCompositor_CopySwapchainBackend(windowId, &backend);
    return backend;
}

KINE_VULKAN_COMPOSITOR_API void Kine_VulkanCompositor_SetFrameProfileCallback(
    KineVulkanCompositor* c, KineVulkanCompositorProfileCallback callback, void* user)
{
    if (!c) return;
    c->frameProfile = callback;
    c->frameProfileUser = user;
}

struct KineVkProfileScope {
    KineVulkanCompositorProfileCallback callback;
    void* user;
    const char* phase;
    KineVkProfileScope(KineVulkanCompositor* c, const char* name)
        : callback(c->frameProfile), user(c->frameProfileUser), phase(name) {
        if (callback) callback(user, phase, true);
    }
    ~KineVkProfileScope() { if (callback) callback(user, phase, false); }
};

template<class F>
static auto kine_vk_profile_call(KineVulkanCompositor* c, const char* phase, F&& f) -> decltype(f()) {
    KineVkProfileScope scope(c, phase);
    return f();
}

static bool kine_vk_has_extension(
    const std::vector<const char*>& extensions,
    const char* name)
{
    return name && std::any_of(
        extensions.begin(),
        extensions.end(),
        [name](const char* extension) {
            return extension && std::strcmp(extension, name) == 0;
        });
}

static bool kine_vk_instance_extension_available(
    PFN_vkGetInstanceProcAddr getInstanceProcAddr,
    const char* name)
{
    if (!getInstanceProcAddr || !name) {
        return false;
    }
    auto enumerate = reinterpret_cast<PFN_vkEnumerateInstanceExtensionProperties>(
        getInstanceProcAddr(VK_NULL_HANDLE, "vkEnumerateInstanceExtensionProperties"));
    if (!enumerate) {
        return false;
    }

    uint32_t count = 0;
    if (enumerate(nullptr, &count, nullptr) != VK_SUCCESS || count == 0) {
        return false;
    }
    std::vector<VkExtensionProperties> properties(count);
    if (enumerate(nullptr, &count, properties.data()) != VK_SUCCESS) {
        return false;
    }
    return std::any_of(properties.begin(), properties.end(), [name](const auto& property) {
        return std::strcmp(property.extensionName, name) == 0;
    });
}

static void kine_vk_set_error(KineVulkanCompositor* compositor, const char* message)
{
    if (compositor) {
        compositor->lastError = message ? message : "";
    }
}

template<typename T>
static T kine_vk_instance_proc(KineVulkanCompositor* compositor, const char* name)
{
    if (!compositor || !compositor->getInstanceProcAddr || !name) {
        return nullptr;
    }
    return reinterpret_cast<T>(compositor->getInstanceProcAddr(compositor->instance, name));
}

template<typename T>
static T kine_vk_device_proc(KineVulkanCompositor* compositor, const char* name)
{
    if (!compositor || !name) {
        return nullptr;
    }

    if (compositor->getDeviceProcAddr && compositor->device) {
        if (auto proc = compositor->getDeviceProcAddr(compositor->device, name)) {
            return reinterpret_cast<T>(proc);
        }
    }

    if (compositor->getInstanceProcAddr && compositor->instance) {
        auto proc = compositor->getInstanceProcAddr(compositor->instance, name);
        return reinterpret_cast<T>(proc);
    }

    return nullptr;
}

static bool kine_vk_handle_present_result(KineVulkanCompositor* c, VkResult result)
{
    if (result == VK_SUCCESS || result == VK_SUBOPTIMAL_KHR) return true;
    if (result == VK_ERROR_OUT_OF_DATE_KHR) {
        c->needsResize = true;
        return true;
    }
    if (result == VK_ERROR_DEVICE_LOST) {
        c->device_lost = true;
        kine_vk_set_error(c, "vkQueuePresentKHR failed: device lost");
        return false;
    }
    kine_vk_set_error(c,"vkQueuePresentKHR failed");
    return false;
}

static VkResult kine_vk_present_job(PFN_vkQueuePresentKHR present, VkQueue queue, const KinePresentJob& job)
{
    VkPresentInfoKHR info{};
    info.sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
    info.swapchainCount = 1;
    info.pSwapchains = &job.swapchain;
    info.pImageIndices = &job.image;
    if (job.semaphore) {
        info.waitSemaphoreCount = 1;
        info.pWaitSemaphores = &job.semaphore;
    }
    return present(queue,&info);
}

static bool kine_vk_drain_present(KineVulkanCompositor* c)
{
    c->presentWaitNs = 0;
    if (c->wsiBackend.drain) {
        const auto result = kine_vk_profile_call(c, "Vulkan Odin Present Drain", [&] {
            return static_cast<VkResult>(c->wsiBackend.drain(
                c->wsiBackend.user, &c->presentWaitNs));
        });
        return kine_vk_handle_present_result(c, result);
    }
    return true;
}

static bool kine_vk_create_instance(KineVulkanCompositor* compositor)
{
    compositor->getInstanceProcAddr = reinterpret_cast<PFN_vkGetInstanceProcAddr>(
        SDL_Vulkan_GetVkGetInstanceProcAddr());
    if (!compositor->getInstanceProcAddr) {
        kine_vk_set_error(compositor, "SDL_Vulkan_GetVkGetInstanceProcAddr failed");
        return false;
    }

    auto vkCreateInstance = reinterpret_cast<PFN_vkCreateInstance>(
        compositor->getInstanceProcAddr(VK_NULL_HANDLE, "vkCreateInstance"));
    if (!vkCreateInstance) {
        kine_vk_set_error(compositor, "vkCreateInstance unavailable");
        return false;
    }

    uint32_t extensionCount = 0;
    char const* const* sdlExtensions = SDL_Vulkan_GetInstanceExtensions(&extensionCount);
    if (!sdlExtensions || extensionCount == 0) {
        kine_vk_set_error(compositor, "SDL_Vulkan_GetInstanceExtensions failed");
        return false;
    }

    uint32_t loaderVersion = VK_API_VERSION_1_0;
    auto enumerateVersion = reinterpret_cast<PFN_vkEnumerateInstanceVersion>(
        compositor->getInstanceProcAddr(VK_NULL_HANDLE, "vkEnumerateInstanceVersion"));
    if (enumerateVersion) {
        enumerateVersion(&loaderVersion);
    }
    compositor->apiVersion = std::min(loaderVersion, VK_API_VERSION_1_1);

    std::vector<const char*> extensions(sdlExtensions, sdlExtensions + extensionCount);
    constexpr const char* portabilityEnumeration = "VK_KHR_portability_enumeration";
    const bool hasPortabilityEnumeration = kine_vk_instance_extension_available(
        compositor->getInstanceProcAddr,
        portabilityEnumeration);
    if (hasPortabilityEnumeration &&
        !kine_vk_has_extension(extensions, portabilityEnumeration)) {
        extensions.push_back(portabilityEnumeration);
    }

    VkApplicationInfo appInfo{};
    appInfo.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    appInfo.pApplicationName = "Kinemium";
    appInfo.applicationVersion = VK_MAKE_VERSION(0, 1, 0);
    appInfo.pEngineName = "Kinemium";
    appInfo.engineVersion = VK_MAKE_VERSION(0, 1, 0);
    appInfo.apiVersion = compositor->apiVersion;

    VkInstanceCreateInfo createInfo{};
    createInfo.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    createInfo.pApplicationInfo = &appInfo;
    createInfo.enabledExtensionCount = static_cast<uint32_t>(extensions.size());
    createInfo.ppEnabledExtensionNames = extensions.data();
#if defined(VK_KHR_portability_enumeration)
    if (hasPortabilityEnumeration) {
        createInfo.flags |= VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;
    }
#endif

    VkResult result = vkCreateInstance(&createInfo, nullptr, &compositor->instance);
    if (result != VK_SUCCESS) {
        kine_vk_set_error(compositor, "vkCreateInstance failed");
        return false;
    }

    return true;
}

static bool kine_vk_create_surface(KineVulkanCompositor* compositor, void* sdlWindow)
{
    if (compositor->swapchainBackend.createSurface) {
        uint64_t surface = 0;
        auto result = compositor->swapchainBackend.createSurface(sdlWindow, compositor->instance, &surface);
        if (result != VK_SUCCESS) {
            kine_vk_set_error(compositor, "Odin SDL surface creation failed");
            return false;
        }
        compositor->surface = (VkSurfaceKHR)surface;
        return true;
    }
    if (!SDL_Vulkan_CreateSurface(
            reinterpret_cast<SDL_Window*>(sdlWindow),
            compositor->instance,
            nullptr,
            &compositor->surface)) {
        kine_vk_set_error(compositor, "SDL_Vulkan_CreateSurface failed");
        return false;
    }
    return true;
}

static const char* kine_vk_gpu_preference_name()
{
    for (const char* variable : { "KINE_VULKAN_GPU", "KINE_GPU" }) {
        const char* value = std::getenv(variable);
        if (value && value[0] != '\0') {
            return value;
        }
    }
    return nullptr;
}


static const char* kine_vk_present_mode_name(VkPresentModeKHR mode)
{
    switch (mode) {
        case VK_PRESENT_MODE_FIFO_KHR:
            return "fifo";
        case VK_PRESENT_MODE_MAILBOX_KHR:
            return "mailbox";
        case VK_PRESENT_MODE_IMMEDIATE_KHR:
            return "immediate";
        case VK_PRESENT_MODE_FIFO_RELAXED_KHR:
            return "fifo-relaxed";
        default:
            return "unknown";
    }
}

static int kine_vk_gpu_preference_index()
{
    for (const char* variable : { "KINE_VULKAN_GPU_INDEX", "KINE_GPU_INDEX" }) {
        const char* value = std::getenv(variable);
        if (!value || value[0] == '\0') {
            continue;
        }
        char* end = nullptr;
        const long parsed = std::strtol(value, &end, 10);
        if (end != value && parsed >= 0 && parsed <= 127) {
            return static_cast<int>(parsed);
        }
        fprintf(stderr,
            "[Kine] ignoring invalid %s=%s (expected an index in 0..127)\n",
            variable, value);
    }
    return -1;
}

static int kine_vk_device_score(VkPhysicalDeviceType type)
{
    switch (type) {
        case VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU:
            return 4;
        case VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU:
            return 3;
        case VK_PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU:
            return 2;
        case VK_PHYSICAL_DEVICE_TYPE_CPU:
            return 1;
        default:
            return 0;
    }
}

struct KineVkDeviceCandidate {
    VkPhysicalDevice device = VK_NULL_HANDLE;
    uint32_t queueFamilyIndex = UINT32_MAX;
    uint32_t queueCount = 0;
    VkPhysicalDeviceProperties properties = {};
    uint32_t order = 0;
};

static bool kine_vk_pick_device(KineVulkanCompositor* compositor)
{
    auto vkEnumeratePhysicalDevices = kine_vk_instance_proc<PFN_vkEnumeratePhysicalDevices>(
        compositor, "vkEnumeratePhysicalDevices");
    auto vkGetPhysicalDeviceQueueFamilyProperties =
        kine_vk_instance_proc<PFN_vkGetPhysicalDeviceQueueFamilyProperties>(
            compositor, "vkGetPhysicalDeviceQueueFamilyProperties");
    auto vkGetPhysicalDeviceSurfaceSupportKHR =
        kine_vk_instance_proc<PFN_vkGetPhysicalDeviceSurfaceSupportKHR>(
            compositor, "vkGetPhysicalDeviceSurfaceSupportKHR");
    auto vkGetPhysicalDeviceProperties =
        kine_vk_instance_proc<PFN_vkGetPhysicalDeviceProperties>(
            compositor, "vkGetPhysicalDeviceProperties");
    if (!vkEnumeratePhysicalDevices || !vkGetPhysicalDeviceQueueFamilyProperties ||
        !vkGetPhysicalDeviceSurfaceSupportKHR || !vkGetPhysicalDeviceProperties) {
        kine_vk_set_error(compositor, "required physical-device Vulkan procs unavailable");
        return false;
    }

    uint32_t deviceCount = 0;
    if (vkEnumeratePhysicalDevices(compositor->instance, &deviceCount, nullptr) != VK_SUCCESS ||
        deviceCount == 0) {
        kine_vk_set_error(compositor, "no Vulkan physical devices found");
        return false;
    }

    std::vector<VkPhysicalDevice> devices(deviceCount);
    if (vkEnumeratePhysicalDevices(compositor->instance, &deviceCount, devices.data()) != VK_SUCCESS) {
        kine_vk_set_error(compositor, "vkEnumeratePhysicalDevices failed");
        return false;
    }

    std::vector<KineVkDeviceCandidate> candidates;
    candidates.reserve(deviceCount);
    for (uint32_t deviceIndex = 0; deviceIndex < deviceCount; ++deviceIndex) {
        VkPhysicalDevice device = devices[deviceIndex];
        uint32_t queueFamilyCount = 0;
        vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, nullptr);
        if (queueFamilyCount == 0) {
            continue;
        }

        std::vector<VkQueueFamilyProperties> families(queueFamilyCount);
        vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, families.data());

        for (uint32_t i = 0; i < queueFamilyCount; ++i) {
            VkBool32 presentSupported = VK_FALSE;
            vkGetPhysicalDeviceSurfaceSupportKHR(device, i, compositor->surface, &presentSupported);
            if ((families[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) && presentSupported) {
                KineVkDeviceCandidate candidate;
                candidate.device = device;
                candidate.queueFamilyIndex = i;
                candidate.queueCount = families[i].queueCount;
                candidate.order = deviceIndex;
                vkGetPhysicalDeviceProperties(device, &candidate.properties);
                candidates.push_back(candidate);
                break;
            }
        }
    }

    if (candidates.empty()) {
        kine_vk_set_error(compositor, "no graphics+present Vulkan queue found");
        return false;
    }

    const char* preferredName = kine_vk_gpu_preference_name();
    const int preferredIndex = kine_vk_gpu_preference_index();
    auto best = candidates.begin();
    bool havePreference = false;
    if (preferredName) {
        auto match = std::find_if(candidates.begin(), candidates.end(),
            [preferredName](const KineVkDeviceCandidate& candidate) {
                return std::strstr(candidate.properties.deviceName, preferredName) != nullptr;
            });
        if (match != candidates.end()) {
            best = match;
            havePreference = true;
        } else {
            fprintf(stderr,
                "[Kine] no Vulkan device matches KINE_VULKAN_GPU='%s'; "
                "falling back to the discrete GPU preference\n",
                preferredName);
        }
    } else if (preferredIndex >= 0) {
        auto match = std::find_if(candidates.begin(), candidates.end(),
            [preferredIndex](const KineVkDeviceCandidate& candidate) {
                return candidate.order == static_cast<uint32_t>(preferredIndex);
            });
        if (match != candidates.end()) {
            best = match;
            havePreference = true;
        } else {
            fprintf(stderr,
                "[Kine] KINE_VULKAN_GPU_INDEX=%d is not a usable Vulkan device; "
                "falling back to the discrete GPU preference\n",
                preferredIndex);
        }
    }

    if (!havePreference) {
        for (auto candidate = candidates.begin(); candidate != candidates.end(); ++candidate) {
            if (kine_vk_device_score(candidate->properties.deviceType) >
                kine_vk_device_score(best->properties.deviceType)) {
                best = candidate;
            }
        }
    }

    compositor->physicalDevice = best->device;
    compositor->graphicsQueueFamilyIndex = best->queueFamilyIndex;
    compositor->graphicsQueueCount = best->queueCount;
    fprintf(stderr,
        "[Kine] compositor Vulkan device: '%s' (type %d, index %u)\n",
        best->properties.deviceName,
        static_cast<int>(best->properties.deviceType),
        best->order);
    return true;
}

static bool kine_vk_validate_present_queue(KineVulkanCompositor* compositor)
{
    auto vkGetPhysicalDeviceSurfaceSupportKHR =
        kine_vk_instance_proc<PFN_vkGetPhysicalDeviceSurfaceSupportKHR>(
            compositor, "vkGetPhysicalDeviceSurfaceSupportKHR");
    if (!vkGetPhysicalDeviceSurfaceSupportKHR) {
        kine_vk_set_error(compositor, "vkGetPhysicalDeviceSurfaceSupportKHR unavailable");
        return false;
    }

    VkBool32 presentSupported = VK_FALSE;
    if (vkGetPhysicalDeviceSurfaceSupportKHR(
            compositor->physicalDevice,
            compositor->graphicsQueueFamilyIndex,
            compositor->surface,
            &presentSupported) != VK_SUCCESS || !presentSupported) {
        kine_vk_set_error(compositor, "external Vulkan graphics queue cannot present to this SDL surface");
        return false;
    }
    return true;
}

static bool kine_vk_create_device(KineVulkanCompositor* compositor)
{
    auto vkCreateDevice = kine_vk_instance_proc<PFN_vkCreateDevice>(compositor, "vkCreateDevice");
    auto vkEnumerateDeviceExtensionProperties =
        kine_vk_instance_proc<PFN_vkEnumerateDeviceExtensionProperties>(
            compositor, "vkEnumerateDeviceExtensionProperties");
    if (!vkCreateDevice || !vkEnumerateDeviceExtensionProperties) {
        kine_vk_set_error(compositor, "required device-creation Vulkan procs unavailable");
        return false;
    }

    float priorities[] = { 1.0f, 1.0f };
    VkDeviceQueueCreateInfo queueInfo{};
    queueInfo.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
    queueInfo.queueFamilyIndex = compositor->graphicsQueueFamilyIndex;
    queueInfo.queueCount = std::min<uint32_t>(compositor->graphicsQueueCount, 2);
    if (queueInfo.queueCount == 0) {
        queueInfo.queueCount = 1;
    }
    queueInfo.pQueuePriorities = priorities;

    uint32_t availableExtensionCount = 0;
    if (vkEnumerateDeviceExtensionProperties(
            compositor->physicalDevice,
            nullptr,
            &availableExtensionCount,
            nullptr) != VK_SUCCESS) {
        kine_vk_set_error(compositor, "vkEnumerateDeviceExtensionProperties failed");
        return false;
    }
    std::vector<VkExtensionProperties> availableExtensions(availableExtensionCount);
    if (availableExtensionCount > 0 && vkEnumerateDeviceExtensionProperties(
            compositor->physicalDevice,
            nullptr,
            &availableExtensionCount,
            availableExtensions.data()) != VK_SUCCESS) {
        kine_vk_set_error(compositor, "vkEnumerateDeviceExtensionProperties list failed");
        return false;
    }
    auto deviceExtensionAvailable = [&availableExtensions](const char* name) {
        return std::any_of(
            availableExtensions.begin(),
            availableExtensions.end(),
            [name](const auto& extension) {
                return std::strcmp(extension.extensionName, name) == 0;
            });
    };
    if (!deviceExtensionAvailable(VK_KHR_SWAPCHAIN_EXTENSION_NAME)) {
        kine_vk_set_error(compositor, "VK_KHR_swapchain is unavailable on the selected device");
        return false;
    }

    std::vector<const char*> extensions{VK_KHR_SWAPCHAIN_EXTENSION_NAME};
    constexpr const char* portabilitySubset = "VK_KHR_portability_subset";
    if (deviceExtensionAvailable(portabilitySubset)) {
        extensions.push_back(portabilitySubset);
    }


    VkPhysicalDeviceDescriptorIndexingFeaturesEXT indexingFeatures{};
    bool enableDescriptorIndexing = false;
    constexpr const char* descriptorIndexing = "VK_EXT_descriptor_indexing";
    auto vkGetPhysicalDeviceFeatures2 = kine_vk_instance_proc<PFN_vkGetPhysicalDeviceFeatures2>(
        compositor, "vkGetPhysicalDeviceFeatures2");
    if (deviceExtensionAvailable(descriptorIndexing) && vkGetPhysicalDeviceFeatures2) {
        indexingFeatures.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_INDEXING_FEATURES_EXT;
        VkPhysicalDeviceFeatures2 features2{};
        features2.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2;
        features2.pNext = &indexingFeatures;
        vkGetPhysicalDeviceFeatures2(compositor->physicalDevice, &features2);
        enableDescriptorIndexing = indexingFeatures.descriptorBindingPartiallyBound == VK_TRUE;
    }
    if (enableDescriptorIndexing) {
        indexingFeatures.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_INDEXING_FEATURES_EXT;
        indexingFeatures.pNext = nullptr;
        indexingFeatures.descriptorBindingPartiallyBound = VK_TRUE;
        extensions.push_back(descriptorIndexing);
    }

    VkDeviceCreateInfo createInfo{};
    createInfo.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
    createInfo.queueCreateInfoCount = 1;
    createInfo.pQueueCreateInfos = &queueInfo;
    createInfo.enabledExtensionCount = static_cast<uint32_t>(extensions.size());
    createInfo.ppEnabledExtensionNames = extensions.data();
    if (enableDescriptorIndexing) {
        createInfo.pNext = &indexingFeatures;
    }

    VkResult result = vkCreateDevice(compositor->physicalDevice, &createInfo, nullptr, &compositor->device);
    if (result != VK_SUCCESS) {
        kine_vk_set_error(compositor, "vkCreateDevice failed");
        return false;
    }

    compositor->getDeviceProcAddr = reinterpret_cast<PFN_vkGetDeviceProcAddr>(
        compositor->getInstanceProcAddr(compositor->instance, "vkGetDeviceProcAddr"));
    if (!compositor->getDeviceProcAddr) {
        kine_vk_set_error(compositor, "vkGetDeviceProcAddr unavailable");
        return false;
    }

    auto vkGetDeviceQueue = kine_vk_device_proc<PFN_vkGetDeviceQueue>(compositor, "vkGetDeviceQueue");
    if (!vkGetDeviceQueue) {
        kine_vk_set_error(compositor, "vkGetDeviceQueue unavailable");
        return false;
    }

    vkGetDeviceQueue(compositor->device, compositor->graphicsQueueFamilyIndex, 0, &compositor->graphicsQueue);
    if (!compositor->graphicsQueue) {
        kine_vk_set_error(compositor, "vkGetDeviceQueue returned null");
        return false;
    }

    return true;
}

static KineVulkanFrameDispatch kine_vk_frame_dispatch(KineVulkanCompositor* c);

static bool kine_vk_create_frame_resources(KineVulkanCompositor* compositor)
{
    if (compositor->swapchainBackend.createRoot) {
        auto d = kine_vk_frame_dispatch(compositor);
        uint64_t pool = 0, fence = 0;
        auto result = compositor->swapchainBackend.createRoot(&d, compositor->graphicsQueueFamilyIndex, &pool, &fence);
        if (result != VK_SUCCESS) {
            if (result == VK_ERROR_DEVICE_LOST) compositor->device_lost = true;
            kine_vk_set_error(compositor, "Odin root resources failed");
            return false;
        }
        compositor->commandPool = (VkCommandPool)pool;
        compositor->acquireFence = (VkFence)fence;
        const char* override = std::getenv("KINE_VULKAN_ACQUIRE");
        compositor->gpuAcquire = !override || std::strcmp(override, "cpu") != 0;
        return true;
    }
    auto vkCreateCommandPool = kine_vk_device_proc<PFN_vkCreateCommandPool>(
        compositor, "vkCreateCommandPool");
    auto vkCreateFence = kine_vk_device_proc<PFN_vkCreateFence>(
        compositor, "vkCreateFence");
    if (!vkCreateCommandPool || !vkCreateFence) {
        kine_vk_set_error(compositor, "required frame-resource Vulkan procs unavailable");
        return false;
    }

    VkCommandPoolCreateInfo poolInfo{};
    poolInfo.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
    poolInfo.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    poolInfo.queueFamilyIndex = compositor->graphicsQueueFamilyIndex;
    if (vkCreateCommandPool(compositor->device, &poolInfo, nullptr, &compositor->commandPool) != VK_SUCCESS) {
        kine_vk_set_error(compositor, "vkCreateCommandPool failed");
        return false;
    }

    VkFenceCreateInfo fenceInfo{};
    fenceInfo.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
    if (vkCreateFence(compositor->device, &fenceInfo, nullptr, &compositor->acquireFence) != VK_SUCCESS) {
        kine_vk_set_error(compositor, "vkCreateFence failed");
        return false;
    }

    const char* acquireOverride = std::getenv("KINE_VULKAN_ACQUIRE");
    compositor->gpuAcquire = !acquireOverride ||
        std::strcmp(acquireOverride, "cpu") != 0;
    return true;
}

static bool kine_vk_record_skia_handoff(KineVulkanCompositor* compositor, VkCommandBuffer command, VkQueryPool timing);

static void kine_vk_init_timing(KineVulkanCompositor* c)
{
    c->timestampBits = 0;
    c->latestTimingSerial = 0;
    c->latestTimingNs = 0;
    c->latestStageValid = false;
    c->latestOverlayValid = false;
    const char* detail = std::getenv("KINE_VULKAN_GPU_TIMING_DETAIL");
    c->detailedTiming = detail && std::strcmp(detail, "1") == 0;
    const char* enabled = std::getenv("KINE_VULKAN_GPU_TIMING");
#if defined(__ANDROID__)
    if (!enabled || std::strcmp(enabled, "1") != 0) return;
#else
    if (enabled && std::strcmp(enabled, "0") == 0) return;
#endif
    auto getFamilies = kine_vk_instance_proc<PFN_vkGetPhysicalDeviceQueueFamilyProperties>(c,"vkGetPhysicalDeviceQueueFamilyProperties");
    auto getProperties = kine_vk_instance_proc<PFN_vkGetPhysicalDeviceProperties>(c,"vkGetPhysicalDeviceProperties");
    if (!getFamilies || !getProperties) return;
    uint32_t count = 0;
    getFamilies(c->physicalDevice,&count,nullptr);
    if (c->graphicsQueueFamilyIndex >= count) return;
    std::vector<VkQueueFamilyProperties> families(count);
    getFamilies(c->physicalDevice,&count,families.data());
    VkPhysicalDeviceProperties properties{};
    getProperties(c->physicalDevice,&properties);
    c->timestampBits = families[c->graphicsQueueFamilyIndex].timestampValidBits;
    c->timestampPeriod = properties.limits.timestampPeriod;
}

static void kine_vk_collect_timing(KineVulkanCompositor* c, KineVulkanFrameSlot& slot)
{
    if (!slot.timing || !slot.timingSerial || slot.timingSerial <= c->latestTimingSerial) return;
    auto getResults = kine_vk_device_proc<PFN_vkGetQueryPoolResults>(c,"vkGetQueryPoolResults");
    if (!getResults) return;
    uint64_t values[2]{};
    if (getResults(c->device,slot.timing,0,2,sizeof(values),values,sizeof(uint64_t),VK_QUERY_RESULT_64_BIT) != VK_SUCCESS) return;
    uint64_t ticks = values[1]-values[0];
    if (c->timestampBits < 64) ticks &= (uint64_t(1)<<c->timestampBits)-1;
    c->latestTimingSerial = slot.timingSerial;
    c->latestTimingNs = uint64_t(double(ticks)*c->timestampPeriod);
    c->latestStageValid = false;
    c->latestOverlayValid = false;
    uint64_t middle = 0;
    if (slot.timingHandoff && getResults(c->device, slot.timing, 2, 1, sizeof(middle),
            &middle, sizeof(middle), VK_QUERY_RESULT_64_BIT) == VK_SUCCESS) {
        uint64_t baseTicks = middle - values[0];
        if (c->timestampBits < 64) baseTicks &= (uint64_t(1)<<c->timestampBits)-1;
        if (baseTicks <= ticks) {
            c->latestBaseNs = uint64_t(double(baseTicks)*c->timestampPeriod);
            c->latestRenderNs = uint64_t(double(ticks-baseTicks)*c->timestampPeriod);
            c->latestStageValid = true;
            uint64_t overlay = 0;
            if (slot.timingOverlay && getResults(c->device, slot.timing, 3, 1,
                    sizeof(overlay), &overlay, sizeof(overlay), VK_QUERY_RESULT_64_BIT) == VK_SUCCESS) {
                uint64_t overlayTicks = overlay - values[0];
                if (c->timestampBits < 64) overlayTicks &= (uint64_t(1)<<c->timestampBits)-1;
                if (overlayTicks >= baseTicks && overlayTicks <= ticks) {
                    c->latestFilamentNs = uint64_t(double(overlayTicks-baseTicks)*c->timestampPeriod);
                    c->latestOverlayNs = uint64_t(double(ticks-overlayTicks)*c->timestampPeriod);
                    c->latestOverlayValid = true;
                }
            }
        }
    }
}

KINE_VULKAN_COMPOSITOR_API int Kine_VulkanCompositor_GetLatestQueueDetail(
    KineVulkanCompositor* c, uint64_t* serial, uint64_t* filament, uint64_t* overlay)
{
    if (!c || !serial || !filament || !overlay || !c->latestOverlayValid) return 0;
    *serial = c->latestTimingSerial;
    *filament = c->latestFilamentNs;
    *overlay = c->latestOverlayNs;
    return 1;
}

KINE_VULKAN_COMPOSITOR_API int Kine_VulkanCompositor_GetLatestQueueStages(
    KineVulkanCompositor* c, uint64_t* serial, uint64_t* base, uint64_t* render)
{
    if (!c || !serial || !base || !render || !c->latestStageValid) return 0;
    *serial = c->latestTimingSerial;
    *base = c->latestBaseNs;
    *render = c->latestRenderNs;
    return 1;
}

KINE_VULKAN_COMPOSITOR_API int Kine_VulkanCompositor_GetLatestQueueTiming(KineVulkanCompositor* c, uint64_t* serial, uint64_t* ns)
{
    if (!c || !serial || !ns || !c->timestampBits || !c->latestTimingSerial) return 0;
    *serial = c->latestTimingSerial;
    *ns = c->latestTimingNs;
    return 1;
}

static KineVulkanFrameDispatch kine_vk_frame_dispatch(KineVulkanCompositor* c)
{
    return {c->device, reinterpret_cast<void*>(c->getDeviceProcAddr), (uint64_t)c->commandPool,
        uint32_t(c->timestampBits != 0), uint32_t(c->detailedTiming), uint32_t(c->offscreen)};
}

static VkResult kine_vk_retire_fence(KineVulkanCompositor* c, VkFence fence, bool wait)
{
    if (c->swapchainBackend.retireFence) {
        auto d = kine_vk_frame_dispatch(c);
        return static_cast<VkResult>(c->swapchainBackend.retireFence(&d, (uint64_t)fence, uint32_t(wait)));
    }
    if (wait) {
        auto proc = kine_vk_device_proc<PFN_vkWaitForFences>(c, "vkWaitForFences");
        return proc ? proc(c->device, 1, &fence, VK_TRUE, UINT64_MAX) : VK_ERROR_INITIALIZATION_FAILED;
    }
    auto proc = kine_vk_device_proc<PFN_vkGetFenceStatus>(c, "vkGetFenceStatus");
    return proc ? proc(c->device, fence) : VK_ERROR_INITIALIZATION_FAILED;
}

static VkResult kine_vk_submit(KineVulkanCompositor* c, VkCommandBuffer command,
    VkSemaphore wait, VkSemaphore signal, VkFence fence)
{
    if (c->swapchainBackend.submit) {
        auto dispatch = kine_vk_frame_dispatch(c);
        return static_cast<VkResult>(c->swapchainBackend.submit(&dispatch, c->graphicsQueue,
            command, (uint64_t)wait, (uint64_t)signal, (uint64_t)fence));
    }
    auto submit = kine_vk_device_proc<PFN_vkQueueSubmit>(c, "vkQueueSubmit");
    if (!submit) return VK_ERROR_INITIALIZATION_FAILED;
    VkSubmitInfo info{};
    info.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    VkPipelineStageFlags stage = VK_PIPELINE_STAGE_ALL_COMMANDS_BIT;
    if (wait) { info.waitSemaphoreCount = 1; info.pWaitSemaphores = &wait; info.pWaitDstStageMask = &stage; }
    if (signal) { info.signalSemaphoreCount = 1; info.pSignalSemaphores = &signal; }
    if (command) { info.commandBufferCount = 1; info.pCommandBuffers = &command; }
    return submit(c->graphicsQueue, 1, &info, fence);
}

static const std::vector<VkImage>& kine_vk_render_images(const KineVulkanCompositor* c)
{
    return c->offscreen ? c->renderImages : c->swapchainImages;
}

static std::vector<VkImageLayout>& kine_vk_render_layouts(KineVulkanCompositor* c)
{
    return c->offscreen ? c->renderLayouts : c->swapchainImageLayouts;
}

static VkImageUsageFlags kine_vk_render_usage(const KineVulkanCompositor* c)
{
    return c->offscreen ? VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT |
        VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT : c->swapchainUsage;
}

static bool kine_vk_create_image_frames(KineVulkanCompositor* compositor)
{
    auto vkAllocateCommandBuffers = kine_vk_device_proc<PFN_vkAllocateCommandBuffers>(
        compositor, "vkAllocateCommandBuffers");
    auto vkCreateFence = kine_vk_device_proc<PFN_vkCreateFence>(
        compositor, "vkCreateFence");
    if (!vkAllocateCommandBuffers || !vkCreateFence) {
        kine_vk_set_error(compositor, "required image-frame Vulkan procs unavailable");
        return false;
    }

    VkFenceCreateInfo fenceInfo{};
    fenceInfo.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;

    kine_vk_init_timing(compositor);
    auto createQueryPool = kine_vk_device_proc<PFN_vkCreateQueryPool>(compositor,"vkCreateQueryPool");
    compositor->frames.clear();
    compositor->frames.resize(kine_vk_render_images(compositor).size());
    for (auto& frame : compositor->frames) {
        for (auto& slot : frame.slots) {
            if (compositor->offscreen && &slot != &frame.slots[0]) continue;
            if (compositor->swapchainBackend.createFrame) {
                auto dispatch = kine_vk_frame_dispatch(compositor);
                KineVulkanFrameResources resources{};
                auto result = compositor->swapchainBackend.createFrame(&dispatch, &resources);
                if (result != VK_SUCCESS) {
                    if (result == VK_ERROR_DEVICE_LOST) compositor->device_lost = true;
                    kine_vk_set_error(compositor, "Odin frame resource allocation failed");
                    return false;
                }
                slot.acquire = (VkCommandBuffer)resources.commands[0];
                slot.handoff = (VkCommandBuffer)resources.commands[1];
                slot.present = (VkCommandBuffer)resources.commands[2];
                slot.overlayTiming = (VkCommandBuffer)resources.commands[3];
                slot.renderComplete = (VkCommandBuffer)resources.commands[4];
                slot.finished = (VkFence)resources.fence;
                slot.timing = (VkQueryPool)resources.query;
                if (compositor->offscreen) {
                    uint64_t semaphore = 0, fence = 0;
                    if (compositor->swapchainBackend.createSync(&dispatch, &semaphore, &fence, nullptr) != VK_SUCCESS) {
                        kine_vk_set_error(compositor, "Odin late acquire semaphore allocation failed");
                        return false;
                    }
                    slot.lateAcquire = (VkSemaphore)semaphore;
                    slot.lateAcquireFence = (VkFence)fence;
                    uint64_t ready = 0, returned = 0;
                    auto syncResult = compositor->swapchainBackend.createSync(&dispatch, &ready, nullptr, nullptr);
                    slot.copyReady = (VkSemaphore)ready;
                    if (syncResult == VK_SUCCESS) syncResult = compositor->swapchainBackend.createSync(&dispatch, &returned, nullptr, nullptr);
                    slot.copyReturned = (VkSemaphore)returned;
                    if (syncResult != VK_SUCCESS) {
                        if (syncResult == VK_ERROR_DEVICE_LOST) compositor->device_lost = true;
                        kine_vk_set_error(compositor, "Odin copy queue synchronization allocation failed");
                        return false;
                    }
                }
                continue;
            }
            VkCommandBuffer buffers[3] = {};
            VkCommandBufferAllocateInfo bufferInfo{};
            bufferInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
            bufferInfo.commandPool = compositor->commandPool;
            bufferInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
            bufferInfo.commandBufferCount = 3;
            if (vkAllocateCommandBuffers(compositor->device, &bufferInfo, buffers) != VK_SUCCESS) {
                kine_vk_set_error(compositor, "failed allocating swapchain image command buffers");
                return false;
            }
            slot.acquire = buffers[0];
            slot.handoff = buffers[1];
            slot.present = buffers[2];
            if (compositor->timestampBits && createQueryPool) {
                VkQueryPoolCreateInfo queryInfo{};
                queryInfo.sType = VK_STRUCTURE_TYPE_QUERY_POOL_CREATE_INFO;
                queryInfo.queryType = VK_QUERY_TYPE_TIMESTAMP;
                queryInfo.queryCount = 4;
                if (createQueryPool(compositor->device,&queryInfo,nullptr,&slot.timing) != VK_SUCCESS)
                    slot.timing = VK_NULL_HANDLE;
            }

            if (slot.timing && compositor->detailedTiming) {
                auto begin = kine_vk_device_proc<PFN_vkBeginCommandBuffer>(compositor, "vkBeginCommandBuffer");
                auto end = kine_vk_device_proc<PFN_vkEndCommandBuffer>(compositor, "vkEndCommandBuffer");
                auto stamp = kine_vk_device_proc<PFN_vkCmdWriteTimestamp>(compositor, "vkCmdWriteTimestamp");
                bufferInfo.commandBufferCount = 1;
                if (!begin || !end || !stamp ||
                    vkAllocateCommandBuffers(compositor->device, &bufferInfo, &slot.overlayTiming) != VK_SUCCESS) return false;
                VkCommandBufferBeginInfo info{};
                info.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
                if (begin(slot.overlayTiming, &info) != VK_SUCCESS) return false;
                stamp(slot.overlayTiming, VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, slot.timing, 3);
                if (end(slot.overlayTiming) != VK_SUCCESS) return false;
            }


            if (vkCreateFence(compositor->device, &fenceInfo, nullptr, &slot.finished) != VK_SUCCESS ||
                !kine_vk_record_skia_handoff(compositor, slot.handoff, slot.timing)) {
                kine_vk_set_error(compositor, "failed creating swapchain image frame resources");
                return false;
            }
        }
    }
    return true;
}

static bool kine_vk_flush_surface(KineVulkanCompositor* c, KineSkiaSurface* surface)
{
    if (c->swapchainBackend.flushSurface) return c->swapchainBackend.flushSurface(surface) != 0;
    return Kine_Skia_Surface_FlushVulkanLayout(surface, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL) != 0;
}

static bool kine_vk_wait_surface(KineVulkanCompositor* c, KineSkiaSurface* surface, VkSemaphore semaphore)
{
    if (c->swapchainBackend.waitSurface) return c->swapchainBackend.waitSurface(surface, semaphore) != 0;
    return Kine_Skia_Surface_WaitVulkanSemaphore(surface, semaphore) != 0;
}

static void kine_vk_release_frame_surfaces(KineVulkanCompositor* c, KineVulkanFrame& frame)
{
    if (frame.base) {
        if (c->swapchainBackend.releaseSurface) c->swapchainBackend.releaseSurface(frame.base);
        else Kine_Skia_Surface_Destroy(frame.base);
        frame.base = nullptr;
    }
    if (frame.overlay) {
        if (c->swapchainBackend.releaseSurface) c->swapchainBackend.releaseSurface(frame.overlay);
        else Kine_Skia_Surface_Destroy(frame.overlay);
        frame.overlay = nullptr;
    }
}

static uint32_t kine_vk_find_memory_type(
    KineVulkanCompositor* compositor,
    uint32_t typeFilter,
    VkMemoryPropertyFlags properties)
{
    auto vkGetPhysicalDeviceMemoryProperties =
        kine_vk_instance_proc<PFN_vkGetPhysicalDeviceMemoryProperties>(
            compositor, "vkGetPhysicalDeviceMemoryProperties");
    if (!vkGetPhysicalDeviceMemoryProperties) {
        return UINT32_MAX;
    }

    VkPhysicalDeviceMemoryProperties memoryProperties{};
    vkGetPhysicalDeviceMemoryProperties(compositor->physicalDevice, &memoryProperties);
    for (uint32_t i = 0; i < memoryProperties.memoryTypeCount; ++i) {
        if ((typeFilter & (1u << i)) &&
            (memoryProperties.memoryTypes[i].propertyFlags & properties) == properties) {
            return i;
        }
    }
    return UINT32_MAX;
}

static bool kine_vk_choose_depth_format(KineVulkanCompositor* compositor, VkFormat* outFormat)
{
    auto vkGetPhysicalDeviceFormatProperties =
        kine_vk_instance_proc<PFN_vkGetPhysicalDeviceFormatProperties>(
            compositor, "vkGetPhysicalDeviceFormatProperties");
    if (!vkGetPhysicalDeviceFormatProperties || !outFormat) {
        return false;
    }

    const VkFormat candidates[] = {
        VK_FORMAT_D32_SFLOAT,
        VK_FORMAT_D24_UNORM_S8_UINT,
        VK_FORMAT_D16_UNORM,
    };
    for (VkFormat format : candidates) {
        VkFormatProperties properties{};
        vkGetPhysicalDeviceFormatProperties(compositor->physicalDevice, format, &properties);
        if (properties.optimalTilingFeatures & VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT) {
            *outFormat = format;
            return true;
        }
    }
    return false;
}

static void kine_vk_destroy_depth_attachment(KineVulkanCompositor* compositor)
{
    if (compositor->swapchainBackend.destroyColor) {
        auto d = kine_vk_frame_dispatch(compositor);
        compositor->swapchainBackend.destroyColor(&d, (uint64_t)compositor->depthImage, (uint64_t)compositor->depthImageMemory);
        compositor->depthImage = VK_NULL_HANDLE;
        compositor->depthImageMemory = VK_NULL_HANDLE;
        compositor->depthFormat = VK_FORMAT_UNDEFINED;
        return;
    }
    if (compositor->depthImage) {
        if (auto vkDestroyImage = kine_vk_device_proc<PFN_vkDestroyImage>(
                compositor, "vkDestroyImage")) {
            vkDestroyImage(compositor->device, compositor->depthImage, nullptr);
        }
        compositor->depthImage = VK_NULL_HANDLE;
    }
    if (compositor->depthImageMemory) {
        if (auto vkFreeMemory = kine_vk_device_proc<PFN_vkFreeMemory>(
                compositor, "vkFreeMemory")) {
            vkFreeMemory(compositor->device, compositor->depthImageMemory, nullptr);
        }
        compositor->depthImageMemory = VK_NULL_HANDLE;
    }
    compositor->depthFormat = VK_FORMAT_UNDEFINED;
}

static bool kine_vk_create_depth_attachment(KineVulkanCompositor* compositor)
{
    if (compositor->swapchainBackend.createDepth) {
        auto d = kine_vk_frame_dispatch(compositor);
        uint64_t image = 0, memory = 0;
        uint32_t format = 0;
        auto result = compositor->swapchainBackend.createDepth(&d, compositor->instance,
            compositor->physicalDevice, reinterpret_cast<void*>(compositor->getInstanceProcAddr),
            compositor->width, compositor->height, &image, &memory, &format);
        if (result != VK_SUCCESS) {
            if (result == VK_ERROR_DEVICE_LOST) compositor->device_lost = true;
            kine_vk_set_error(compositor, "Odin depth attachment allocation failed");
            return false;
        }
        compositor->depthImage = (VkImage)image;
        compositor->depthImageMemory = (VkDeviceMemory)memory;
        compositor->depthFormat = (VkFormat)format;
        return true;
    }
    auto vkCreateImage = kine_vk_device_proc<PFN_vkCreateImage>(
        compositor, "vkCreateImage");
    auto vkGetImageMemoryRequirements = kine_vk_device_proc<PFN_vkGetImageMemoryRequirements>(
        compositor, "vkGetImageMemoryRequirements");
    auto vkAllocateMemory = kine_vk_device_proc<PFN_vkAllocateMemory>(
        compositor, "vkAllocateMemory");
    auto vkBindImageMemory = kine_vk_device_proc<PFN_vkBindImageMemory>(
        compositor, "vkBindImageMemory");
    if (!vkCreateImage || !vkGetImageMemoryRequirements || !vkAllocateMemory || !vkBindImageMemory) {
        kine_vk_set_error(compositor, "required depth-attachment Vulkan procs unavailable");
        return false;
    }

    VkFormat depthFormat = VK_FORMAT_UNDEFINED;
    if (!kine_vk_choose_depth_format(compositor, &depthFormat)) {
        kine_vk_set_error(compositor, "no supported Vulkan depth format found");
        return false;
    }

    VkImageCreateInfo imageInfo{};
    imageInfo.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
    imageInfo.imageType = VK_IMAGE_TYPE_2D;
    imageInfo.extent.width = compositor->width;
    imageInfo.extent.height = compositor->height;
    imageInfo.extent.depth = 1;
    imageInfo.mipLevels = 1;
    imageInfo.arrayLayers = 1;
    imageInfo.format = depthFormat;
    imageInfo.tiling = VK_IMAGE_TILING_OPTIMAL;
    imageInfo.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    imageInfo.usage = VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT;
    imageInfo.samples = VK_SAMPLE_COUNT_1_BIT;
    imageInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    if (vkCreateImage(compositor->device, &imageInfo, nullptr, &compositor->depthImage) != VK_SUCCESS) {
        kine_vk_set_error(compositor, "vkCreateImage depth failed");
        return false;
    }

    VkMemoryRequirements requirements{};
    vkGetImageMemoryRequirements(compositor->device, compositor->depthImage, &requirements);
    uint32_t memoryTypeIndex = kine_vk_find_memory_type(
        compositor,
        requirements.memoryTypeBits,
        VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    if (memoryTypeIndex == UINT32_MAX) {
        kine_vk_set_error(compositor, "no device-local memory type for depth image");
        return false;
    }

    VkMemoryAllocateInfo allocateInfo{};
    allocateInfo.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    allocateInfo.allocationSize = requirements.size;
    allocateInfo.memoryTypeIndex = memoryTypeIndex;
    if (vkAllocateMemory(
            compositor->device,
            &allocateInfo,
            nullptr,
            &compositor->depthImageMemory) != VK_SUCCESS) {
        kine_vk_set_error(compositor, "vkAllocateMemory depth failed");
        return false;
    }

    if (vkBindImageMemory(
            compositor->device,
            compositor->depthImage,
            compositor->depthImageMemory,
            0) != VK_SUCCESS) {
        kine_vk_set_error(compositor, "vkBindImageMemory depth failed");
        return false;
    }

    compositor->depthFormat = depthFormat;
    return true;
}

static bool kine_vk_create_skia_context(KineVulkanCompositor* compositor)
{
    KineSkiaVulkanBackend backend{};
    backend.instance = compositor->instance;
    backend.physicalDevice = compositor->physicalDevice;
    backend.device = compositor->device;
    backend.queue = compositor->graphicsQueue;
    backend.graphicsQueueFamilyIndex = compositor->graphicsQueueFamilyIndex;
    backend.maxApiVersion = compositor->apiVersion;
    backend.getInstanceProcAddr = reinterpret_cast<void*>(compositor->getInstanceProcAddr);
    backend.getDeviceProcAddr = reinterpret_cast<void*>(compositor->getDeviceProcAddr);

    compositor->skiaContext = Kine_Skia_Vulkan_CreateContext(&backend);
    if (!compositor->skiaContext) {
        kine_vk_set_error(compositor, "Kine_Skia_Vulkan_CreateContext failed");
        return false;
    }

    return true;
}

static bool kine_vk_create_swapchain(KineVulkanCompositor* compositor)
{
    auto vkGetPhysicalDeviceSurfaceCapabilitiesKHR =
        kine_vk_instance_proc<PFN_vkGetPhysicalDeviceSurfaceCapabilitiesKHR>(
            compositor, "vkGetPhysicalDeviceSurfaceCapabilitiesKHR");
    auto vkGetPhysicalDeviceSurfaceFormatsKHR =
        kine_vk_instance_proc<PFN_vkGetPhysicalDeviceSurfaceFormatsKHR>(
            compositor, "vkGetPhysicalDeviceSurfaceFormatsKHR");
    auto vkGetPhysicalDeviceSurfacePresentModesKHR =
        kine_vk_instance_proc<PFN_vkGetPhysicalDeviceSurfacePresentModesKHR>(
            compositor, "vkGetPhysicalDeviceSurfacePresentModesKHR");
    auto vkCreateSwapchainKHR = kine_vk_device_proc<PFN_vkCreateSwapchainKHR>(
        compositor, "vkCreateSwapchainKHR");
    auto vkGetSwapchainImagesKHR = kine_vk_device_proc<PFN_vkGetSwapchainImagesKHR>(
        compositor, "vkGetSwapchainImagesKHR");
    auto vkCreateSemaphore = kine_vk_device_proc<PFN_vkCreateSemaphore>(
        compositor, "vkCreateSemaphore");
    auto vkCreateFence = kine_vk_device_proc<PFN_vkCreateFence>(
        compositor, "vkCreateFence");
    if (!vkGetPhysicalDeviceSurfaceCapabilitiesKHR || !vkGetPhysicalDeviceSurfaceFormatsKHR ||
        !vkGetPhysicalDeviceSurfacePresentModesKHR || !vkCreateSwapchainKHR ||
        !vkGetSwapchainImagesKHR || !vkCreateSemaphore ||
        !vkCreateFence) {
        kine_vk_set_error(compositor, "required swapchain Vulkan procs unavailable");
        return false;
    }

    VkSurfaceFormatKHR chosenFormat{};
    VkExtent2D extent{};
    uint32_t imageCount = 0;
    VkImageUsageFlags swapchainUsage = 0;
    VkPresentModeKHR presentMode = VK_PRESENT_MODE_FIFO_KHR;
    compositor->nativeSwapchain = false;
    if (compositor->swapchainBackend.create && compositor->swapchainBackend.destroy) {
        auto destroy = kine_vk_device_proc<PFN_vkDestroySwapchainKHR>(compositor, "vkDestroySwapchainKHR");
        if (destroy) {
            const KineVulkanSwapchainDispatch dispatch{
                compositor->physicalDevice, compositor->device,
                reinterpret_cast<void*>(vkGetPhysicalDeviceSurfaceCapabilitiesKHR),
                reinterpret_cast<void*>(vkGetPhysicalDeviceSurfaceFormatsKHR),
                reinterpret_cast<void*>(vkGetPhysicalDeviceSurfacePresentModesKHR),
                reinterpret_cast<void*>(vkCreateSwapchainKHR),
                (uint64_t)compositor->surface, compositor->width, compositor->height,
                compositor->swapchainBackend.modePolicy, compositor->swapchainBackend.imageOverride,
            };
            KineVulkanSwapchainResult native{};
            const auto status = static_cast<VkResult>(compositor->swapchainBackend.create(&dispatch, &native));
            if (status == VK_SUCCESS && native.swapchain) {
                compositor->swapchain = (VkSwapchainKHR)native.swapchain;
                extent = {native.width, native.height};
                chosenFormat = {static_cast<VkFormat>(native.format), static_cast<VkColorSpaceKHR>(native.colorSpace)};
                swapchainUsage = native.usage;
                presentMode = static_cast<VkPresentModeKHR>(native.presentMode);
                imageCount = native.requestedImages;
                compositor->nativeSwapchain = true;
                fprintf(stderr, "[Kine] Odin swapchain created\n");
                fprintf(stderr, "[Kine] selected Skia-compatible swapchain format=%u\n", native.format);
                fprintf(stderr, "[Kine] swapchain present mode=%s (images=%u)\n",
                    kine_vk_present_mode_name(presentMode), imageCount);
            } else {
                if (native.swapchain) {
                    compositor->swapchainBackend.destroy(compositor->device,
                        reinterpret_cast<void*>(destroy), native.swapchain);
                }
                kine_vk_set_error(compositor, "Odin Vulkan swapchain creation failed");
                return false;
            }
        } else {
            kine_vk_set_error(compositor, "Vulkan swapchain destruction unavailable");
            return false;
        }
    }

    if (!compositor->nativeSwapchain) {
        kine_vk_set_error(compositor, "Odin compositor swapchain backend unavailable");
        return false;
    }
    compositor->presentMode = presentMode;

    uint32_t swapchainImageCount = 0;
    if (vkGetSwapchainImagesKHR(
            compositor->device, compositor->swapchain, &swapchainImageCount, nullptr) != VK_SUCCESS ||
        swapchainImageCount == 0) {
        kine_vk_set_error(compositor, "vkGetSwapchainImagesKHR failed");
        return false;
    }

    compositor->swapchainImages.resize(swapchainImageCount);
    if (vkGetSwapchainImagesKHR(
            compositor->device,
            compositor->swapchain,
            &swapchainImageCount,
            compositor->swapchainImages.data()) != VK_SUCCESS) {
        kine_vk_set_error(compositor, "vkGetSwapchainImagesKHR images failed");
        return false;
    }

    VkSurfaceCapabilitiesKHR prefetchCapabilities{};
    compositor->minimumImageCount = UINT32_MAX;
    if (vkGetPhysicalDeviceSurfaceCapabilitiesKHR(compositor->physicalDevice,
            compositor->surface, &prefetchCapabilities) == VK_SUCCESS) {
        compositor->minimumImageCount = prefetchCapabilities.minImageCount;
    }
    compositor->swapchainFormat = chosenFormat.format;
    compositor->swapchainUsage = swapchainUsage;
    compositor->swapchainExtent = extent;
    compositor->width = extent.width;
    compositor->height = extent.height;
    compositor->swapchainImageLayouts.assign(
        compositor->swapchainImages.size(),
        VK_IMAGE_LAYOUT_UNDEFINED);


    compositor->renderFinishedSemaphores.assign(swapchainImageCount, VK_NULL_HANDLE);
    for (VkSemaphore& semaphore : compositor->renderFinishedSemaphores) {
        auto dispatch = kine_vk_frame_dispatch(compositor);
        uint64_t nativeSemaphore = 0;
        if (compositor->swapchainBackend.createSync(&dispatch, &nativeSemaphore, nullptr, nullptr) != VK_SUCCESS) {
            kine_vk_set_error(compositor, "Odin present synchronization allocation failed");
            return false;
        }
        semaphore = (VkSemaphore)nativeSemaphore;
    }

    compositor->acquireSlots.resize(swapchainImageCount + 1);
    compositor->nextAcquireSlot = 0;
    for (auto& sync : compositor->acquireSlots) {
        auto dispatch = kine_vk_frame_dispatch(compositor);
        uint64_t ready = 0, consumed = 0, prefetched = 0;
        if (compositor->swapchainBackend.createSync(&dispatch, &ready, &consumed, &prefetched) != VK_SUCCESS) {
            kine_vk_set_error(compositor, "Odin acquire synchronization allocation failed");
            return false;
        }
        sync.ready = (VkSemaphore)ready;
        sync.consumed = (VkFence)consumed;
        sync.prefetched = (VkFence)prefetched;
    }

    compositor->offscreen = compositor->swapchainBackend.offscreen &&
        (compositor->swapchainUsage & VK_IMAGE_USAGE_TRANSFER_DST_BIT);
    if (compositor->offscreen) {
        auto d = kine_vk_frame_dispatch(compositor);
        for (uint32_t i = 0; i < 3; ++i) {
            uint64_t image = 0, memory = 0;
            auto result = compositor->swapchainBackend.createColor(&d, compositor->instance,
                compositor->physicalDevice, reinterpret_cast<void*>(compositor->getInstanceProcAddr),
                compositor->width, compositor->height, uint32_t(compositor->swapchainFormat), &image, &memory);
            if (result != VK_SUCCESS) {
                for (size_t j = 0; j < compositor->renderImages.size(); ++j)
                    compositor->swapchainBackend.destroyColor(&d, (uint64_t)compositor->renderImages[j], (uint64_t)compositor->renderMemory[j]);
                compositor->renderImages.clear();
                compositor->renderMemory.clear();
                compositor->offscreen = false;
                if (result == VK_ERROR_DEVICE_LOST) {compositor->device_lost = true; return false;}
                fprintf(stderr, "[Kine] Odin offscreen allocation unavailable; using direct rendering\n");
                break;
            }
            compositor->renderImages.push_back((VkImage)image);
            compositor->renderMemory.push_back((VkDeviceMemory)memory);
        }
    }
    compositor->renderLayouts.assign(compositor->renderImages.size(), VK_IMAGE_LAYOUT_UNDEFINED);
    compositor->nextRenderImage = 0;
    if (compositor->offscreen) fprintf(stderr, "[Kine] Odin offscreen presentation active (3 render images)\n");
    if (!kine_vk_create_image_frames(compositor)) return false;
    auto getProperties = kine_vk_instance_proc<PFN_vkGetPhysicalDeviceProperties>(
        compositor, "vkGetPhysicalDeviceProperties");
    if (getProperties) {
        VkPhysicalDeviceProperties properties{};
        getProperties(compositor->physicalDevice, &properties);
        fprintf(stderr, "[Kine] active swapchain extent=%ux%u present=%s vendor=%04x device=%04x gpu=%s\n",
            extent.width, extent.height, kine_vk_present_mode_name(presentMode),
            properties.vendorID, properties.deviceID, properties.deviceName);
    }
    return true;
}

static bool kine_vk_finish_prefetch(KineVulkanCompositor* c)
{
    c->prefetchedImage = UINT32_MAX;
    c->prefetchedSlot = UINT32_MAX;
    if (c->device_lost) return false;
    auto wait = kine_vk_device_proc<PFN_vkWaitForFences>(c, "vkWaitForFences");
    if (!wait) return false;
    for (auto& frame : c->frames) {
        for (auto& slot : frame.slots) {
            if (!slot.lateAcquirePending) continue;
            auto status = wait(c->device, 1, &slot.lateAcquireFence, VK_TRUE, UINT64_MAX);
            if (status == VK_ERROR_DEVICE_LOST) c->device_lost = true;
            if (status != VK_SUCCESS) return false;
            slot.lateAcquirePending = false;
        }
    }
    for (auto& slot : c->acquireSlots) {
        if (!slot.prefetchPending) continue;
        const auto status = wait(c->device, 1, &slot.prefetched, VK_TRUE, UINT64_MAX);
        if (status == VK_ERROR_DEVICE_LOST) c->device_lost = true;
        if (status != VK_SUCCESS) return false;
        slot.prefetchPending = false;
    }
    return true;
}

static void kine_vk_prefetch_next(KineVulkanCompositor* c)
{
    if (c->offscreen || !c->prefetchEnabled || !c->wsiBackend.asynchronous || !c->gpuAcquire ||
        c->needsResize || c->prefetchedImage != UINT32_MAX ||
        c->swapchainImages.size() <= c->minimumImageCount || c->acquireSlots.empty()) return;

    auto getStatus = kine_vk_device_proc<PFN_vkGetFenceStatus>(c, "vkGetFenceStatus");
    auto reset = kine_vk_device_proc<PFN_vkResetFences>(c, "vkResetFences");
    if (!getStatus || !reset) {
        c->prefetchEnabled = false;
        return;
    }

    uint32_t selected = UINT32_MAX;
    for (uint32_t i = 0; i < c->acquireSlots.size(); ++i) {
        const uint32_t index = (c->nextAcquireSlot + i) % c->acquireSlots.size();
        auto& slot = c->acquireSlots[index];
        if (slot.inFlight && getStatus(c->device, slot.consumed) != VK_SUCCESS) continue;
        if (slot.prefetchPending && getStatus(c->device, slot.prefetched) != VK_SUCCESS) continue;
        if (reset(c->device, 1, &slot.consumed) != VK_SUCCESS ||
            reset(c->device, 1, &slot.prefetched) != VK_SUCCESS) {
            c->prefetchEnabled = false;
            return;
        }
        slot.inFlight = false;
        slot.prefetchPending = false;
        selected = index;
        break;
    }
    if (selected == UINT32_MAX) {
        ++c->prefetchMisses;
        return;
    }

    auto& slot = c->acquireSlots[selected];
    uint32_t image = UINT32_MAX;
    const auto status = kine_vk_profile_call(c, "Vulkan WSI Prefetch", [&] {
        return static_cast<VkResult>(c->wsiBackend.acquire(c->wsiBackend.user,
            (uint64_t)c->swapchain, 0, (uint64_t)slot.ready, (uint64_t)slot.prefetched, &image));
    });
    if (status == VK_SUCCESS || status == VK_SUBOPTIMAL_KHR) {
        slot.prefetchPending = true;
        c->prefetchedImage = image;
        c->prefetchedSlot = selected;
        c->nextAcquireSlot = (selected + 1) % c->acquireSlots.size();
        ++c->prefetchHits;
    } else {
        ++c->prefetchMisses;
        if (status == VK_ERROR_OUT_OF_DATE_KHR) c->needsResize = true;
        if (status == VK_ERROR_DEVICE_LOST) c->device_lost = true;
        if (status != VK_NOT_READY && status != VK_TIMEOUT &&
            status != VK_ERROR_OUT_OF_DATE_KHR) c->prefetchEnabled = false;
    }
}

static void kine_vk_destroy_swapchain_attachments(KineVulkanCompositor* compositor)
{
    if (!compositor || !compositor->device) {
        return;
    }

    auto vkDestroyFence = kine_vk_device_proc<PFN_vkDestroyFence>(compositor, "vkDestroyFence");
    auto vkFreeCommandBuffers = kine_vk_device_proc<PFN_vkFreeCommandBuffers>(
        compositor, "vkFreeCommandBuffers");
    auto destroyQueryPool = kine_vk_device_proc<PFN_vkDestroyQueryPool>(compositor,"vkDestroyQueryPool");
    for (auto& frame : compositor->frames) {
        kine_vk_release_frame_surfaces(compositor, frame);
        for (auto& slot : frame.slots) {
            if (compositor->swapchainBackend.destroyFrame) {
                auto dispatch = kine_vk_frame_dispatch(compositor);
                KineVulkanFrameResources resources{{slot.acquire, slot.handoff, slot.present, slot.overlayTiming, slot.renderComplete},
                    (uint64_t)slot.finished, (uint64_t)slot.timing};
                if (slot.lateAcquire) compositor->swapchainBackend.destroySync(&dispatch, (uint64_t)slot.lateAcquire, (uint64_t)slot.lateAcquireFence, 0);
                if (slot.copyReady) compositor->swapchainBackend.destroySync(&dispatch, (uint64_t)slot.copyReady, 0, 0);
                if (slot.copyReturned) compositor->swapchainBackend.destroySync(&dispatch, (uint64_t)slot.copyReturned, 0, 0);
                compositor->swapchainBackend.destroyFrame(&dispatch, &resources);
                slot = {};
                continue;
            }
            if (slot.timing && destroyQueryPool) destroyQueryPool(compositor->device,slot.timing,nullptr);
            slot.timing = VK_NULL_HANDLE;
            if (slot.finished && vkDestroyFence) {
                vkDestroyFence(compositor->device, slot.finished, nullptr);
                slot.finished = VK_NULL_HANDLE;
            }
            VkCommandBuffer buffers[3] = { slot.acquire, slot.handoff, slot.present };
            if (buffers[0] && vkFreeCommandBuffers) {
                vkFreeCommandBuffers(compositor->device, compositor->commandPool, 3, buffers);
            }
            if (slot.overlayTiming && vkFreeCommandBuffers)
                vkFreeCommandBuffers(compositor->device, compositor->commandPool, 1, &slot.overlayTiming);
            slot.overlayTiming = VK_NULL_HANDLE;
            slot.acquire = VK_NULL_HANDLE;
            slot.handoff = VK_NULL_HANDLE;
            slot.present = VK_NULL_HANDLE;
        }
    }
    compositor->frames.clear();
    compositor->activeSlot = nullptr;
    Kine_Skia_Vulkan_PurgeResources(compositor->skiaContext);

    if (compositor->swapchainBackend.destroyColor) {
        auto dispatch = kine_vk_frame_dispatch(compositor);
        for (size_t i = 0; i < compositor->renderImages.size(); ++i)
            compositor->swapchainBackend.destroyColor(&dispatch, (uint64_t)compositor->renderImages[i], (uint64_t)compositor->renderMemory[i]);
    }
    compositor->renderImages.clear();
    compositor->renderMemory.clear();
    compositor->renderLayouts.clear();
    compositor->offscreen = false;
    compositor->swapchainImages.clear();
    compositor->swapchainImageLayouts.clear();

    kine_vk_destroy_depth_attachment(compositor);

    if (!compositor->acquireSlots.empty()) {
        auto vkDestroySemaphore = kine_vk_device_proc<PFN_vkDestroySemaphore>(
            compositor, "vkDestroySemaphore");
        auto vkDestroyFence = kine_vk_device_proc<PFN_vkDestroyFence>(
            compositor, "vkDestroyFence");
        for (auto& sync : compositor->acquireSlots) {
            if (compositor->swapchainBackend.destroySync) {
                auto dispatch = kine_vk_frame_dispatch(compositor);
                compositor->swapchainBackend.destroySync(&dispatch, (uint64_t)sync.ready, (uint64_t)sync.consumed, (uint64_t)sync.prefetched);
                continue;
            }
            if (sync.ready && vkDestroySemaphore) {
                vkDestroySemaphore(compositor->device, sync.ready, nullptr);
            }
            if (sync.consumed && vkDestroyFence) {
                vkDestroyFence(compositor->device, sync.consumed, nullptr);
            }
            if (sync.prefetched && vkDestroyFence) {
                vkDestroyFence(compositor->device, sync.prefetched, nullptr);
            }
        }
        compositor->acquireSlots.clear();
        compositor->nextAcquireSlot = 0;
    }

    if (!compositor->renderFinishedSemaphores.empty()) {
        if (auto vkDestroySemaphore = kine_vk_device_proc<PFN_vkDestroySemaphore>(
                compositor, "vkDestroySemaphore")) {
            for (VkSemaphore semaphore : compositor->renderFinishedSemaphores) {
                if (semaphore) {
                    if (compositor->swapchainBackend.destroySync) {
                        auto dispatch = kine_vk_frame_dispatch(compositor);
                        compositor->swapchainBackend.destroySync(&dispatch, (uint64_t)semaphore, 0, 0);
                    } else vkDestroySemaphore(compositor->device, semaphore, nullptr);
                }
            }
        }
        compositor->renderFinishedSemaphores.clear();
    }

    if (compositor->swapchain) {
        if (auto vkDestroySwapchainKHR = kine_vk_device_proc<PFN_vkDestroySwapchainKHR>(
                compositor, "vkDestroySwapchainKHR")) {
            if (compositor->nativeSwapchain && compositor->swapchainBackend.destroy) {
                compositor->swapchainBackend.destroy(compositor->device,
                    reinterpret_cast<void*>(vkDestroySwapchainKHR), (uint64_t)compositor->swapchain);
            } else {
                vkDestroySwapchainKHR(compositor->device, compositor->swapchain, nullptr);
            }
        }
        compositor->swapchain = VK_NULL_HANDLE;
        compositor->nativeSwapchain = false;
    }
    compositor->swapchainFormat = VK_FORMAT_UNDEFINED;
    compositor->swapchainUsage = 0;
    compositor->swapchainExtent = {};
}

static bool kine_vk_transition_current_image(
    KineVulkanCompositor* compositor,
    VkCommandBuffer commandBuffer,
    VkImageLayout oldLayout,
    VkImageLayout newLayout,
    VkSemaphore waitSemaphore = VK_NULL_HANDLE,
    VkSemaphore signalSemaphore = VK_NULL_HANDLE,
    VkFence fence = VK_NULL_HANDLE)
{
    const bool timed = compositor->activeSlot && compositor->activeSlot->timing;
    if (oldLayout == newLayout && !timed) {


        if (fence != VK_NULL_HANDLE || signalSemaphore != VK_NULL_HANDLE || waitSemaphore != VK_NULL_HANDLE) {
            auto result = kine_vk_submit(compositor, VK_NULL_HANDLE, waitSemaphore, signalSemaphore, fence);
            if (result != VK_SUCCESS) {
                if (result == VK_ERROR_DEVICE_LOST) compositor->device_lost = true;
                kine_vk_set_error(compositor, "vkQueueSubmit failed");
                return false;
            }
        }
        return true;
    }

    auto vkResetCommandBuffer = kine_vk_device_proc<PFN_vkResetCommandBuffer>(
        compositor, "vkResetCommandBuffer");
    auto vkBeginCommandBuffer = kine_vk_device_proc<PFN_vkBeginCommandBuffer>(
        compositor, "vkBeginCommandBuffer");
    auto vkCmdPipelineBarrier = kine_vk_device_proc<PFN_vkCmdPipelineBarrier>(
        compositor, "vkCmdPipelineBarrier");
    auto vkEndCommandBuffer = kine_vk_device_proc<PFN_vkEndCommandBuffer>(
        compositor, "vkEndCommandBuffer");
    auto vkQueueSubmit = kine_vk_device_proc<PFN_vkQueueSubmit>(
        compositor, "vkQueueSubmit");
    if (!vkResetCommandBuffer || !vkBeginCommandBuffer || !vkCmdPipelineBarrier ||
        !vkEndCommandBuffer || !vkQueueSubmit ||
        !commandBuffer || compositor->currentImageIndex >= kine_vk_render_images(compositor).size()) {
        kine_vk_set_error(compositor, "required image-transition Vulkan procs unavailable");
        return false;
    }

    auto* slot = compositor->activeSlot;
    const bool isPresent = newLayout == VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
    const bool reusable = slot && (isPresent ?
        (commandBuffer == slot->present && oldLayout == VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL) :
        (commandBuffer == slot->acquire && newLayout == VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL));
    const bool recorded = reusable && (isPresent ? slot->presentRecorded : slot->acquireRecordedLayout == oldLayout);
    if (!recorded && compositor->swapchainBackend.recordTransition) {
        auto dispatch = kine_vk_frame_dispatch(compositor);
        KineVulkanTransition transition{commandBuffer,
            (uint64_t)kine_vk_render_images(compositor)[compositor->currentImageIndex],
            timed ? (uint64_t)slot->timing : 0, uint32_t(oldLayout), uint32_t(newLayout), uint32_t(reusable)};
        auto result = compositor->swapchainBackend.recordTransition(&dispatch, &transition);
        if (result != VK_SUCCESS) {
            if (result == VK_ERROR_DEVICE_LOST) compositor->device_lost = true;
            kine_vk_set_error(compositor, "Odin image transition recording failed");
            return false;
        }
        if (reusable) {
            if (isPresent) slot->presentRecorded = true;
            else slot->acquireRecordedLayout = oldLayout;
        }
    } else if (!recorded) {
        if (vkResetCommandBuffer(commandBuffer, 0) != VK_SUCCESS) {
            kine_vk_set_error(compositor, "vkResetCommandBuffer failed");
            return false;
        }

        VkCommandBufferBeginInfo beginInfo{};
        beginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
        beginInfo.flags = reusable ? 0 : VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
        if (vkBeginCommandBuffer(commandBuffer, &beginInfo) != VK_SUCCESS) {
            kine_vk_set_error(compositor, "vkBeginCommandBuffer failed");
            return false;
        }

        VkImageMemoryBarrier barrier{};
        barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
        barrier.oldLayout = oldLayout;
        barrier.newLayout = newLayout;
        barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        barrier.image = kine_vk_render_images(compositor)[compositor->currentImageIndex];
        barrier.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
        barrier.subresourceRange.baseMipLevel = 0;
        barrier.subresourceRange.levelCount = 1;
        barrier.subresourceRange.baseArrayLayer = 0;
        barrier.subresourceRange.layerCount = 1;

        VkPipelineStageFlags srcStage = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
        VkPipelineStageFlags dstStage = VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT;

        if (oldLayout == VK_IMAGE_LAYOUT_UNDEFINED) {
            barrier.srcAccessMask = 0;
            srcStage = VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
        } else if (oldLayout == VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL) {


            barrier.srcAccessMask =
                VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT | VK_ACCESS_TRANSFER_READ_BIT;
            srcStage =
                VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT | VK_PIPELINE_STAGE_TRANSFER_BIT;
        } else if (oldLayout == VK_IMAGE_LAYOUT_PRESENT_SRC_KHR) {
            barrier.srcAccessMask = 0;
            srcStage = VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT;
        }

        if (newLayout == VK_IMAGE_LAYOUT_PRESENT_SRC_KHR) {
            barrier.dstAccessMask = 0;
            dstStage = VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT;
        } else if (newLayout == VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL) {
            barrier.dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_READ_BIT | VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
            dstStage = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
        }

        if (oldLayout != newLayout) vkCmdPipelineBarrier(
            commandBuffer,
            srcStage,
            dstStage,
            0,
            0,
            nullptr,
            0,
            nullptr,
            1,
            &barrier);

        if (timed) {
            auto writeTimestamp = kine_vk_device_proc<PFN_vkCmdWriteTimestamp>(compositor,"vkCmdWriteTimestamp");
            auto resetQueries = kine_vk_device_proc<PFN_vkCmdResetQueryPool>(compositor,"vkCmdResetQueryPool");
            auto pool = compositor->activeSlot->timing;
            if (writeTimestamp && resetQueries) {
                if (newLayout == VK_IMAGE_LAYOUT_PRESENT_SRC_KHR) {
                    writeTimestamp(commandBuffer,VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT,pool,1);
                } else {
                    resetQueries(commandBuffer,pool,0,4);
                    writeTimestamp(commandBuffer,VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT,pool,0);
                }
            }
        }

        if (vkEndCommandBuffer(commandBuffer) != VK_SUCCESS) {
            kine_vk_set_error(compositor, "vkEndCommandBuffer failed");
            return false;
        }

        if (reusable) {
            if (isPresent) slot->presentRecorded = true;
            else slot->acquireRecordedLayout = oldLayout;
        }
    }

    VkResult submit_result = kine_vk_submit(compositor, commandBuffer, waitSemaphore, signalSemaphore, fence);
    if (submit_result != VK_SUCCESS) {
        if (submit_result == VK_ERROR_DEVICE_LOST) {
            compositor->device_lost = true;
            kine_vk_set_error(compositor, "vkQueueSubmit failed: device lost");
        } else {
            kine_vk_set_error(compositor, "vkQueueSubmit failed");
        }
        return false;
    }

    kine_vk_render_layouts(compositor)[compositor->currentImageIndex] = newLayout;
    return true;
}

static bool kine_vk_wait_for_filament(
    KineVulkanCompositor* compositor,
    VkSemaphore semaphore)
{
    if (!compositor || !semaphore) {
        return true;
    }


    auto* slot = compositor->activeSlot;
    const auto result = kine_vk_submit(compositor, slot ? slot->overlayTiming : VK_NULL_HANDLE, semaphore, VK_NULL_HANDLE, VK_NULL_HANDLE);
    if (result != VK_SUCCESS) {
        if (result == VK_ERROR_DEVICE_LOST) compositor->device_lost = true;
        kine_vk_set_error(compositor,
            "failed submitting Filament-to-overlay synchronization");
        return false;
    }
    if (slot && slot->overlayTiming) slot->timingOverlay = true;
    return true;
}

static bool kine_vk_record_skia_handoff(KineVulkanCompositor* compositor, VkCommandBuffer command, VkQueryPool timing)
{
    auto begin = kine_vk_device_proc<PFN_vkBeginCommandBuffer>(compositor, "vkBeginCommandBuffer");
    auto barrier = kine_vk_device_proc<PFN_vkCmdPipelineBarrier>(compositor, "vkCmdPipelineBarrier");
    auto end = kine_vk_device_proc<PFN_vkEndCommandBuffer>(compositor, "vkEndCommandBuffer");
    if (!begin || !barrier || !end) return false;
    VkCommandBufferBeginInfo beginInfo{};
    beginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;

    if (begin(command, &beginInfo) != VK_SUCCESS) return false;
    VkMemoryBarrier memory{};
    memory.sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER;
    memory.srcAccessMask = VK_ACCESS_MEMORY_READ_BIT | VK_ACCESS_MEMORY_WRITE_BIT;
    memory.dstAccessMask = VK_ACCESS_MEMORY_READ_BIT | VK_ACCESS_MEMORY_WRITE_BIT;
    barrier(command, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT,
        0, 1, &memory, 0, nullptr, 0, nullptr);
    if (timing) {
        auto timestamp = kine_vk_device_proc<PFN_vkCmdWriteTimestamp>(compositor, "vkCmdWriteTimestamp");
        if (!timestamp) return false;
        timestamp(command, VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, timing, 2);
    }
    return end(command) == VK_SUCCESS;
}

static bool kine_vk_submit_skia_handoff(KineVulkanCompositor* compositor, VkCommandBuffer command)
{
    const auto result = kine_vk_submit(compositor, command, VK_NULL_HANDLE, VK_NULL_HANDLE, VK_NULL_HANDLE);
    if (result == VK_ERROR_DEVICE_LOST) compositor->device_lost = true;
    return result == VK_SUCCESS;
}

static KineSkiaSurface* kine_vk_create_current_skia_surface(KineVulkanCompositor* compositor)
{
    if (!compositor || !compositor->skiaContext ||
        compositor->currentImageIndex >= kine_vk_render_images(compositor).size()) {
        return nullptr;
    }

    if (compositor->swapchainBackend.wrapSurface) {
        return static_cast<KineSkiaSurface*>(compositor->swapchainBackend.wrapSurface(
            compositor->skiaContext, kine_vk_render_images(compositor)[compositor->currentImageIndex],
            compositor->width, compositor->height, uint32_t(compositor->swapchainFormat), kine_vk_render_usage(compositor)));
    }
    KineSkiaVulkanImageInfo imageInfo{};
    imageInfo.image = kine_vk_render_images(compositor)[compositor->currentImageIndex];
    imageInfo.format = compositor->swapchainFormat;
    imageInfo.imageLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
    imageInfo.imageTiling = VK_IMAGE_TILING_OPTIMAL;
    imageInfo.imageUsageFlags = kine_vk_render_usage(compositor);
    imageInfo.sampleCount = 1;
    imageInfo.levelCount = 1;
    imageInfo.currentQueueFamily = VK_QUEUE_FAMILY_IGNORED;

    return Kine_Skia_Surface_CreateVulkanRenderTarget(
        compositor->skiaContext,
        static_cast<int>(compositor->width),
        static_cast<int>(compositor->height),
        &imageInfo);
}

extern "C" {

KINE_VULKAN_COMPOSITOR_API void Kine_VulkanCompositor_SetPresentQueue(KineVulkanCompositor* c, void* queue)
{
    if (!c || kine_vk_frame_active(c) || !queue || c->wsiBackend.present) return;
    c->presentQueue = reinterpret_cast<VkQueue>(queue);
    if (c->presentQueue != c->graphicsQueue) {
        fprintf(stderr,"[Kine] dedicated Vulkan presentation queue enabled\n");
    }
}

KINE_VULKAN_COMPOSITOR_API void Kine_VulkanCompositor_EnableCopyQueue(KineVulkanCompositor* c, uint32_t family)
{
    if (!c || kine_vk_frame_active(c) || c->wsiBackend.present) return;
    c->sameFamilyCopyQueue = c->presentQueue && c->presentQueue != c->graphicsQueue && family == c->graphicsQueueFamilyIndex;
}

KINE_VULKAN_COMPOSITOR_API int Kine_VulkanCompositor_IsOffscreen(const KineVulkanCompositor* c) { return c && c->offscreen; }

KINE_VULKAN_COMPOSITOR_API int Kine_VulkanCompositor_GetWsiDispatch(
    KineVulkanCompositor* c, KineVulkanWsiDispatch* out)
{
    if (!c || !out || !c->device || kine_vk_frame_active(c)) return 0;
    const auto acquire = kine_vk_device_proc<PFN_vkAcquireNextImageKHR>(c, "vkAcquireNextImageKHR");
    const auto present = kine_vk_device_proc<PFN_vkQueuePresentKHR>(c, "vkQueuePresentKHR");
    if (!acquire || !present) return 0;
    const auto queue = c->presentQueue ? c->presentQueue : c->graphicsQueue;
    if (!queue) return 0;
    *out = {c->device, queue, reinterpret_cast<void*>(acquire),
        reinterpret_cast<void*>(present), uint32_t(queue != c->graphicsQueue)};
    return 1;
}

KINE_VULKAN_COMPOSITOR_API int Kine_VulkanCompositor_SetWsiBackend(
    KineVulkanCompositor* c, const KineVulkanWsiBackend* backend)
{
    if (!c) return 0;
    if (!backend) {
        if (c->wsiBackend.drain) kine_vk_drain_present(c);
        c->prefetchEnabled = false;
        c->wsiBackend = {};
        return 1;
    }
    if (kine_vk_frame_active(c) || c->wsiBackend.present ||
        !backend->acquire || !backend->present || !backend->drain ||
        (backend->asynchronous && (!c->presentQueue || c->presentQueue == c->graphicsQueue))) return 0;
    c->wsiBackend = *backend;
    c->prefetchEnabled = !c->offscreen && backend->asynchronous && c->gpuAcquire;
    if (c->prefetchEnabled) fprintf(stderr, "[Kine] Odin WSI pre-acquisition enabled\n");
    if (c->offscreen && c->sameFamilyCopyQueue && backend->asynchronous)
        fprintf(stderr, "[Kine] Odin offscreen separate final-copy queue enabled\n");
    return 1;
}

KINE_VULKAN_COMPOSITOR_API void Kine_VulkanCompositor_GetPrefetchStats(
    const KineVulkanCompositor* c, uint64_t* hits, uint64_t* misses)
{
    if (hits) *hits = c ? c->prefetchHits : 0;
    if (misses) *misses = c ? c->prefetchMisses : 0;
}

KINE_VULKAN_COMPOSITOR_API uint64_t Kine_VulkanCompositor_GetPresentWaitNs(const KineVulkanCompositor* c)
{
    return c ? c->presentWaitNs : 0;
}

KINE_VULKAN_COMPOSITOR_API uint32_t
Kine_VulkanCompositor_GetSDLWindowId(const KineVulkanCompositor* compositor)
{
    return compositor ? compositor->windowId : 0;
}

KINE_VULKAN_COMPOSITOR_API KineVulkanCompositor*
Kine_VulkanCompositor_CreateForSDLWindow(void* sdlWindow, int width, int height)
{
    if (!sdlWindow || width <= 0 || height <= 0) {
        return nullptr;
    }

    auto* compositor = new KineVulkanCompositor();
    compositor->windowId = SDL_GetWindowID(static_cast<SDL_Window*>(sdlWindow));
    compositor->swapchainBackend = kine_vk_window_swapchain_backend(compositor->windowId);
    if (!compositor->swapchainBackend.createProvider) {delete compositor; return nullptr;}
    compositor->nativeProvider = compositor->swapchainBackend.createProvider();
    if (!compositor->nativeProvider) {delete compositor; return nullptr;}
    compositor->width = static_cast<uint32_t>(width);
    compositor->height = static_cast<uint32_t>(height);
    compositor->ownsInstance = true;
    compositor->ownsDevice = true;

    if (!kine_vk_create_instance(compositor) ||
        !kine_vk_create_surface(compositor, sdlWindow) ||
        !kine_vk_pick_device(compositor) ||
        !kine_vk_create_device(compositor) ||
        !kine_vk_create_frame_resources(compositor) ||
        !kine_vk_create_swapchain(compositor)) {
        return compositor;
    }

    if (!kine_vk_create_depth_attachment(compositor)) {
        fprintf(stderr, "kine_vulkan_compositor: depth attachment unavailable, continuing without swapchain depth: %s\n",
            compositor->lastError.c_str());
        kine_vk_destroy_depth_attachment(compositor);
        if (compositor->device_lost) return compositor;
        compositor->lastError.clear();
    }

    if (!kine_vk_create_skia_context(compositor)) {
        return compositor;
    }

    compositor->lastError.clear();
    return compositor;
}

KINE_VULKAN_COMPOSITOR_API KineVulkanCompositor*
Kine_VulkanCompositor_CreateForSDLWindowWithBackend(
    void* sdlWindow,
    int width,
    int height,
    const KineVulkanCompositorBackend* backend)
{
    if (!sdlWindow || width <= 0 || height <= 0 || !backend ||
        !backend->instance || !backend->physicalDevice || !backend->device ||
        !backend->queue || !backend->getInstanceProcAddr) {
        return nullptr;
    }

    auto* compositor = new KineVulkanCompositor();
    compositor->windowId = SDL_GetWindowID(static_cast<SDL_Window*>(sdlWindow));
    compositor->swapchainBackend = kine_vk_window_swapchain_backend(compositor->windowId);
    if (!compositor->swapchainBackend.createProvider) {delete compositor; return nullptr;}
    compositor->nativeProvider = compositor->swapchainBackend.createProvider();
    if (!compositor->nativeProvider) {delete compositor; return nullptr;}
    compositor->width = static_cast<uint32_t>(width);
    compositor->height = static_cast<uint32_t>(height);
    compositor->ownsInstance = false;
    compositor->ownsDevice = false;
    compositor->getInstanceProcAddr =
        reinterpret_cast<PFN_vkGetInstanceProcAddr>(backend->getInstanceProcAddr);
    compositor->getDeviceProcAddr =
        reinterpret_cast<PFN_vkGetDeviceProcAddr>(backend->getDeviceProcAddr);
    compositor->instance = reinterpret_cast<VkInstance>(backend->instance);
    compositor->physicalDevice = reinterpret_cast<VkPhysicalDevice>(backend->physicalDevice);
    compositor->device = reinterpret_cast<VkDevice>(backend->device);
    compositor->graphicsQueue = reinterpret_cast<VkQueue>(backend->queue);
    compositor->graphicsQueueFamilyIndex = backend->graphicsQueueFamilyIndex;
    compositor->graphicsQueueCount = 1;
    compositor->apiVersion = backend->maxApiVersion != 0
        ? backend->maxApiVersion
        : VK_API_VERSION_1_0;

    if (!compositor->getDeviceProcAddr) {
        compositor->getDeviceProcAddr = reinterpret_cast<PFN_vkGetDeviceProcAddr>(
            compositor->getInstanceProcAddr(compositor->instance, "vkGetDeviceProcAddr"));
    }
    if (!compositor->getDeviceProcAddr) {
        kine_vk_set_error(compositor, "vkGetDeviceProcAddr unavailable for external Vulkan device");
        return compositor;
    }

    if (!kine_vk_create_surface(compositor, sdlWindow) ||
        !kine_vk_validate_present_queue(compositor) ||
        !kine_vk_create_frame_resources(compositor) ||
        !kine_vk_create_swapchain(compositor)) {
        return compositor;
    }

    if (!kine_vk_create_depth_attachment(compositor)) {
        fprintf(stderr, "kine_vulkan_compositor: depth attachment unavailable, continuing without swapchain depth: %s\n",
            compositor->lastError.c_str());
        kine_vk_destroy_depth_attachment(compositor);
        if (compositor->device_lost) return compositor;
        compositor->lastError.clear();
    }

    if (!kine_vk_create_skia_context(compositor)) {
        return compositor;
    }

    compositor->lastError.clear();
    return compositor;
}

KINE_VULKAN_COMPOSITOR_API void
Kine_VulkanCompositor_Destroy(KineVulkanCompositor* compositor)
{
    if (!compositor) {
        return;
    }

    if (compositor->wsiBackend.drain) kine_vk_drain_present(compositor);
    if (compositor->prefetchHits || compositor->prefetchMisses) {
        fprintf(stderr, "[Kine] Odin WSI pre-acquisition hits=%llu misses=%llu\n",
            (unsigned long long)compositor->prefetchHits, (unsigned long long)compositor->prefetchMisses);
    }
    if (compositor->device) kine_vk_finish_prefetch(compositor);
    if (compositor->device) {
        if (auto vkDeviceWaitIdle = kine_vk_device_proc<PFN_vkDeviceWaitIdle>(compositor, "vkDeviceWaitIdle")) {
            vkDeviceWaitIdle(compositor->device);
        }
    }


    compositor->currentSkiaSurface = nullptr;
    compositor->overlaySkiaSurface = nullptr;

    if (compositor->device) {
        if (compositor->terrainMc) {
            Kine_TerrainMc_Destroy(compositor->terrainMc);
            compositor->terrainMc = nullptr;
        }
        if (compositor->acquireFence && !compositor->swapchainBackend.destroyRoot) {
            if (auto vkDestroyFence = kine_vk_device_proc<PFN_vkDestroyFence>(
                    compositor, "vkDestroyFence")) {
                vkDestroyFence(compositor->device, compositor->acquireFence, nullptr);
            }
            compositor->acquireFence = VK_NULL_HANDLE;
        }
        for (auto& frame : compositor->frames) {
            kine_vk_release_frame_surfaces(compositor, frame);
        }
        if (compositor->skiaContext) {
            Kine_Skia_Vulkan_DestroyContext(compositor->skiaContext);
            compositor->skiaContext = nullptr;
        }
        kine_vk_destroy_swapchain_attachments(compositor);
        if (compositor->swapchainBackend.destroyRoot) {
            auto dispatch = kine_vk_frame_dispatch(compositor);
            compositor->swapchainBackend.destroyRoot(&dispatch, (uint64_t)compositor->commandPool, (uint64_t)compositor->acquireFence);
            compositor->commandPool = VK_NULL_HANDLE;
            compositor->acquireFence = VK_NULL_HANDLE;
        }
        if (compositor->commandPool) {
            if (auto vkDestroyCommandPool = kine_vk_device_proc<PFN_vkDestroyCommandPool>(
                    compositor, "vkDestroyCommandPool")) {
                vkDestroyCommandPool(compositor->device, compositor->commandPool, nullptr);
            }
            compositor->commandPool = VK_NULL_HANDLE;
        }
        if (compositor->ownsDevice) {
            if (compositor->swapchainBackend.destroyDevice) {
                auto d = kine_vk_frame_dispatch(compositor);
                compositor->swapchainBackend.destroyDevice(&d);
            } else if (auto vkDestroyDevice = kine_vk_device_proc<PFN_vkDestroyDevice>(compositor, "vkDestroyDevice")) {
                vkDestroyDevice(compositor->device, nullptr);
            }
        }
        compositor->device = VK_NULL_HANDLE;
    }

    if (compositor->surface && compositor->instance) {
        if (compositor->swapchainBackend.destroySurface) {
            compositor->swapchainBackend.destroySurface(compositor->instance, (uint64_t)compositor->surface);
        } else if (auto vkDestroySurfaceKHR = kine_vk_instance_proc<PFN_vkDestroySurfaceKHR>(
                compositor, "vkDestroySurfaceKHR")) {
            vkDestroySurfaceKHR(compositor->instance, compositor->surface, nullptr);
        }
        compositor->surface = VK_NULL_HANDLE;
    }

    if (compositor->instance && compositor->ownsInstance) {
        if (compositor->swapchainBackend.destroyInstance) {
            compositor->swapchainBackend.destroyInstance(compositor->instance, reinterpret_cast<void*>(compositor->getInstanceProcAddr));
        } else if (auto vkDestroyInstance = kine_vk_instance_proc<PFN_vkDestroyInstance>(
                compositor, "vkDestroyInstance")) {
            vkDestroyInstance(compositor->instance, nullptr);
        }
    }
    compositor->instance = VK_NULL_HANDLE;

    if (compositor->nativeProvider) compositor->swapchainBackend.destroyProvider(compositor->nativeProvider);
    delete compositor;
}

KINE_VULKAN_COMPOSITOR_API int
Kine_VulkanCompositor_Resize(
    KineVulkanCompositor* compositor,
    int width,
    int height)
{
    if (!compositor || !compositor->device || compositor->device_lost || width <= 0 || height <= 0) {
        return 0;
    }
    if (!kine_vk_drain_present(compositor)) return 0;
    if (compositor->width == static_cast<uint32_t>(width) &&
        compositor->height == static_cast<uint32_t>(height) &&
        compositor->swapchain && !compositor->needsResize) {
        return 1;
    }

    compositor->needsResize = true;
    if (!kine_vk_finish_prefetch(compositor)) {
        kine_vk_set_error(compositor, "failed waiting for prefetched image during resize");
        return 0;
    }
    compositor->overlapPresent = false;
    auto vkDeviceWaitIdle = kine_vk_device_proc<PFN_vkDeviceWaitIdle>(
        compositor, "vkDeviceWaitIdle");
    const auto idle = vkDeviceWaitIdle ? vkDeviceWaitIdle(compositor->device) : VK_ERROR_INITIALIZATION_FAILED;
    if (idle != VK_SUCCESS) {
        if (idle == VK_ERROR_DEVICE_LOST) compositor->device_lost = true;
        kine_vk_set_error(compositor, "vkDeviceWaitIdle failed during compositor resize");
        return 0;
    }


    compositor->currentSkiaSurface = nullptr;
    compositor->overlaySkiaSurface = nullptr;
    kine_vk_provider_action(compositor, KINE_PROVIDER_RESET);
    compositor->currentImageIndex = UINT32_MAX;
    kine_vk_destroy_swapchain_attachments(compositor);

    compositor->width = static_cast<uint32_t>(width);
    compositor->height = static_cast<uint32_t>(height);
    if (!kine_vk_create_swapchain(compositor)) {
        kine_vk_destroy_swapchain_attachments(compositor);
        return 0;
    }
    if (!kine_vk_create_depth_attachment(compositor)) {
        fprintf(stderr,
            "kine_vulkan_compositor: depth attachment unavailable after resize: %s\n",
            compositor->lastError.c_str());
        kine_vk_destroy_depth_attachment(compositor);
    }

    compositor->needsResize = false;
    compositor->lastError.clear();
    return 1;
}

KINE_VULKAN_COMPOSITOR_API int
Kine_VulkanCompositor_IsReady(const KineVulkanCompositor* compositor)
{
    return compositor && !compositor->device_lost && compositor->instance && compositor->surface &&
        compositor->physicalDevice && compositor->device &&
        compositor->graphicsQueue && compositor->swapchain &&
        !compositor->swapchainImages.empty() && compositor->commandPool &&
        compositor->frames.size() == kine_vk_render_images(compositor).size() &&
        compositor->acquireFence && compositor->skiaContext &&
        compositor->lastError.empty();
}

KINE_VULKAN_COMPOSITOR_API int
Kine_VulkanCompositor_UsesOdinBackend(const KineVulkanCompositor* compositor)
{
    return compositor && compositor->nativeSwapchain && compositor->nativeProvider &&
        compositor->swapchainBackend.frameFlow ? 1 : 0;
}

KINE_VULKAN_COMPOSITOR_API int
Kine_VulkanCompositor_IsDeviceLost(const KineVulkanCompositor* compositor)
{
    return compositor && compositor->device_lost;
}

KINE_VULKAN_COMPOSITOR_API int
Kine_VulkanCompositor_NeedsResize(const KineVulkanCompositor* compositor)
{
    return compositor && compositor->needsResize;
}

KINE_VULKAN_COMPOSITOR_API const char*
Kine_VulkanCompositor_GetLastError(const KineVulkanCompositor* compositor)
{
    if (!compositor) {
        return "null compositor";
    }
    return compositor->lastError.c_str();
}

KINE_VULKAN_COMPOSITOR_API int
Kine_VulkanCompositor_GetInfo(
    const KineVulkanCompositor* compositor,
    KineVulkanCompositorInfo* outInfo)
{
    if (!compositor || !outInfo) {
        return 0;
    }

    std::memset(outInfo, 0, sizeof(*outInfo));
    outInfo->instance = compositor->instance;
    outInfo->surface = compositor->surface;
    outInfo->physicalDevice = compositor->physicalDevice;
    outInfo->device = compositor->device;
    outInfo->graphicsQueue = compositor->graphicsQueue;
    outInfo->swapchain = compositor->swapchain;
    outInfo->swapchainFormat = static_cast<uint32_t>(compositor->swapchainFormat);
    outInfo->swapchainImageCount = static_cast<uint32_t>(compositor->swapchainImages.size());
    outInfo->graphicsQueueFamilyIndex = compositor->graphicsQueueFamilyIndex;
    outInfo->graphicsQueueCount = compositor->graphicsQueueCount;
    outInfo->width = compositor->width;
    outInfo->height = compositor->height;
    return 1;
}

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
    uint32_t* outIndexCount)
{
    if (!compositor || !compositor->device || !compositor->graphicsQueue) {
        return 0;
    }

    if (!compositor->terrainMc) {
        char err[256] = {0};
        compositor->terrainMc = Kine_TerrainMc_Create(
            compositor->instance,
            compositor->physicalDevice,
            compositor->device,
            compositor->graphicsQueue,
            compositor->graphicsQueueFamilyIndex,
            err,
            sizeof(err));
        if (!compositor->terrainMc) {
            compositor->lastError = err[0] ? err : "terrain mesher creation failed";
            return 0;
        }
    }

    char err[256] = {0};
    int ok = Kine_TerrainMc_Mesh(
        compositor->terrainMc,
        occ,
        mat,
        originX,
        originY,
        originZ,
        voxelSize,
        isoLevel,
        outVertices,
        outWeights,
        outIndices,
        vertexCapacity,
        indexCapacity,
        outVertexCount,
        outIndexCount,
        err,
        sizeof(err));
    if (!ok) {
        compositor->lastError = err[0] ? err : "terrain mesh failed";
    }
    return ok;
}

KINE_VULKAN_COMPOSITOR_API void*
Kine_VulkanCompositor_GetSkiaContext(KineVulkanCompositor* compositor)
{
    return compositor ? compositor->skiaContext : nullptr;
}

KINE_VULKAN_COMPOSITOR_API void*
Kine_VulkanCompositor_GetCurrentSkiaSurface(KineVulkanCompositor* compositor)
{
    return compositor ? compositor->currentSkiaSurface : nullptr;
}

KINE_VULKAN_COMPOSITOR_API int
Kine_VulkanCompositor_GetXRPanelSource(KineVulkanCompositor* compositor, void** image,
    uint32_t* width, uint32_t* height, uint32_t* format)
{
    if (!compositor || !image || !width || !height || !format) return 0;
    if (!kine_vk_provider_action(compositor, KINE_PROVIDER_XR_READY) ||
        compositor->currentImageIndex >= kine_vk_render_images(compositor).size() ||
        !(kine_vk_render_usage(compositor) & VK_IMAGE_USAGE_TRANSFER_SRC_BIT)) return 0;
    auto* surface = compositor->overlaySkiaSurface ?
        compositor->overlaySkiaSurface : compositor->currentSkiaSurface;
    if (!surface) return 0;
    if (!kine_vk_flush_surface(compositor,surface)) return 0;
    *image = kine_vk_render_images(compositor)[compositor->currentImageIndex];
    *width = compositor->width;
    *height = compositor->height;
    *format = static_cast<uint32_t>(compositor->swapchainFormat);
    return 1;
}

KINE_VULKAN_COMPOSITOR_API uint32_t
Kine_VulkanCompositor_GetSwapchainImages(
    KineVulkanCompositor* compositor,
    void** outImages,
    uint32_t maxImages)
{
    if (!compositor) {
        return 0;
    }

    uint32_t count = static_cast<uint32_t>(kine_vk_render_images(compositor).size());
    if (outImages && maxImages > 0) {
        uint32_t n = std::min(count, maxImages);
        for (uint32_t i = 0; i < n; ++i) {
            outImages[i] = kine_vk_render_images(compositor)[i];
        }
    }
    return count;
}

KINE_VULKAN_COMPOSITOR_API uint32_t
Kine_VulkanCompositor_GetDepthAttachment(
    KineVulkanCompositor* compositor,
    void** outImage,
    uint32_t* outFormat)
{
    if (outImage) {
        *outImage = nullptr;
    }
    if (outFormat) {
        *outFormat = 0;
    }
    if (!compositor || !compositor->depthImage || compositor->depthFormat == VK_FORMAT_UNDEFINED) {
        return 0;
    }
    if (outImage) {
        *outImage = compositor->depthImage;
    }
    if (outFormat) {
        *outFormat = static_cast<uint32_t>(compositor->depthFormat);
    }
    return 1;
}

KINE_VULKAN_COMPOSITOR_API int
Kine_VulkanCompositor_WaitForQueueIdle(KineVulkanCompositor* compositor)
{
    if (!compositor) {
        return 0;
    }
    if (!kine_vk_drain_present(compositor)) return 0;
    auto vkQueueWaitIdle = kine_vk_device_proc<PFN_vkQueueWaitIdle>(
        compositor, "vkQueueWaitIdle");
    return vkQueueWaitIdle && vkQueueWaitIdle(compositor->graphicsQueue) == VK_SUCCESS &&
        (!compositor->presentQueue || compositor->presentQueue == compositor->graphicsQueue || vkQueueWaitIdle(compositor->presentQueue) == VK_SUCCESS);
}

KINE_VULKAN_COMPOSITOR_API int
Kine_VulkanCompositor_PrepareFilament(KineVulkanCompositor* compositor)
{
    if (!compositor) {
        return 0;
    }
    const auto preparation = kine_vk_provider_action(compositor, KINE_PROVIDER_CHECK_PREPARE);
    if (!preparation || compositor->currentImageIndex >= kine_vk_render_images(compositor).size()) {
        kine_vk_set_error(compositor, "Filament preparation requires an active compositor frame");
        return 0;
    }
    if (preparation == 2) return 1;


    if (compositor->currentSkiaSurface) {
        if (!kine_vk_profile_call(compositor,"Vulkan Skia Flush",[&] {
                return kine_vk_flush_surface(compositor,compositor->currentSkiaSurface);
            })) {
            kine_vk_set_error(compositor,"failed restoring Skia base image layout");
            return 0;
        }
        if (!compositor->activeSlot ||
            !kine_vk_profile_call(compositor, "Vulkan Skia Handoff Submit", [&] { return kine_vk_submit_skia_handoff(compositor, compositor->activeSlot->handoff); })) {
            kine_vk_set_error(compositor, "failed submitting Skia-to-Filament synchronization");
            return 0;
        }
        compositor->activeSlot->timingHandoff = true;


        compositor->currentSkiaSurface = nullptr;
    }


    if (!kine_vk_provider_action(compositor, KINE_PROVIDER_PREPARE)) return 0;
    compositor->lastError.clear();
    return 1;
}

KINE_VULKAN_COMPOSITOR_API uint32_t
Kine_VulkanCompositor_FilamentAcquire(
    KineVulkanCompositor* compositor,
    uint32_t* outImageIndex,
    void** outImageReadySemaphore)
{
    if (outImageReadySemaphore) {
        *outImageReadySemaphore = nullptr;
    }
    if (!compositor) {
        return VK_ERROR_INITIALIZATION_FAILED;
    }

    return kine_vk_provider_action(compositor, KINE_PROVIDER_ACQUIRE, UINT32_MAX,
        VK_NULL_HANDLE, outImageIndex) ? VK_SUCCESS : VK_ERROR_OUT_OF_DATE_KHR;
}

KINE_VULKAN_COMPOSITOR_API uint32_t
Kine_VulkanCompositor_FilamentPresent(
    KineVulkanCompositor* compositor,
    uint32_t imageIndex,
    void* finishedDrawingSemaphore)
{
    if (!compositor) {
        return VK_ERROR_INITIALIZATION_FAILED;
    }

    return kine_vk_provider_action(compositor, KINE_PROVIDER_PRESENT, imageIndex,
        reinterpret_cast<VkSemaphore>(finishedDrawingSemaphore)) ? VK_SUCCESS : VK_ERROR_OUT_OF_DATE_KHR;
}

struct KineFrameFlow {
    KineVulkanCompositor* compositor;
    KineVulkanAcquireSlot* acquireSlot = nullptr;
    VkSemaphore filamentFinished = VK_NULL_HANDLE;
    VkSemaphore renderFinished = VK_NULL_HANDLE;
    uint32_t presentImage = UINT32_MAX;
};

static int32_t kine_vk_end_step(KineFrameFlow& flow, uint32_t step);

static int32_t kine_vk_begin_acquire(KineFrameFlow& flow)
{
    auto* compositor = flow.compositor;
    const bool prefetched = compositor->prefetchedImage != UINT32_MAX;
    compositor->overlapPresent = prefetched && compositor->wsiBackend.asynchronous;
    compositor->presentWaitNs = 0;
    if ((!compositor->offscreen && !compositor->overlapPresent && !kine_vk_drain_present(compositor)) ||
        compositor->needsResize) return 0;

    auto vkAcquireNextImageKHR = compositor->wsiBackend.acquire ? nullptr :
        kine_vk_device_proc<PFN_vkAcquireNextImageKHR>(compositor, "vkAcquireNextImageKHR");
    auto vkWaitForFences = kine_vk_device_proc<PFN_vkWaitForFences>(
        compositor, "vkWaitForFences");
    auto vkResetFences = kine_vk_device_proc<PFN_vkResetFences>(
        compositor, "vkResetFences");
    auto vkGetFenceStatus = kine_vk_device_proc<PFN_vkGetFenceStatus>(
        compositor, "vkGetFenceStatus");
    if ((!compositor->wsiBackend.acquire && !vkAcquireNextImageKHR) || !vkWaitForFences || !vkResetFences || !vkGetFenceStatus) {
        kine_vk_set_error(compositor, "required acquire Vulkan procs unavailable");
        return 0;
    }


    auto*& acquireSlot = flow.acquireSlot;
    if (!compositor->offscreen && !prefetched && compositor->gpuAcquire && !compositor->acquireSlots.empty()) {
        acquireSlot = &compositor->acquireSlots[
            compositor->nextAcquireSlot++ % compositor->acquireSlots.size()];
        if (acquireSlot->inFlight) {
            VkResult status = kine_vk_retire_fence(compositor, acquireSlot->consumed, false);
            if (status == VK_NOT_READY) {
                status = kine_vk_profile_call(compositor, "Vulkan Fence Wait", [&] { return kine_vk_retire_fence(compositor, acquireSlot->consumed, true); });
            }
            if (status != VK_SUCCESS) {
                if (status == VK_ERROR_DEVICE_LOST) compositor->device_lost = true;
                kine_vk_set_error(compositor, "vkWaitForFences async acquire reuse failed");
                return 0;
            }
            acquireSlot->inFlight = false;
        }
        if (acquireSlot->prefetchPending) {
            auto status = kine_vk_retire_fence(compositor, acquireSlot->prefetched, true);
            if (status != VK_SUCCESS) {
                if (status == VK_ERROR_DEVICE_LOST) compositor->device_lost = true;
                compositor->needsResize = true;
                kine_vk_set_error(compositor, "prefetched acquire fence retirement failed");
                return 0;
            }
            acquireSlot->prefetchPending = false;
        }
        const auto reset = vkResetFences(compositor->device, 1, &acquireSlot->consumed);
        if (reset != VK_SUCCESS) {
            if (reset == VK_ERROR_DEVICE_LOST) compositor->device_lost = true;
            kine_vk_set_error(compositor, "vkResetFences async acquire failed");
            return 0;
        }
    }

    compositor->currentImageIndex = UINT32_MAX;
    if (compositor->offscreen) {
        uint32_t readyMask = 0;
        for (uint32_t step = 0; step < compositor->frames.size(); ++step) {
            uint32_t index = (compositor->nextRenderImage + step) % compositor->frames.size();
            auto& candidate = compositor->frames[index].slots[0];
            if (candidate.inFlight) {
                auto result = kine_vk_retire_fence(compositor, candidate.finished, false);
                if (result == VK_ERROR_DEVICE_LOST) {
                    compositor->device_lost = true;
                    return 0;
                }
                if (result == VK_NOT_READY) continue;
                if (result != VK_SUCCESS) {
                    kine_vk_set_error(compositor, "offscreen fence status failed");
                    return 0;
                }
                kine_vk_collect_timing(compositor, candidate);
                candidate.inFlight = false;
            }
            readyMask |= 1u << index;
        }
        compositor->currentImageIndex = compositor->swapchainBackend.selectReady(
            compositor->nextRenderImage, uint32_t(compositor->frames.size()), readyMask, &compositor->nextRenderImage);
    } else if (prefetched) {
        if (compositor->prefetchedSlot >= compositor->acquireSlots.size()) {
            kine_vk_set_error(compositor, "invalid prefetched acquire slot");
            compositor->needsResize = true;
            return 0;
        }
        acquireSlot = &compositor->acquireSlots[compositor->prefetchedSlot];
        compositor->currentImageIndex = compositor->prefetchedImage;
        compositor->prefetchedImage = UINT32_MAX;
        compositor->prefetchedSlot = UINT32_MAX;
    } else {
        VkResult acquired = kine_vk_profile_call(compositor, "Vulkan WSI Acquire", [&] {
            const auto semaphore = acquireSlot ? acquireSlot->ready : VK_NULL_HANDLE;
            const auto fence = acquireSlot ? VK_NULL_HANDLE : compositor->acquireFence;
            if (compositor->wsiBackend.acquire) {
                return static_cast<VkResult>(compositor->wsiBackend.acquire(
                    compositor->wsiBackend.user, (uint64_t)compositor->swapchain,
                    UINT64_MAX, (uint64_t)semaphore, (uint64_t)fence, &compositor->currentImageIndex));
            }
            return vkAcquireNextImageKHR(compositor->device, compositor->swapchain,
                UINT64_MAX, semaphore, fence, &compositor->currentImageIndex);
        });
        if (acquired != VK_SUCCESS && acquired != VK_SUBOPTIMAL_KHR) {
            if (acquired == VK_ERROR_DEVICE_LOST) compositor->device_lost = true;
            if (acquired == VK_ERROR_OUT_OF_DATE_KHR) {
                compositor->needsResize = true;
                return 0;
            }
            kine_vk_set_error(compositor, "vkAcquireNextImageKHR failed");
            return 0;
        }

        if (!acquireSlot) {
            const auto status = kine_vk_profile_call(compositor, "Vulkan Fence Wait", [&] {
                return vkWaitForFences(compositor->device, 1, &compositor->acquireFence, VK_TRUE, UINT64_MAX);
            });
            if (status != VK_SUCCESS) {
                if (status == VK_ERROR_DEVICE_LOST) compositor->device_lost = true;
                kine_vk_set_error(compositor, "vkWaitForFences failed");
                return 0;
            }
            const auto reset = vkResetFences(compositor->device, 1, &compositor->acquireFence);
            if (reset != VK_SUCCESS) {
                if (reset == VK_ERROR_DEVICE_LOST) compositor->device_lost = true;
                kine_vk_set_error(compositor, "vkResetFences acquire failed");
                return 0;
            }
        }

    }

    if (compositor->currentImageIndex >= compositor->frames.size()) {
        kine_vk_set_error(compositor, "vkAcquireNextImageKHR returned an invalid image index");
        return 0;
    }

    return 1;
}

static int32_t kine_vk_begin_claim(KineFrameFlow& flow)
{
    auto* compositor = flow.compositor;
    auto vkResetFences = kine_vk_device_proc<PFN_vkResetFences>(compositor, "vkResetFences");
    if (!vkResetFences) return 0;
    auto& frame = compositor->frames[compositor->currentImageIndex];
    uint32_t selectedSlot = frame.nextSlot;
    if (compositor->offscreen) {
        selectedSlot = 0;
    } else if (compositor->swapchainBackend.selectReady) {
        uint32_t ready = 0;
        for (uint32_t i = 0; i < KineVulkanFrame::SlotCount; ++i) {
            auto& candidate = frame.slots[i];
            if (candidate.inFlight) {
                auto status = kine_vk_retire_fence(compositor, candidate.finished, false);
                if (status == VK_NOT_READY) continue;
                if (status != VK_SUCCESS) {
                    if (status == VK_ERROR_DEVICE_LOST) compositor->device_lost = true;
                    compositor->needsResize = true;
                    kine_vk_set_error(compositor, "frame fence status failed");
                    return 0;
                }
                kine_vk_collect_timing(compositor, candidate);
                candidate.inFlight = false;
            }
            ready |= 1u << i;
        }
        selectedSlot = compositor->swapchainBackend.selectReady(frame.nextSlot, KineVulkanFrame::SlotCount, ready, &frame.nextSlot);
    } else {
        frame.nextSlot = (frame.nextSlot + 1) % KineVulkanFrame::SlotCount;
    }
    if (selectedSlot >= KineVulkanFrame::SlotCount) {
        kine_vk_set_error(compositor, "invalid frame submission slot");
        compositor->needsResize = true;
        return 0;
    }
    auto& slot = frame.slots[selectedSlot];


    if (slot.inFlight) {
        auto status = kine_vk_retire_fence(compositor, slot.finished, false);
        if (status == VK_NOT_READY) {
            status = kine_vk_profile_call(compositor, "Vulkan Fence Wait", [&] {
                return kine_vk_retire_fence(compositor, slot.finished, true);
            });
        }
        if (status != VK_SUCCESS) {
            if (status == VK_ERROR_DEVICE_LOST) compositor->device_lost = true;
            kine_vk_set_error(compositor, "vkWaitForFences image frame failed");
            compositor->needsResize = true;
            return 0;
        }
        kine_vk_collect_timing(compositor,slot);
        slot.inFlight = false;
    }
    const auto reset = vkResetFences(compositor->device, 1, &slot.finished);
    if (reset != VK_SUCCESS) {
        if (reset == VK_ERROR_DEVICE_LOST) compositor->device_lost = true;
        kine_vk_set_error(compositor, "vkResetFences image frame failed");
        compositor->needsResize = true;
        return 0;
    }
    compositor->activeSlot = &slot;
    slot.timingSerial = ++compositor->timingSerial;
    slot.timingHandoff = false;
    slot.timingOverlay = false;

    return 1;
}

static int32_t kine_vk_begin_canvas(KineFrameFlow& flow)
{
    auto* compositor = flow.compositor;
    auto& frame = compositor->frames[compositor->currentImageIndex];
    auto& slot = *compositor->activeSlot;
    auto* acquireSlot = flow.acquireSlot;
    VkImageLayout currentLayout = kine_vk_render_layouts(compositor)[compositor->currentImageIndex];
    if (!kine_vk_profile_call(compositor, "Vulkan Transition Submit", [&] { return kine_vk_transition_current_image(
            compositor,
            slot.acquire,
            currentLayout,
            VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
            acquireSlot ? acquireSlot->ready : (slot.copyReturnPending ? slot.copyReturned : VK_NULL_HANDLE),
            VK_NULL_HANDLE,
            acquireSlot ? acquireSlot->consumed : VK_NULL_HANDLE); })) {


        if (acquireSlot) compositor->needsResize = true;
        return 0;
    }
    if (acquireSlot) acquireSlot->inFlight = true;
    slot.copyReturnPending = false;

    if (!frame.base) {
        frame.base = kine_vk_create_current_skia_surface(compositor);
    }
    compositor->currentSkiaSurface = frame.base;
    if (!compositor->currentSkiaSurface) {
        kine_vk_set_error(compositor, "Kine_Skia_Surface_CreateVulkanRenderTarget failed");
        compositor->needsResize = true;
        return 0;
    }

    return 1;
}

static int32_t kine_vk_begin_publish(KineFrameFlow& flow)
{
    auto* compositor = flow.compositor;
    if (!kine_vk_provider_action(compositor, KINE_PROVIDER_BEGIN, compositor->currentImageIndex)) {
        compositor->needsResize = true;
        return 0;
    }
    compositor->lastError.clear();
    return 1;
}

static int32_t kine_vk_frame_step(void* user, uint32_t step)
{
    if (!user) return 0;
    auto& flow = *static_cast<KineFrameFlow*>(user);
    switch (step) {
    case KINE_FRAME_ACQUIRE: return kine_vk_begin_acquire(flow);
    case KINE_FRAME_CLAIM: return kine_vk_begin_claim(flow);
    case KINE_FRAME_CANVAS: return kine_vk_begin_canvas(flow);
    case KINE_FRAME_PUBLISH: return kine_vk_begin_publish(flow);
    default: return kine_vk_end_step(flow, step);
    }
}

static bool kine_vk_run_frame_flow(KineFrameFlow& flow, bool ending)
{
    auto* c = flow.compositor;
    return c->nativeProvider && c->swapchainBackend.frameFlow &&
        c->swapchainBackend.frameFlow(&flow, kine_vk_frame_step, uint32_t(ending)) != 0;
}

KINE_VULKAN_COMPOSITOR_API void*
Kine_VulkanCompositor_BeginFrame(KineVulkanCompositor* compositor)
{
    if (!Kine_VulkanCompositor_IsReady(compositor)) return nullptr;
    if (kine_vk_frame_active(compositor)) return compositor->currentSkiaSurface;
    KineFrameFlow flow{compositor};
    if (!kine_vk_run_frame_flow(flow, false)) {
        compositor->needsResize = true;
        return nullptr;
    }
    return compositor->currentSkiaSurface;
}

KINE_VULKAN_COMPOSITOR_API void*
Kine_VulkanCompositor_BeginOverlay(KineVulkanCompositor* compositor)
{
    if (!compositor) {
        return nullptr;
    }
    if (compositor->overlaySkiaSurface) {
        return compositor->overlaySkiaSurface;
    }

    uint64_t finished = 0;
    const auto status = kine_vk_profile_call(compositor, "Vulkan Filament Callback Wait", [&] {
        return kine_vk_provider_action(compositor, KINE_PROVIDER_WAIT_OVERLAY, UINT32_MAX, VK_NULL_HANDLE, nullptr, &finished);
    });
    if (status <= 0) {
        kine_vk_set_error(compositor, status < 0 ? "timed out waiting for Filament before overlay" : "overlay requires an active compositor frame");
        return nullptr;
    }
    if (status == 2) {
        if (!kine_vk_provider_action(compositor, KINE_PROVIDER_OVERLAY)) return nullptr;
        compositor->lastError.clear();
        return compositor->currentSkiaSurface;
    }
    VkSemaphore filamentFinished = (VkSemaphore)finished;

    if (compositor->currentImageIndex < compositor->frames.size()) {
        auto& frame = compositor->frames[compositor->currentImageIndex];
        if (!frame.overlay) {
            frame.overlay = kine_vk_create_current_skia_surface(compositor);
        }
        compositor->overlaySkiaSurface = frame.overlay;
    }
    if (!compositor->overlaySkiaSurface) {
        kine_vk_set_error(compositor,"failed to create post-Filament Skia overlay surface");
        return nullptr;
    }
    if (filamentFinished && !kine_vk_profile_call(compositor,"Vulkan Overlay Handoff",[&] {
        const char* legacy = std::getenv("KINE_VULKAN_LEGACY_OVERLAY_SUBMIT");
        if (!(compositor->activeSlot && compositor->activeSlot->overlayTiming) &&
            !(legacy && std::strcmp(legacy,"1")==0) &&
            kine_vk_wait_surface(compositor,compositor->overlaySkiaSurface,filamentFinished)) return true;
        return kine_vk_wait_for_filament(compositor,filamentFinished);
    })) return nullptr;


    if (!kine_vk_provider_action(compositor, KINE_PROVIDER_OVERLAY)) return nullptr;
    if (!compositor->overlaySkiaSurface) {
        kine_vk_set_error(compositor, "failed to create post-Filament Skia overlay surface");
        return nullptr;
    }
    compositor->lastError.clear();
    return compositor->overlaySkiaSurface;
}

static int32_t kine_vk_end_flush(KineFrameFlow& flow)
{
    auto* compositor = flow.compositor;
    uint64_t finished = 0;
    const auto status = kine_vk_profile_call(compositor, "Vulkan Filament Callback Wait", [&] {
        return kine_vk_provider_action(compositor, KINE_PROVIDER_WAIT_END, UINT32_MAX, VK_NULL_HANDLE, nullptr, &finished);
    });
    if (status <= 0) {
        if (status < 0) kine_vk_set_error(compositor, "timed out waiting for Filament present callback");
        return 0;
    }
    flow.filamentFinished = (VkSemaphore)finished;

    auto vkQueuePresentKHR = compositor->wsiBackend.present ? nullptr :
        kine_vk_device_proc<PFN_vkQueuePresentKHR>(compositor, "vkQueuePresentKHR");
    if (!compositor->wsiBackend.present && !vkQueuePresentKHR) {
        kine_vk_set_error(compositor, "vkQueuePresentKHR unavailable");
        return 0;
    }

    if (compositor->currentSkiaSurface) {
        if (!kine_vk_profile_call(compositor,"Vulkan Skia Flush",[&] {
                return kine_vk_flush_surface(compositor,compositor->currentSkiaSurface);
            })) {
            kine_vk_set_error(compositor,"failed restoring Skia base image layout");
            return 0;
        }
    }
    if (compositor->overlaySkiaSurface) {
        if (!kine_vk_profile_call(compositor,"Vulkan Skia Overlay Flush",[&] {
                return kine_vk_flush_surface(compositor,compositor->overlaySkiaSurface);
            })) {
            kine_vk_set_error(compositor,"failed restoring Skia overlay image layout");
            return 0;
        }
    }

    return 1;
}

static int32_t kine_vk_end_acquire(KineFrameFlow& flow)
{
    auto* compositor = flow.compositor;
    auto& presentImage = flow.presentImage;
    presentImage = compositor->currentImageIndex;
    auto* slot = compositor->activeSlot;
    if (!slot) {
        kine_vk_set_error(compositor, "compositor frame is missing its submission slot");
        return 0;
    }
    if (compositor->offscreen) {
        if (flow.filamentFinished && !kine_vk_wait_for_filament(compositor, flow.filamentFinished)) {
            compositor->needsResize = true;
            return 0;
        }
        if (!kine_vk_drain_present(compositor) || compositor->needsResize) {
            compositor->needsResize = true;
            return 0;
        }
        auto acquire = kine_vk_device_proc<PFN_vkAcquireNextImageKHR>(compositor, "vkAcquireNextImageKHR");
        auto wait = kine_vk_device_proc<PFN_vkWaitForFences>(compositor, "vkWaitForFences");
        auto reset = kine_vk_device_proc<PFN_vkResetFences>(compositor, "vkResetFences");
        if (!wait || !reset) {compositor->needsResize = true; return 0;}
        if (slot->lateAcquirePending) {
            auto status = wait(compositor->device, 1, &slot->lateAcquireFence, VK_TRUE, UINT64_MAX);
            if (status != VK_SUCCESS) {
                if (status == VK_ERROR_DEVICE_LOST) compositor->device_lost = true;
                compositor->needsResize = true;
                return 0;
            }
            slot->lateAcquirePending = false;
        }
        auto resetResult = reset(compositor->device, 1, &slot->lateAcquireFence);
        if (resetResult != VK_SUCCESS) {
            if (resetResult == VK_ERROR_DEVICE_LOST) compositor->device_lost = true;
            compositor->needsResize = true;
            return 0;
        }
        VkResult result = kine_vk_profile_call(compositor, "Vulkan Late WSI Acquire", [&] {
            if (compositor->wsiBackend.acquire) return static_cast<VkResult>(compositor->wsiBackend.acquire(
                compositor->wsiBackend.user, (uint64_t)compositor->swapchain, UINT64_MAX,
                (uint64_t)slot->lateAcquire, (uint64_t)slot->lateAcquireFence, &presentImage));
            return acquire ? acquire(compositor->device, compositor->swapchain, UINT64_MAX, slot->lateAcquire, slot->lateAcquireFence, &presentImage) : VK_ERROR_INITIALIZATION_FAILED;
        });
        slot->lateAcquirePending = result == VK_SUCCESS || result == VK_SUBOPTIMAL_KHR;
        if (!slot->lateAcquirePending || presentImage >= compositor->swapchainImages.size()) {
            if (result == VK_ERROR_DEVICE_LOST) compositor->device_lost = true;
            compositor->needsResize = true;
            kine_vk_set_error(compositor, "late WSI acquisition failed");
            return 0;
        }
    }

    return 1;
}

static int32_t kine_vk_end_submit(KineFrameFlow& flow)
{
    auto* compositor = flow.compositor;
    auto* slot = compositor->activeSlot;
    auto presentImage = flow.presentImage;
    auto filamentFinished = flow.filamentFinished;
    auto& renderFinished = flow.renderFinished;
    if (presentImage < compositor->renderFinishedSemaphores.size()) {
        renderFinished = compositor->renderFinishedSemaphores[presentImage];
    }

    if (compositor->offscreen) {
        auto d = kine_vk_frame_dispatch(compositor);
        const bool separateCopy = compositor->sameFamilyCopyQueue && compositor->wsiBackend.asynchronous;
        auto result = kine_vk_profile_call(compositor, "Vulkan Offscreen Copy", [&] {
            return static_cast<VkResult>(compositor->swapchainBackend.copyColor(&d, slot->present,
                (uint64_t)compositor->renderImages[compositor->currentImageIndex],
                (uint64_t)compositor->swapchainImages[presentImage], compositor->width, compositor->height,
                uint32_t(compositor->swapchainFormat), uint32_t(compositor->swapchainImageLayouts[presentImage]), separateCopy ? 0 : (uint64_t)slot->timing));
        });
        if (result == VK_SUCCESS) {
            if (separateCopy) {
                result = static_cast<VkResult>(compositor->swapchainBackend.submitCopy(&d, compositor->graphicsQueue,
                    compositor->presentQueue, slot->renderComplete, slot->present, (uint64_t)slot->copyReady,
                    (uint64_t)slot->lateAcquire, (uint64_t)renderFinished, (uint64_t)slot->copyReturned, (uint64_t)slot->finished));
                slot->copyReturnPending = result == VK_SUCCESS;
            } else {
                result = kine_vk_submit(compositor, slot->present, slot->lateAcquire, renderFinished, slot->finished);
            }
        }
        if (result != VK_SUCCESS) {
            if (result == VK_ERROR_DEVICE_LOST) compositor->device_lost = true;
            compositor->needsResize = true;
            kine_vk_set_error(compositor, "Odin offscreen copy failed");
            return 0;
        }
        compositor->swapchainImageLayouts[presentImage] = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
    } else {

        if (!kine_vk_profile_call(compositor, "Vulkan Transition Submit", [&] { return kine_vk_transition_current_image(
                compositor,
                slot->present,
                VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
                VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
                filamentFinished,
                renderFinished,
                slot->finished); })) {
            return 0;
        }

    }
    slot->inFlight = true;

    compositor->currentSkiaSurface = nullptr;
    compositor->overlaySkiaSurface = nullptr;

    return 1;
}

static int32_t kine_vk_end_present(KineFrameFlow& flow)
{
    auto* compositor = flow.compositor;
    auto presentImage = flow.presentImage;
    auto renderFinished = flow.renderFinished;
    auto vkQueuePresentKHR = compositor->wsiBackend.present ? nullptr :
        kine_vk_device_proc<PFN_vkQueuePresentKHR>(compositor, "vkQueuePresentKHR");
    const KinePresentJob job{compositor->swapchain,renderFinished,presentImage};
    VkResult presented = VK_SUCCESS;
    if (compositor->wsiBackend.present) {
        if (compositor->overlapPresent && !kine_vk_drain_present(compositor)) {
            presented = compositor->device_lost ? VK_ERROR_DEVICE_LOST : VK_ERROR_UNKNOWN;
            compositor->needsResize = true;
        } else if (compositor->needsResize || compositor->device_lost) {
            presented = compositor->device_lost ? VK_ERROR_DEVICE_LOST : VK_ERROR_OUT_OF_DATE_KHR;
        } else {
            kine_vk_prefetch_next(compositor);
            if (compositor->device_lost) {
                presented = VK_ERROR_DEVICE_LOST;
            } else {
                presented = kine_vk_profile_call(compositor,
                    compositor->wsiBackend.asynchronous ? "Vulkan Odin Present Enqueue" : "Vulkan WSI Present", [&] {
                        return static_cast<VkResult>(compositor->wsiBackend.present(compositor->wsiBackend.user,
                            (uint64_t)job.swapchain, (uint64_t)job.semaphore, job.image));
                    });
            }
        }
    } else {
        presented = kine_vk_profile_call(compositor,"Vulkan WSI Present",[&] {
            return kine_vk_present_job(vkQueuePresentKHR,compositor->presentQueue ? compositor->presentQueue : compositor->graphicsQueue,job);
        });
    }

    kine_vk_provider_action(compositor, KINE_PROVIDER_RESET);
    compositor->currentImageIndex = UINT32_MAX;
    compositor->activeSlot = nullptr;
    compositor->overlapPresent = false;

    if (!kine_vk_handle_present_result(compositor,presented)) return 0;

    compositor->lastError.clear();
    return 1;
}

static int32_t kine_vk_end_step(KineFrameFlow& flow, uint32_t step)
{
    switch (step) {
    case KINE_FRAME_FLUSH: return kine_vk_end_flush(flow);
    case KINE_FRAME_LATE_ACQUIRE: return kine_vk_end_acquire(flow);
    case KINE_FRAME_SUBMIT: return kine_vk_end_submit(flow);
    case KINE_FRAME_PRESENT: return kine_vk_end_present(flow);
    default: return 0;
    }
}

KINE_VULKAN_COMPOSITOR_API int
Kine_VulkanCompositor_EndFrame(KineVulkanCompositor* compositor)
{
    if (!compositor || !kine_vk_frame_active(compositor)) return 0;
    KineFrameFlow flow{compositor};
    if (!kine_vk_run_frame_flow(flow, true)) {
        compositor->needsResize = true;
        return 0;
    }
    return 1;
}

}
