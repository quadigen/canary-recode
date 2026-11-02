#include "kine_terrain_mc.h"

#include <vulkan/vulkan.h>

#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <stdlib.h>

#include "kine_terrain_mc_spv.h"

// Must match kine_terrain_mc.comp / Terrain.odin.
#define KINE_TERRAIN_MC_CHUNK 16
#define KINE_TERRAIN_MC_LATT (KINE_TERRAIN_MC_CHUNK + 1)             // 17
#define KINE_TERRAIN_MC_LATT3 (KINE_TERRAIN_MC_LATT * KINE_TERRAIN_MC_LATT * KINE_TERRAIN_MC_LATT) // 4913
#define KINE_TERRAIN_MC_EDGE_COUNT (3 * KINE_TERRAIN_MC_LATT3)      // 14739
#define KINE_TERRAIN_MC_CELL_COUNT (KINE_TERRAIN_MC_CHUNK * KINE_TERRAIN_MC_CHUNK * KINE_TERRAIN_MC_CHUNK)
#define KINE_TERRAIN_MC_LOCAL_SIZE 64

struct KineTerrainMc {
    VkDevice device;
    VkPhysicalDevice physical_device;
    VkQueue queue;
    uint32_t queue_family;

    VkCommandPool command_pool;
    VkCommandBuffer command_buffer;
    VkFence fence;

    VkDescriptorSetLayout set_layout;
    VkPipelineLayout pipeline_layout;
    VkPipeline pipeline;
    VkDescriptorPool descriptor_pool;
    VkDescriptorSet descriptor_set;

    VkBuffer occ_buf;
    VkBuffer mat_buf;
    VkBuffer edge_buf;
    VkBuffer vert_buf;
    VkBuffer weight_buf;
    VkBuffer index_buf;
    VkBuffer counter_buf;

    VkDeviceMemory occ_mem;
    VkDeviceMemory mat_mem;
    VkDeviceMemory edge_mem;
    VkDeviceMemory vert_mem;
    VkDeviceMemory weight_mem;
    VkDeviceMemory index_mem;
    VkDeviceMemory counter_mem;

    float* occ_map;
    uint32_t* mat_map;
    uint32_t* edge_map;
    float* vert_map;
    float* weight_map;
    uint32_t* index_map;
    uint32_t* counter_map;
};

static int terrain_mc_error(char* err, uint32_t cap, const char* fmt, ...) {
    if (err && cap > 0) {
        va_list args;
        va_start(args, fmt);
        vsnprintf(err, cap, fmt, args);
        va_end(args);
    }
    return 0;
}

static uint32_t terrain_mc_groups(uint32_t threads) {
    return (threads + KINE_TERRAIN_MC_LOCAL_SIZE - 1) / KINE_TERRAIN_MC_LOCAL_SIZE;
}

static int terrain_mc_find_memory(VkPhysicalDevice pd, uint32_t type_bits, VkMemoryPropertyFlags want, uint32_t* out) {
    VkPhysicalDeviceMemoryProperties props;
    vkGetPhysicalDeviceMemoryProperties(pd, &props);
    for (uint32_t i = 0; i < props.memoryTypeCount; ++i) {
        if ((type_bits & (1u << i)) && (props.memoryTypes[i].propertyFlags & want) == want) {
            *out = i;
            return 1;
        }
    }
    return 0;
}

static VkResult terrain_mc_make_buffer(
    KineTerrainMc* mc, VkDeviceSize size, VkBuffer* buf, VkDeviceMemory* mem, void** map) {
    VkBufferCreateInfo bi = {};
    bi.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    bi.size = size;
    bi.usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT;
    bi.sharingMode = VK_SHARING_MODE_EXCLUSIVE;

    VkResult r = vkCreateBuffer(mc->device, &bi, NULL, buf);
    if (r != VK_SUCCESS) {
        return r;
    }

    VkMemoryRequirements req;
    vkGetBufferMemoryRequirements(mc->device, *buf, &req);

    uint32_t type_index = 0;
    if (!terrain_mc_find_memory(
            mc->physical_device, req.memoryTypeBits,
            VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, &type_index)) {
        return VK_ERROR_FEATURE_NOT_PRESENT;
    }

    VkMemoryAllocateInfo ai = {};
    ai.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    ai.allocationSize = req.size;
    ai.memoryTypeIndex = type_index;
    r = vkAllocateMemory(mc->device, &ai, NULL, mem);
    if (r != VK_SUCCESS) {
        return r;
    }
    r = vkBindBufferMemory(mc->device, *buf, *mem, 0);
    if (r != VK_SUCCESS) {
        return r;
    }
    r = vkMapMemory(mc->device, *mem, 0, VK_WHOLE_SIZE, 0, map);
    return r;
}

static int terrain_mc_build_pipeline(KineTerrainMc* mc, char* err, uint32_t err_cap) {
    VkDescriptorSetLayoutBinding bindings[7];
    memset(bindings, 0, sizeof(bindings));
    for (int i = 0; i < 7; ++i) {
        bindings[i].binding = (uint32_t)i;
        bindings[i].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
        bindings[i].descriptorCount = 1;
        bindings[i].stageFlags = VK_SHADER_STAGE_COMPUTE_BIT;
    }

    VkDescriptorSetLayoutCreateInfo sl = {};
    sl.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
    sl.bindingCount = 7;
    sl.pBindings = bindings;
    if (vkCreateDescriptorSetLayout(mc->device, &sl, NULL, &mc->set_layout) != VK_SUCCESS) {
        return terrain_mc_error(err, err_cap, "descriptor set layout creation failed");
    }

    VkPushConstantRange push = {};
    push.stageFlags = VK_SHADER_STAGE_COMPUTE_BIT;
    push.offset = 0;
    push.size = 32; // ivec4 origin_pass + vec4 params

    VkPipelineLayoutCreateInfo pl = {};
    pl.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
    pl.setLayoutCount = 1;
    pl.pSetLayouts = &mc->set_layout;
    pl.pushConstantRangeCount = 1;
    pl.pPushConstantRanges = &push;
    if (vkCreatePipelineLayout(mc->device, &pl, NULL, &mc->pipeline_layout) != VK_SUCCESS) {
        return terrain_mc_error(err, err_cap, "pipeline layout creation failed");
    }

    VkShaderModuleCreateInfo smi = {};
    smi.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
    smi.codeSize = sizeof(kine_terrain_mc_spv);
    smi.pCode = kine_terrain_mc_spv;
    VkShaderModule module = VK_NULL_HANDLE;
    if (vkCreateShaderModule(mc->device, &smi, NULL, &module) != VK_SUCCESS) {
        return terrain_mc_error(err, err_cap, "shader module creation failed");
    }

    VkPipelineShaderStageCreateInfo stage = {};
    stage.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    stage.stage = VK_SHADER_STAGE_COMPUTE_BIT;
    stage.module = module;
    stage.pName = "main";

    VkComputePipelineCreateInfo cp = {};
    cp.sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO;
    cp.stage = stage;
    cp.layout = mc->pipeline_layout;

    VkResult r = vkCreateComputePipelines(mc->device, VK_NULL_HANDLE, 1, &cp, NULL, &mc->pipeline);
    vkDestroyShaderModule(mc->device, module, NULL);
    if (r != VK_SUCCESS) {
        return terrain_mc_error(err, err_cap, "compute pipeline creation failed");
    }

    VkDescriptorPoolSize pool_size = {};
    pool_size.type = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
    pool_size.descriptorCount = 7;

    VkDescriptorPoolCreateInfo dp = {};
    dp.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
    dp.maxSets = 1;
    dp.poolSizeCount = 1;
    dp.pPoolSizes = &pool_size;
    if (vkCreateDescriptorPool(mc->device, &dp, NULL, &mc->descriptor_pool) != VK_SUCCESS) {
        return terrain_mc_error(err, err_cap, "descriptor pool creation failed");
    }

    VkDescriptorSetAllocateInfo ai = {};
    ai.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
    ai.descriptorPool = mc->descriptor_pool;
    ai.descriptorSetCount = 1;
    ai.pSetLayouts = &mc->set_layout;
    if (vkAllocateDescriptorSets(mc->device, &ai, &mc->descriptor_set) != VK_SUCCESS) {
        return terrain_mc_error(err, err_cap, "descriptor set allocation failed");
    }

    VkDescriptorBufferInfo infos[7];
    VkBuffer bufs[7] = {mc->occ_buf,   mc->mat_buf, mc->edge_buf, mc->vert_buf,
                        mc->weight_buf, mc->index_buf, mc->counter_buf};
    for (int i = 0; i < 7; ++i) {
        infos[i].buffer = bufs[i];
        infos[i].offset = 0;
        infos[i].range = VK_WHOLE_SIZE;
    }

    VkWriteDescriptorSet writes[7];
    memset(writes, 0, sizeof(writes));
    for (int i = 0; i < 7; ++i) {
        writes[i].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
        writes[i].dstSet = mc->descriptor_set;
        writes[i].dstBinding = (uint32_t)i;
        writes[i].descriptorCount = 1;
        writes[i].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
        writes[i].pBufferInfo = &infos[i];
    }
    vkUpdateDescriptorSets(mc->device, 7, writes, 0, NULL);
    return 1;
}

KineTerrainMc* Kine_TerrainMc_Create(
    void* instance,
    void* physical_device,
    void* device,
    void* queue,
    uint32_t queue_family_index,
    char* err,
    uint32_t err_cap) {
    (void)instance;

    if (!physical_device || !device || !queue) {
        terrain_mc_error(err, err_cap, "null Vulkan handle");
        return NULL;
    }

    KineTerrainMc* mc = (KineTerrainMc*)calloc(1, sizeof(KineTerrainMc));
    if (!mc) {
        terrain_mc_error(err, err_cap, "out of memory");
        return NULL;
    }
    mc->device = (VkDevice)device;
    mc->physical_device = (VkPhysicalDevice)physical_device;
    mc->queue = (VkQueue)queue;
    mc->queue_family = queue_family_index;

    VkCommandPoolCreateInfo cp = {};
    cp.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
    cp.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    cp.queueFamilyIndex = queue_family_index;
    if (vkCreateCommandPool(mc->device, &cp, NULL, &mc->command_pool) != VK_SUCCESS) {
        terrain_mc_error(err, err_cap, "command pool creation failed");
        Kine_TerrainMc_Destroy(mc);
        return NULL;
    }

    VkCommandBufferAllocateInfo cb = {};
    cb.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    cb.commandPool = mc->command_pool;
    cb.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    cb.commandBufferCount = 1;
    if (vkAllocateCommandBuffers(mc->device, &cb, &mc->command_buffer) != VK_SUCCESS) {
        terrain_mc_error(err, err_cap, "command buffer allocation failed");
        Kine_TerrainMc_Destroy(mc);
        return NULL;
    }

    VkFenceCreateInfo fi = {};
    fi.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
    if (vkCreateFence(mc->device, &fi, NULL, &mc->fence) != VK_SUCCESS) {
        terrain_mc_error(err, err_cap, "fence creation failed");
        Kine_TerrainMc_Destroy(mc);
        return NULL;
    }

    struct {
        VkDeviceSize size;
        VkBuffer* buf;
        VkDeviceMemory* mem;
        void** map;
    } allocs[] = {
        {(VkDeviceSize)KINE_TERRAIN_MC_CACHE_CELLS * sizeof(float), &mc->occ_buf, &mc->occ_mem, (void**)&mc->occ_map},
        {(VkDeviceSize)KINE_TERRAIN_MC_CACHE_CELLS * sizeof(uint32_t), &mc->mat_buf, &mc->mat_mem, (void**)&mc->mat_map},
        {(VkDeviceSize)KINE_TERRAIN_MC_EDGE_COUNT * sizeof(uint32_t), &mc->edge_buf, &mc->edge_mem, (void**)&mc->edge_map},
        {(VkDeviceSize)KINE_TERRAIN_MC_MAX_VERTICES * 8 * sizeof(float), &mc->vert_buf, &mc->vert_mem, (void**)&mc->vert_map},
        {(VkDeviceSize)KINE_TERRAIN_MC_MAX_VERTICES * 8 * sizeof(float), &mc->weight_buf, &mc->weight_mem, (void**)&mc->weight_map},
        {(VkDeviceSize)KINE_TERRAIN_MC_MAX_INDICES * sizeof(uint32_t), &mc->index_buf, &mc->index_mem, (void**)&mc->index_map},
        {(VkDeviceSize)2 * sizeof(uint32_t), &mc->counter_buf, &mc->counter_mem, (void**)&mc->counter_map},
    };
    for (size_t i = 0; i < sizeof(allocs) / sizeof(allocs[0]); ++i) {
        VkResult r = terrain_mc_make_buffer(mc, allocs[i].size, allocs[i].buf, allocs[i].mem, allocs[i].map);
        if (r != VK_SUCCESS) {
            terrain_mc_error(err, err_cap, "buffer allocation failed (0x%x)", (unsigned)r);
            Kine_TerrainMc_Destroy(mc);
            return NULL;
        }
    }

    if (!terrain_mc_build_pipeline(mc, err, err_cap)) {
        Kine_TerrainMc_Destroy(mc);
        return NULL;
    }
    return mc;
}

void Kine_TerrainMc_Destroy(KineTerrainMc* mc) {
    if (!mc) {
        return;
    }
    if (mc->device) {
        if (mc->pipeline) vkDestroyPipeline(mc->device, mc->pipeline, NULL);
        if (mc->pipeline_layout) vkDestroyPipelineLayout(mc->device, mc->pipeline_layout, NULL);
        if (mc->descriptor_pool) vkDestroyDescriptorPool(mc->device, mc->descriptor_pool, NULL);
        if (mc->set_layout) vkDestroyDescriptorSetLayout(mc->device, mc->set_layout, NULL);

        struct { VkBuffer buf; VkDeviceMemory mem; void* map; } res[] = {
            {mc->occ_buf, mc->occ_mem, mc->occ_map},
            {mc->mat_buf, mc->mat_mem, mc->mat_map},
            {mc->edge_buf, mc->edge_mem, mc->edge_map},
            {mc->vert_buf, mc->vert_mem, mc->vert_map},
            {mc->weight_buf, mc->weight_mem, mc->weight_map},
            {mc->index_buf, mc->index_mem, mc->index_map},
            {mc->counter_buf, mc->counter_mem, mc->counter_map},
        };
        for (size_t i = 0; i < sizeof(res) / sizeof(res[0]); ++i) {
            if (res[i].map) vkUnmapMemory(mc->device, res[i].mem);
            if (res[i].buf) vkDestroyBuffer(mc->device, res[i].buf, NULL);
            if (res[i].mem) vkFreeMemory(mc->device, res[i].mem, NULL);
        }
        if (mc->fence) vkDestroyFence(mc->device, mc->fence, NULL);
        if (mc->command_pool) vkDestroyCommandPool(mc->device, mc->command_pool, NULL);
    }
    free(mc);
}

int Kine_TerrainMc_Mesh(
    KineTerrainMc* mc,
    const float* occ,
    const uint32_t* mat,
    int origin_x,
    int origin_y,
    int origin_z,
    float voxel_size,
    float iso_level,
    float* out_verts,
    float* out_weights,
    uint32_t* out_indices,
    uint32_t vert_capacity,
    uint32_t index_capacity,
    uint32_t* out_vert_count,
    uint32_t* out_index_count,
    char* err,
    uint32_t err_cap) {
    if (!mc || !occ || !mat) {
        return terrain_mc_error(err, err_cap, "null argument");
    }

    memcpy(mc->occ_map, occ, (size_t)KINE_TERRAIN_MC_CACHE_CELLS * sizeof(float));
    memcpy(mc->mat_map, mat, (size_t)KINE_TERRAIN_MC_CACHE_CELLS * sizeof(uint32_t));
    mc->counter_map[0] = 0;
    mc->counter_map[1] = 0;

    vkResetCommandBuffer(mc->command_buffer, 0);

    VkCommandBufferBeginInfo bi = {};
    bi.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    bi.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    if (vkBeginCommandBuffer(mc->command_buffer, &bi) != VK_SUCCESS) {
        return terrain_mc_error(err, err_cap, "begin command buffer failed");
    }

    VkCommandBuffer cb = mc->command_buffer;
    vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_COMPUTE, mc->pipeline);
    vkCmdBindDescriptorSets(cb, VK_PIPELINE_BIND_POINT_COMPUTE, mc->pipeline_layout, 0, 1, &mc->descriptor_set, 0, NULL);

    struct {
        int32_t origin[3];
        int32_t pass;
        float voxel;
        float iso;
        float pad0;
        float pad1;
    } push;

    push.origin[0] = origin_x;
    push.origin[1] = origin_y;
    push.origin[2] = origin_z;
    push.pass = 1;
    push.voxel = voxel_size;
    push.iso = iso_level;
    push.pad0 = 0.0f;
    push.pad1 = 0.0f;
    vkCmdPushConstants(cb, mc->pipeline_layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(push), &push);
    vkCmdDispatch(cb, terrain_mc_groups(KINE_TERRAIN_MC_EDGE_COUNT), 1, 1);

    VkMemoryBarrier barrier = {};
    barrier.sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER;
    barrier.srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT;
    barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT | VK_ACCESS_SHADER_WRITE_BIT;
    vkCmdPipelineBarrier(
        cb, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0, 1, &barrier, 0, NULL, 0, NULL);

    push.pass = 0;
    vkCmdPushConstants(cb, mc->pipeline_layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(push), &push);
    vkCmdDispatch(cb, terrain_mc_groups(KINE_TERRAIN_MC_CELL_COUNT), 1, 1);

    if (vkEndCommandBuffer(cb) != VK_SUCCESS) {
        return terrain_mc_error(err, err_cap, "end command buffer failed");
    }

    vkResetFences(mc->device, 1, &mc->fence);

    VkSubmitInfo si = {};
    si.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    si.commandBufferCount = 1;
    si.pCommandBuffers = &cb;
    if (vkQueueSubmit(mc->queue, 1, &si, mc->fence) != VK_SUCCESS) {
        return terrain_mc_error(err, err_cap, "queue submit failed");
    }
    if (vkWaitForFences(mc->device, 1, &mc->fence, VK_TRUE, UINT64_MAX) != VK_SUCCESS) {
        return terrain_mc_error(err, err_cap, "fence wait failed");
    }

    uint32_t vert_count = mc->counter_map[0];
    uint32_t index_count = mc->counter_map[1];

    if (vert_count > KINE_TERRAIN_MC_MAX_VERTICES || index_count > KINE_TERRAIN_MC_MAX_INDICES) {
        return terrain_mc_error(err, err_cap, "shader overran output bounds (%u verts, %u indices)", vert_count, index_count);
    }
    if (vert_count > vert_capacity || index_count > index_capacity) {
        return terrain_mc_error(
            err, err_cap, "output capacity too small (need %u verts / %u indices)", vert_count, index_count);
    }

    if (vert_count > 0) {
        memcpy(out_verts, mc->vert_map, (size_t)vert_count * 8 * sizeof(float));
        memcpy(out_weights, mc->weight_map, (size_t)vert_count * 8 * sizeof(float));
    }
    if (index_count > 0) {
        memcpy(out_indices, mc->index_map, (size_t)index_count * sizeof(uint32_t));
    }

    if (out_vert_count) *out_vert_count = vert_count;
    if (out_index_count) *out_index_count = index_count;
    return 1;
}
