// GPU terrain marching-cubes mesher.
//
// Meshes one terrain chunk on the compositor's Vulkan device using the compute
// shader in kine_terrain_mc.comp (generated as kine_terrain_mc.comp from the
// template + the Odin triangle table). The output feeds
// Kine_Filament_CreateTerrainMesh directly.
//
// The module deliberately depends on nothing but Vulkan so it can be built and
// tested headless, without a window or a compositor.
#ifndef KINE_TERRAIN_MC_H
#define KINE_TERRAIN_MC_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// 16 + 1 + 2 * 2 = 21, matching Terrain.odin TERRAIN_CACHE_DIM.
#define KINE_TERRAIN_MC_CACHE_DIM 21
#define KINE_TERRAIN_MC_CACHE_CELLS (KINE_TERRAIN_MC_CACHE_DIM * KINE_TERRAIN_MC_CACHE_DIM * KINE_TERRAIN_MC_CACHE_DIM)
// 3 * 17^3 = 14739, the direct-mapped edge-vertex slots per chunk.
#define KINE_TERRAIN_MC_MAX_VERTICES 14739
// 16^3 cells * 5 triangles * 3 indices.
#define KINE_TERRAIN_MC_MAX_INDICES 61440

typedef struct KineTerrainMc KineTerrainMc;

// Creates a mesher bound to an existing device/queue. instance/device/queue are
// VkInstance/VkDevice/VkQueue handles (passed as void* to keep this header free
// of vulkan.h). Returns NULL on failure; if err is non-NULL a message is copied
// into it.
KineTerrainMc* Kine_TerrainMc_Create(
    void* instance,
    void* physical_device,
    void* device,
    void* queue,
    uint32_t queue_family_index,
    char* err,
    uint32_t err_cap);

void Kine_TerrainMc_Destroy(KineTerrainMc* mc);

// Meshes the chunk whose lattice origin is (origin_x, origin_y, origin_z).
// occ/mat are the chunk density cache, laid out as CACHE_DIM^3 with the last
// axis fastest: index = (x * CACHE_DIM + y) * CACHE_DIM + z. occ holds
// occupancy in 0..1, mat holds the material layer in 0..5.
//
// Outputs are written to out_verts (8 floats per vertex: position, normal, uv),
// out_weights (8 floats per vertex, the terrain material weights) and
// out_indices (three uint32 per triangle). Capacity is checked before copying;
// on overflow the function fails without writing past the buffers.
//
// Returns 1 on success, 0 on failure (error copied into err if non-NULL).
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
    uint32_t err_cap);

#ifdef __cplusplus
}
#endif

#endif // KINE_TERRAIN_MC_H
