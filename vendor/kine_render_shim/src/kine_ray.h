#ifndef KINE_RAY_H
#define KINE_RAY_H

// Internal bridge between kine_filament_shim.cpp (which owns the Filament
// context and its Vulkan device) and kine_ray_shim.cpp (which owns the Ray path
// tracer). Both headers are deliberately free of Filament and Ray includes so
// the two translation units stay independent: Ray's VulkanFunctions.h declares
// its own Vulkan handle types and must not meet backend/platforms/VulkanPlatform.h.

#include <stdint.h>

#include "kine_filament_shim.h" // KineRayProperties

struct KineRayDevice {
	void *instance;		 // VkInstance (owned by Filament / the compositor)
	void *physicalDevice;	 // VkPhysicalDevice
	void *device;		 // VkDevice (shared with Filament and Skia)
	void *getInstanceProcAddr; // PFN_vkGetInstanceProcAddr
	uint32_t graphicsQueueFamilyIndex;
	uint32_t graphicsQueueCount;
};

// A texture handed to Ray as CPU RGBA8 texels. The bytes stay owned by the
// Filament side; Ray copies whatever it needs while the scene is built.
struct KineRayTexture {
	const uint8_t *pixels = nullptr;
	int width = 0;
	int height = 0;

	bool valid() const { return pixels != nullptr && width > 0 && height > 0; }
};

// One queued mesh instance. The vertex data is KineMesh's CPU copy: interleaved
// position(3), normal(3), uv(2) floats.
struct KineRayDraw {
	const void *meshKey;
	const void *shaderKey;
	const float *vertexData;
	int vertexStrideFloats;
	int vertexCount;
	const uint32_t *indices;
	int indexCount;
	const float *xform; // row-major float[16]
	float color[3];
	int materialKind;
	// The batch key's material parameters, so the path tracer can build the same
	// surface kine_apply_material_params() gives the raster pass.
	float param1 = 0.0f;
	float param2 = 0.0f;
	float param3 = 0.0f;
	float transmission = 0.0f;
	// Per-instance UV tiling. Filament applies this as instanceUvScale; Ray has
	// no UV transform, so it is baked into the vertex data instead.
	float uvScale = 1.0f;
	KineRayTexture baseColor;
	KineRayTexture normalMap;
};

// A point or spot light as Filament reports it; the unit conversion into Ray's
// own scale happens on the Ray side, next to the sun's.
struct KineRayLight {
	int type = 0; // 0 = point, 1 = spot
	float position[3] = {};
	float direction[3] = {}; // spots only
	float color[3] = {};     // linear sRGB
	float intensity = 0.0f;  // Filament candela
	float innerConeRadians = 0.0f;
	float outerConeRadians = 0.0f;
	// Mirrors the Light.Shadows toggle. Filament defaults it off, so a light
	// that does not shadow in the raster viewport must not shadow here either.
	bool castShadow = true;
};

struct KineRayCamera {
	float origin[3];
	float forward[3];
	float up[3];
	float fovYDegrees;
	float clipStart;
	float clipEnd;
};

struct KineRayFrame {
	int width;
	int height;
	KineRayCamera camera;
	const KineRayDraw *draws;
	int drawCount;
	float sunTowards[3]; // unit vector pointing towards the sun
	float sunColor[3];
	float sunIntensity; // Filament lux
	float skyColor[3];
	const KineRayLight *lights = nullptr;
	int lightCount = 0;
};

struct KineRayState;

KineRayProperties kine_ray_default_properties();
// Pins every field into its documented range.
KineRayProperties kine_ray_sanitize_properties(const KineRayProperties &properties);

// Creates a Ray Vulkan renderer on the given (already existing) device.
KineRayState *kine_ray_create(const KineRayDevice &device, int width, int height);
void kine_ray_destroy(KineRayState *state);

// Applies path tracer settings; restarts accumulation and re-sends the camera so
// depth/exposure changes take effect immediately.
bool kine_ray_set_properties(KineRayState *state, const KineRayProperties &properties);

// Synchronizes the scene to frame, traces a single sample and refreshes the
// RGBA8 image returned by kine_ray_pixels().
bool kine_ray_render(KineRayState *state, const KineRayFrame &frame);

const uint8_t *kine_ray_pixels(const KineRayState *state);
int kine_ray_sample_count(const KineRayState *state);
const char *kine_ray_last_error();

#endif // KINE_RAY_H
