#if defined(KINE_GPU_CLOUD_NOISE_AVAILABLE) && KINE_FILAMENT_USE_VULKAN && defined(__linux__)
#include "kine_cloud_noise_spirv.h"

struct KineCloudGpuResources {
    KineFilamentVulkanBackend backend{};
    VkImage images[3]{};
    VkDeviceMemory imageMemory[3]{};
    VkImageView views[3]{};
    VkShaderModule modules[3]{};
    VkPipeline pipelines[3]{};
    VkDescriptorSet sets[3]{};
    VkDescriptorSetLayout descriptorLayout = VK_NULL_HANDLE;
    VkPipelineLayout pipelineLayout = VK_NULL_HANDLE;
    VkDescriptorPool descriptorPool = VK_NULL_HANDLE;
    VkBuffer uniforms = VK_NULL_HANDLE;
    VkBuffer readback = VK_NULL_HANDLE;
    VkDeviceMemory uniformMemory = VK_NULL_HANDLE;
    VkDeviceMemory readbackMemory = VK_NULL_HANDLE;
    VkCommandPool pool = VK_NULL_HANDLE;
    VkFence fence = VK_NULL_HANDLE;

    VkDevice device() const { return reinterpret_cast<VkDevice>(backend.device); }
    template <typename T> T proc(const char* name) const {
        auto getInstanceProc = reinterpret_cast<PFN_vkGetInstanceProcAddr>(backend.getInstanceProcAddr);
        auto getDeviceProc = reinterpret_cast<PFN_vkGetDeviceProcAddr>(
                getInstanceProc(reinterpret_cast<VkInstance>(backend.instance), "vkGetDeviceProcAddr"));
        return reinterpret_cast<T>(getDeviceProc(device(), name));
    }
    ~KineCloudGpuResources() {
        if (!device()) return;
        auto d = device();
        auto destroyImage = proc<PFN_vkDestroyImage>("vkDestroyImage");
        auto freeMemory = proc<PFN_vkFreeMemory>("vkFreeMemory");
        auto destroyImageView = proc<PFN_vkDestroyImageView>("vkDestroyImageView");
        auto destroyShader = proc<PFN_vkDestroyShaderModule>("vkDestroyShaderModule");
        auto destroyPipeline = proc<PFN_vkDestroyPipeline>("vkDestroyPipeline");
        for (int i = 0; i < 3; ++i) {
            if (pipelines[i]) destroyPipeline(d, pipelines[i], nullptr);
            if (modules[i]) destroyShader(d, modules[i], nullptr);
            if (views[i]) destroyImageView(d, views[i], nullptr);
            if (images[i]) destroyImage(d, images[i], nullptr);
            if (imageMemory[i]) freeMemory(d, imageMemory[i], nullptr);
        }
        if (pool) proc<PFN_vkDestroyCommandPool>("vkDestroyCommandPool")(d, pool, nullptr);
        if (fence) proc<PFN_vkDestroyFence>("vkDestroyFence")(d, fence, nullptr);
        if (descriptorPool) proc<PFN_vkDestroyDescriptorPool>("vkDestroyDescriptorPool")(d, descriptorPool, nullptr);
        if (pipelineLayout) proc<PFN_vkDestroyPipelineLayout>("vkDestroyPipelineLayout")(d, pipelineLayout, nullptr);
        if (descriptorLayout) proc<PFN_vkDestroyDescriptorSetLayout>("vkDestroyDescriptorSetLayout")(d, descriptorLayout, nullptr);
        if (uniforms) proc<PFN_vkDestroyBuffer>("vkDestroyBuffer")(d, uniforms, nullptr);
        if (readback) proc<PFN_vkDestroyBuffer>("vkDestroyBuffer")(d, readback, nullptr);
        if (uniformMemory) freeMemory(d, uniformMemory, nullptr);
        if (readbackMemory) freeMemory(d, readbackMemory, nullptr);
    }
};

struct KineCloudGpuParameters {
    float shape[4]{};
    float worley[4]{};
    float shapeScales[4]{};
    float shapeSmall[4]{};
    float detail[4]{};
    float detailRemap[4]{};
    float curl[4]{};
    float offset[4]{};
};

static_assert(sizeof(KineCloudGpuParameters) == 128);

static bool kine_cloud_gpu_generate(KineFilamentContext* ctx,
        std::array<std::vector<uint8_t>, 3>& data) {
    const char* disabled = std::getenv("KINE_DISABLE_GPU_CLOUD_NOISE");
    if (disabled && std::strcmp(disabled, "1") == 0) return false;
    KineCloudGpuResources gpu;
    if (!Kine_Filament_GetVulkanBackend(ctx, &gpu.backend)) return false;
    auto d = gpu.device();
    auto instanceProc = reinterpret_cast<PFN_vkGetInstanceProcAddr>(gpu.backend.getInstanceProcAddr);
    auto memoryProc = reinterpret_cast<PFN_vkGetPhysicalDeviceMemoryProperties>(
            instanceProc(reinterpret_cast<VkInstance>(gpu.backend.instance),
                    "vkGetPhysicalDeviceMemoryProperties"));
    auto formatProc = reinterpret_cast<PFN_vkGetPhysicalDeviceFormatProperties>(
            instanceProc(reinterpret_cast<VkInstance>(gpu.backend.instance),
                    "vkGetPhysicalDeviceFormatProperties"));
    if (!memoryProc || !formatProc) return false;
    VkPhysicalDeviceMemoryProperties memory{};
    memoryProc(reinterpret_cast<VkPhysicalDevice>(gpu.backend.physicalDevice), &memory);
    VkFormatProperties formats{};
    formatProc(reinterpret_cast<VkPhysicalDevice>(gpu.backend.physicalDevice),
            VK_FORMAT_R8G8B8A8_UNORM, &formats);
    if ((formats.optimalTilingFeatures & VK_FORMAT_FEATURE_STORAGE_IMAGE_BIT) == 0) return false;

    auto memoryType = [&](uint32_t bits, VkMemoryPropertyFlags flags) {
        for (uint32_t i = 0; i < memory.memoryTypeCount; ++i) {
            if ((bits & (1u << i)) && (memory.memoryTypes[i].propertyFlags & flags) == flags)
                return i;
        }
        return UINT32_MAX;
    };
    auto allocate = gpu.proc<PFN_vkAllocateMemory>("vkAllocateMemory");
    auto imageRequirements = gpu.proc<PFN_vkGetImageMemoryRequirements>("vkGetImageMemoryRequirements");
    auto bufferRequirements = gpu.proc<PFN_vkGetBufferMemoryRequirements>("vkGetBufferMemoryRequirements");
    auto createBuffer = gpu.proc<PFN_vkCreateBuffer>("vkCreateBuffer");
    auto bindBuffer = gpu.proc<PFN_vkBindBufferMemory>("vkBindBufferMemory");
    auto makeBuffer = [&](VkDeviceSize size, VkBufferUsageFlags usage,
            VkBuffer& buffer, VkDeviceMemory& allocation) {
        VkBufferCreateInfo info{};
        info.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
        info.size = size;
        info.usage = usage;
        info.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
        if (createBuffer(d, &info, nullptr, &buffer) != VK_SUCCESS) return false;
        VkMemoryRequirements req{};
        bufferRequirements(d, buffer, &req);
        uint32_t type = memoryType(req.memoryTypeBits,
                VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
        if (type == UINT32_MAX) return false;
        VkMemoryAllocateInfo allocationInfo{};
        allocationInfo.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
        allocationInfo.allocationSize = req.size;
        allocationInfo.memoryTypeIndex = type;
        return allocate(d, &allocationInfo, nullptr, &allocation) == VK_SUCCESS &&
                bindBuffer(d, buffer, allocation, 0) == VK_SUCCESS;
    };

    constexpr uint32_t dimensions[3] = {64, 32, 128};
    constexpr uint32_t depths[3] = {64, 32, 1};
    constexpr size_t lengths[3] = {sizeof(kine_cloud_shape_spirv),
            sizeof(kine_cloud_detail_spirv), sizeof(kine_cloud_curl_spirv)};
    const uint32_t* binaries[3] = {kine_cloud_shape_spirv,
            kine_cloud_detail_spirv, kine_cloud_curl_spirv};
    VkDeviceSize offsets[3] = {0, 64u * 64u * 64u * 4u,
            (64u * 64u * 64u + 32u * 32u * 32u) * 4u};
    const VkDeviceSize readbackBytes = offsets[2] + 128u * 128u * 4u;

    if (!makeBuffer(sizeof(KineCloudGpuParameters), VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
            gpu.uniforms, gpu.uniformMemory) ||
        !makeBuffer(readbackBytes, VK_BUFFER_USAGE_TRANSFER_DST_BIT,
            gpu.readback, gpu.readbackMemory)) return false;

    KineCloudGpuParameters params{};
    params.shape[0] = 0.3f; params.shape[1] = 0.3f;
    params.shape[2] = 1.4f; params.shape[3] = 1.0f;
    params.worley[0] = -0.3f; params.worley[1] = 1.3f;
    params.worley[2] = -0.4f; params.worley[3] = 1.0f;
    params.shapeScales[0] = 4.0f; params.shapeScales[1] = 6.0f;
    params.shapeScales[2] = 6.0f; params.shapeScales[3] = 12.0f;
    params.shapeSmall[0] = 24.0f;
    params.detail[0] = 5.0f; params.detail[1] = 7.5f; params.detail[2] = 10.0f;
    params.detailRemap[0] = -1.0f; params.detailRemap[1] = 1.0f;
    params.curl[0] = 4.0f; params.curl[1] = -0.5f; params.curl[2] = 3.0f;
    auto map = gpu.proc<PFN_vkMapMemory>("vkMapMemory");
    auto unmap = gpu.proc<PFN_vkUnmapMemory>("vkUnmapMemory");
    void* mapped = nullptr;
    if (map(d, gpu.uniformMemory, 0, sizeof(params), 0, &mapped) != VK_SUCCESS) return false;
    std::memcpy(mapped, &params, sizeof(params));
    unmap(d, gpu.uniformMemory);

    auto createImage = gpu.proc<PFN_vkCreateImage>("vkCreateImage");
    auto bindImage = gpu.proc<PFN_vkBindImageMemory>("vkBindImageMemory");
    auto createView = gpu.proc<PFN_vkCreateImageView>("vkCreateImageView");
    auto createModule = gpu.proc<PFN_vkCreateShaderModule>("vkCreateShaderModule");
    for (int i = 0; i < 3; ++i) {
        VkImageCreateInfo info{};
        info.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
        info.imageType = i == 2 ? VK_IMAGE_TYPE_2D : VK_IMAGE_TYPE_3D;
        info.format = VK_FORMAT_R8G8B8A8_UNORM;
        info.extent = {dimensions[i], dimensions[i], depths[i]};
        info.mipLevels = 1;
        info.arrayLayers = 1;
        info.samples = VK_SAMPLE_COUNT_1_BIT;
        info.tiling = VK_IMAGE_TILING_OPTIMAL;
        info.usage = VK_IMAGE_USAGE_STORAGE_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
        info.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
        if (createImage(d, &info, nullptr, &gpu.images[i]) != VK_SUCCESS) return false;
        VkMemoryRequirements req{};
        imageRequirements(d, gpu.images[i], &req);
        const uint32_t type = memoryType(req.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
        if (type == UINT32_MAX) return false;
        VkMemoryAllocateInfo allocationInfo{};
        allocationInfo.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
        allocationInfo.allocationSize = req.size;
        allocationInfo.memoryTypeIndex = type;
        if (allocate(d, &allocationInfo, nullptr, &gpu.imageMemory[i]) != VK_SUCCESS ||
            bindImage(d, gpu.images[i], gpu.imageMemory[i], 0) != VK_SUCCESS) return false;
        VkImageViewCreateInfo view{};
        view.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
        view.image = gpu.images[i];
        view.viewType = i == 2 ? VK_IMAGE_VIEW_TYPE_2D : VK_IMAGE_VIEW_TYPE_3D;
        view.format = VK_FORMAT_R8G8B8A8_UNORM;
        view.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
        if (createView(d, &view, nullptr, &gpu.views[i]) != VK_SUCCESS) return false;
        VkShaderModuleCreateInfo shader{};
        shader.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
        shader.codeSize = lengths[i];
        shader.pCode = binaries[i];
        if (createModule(d, &shader, nullptr, &gpu.modules[i]) != VK_SUCCESS) return false;
    }
    VkDescriptorSetLayoutBinding bindings[2]{};
    bindings[0] = {0, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 1, VK_SHADER_STAGE_COMPUTE_BIT, nullptr};
    bindings[1] = {1, VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, 1, VK_SHADER_STAGE_COMPUTE_BIT, nullptr};
    VkDescriptorSetLayoutCreateInfo layoutInfo{};
    layoutInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
    layoutInfo.bindingCount = 2;
    layoutInfo.pBindings = bindings;
    if (gpu.proc<PFN_vkCreateDescriptorSetLayout>("vkCreateDescriptorSetLayout")(
            d, &layoutInfo, nullptr, &gpu.descriptorLayout) != VK_SUCCESS) return false;
    VkPipelineLayoutCreateInfo pipelineLayoutInfo{};
    pipelineLayoutInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
    pipelineLayoutInfo.setLayoutCount = 1;
    pipelineLayoutInfo.pSetLayouts = &gpu.descriptorLayout;
    if (gpu.proc<PFN_vkCreatePipelineLayout>("vkCreatePipelineLayout")(
            d, &pipelineLayoutInfo, nullptr, &gpu.pipelineLayout) != VK_SUCCESS) return false;
    for (int i = 0; i < 3; ++i) {
        VkComputePipelineCreateInfo pipeline{};
        pipeline.sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO;
        pipeline.layout = gpu.pipelineLayout;
        pipeline.stage.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
        pipeline.stage.stage = VK_SHADER_STAGE_COMPUTE_BIT;
        pipeline.stage.module = gpu.modules[i];
        pipeline.stage.pName = "main";
        if (gpu.proc<PFN_vkCreateComputePipelines>("vkCreateComputePipelines")(
                d, VK_NULL_HANDLE, 1, &pipeline, nullptr, &gpu.pipelines[i]) != VK_SUCCESS)
            return false;
    }
    VkDescriptorPoolSize poolSizes[2] = {
        {VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 3},
        {VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, 3}
    };
    VkDescriptorPoolCreateInfo poolInfo{};
    poolInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
    poolInfo.maxSets = 3;
    poolInfo.poolSizeCount = 2;
    poolInfo.pPoolSizes = poolSizes;
    if (gpu.proc<PFN_vkCreateDescriptorPool>("vkCreateDescriptorPool")(
            d, &poolInfo, nullptr, &gpu.descriptorPool) != VK_SUCCESS) return false;
    VkDescriptorSetLayout layouts[3] = {gpu.descriptorLayout,
            gpu.descriptorLayout, gpu.descriptorLayout};
    VkDescriptorSetAllocateInfo setInfo{};
    setInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
    setInfo.descriptorPool = gpu.descriptorPool;
    setInfo.descriptorSetCount = 3;
    setInfo.pSetLayouts = layouts;
    if (gpu.proc<PFN_vkAllocateDescriptorSets>("vkAllocateDescriptorSets")(
            d, &setInfo, gpu.sets) != VK_SUCCESS) return false;
    auto updateDescriptors = gpu.proc<PFN_vkUpdateDescriptorSets>("vkUpdateDescriptorSets");
    for (int i = 0; i < 3; ++i) {
        VkDescriptorBufferInfo bufferInfo{gpu.uniforms, 0, sizeof(params)};
        VkDescriptorImageInfo imageInfo{VK_NULL_HANDLE, gpu.views[i], VK_IMAGE_LAYOUT_GENERAL};
        VkWriteDescriptorSet writes[2]{};
        writes[0].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
        writes[0].dstSet = gpu.sets[i];
        writes[0].dstBinding = 0;
        writes[0].descriptorCount = 1;
        writes[0].descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
        writes[0].pBufferInfo = &bufferInfo;
        writes[1].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
        writes[1].dstSet = gpu.sets[i];
        writes[1].dstBinding = 1;
        writes[1].descriptorCount = 1;
        writes[1].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_IMAGE;
        writes[1].pImageInfo = &imageInfo;
        updateDescriptors(d, 2, writes, 0, nullptr);
    }

    VkCommandPoolCreateInfo commandPoolInfo{};
    commandPoolInfo.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
    commandPoolInfo.queueFamilyIndex = gpu.backend.graphicsQueueFamilyIndex;
    if (gpu.proc<PFN_vkCreateCommandPool>("vkCreateCommandPool")(
            d, &commandPoolInfo, nullptr, &gpu.pool) != VK_SUCCESS) return false;
    VkCommandBuffer command = VK_NULL_HANDLE;
    VkCommandBufferAllocateInfo commandInfo{};
    commandInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    commandInfo.commandPool = gpu.pool;
    commandInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    commandInfo.commandBufferCount = 1;
    if (gpu.proc<PFN_vkAllocateCommandBuffers>("vkAllocateCommandBuffers")(
            d, &commandInfo, &command) != VK_SUCCESS) return false;
    VkFenceCreateInfo fenceInfo{};
    fenceInfo.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
    if (gpu.proc<PFN_vkCreateFence>("vkCreateFence")(
            d, &fenceInfo, nullptr, &gpu.fence) != VK_SUCCESS) return false;
    VkCommandBufferBeginInfo begin{};
    begin.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    begin.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    if (gpu.proc<PFN_vkBeginCommandBuffer>("vkBeginCommandBuffer")(command, &begin) != VK_SUCCESS)
        return false;
    auto barrier = gpu.proc<PFN_vkCmdPipelineBarrier>("vkCmdPipelineBarrier");
    auto bindPipeline = gpu.proc<PFN_vkCmdBindPipeline>("vkCmdBindPipeline");
    auto bindDescriptors = gpu.proc<PFN_vkCmdBindDescriptorSets>("vkCmdBindDescriptorSets");
    auto dispatch = gpu.proc<PFN_vkCmdDispatch>("vkCmdDispatch");
    auto copy = gpu.proc<PFN_vkCmdCopyImageToBuffer>("vkCmdCopyImageToBuffer");
    for (int i = 0; i < 3; ++i) {
        VkImageMemoryBarrier imageBarrier{};
        imageBarrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
        imageBarrier.dstAccessMask = VK_ACCESS_SHADER_WRITE_BIT;
        imageBarrier.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED;
        imageBarrier.newLayout = VK_IMAGE_LAYOUT_GENERAL;
        imageBarrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        imageBarrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        imageBarrier.image = gpu.images[i];
        imageBarrier.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
        barrier(command, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
                0, 0, nullptr, 0, nullptr, 1, &imageBarrier);
        bindPipeline(command, VK_PIPELINE_BIND_POINT_COMPUTE, gpu.pipelines[i]);
        bindDescriptors(command, VK_PIPELINE_BIND_POINT_COMPUTE, gpu.pipelineLayout,
                0, 1, &gpu.sets[i], 0, nullptr);
        const uint32_t groups = dimensions[i] / (i == 2 ? 16 : 8);
        dispatch(command, groups, groups, i == 2 ? 1 : depths[i] / 8);
        imageBarrier.srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT;
        imageBarrier.dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
        imageBarrier.oldLayout = VK_IMAGE_LAYOUT_GENERAL;
        imageBarrier.newLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
        barrier(command, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT,
                0, 0, nullptr, 0, nullptr, 1, &imageBarrier);
        VkBufferImageCopy region{};
        region.bufferOffset = offsets[i];
        region.imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1};
        region.imageExtent = {dimensions[i], dimensions[i], depths[i]};
        copy(command, gpu.images[i], VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                gpu.readback, 1, &region);
    }
    VkBufferMemoryBarrier readBarrier{};
    readBarrier.sType = VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER;
    readBarrier.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
    readBarrier.dstAccessMask = VK_ACCESS_HOST_READ_BIT;
    readBarrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    readBarrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    readBarrier.buffer = gpu.readback;
    readBarrier.offset = 0;
    readBarrier.size = readbackBytes;
    barrier(command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_HOST_BIT,
            0, 0, nullptr, 1, &readBarrier, 0, nullptr);
    if (gpu.proc<PFN_vkEndCommandBuffer>("vkEndCommandBuffer")(command) != VK_SUCCESS)
        return false;
    ctx->engine->flushAndWait();
    auto queue = reinterpret_cast<VkQueue>(gpu.backend.queue);
    if (gpu.proc<PFN_vkQueueWaitIdle>("vkQueueWaitIdle")(queue) != VK_SUCCESS) return false;
    VkSubmitInfo submit{};
    submit.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    submit.commandBufferCount = 1;
    submit.pCommandBuffers = &command;
    if (gpu.proc<PFN_vkQueueSubmit>("vkQueueSubmit")(
            queue, 1, &submit, gpu.fence) != VK_SUCCESS) return false;
    if (gpu.proc<PFN_vkWaitForFences>("vkWaitForFences")(
            d, 1, &gpu.fence, VK_TRUE, 60000000000ull) != VK_SUCCESS) {
        gpu.proc<PFN_vkQueueWaitIdle>("vkQueueWaitIdle")(queue);
        return false;
    }
    mapped = nullptr;
    if (map(d, gpu.readbackMemory, 0, readbackBytes, 0, &mapped) != VK_SUCCESS)
        return false;
    const auto* bytes = static_cast<const uint8_t*>(mapped);
    for (int i = 0; i < 3; ++i) {
        const size_t count = size_t(dimensions[i]) * dimensions[i] * depths[i] * 4;
        data[i].assign(bytes + offsets[i], bytes + offsets[i] + count);
    }
    unmap(d, gpu.readbackMemory);
    for (int i = 0; i < 3; ++i) {
        if (data[i].empty()) return false;
    }
    return true;
}
#endif
