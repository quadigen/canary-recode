// Headless correctness test for the GPU terrain mesher.
//
// Creates a bare Vulkan compute device (no window, no compositor), meshes a
// voxel sphere, and checks the result is a valid, watertight, plausibly-shaped
// mesh. Run via the kine_terrain_mc_test target.
//
//   kine_terrain_mc_test
//
// Exit code 0 on success.

#include "kine_terrain_mc.h"

#include <vulkan/vulkan.h>

#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <unordered_map>
#include <vector>

#define CHECK(cond, ...)                         \
    do {                                         \
        if (!(cond)) {                           \
            std::printf("FAIL: " __VA_ARGS__);   \
            std::printf("\n");                   \
            return 1;                            \
        }                                        \
    } while (0)

static int g_failures = 0;

static void expect(bool cond, const char* msg) {
    if (!cond) {
        ++g_failures;
        if (g_failures <= 8) {
            std::printf("CHECK FAILED: %s\n", msg);
        }
    }
}

struct Device {
    VkInstance instance = VK_NULL_HANDLE;
    VkPhysicalDevice physical = VK_NULL_HANDLE;
    VkDevice device = VK_NULL_HANDLE;
    VkQueue queue = VK_NULL_HANDLE;
    uint32_t queue_family = 0;
};

static int create_device(Device& out) {
    VkApplicationInfo app = {0};
    app.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    app.pApplicationName = "kine_terrain_mc_test";
    app.apiVersion = VK_API_VERSION_1_2;

    VkInstanceCreateInfo ci = {0};
    ci.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    ci.pApplicationInfo = &app;
    if (vkCreateInstance(&ci, NULL, &out.instance) != VK_SUCCESS) {
        std::printf("FAIL: vkCreateInstance\n");
        return 0;
    }

    uint32_t count = 0;
    vkEnumeratePhysicalDevices(out.instance, &count, NULL);
    if (count == 0) {
        std::printf("FAIL: no Vulkan physical devices\n");
        return 0;
    }
    std::vector<VkPhysicalDevice> devices(count);
    vkEnumeratePhysicalDevices(out.instance, &count, devices.data());

    for (VkPhysicalDevice pd : devices) {
        uint32_t family_count = 0;
        vkGetPhysicalDeviceQueueFamilyProperties(pd, &family_count, NULL);
        std::vector<VkQueueFamilyProperties> families(family_count);
        vkGetPhysicalDeviceQueueFamilyProperties(pd, &family_count, families.data());
        for (uint32_t i = 0; i < family_count; ++i) {
            if (families[i].queueFlags & VK_QUEUE_COMPUTE_BIT) {
                out.physical = pd;
                out.queue_family = i;
                break;
            }
        }
        if (out.physical) {
            break;
        }
    }
    if (!out.physical) {
        std::printf("FAIL: no compute-capable queue family\n");
        return 0;
    }

    VkPhysicalDeviceProperties props;
    vkGetPhysicalDeviceProperties(out.physical, &props);
    std::printf("device: %s\n", props.deviceName);

    float priority = 1.0f;
    VkDeviceQueueCreateInfo qci = {0};
    qci.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
    qci.queueFamilyIndex = out.queue_family;
    qci.queueCount = 1;
    qci.pQueuePriorities = &priority;

    VkDeviceCreateInfo dci = {0};
    dci.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
    dci.queueCreateInfoCount = 1;
    dci.pQueueCreateInfos = &qci;
    if (vkCreateDevice(out.physical, &dci, NULL, &out.device) != VK_SUCCESS) {
        std::printf("FAIL: vkCreateDevice\n");
        return 0;
    }
    vkGetDeviceQueue(out.device, out.queue_family, 0, &out.queue);
    return 1;
}

static void destroy_device(Device& d) {
    if (d.device) vkDestroyDevice(d.device, NULL);
    if (d.instance) vkDestroyInstance(d.instance, NULL);
}

static int cache_index(int x, int y, int z) {
    return (x * KINE_TERRAIN_MC_CACHE_DIM + y) * KINE_TERRAIN_MC_CACHE_DIM + z;
}

// Voxel sphere: occupancy ramps linearly through the iso level at radius r, so
// the isosurface should sit on the sphere to within interpolation error.
static void build_sphere(
    float* occ, uint32_t* mat, float center[3], float radius, int origin[3]) {
    const int dim = KINE_TERRAIN_MC_CACHE_DIM;
    const int pad = 2;
    center[0] = 8.0f;
    center[1] = 7.7f; // off-axis centre catches edge-ordering mistakes
    center[2] = 8.3f;
    radius = 5.0f;
    for (int x = 0; x < dim; ++x) {
        for (int y = 0; y < dim; ++y) {
            for (int z = 0; z < dim; ++z) {
                float vx = (float)(origin[0] - pad + x);
                float vy = (float)(origin[1] - pad + y);
                float vz = (float)(origin[2] - pad + z);
                float dx = vx - center[0];
                float dy = vy - center[1];
                float dz = vz - center[2];
                float dist = std::sqrt(dx * dx + dy * dy + dz * dz);
                float o = 0.5f + (radius - dist);
                if (o < 0.0f) o = 0.0f;
                if (o > 1.0f) o = 1.0f;
                int idx = cache_index(x, y, z);
                occ[idx] = o;
                mat[idx] = (uint32_t)(((x + y + z) % 6));
            }
        }
    }
}

static int validate_watertight(const uint32_t* indices, uint32_t count) {
    std::unordered_map<uint64_t, int> edges;
    for (uint32_t i = 0; i + 2 < count; i += 3) {
        uint32_t tri[3] = {indices[i], indices[i + 1], indices[i + 2]};
        for (int e = 0; e < 3; ++e) {
            uint32_t a = tri[e];
            uint32_t b = tri[(e + 1) % 3];
            uint64_t key = a < b ? ((uint64_t)a << 32) | b : ((uint64_t)b << 32) | a;
            edges[key] += 1;
        }
    }
    int bad = 0;
    for (auto& kv : edges) {
        if (kv.second != 2) {
            ++bad;
        }
    }
    std::printf("edges: %zu (non-manifold/boundary: %d)\n", edges.size(), bad);
    return bad;
}

int main() {
    Device dev;
    if (!create_device(dev)) {
        destroy_device(dev);
        return 1;
    }

    char err[512] = {0};
    KineTerrainMc* mc = Kine_TerrainMc_Create(
        dev.instance, dev.physical, dev.device, dev.queue, dev.queue_family, err, sizeof(err));
    CHECK(mc != NULL, "mesher create: %s", err);

    const int dim = KINE_TERRAIN_MC_CACHE_DIM;
    std::vector<float> occ((size_t)dim * dim * dim);
    std::vector<uint32_t> mat((size_t)dim * dim * dim);
    std::vector<float> verts((size_t)KINE_TERRAIN_MC_MAX_VERTICES * 8);
    std::vector<float> weights((size_t)KINE_TERRAIN_MC_MAX_VERTICES * 8);
    std::vector<uint32_t> indices(KINE_TERRAIN_MC_MAX_INDICES);

    int origin[3] = {0, 0, 0};
    float center[3];
    float radius = 5.0f;
    build_sphere(occ.data(), mat.data(), center, radius, origin);

    uint32_t vcount = 0;
    uint32_t icount = 0;
    int ok = Kine_TerrainMc_Mesh(
        mc, occ.data(), mat.data(), origin[0], origin[1], origin[2], 1.0f, 0.5f, verts.data(),
        weights.data(), indices.data(), KINE_TERRAIN_MC_MAX_VERTICES, KINE_TERRAIN_MC_MAX_INDICES,
        &vcount, &icount, err, sizeof(err));
    CHECK(ok, "mesh: %s", err);

    std::printf("vertices: %u indices: %u triangles: %u\n", vcount, icount, icount / 3);
    expect(vcount > 100, "expected a non-trivial vertex count");
    expect(icount % 3 == 0, "index count must be a multiple of 3");
    expect(icount / 3 > 100, "expected a non-trivial triangle count");

    float max_radius_error = 0.0f;
    for (uint32_t i = 0; i < vcount; ++i) {
        const float* v = &verts[(size_t)i * 8];
        float dx = v[0] - center[0];
        float dy = v[1] - center[1];
        float dz = v[2] - center[2];
        float dist = std::sqrt(dx * dx + dy * dy + dz * dz);
        float re = std::fabs(dist - radius);
        if (re > max_radius_error) max_radius_error = re;

        float nl = std::sqrt(v[3] * v[3] + v[4] * v[4] + v[5] * v[5]);
        expect(std::isfinite(v[0]) && std::isfinite(v[1]) && std::isfinite(v[2]), "finite position");
        expect(std::fabs(nl - 1.0f) < 1.0e-3f, "unit normal");

        const float* w = &weights[(size_t)i * 8];
        float sum = 0.0f;
        for (int k = 0; k < 8; ++k) {
            expect(w[k] >= -1.0e-4f, "non-negative weight");
            sum += w[k];
        }
        expect(std::fabs(sum - 1.0f) < 1.0e-3f, "weights sum to one");
    }
    std::printf("max radius error: %.4f (radius %.2f)\n", max_radius_error, radius);
    expect(max_radius_error < 0.3f, "isosurface should track the sphere");

    for (uint32_t i = 0; i < icount; ++i) {
        expect(indices[i] < vcount, "index in range");
    }
    int bad_edges = validate_watertight(indices.data(), icount);
    expect(bad_edges == 0, "mesh must be watertight");

    // Empty and full chunks must produce no geometry.
    std::vector<float> empty_occ(occ.size(), 0.0f);
    uint32_t e_vc = 123, e_ic = 123;
    ok = Kine_TerrainMc_Mesh(
        mc, empty_occ.data(), mat.data(), 0, 0, 0, 1.0f, 0.5f, verts.data(), weights.data(),
        indices.data(), KINE_TERRAIN_MC_MAX_VERTICES, KINE_TERRAIN_MC_MAX_INDICES, &e_vc, &e_ic, err,
        sizeof(err));
    CHECK(ok, "empty mesh: %s", err);
    expect(e_vc == 0 && e_ic == 0, "empty chunk has no geometry");

    std::vector<float> full_occ(occ.size(), 1.0f);
    e_vc = 123;
    e_ic = 123;
    ok = Kine_TerrainMc_Mesh(
        mc, full_occ.data(), mat.data(), 0, 0, 0, 1.0f, 0.5f, verts.data(), weights.data(),
        indices.data(), KINE_TERRAIN_MC_MAX_VERTICES, KINE_TERRAIN_MC_MAX_INDICES, &e_vc, &e_ic, err,
        sizeof(err));
    CHECK(ok, "full mesh: %s", err);
    expect(e_vc == 0 && e_ic == 0, "full chunk has no geometry");

    // Undersized output buffers must be rejected without crashing.
    uint32_t small_vc = 0, small_ic = 0;
    ok = Kine_TerrainMc_Mesh(
        mc, occ.data(), mat.data(), 0, 0, 0, 1.0f, 0.5f, verts.data(), weights.data(), indices.data(),
        1, 1, &small_vc, &small_ic, err, sizeof(err));
    expect(ok == 0, "undersized output must be rejected");

    Kine_TerrainMc_Destroy(mc);
    destroy_device(dev);

    if (g_failures == 0) {
        std::printf("PASS\n");
        return 0;
    }
    std::printf("FAILED: %d checks\n", g_failures);
    return 1;
}
