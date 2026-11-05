// Ray path tracer, running on the Vulkan device Filament already owns.
//
// Ray never creates an instance or a device when `settings_t::vk_device` and
// `settings_t::vk_functions` are filled: it only submits work to the handles it
// is given. That is what `Kine_Filament_GetVulkanBackend` exposes, and it is the
// same VkDevice Skia and the compositor render on.
//
// This translation unit deliberately does not include vulkan.h: Ray's
// VulkanFunctions.h declares its own handle types and function pointers, and the
// two headers are only compatible through the reinterpret_cast boundary below.

#include "kine_ray.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <memory>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

#include <Ray/Ray.h>

namespace {

std::string g_error;

// Draw-less frames are tolerated for this long before the scene is rebuilt as
// genuinely empty, so a skipped 3D pass cannot blank the viewport.
constexpr int kine_max_empty_frames = 30;

uint64_t kine_hash_bytes(uint64_t hash, const void *data, size_t size) {
	const unsigned char *bytes = static_cast<const unsigned char *>(data);
	for (size_t i = 0; i < size; ++i) {
		hash ^= bytes[i];
		hash *= 1099511628211ull;
	}
	return hash;
}

// The structure hash covers which meshes/materials take part in the scene, the
// transform hash covers where they are. Keeping them apart matters: a moving
// object must only update its instance matrix, because the alternative -- any
// movement forcing a full scene rebuild -- tears down and re-uploads every BVH
// on every frame and restarts the accumulation.
uint64_t kine_hash_draws(const KineRayFrame &frame, bool structure) {
	uint64_t hash = 1469598103934665603ull;
	for (int i = 0; i < frame.drawCount; ++i) {
		const KineRayDraw &draw = frame.draws[i];
		if (structure) {
			hash = kine_hash_bytes(hash, &draw.meshKey, sizeof(draw.meshKey));
			hash = kine_hash_bytes(hash, &draw.shaderKey, sizeof(draw.shaderKey));
			hash = kine_hash_bytes(hash, draw.color, sizeof(draw.color));
			hash = kine_hash_bytes(hash, &draw.materialKind, sizeof(draw.materialKind));
			hash = kine_hash_bytes(hash, &draw.vertexCount, sizeof(draw.vertexCount));
			hash = kine_hash_bytes(hash, &draw.indexCount, sizeof(draw.indexCount));
			// Material identity too: a roughness, metallic, IOR or texture change
			// must rebuild the scene, or Ray would keep tracing the old surface.
			hash = kine_hash_bytes(hash, &draw.param1, sizeof(draw.param1));
			hash = kine_hash_bytes(hash, &draw.param2, sizeof(draw.param2));
			hash = kine_hash_bytes(hash, &draw.param3, sizeof(draw.param3));
			hash = kine_hash_bytes(hash, &draw.transmission, sizeof(draw.transmission));
			hash = kine_hash_bytes(hash, &draw.uvScale, sizeof(draw.uvScale));
			hash = kine_hash_bytes(hash, &draw.baseColor.pixels, sizeof(draw.baseColor.pixels));
			hash = kine_hash_bytes(hash, &draw.normalMap.pixels, sizeof(draw.normalMap.pixels));
		} else {
			hash = kine_hash_bytes(hash, draw.xform, sizeof(float) * 16);
		}
	}
	return hash;
}

uint64_t kine_hash_camera(const KineRayCamera &camera) {
	uint64_t hash = 1469598103934665603ull;
	hash = kine_hash_bytes(hash, camera.origin, sizeof(camera.origin));
	hash = kine_hash_bytes(hash, camera.forward, sizeof(camera.forward));
	hash = kine_hash_bytes(hash, camera.up, sizeof(camera.up));
	hash = kine_hash_bytes(hash, &camera.fovYDegrees, sizeof(camera.fovYDegrees));
	hash = kine_hash_bytes(hash, &camera.clipStart, sizeof(camera.clipStart));
	hash = kine_hash_bytes(hash, &camera.clipEnd, sizeof(camera.clipEnd));
	return hash;
}

uint64_t kine_hash_lighting(const KineRayFrame &frame) {
	uint64_t hash = 1469598103934665603ull;
	hash = kine_hash_bytes(hash, frame.sunTowards, sizeof(frame.sunTowards));
	hash = kine_hash_bytes(hash, frame.sunColor, sizeof(frame.sunColor));
	hash = kine_hash_bytes(hash, &frame.sunIntensity, sizeof(frame.sunIntensity));
	hash = kine_hash_bytes(hash, frame.skyColor, sizeof(frame.skyColor));
	hash = kine_hash_bytes(hash, &frame.lightCount, sizeof(frame.lightCount));
	for (int i = 0; i < frame.lightCount; ++i) {
		const KineRayLight &light = frame.lights[i];
		hash = kine_hash_bytes(hash, &light.type, sizeof(light.type));
		hash = kine_hash_bytes(hash, light.position, sizeof(light.position));
		hash = kine_hash_bytes(hash, light.direction, sizeof(light.direction));
		hash = kine_hash_bytes(hash, light.color, sizeof(light.color));
		hash = kine_hash_bytes(hash, &light.intensity, sizeof(light.intensity));
		hash = kine_hash_bytes(hash, &light.innerConeRadians, sizeof(light.innerConeRadians));
		hash = kine_hash_bytes(hash, &light.outerConeRadians, sizeof(light.outerConeRadians));
		hash = kine_hash_bytes(hash, &light.castShadow, sizeof(light.castShadow));
	}
	return hash;
}

// The Filament-facing API stores row-major matrices (translation at 3/7/11),
// while Ray follows the usual Vulkan/OpenGL column-major layout (translation at
// 12/13/14). Transposing keeps the same mathematical transform.
void kine_transpose_row_major(const float *in, float *out) {
	for (int row = 0; row < 4; ++row) {
		for (int column = 0; column < 4; ++column) {
			out[column * 4 + row] = in[row * 4 + column];
		}
	}
}

uint64_t kine_draw_key(const KineRayDraw &draw) {
	uint64_t hash = 1469598103934665603ull;
	hash = kine_hash_bytes(hash, &draw.meshKey, sizeof(draw.meshKey));
	hash = kine_hash_bytes(hash, &draw.shaderKey, sizeof(draw.shaderKey));
	hash = kine_hash_bytes(hash, draw.color, sizeof(draw.color));
	hash = kine_hash_bytes(hash, &draw.materialKind, sizeof(draw.materialKind));
	hash = kine_hash_bytes(hash, &draw.param1, sizeof(draw.param1));
	hash = kine_hash_bytes(hash, &draw.param2, sizeof(draw.param2));
	hash = kine_hash_bytes(hash, &draw.param3, sizeof(draw.param3));
	hash = kine_hash_bytes(hash, &draw.transmission, sizeof(draw.transmission));
	hash = kine_hash_bytes(hash, &draw.uvScale, sizeof(draw.uvScale));
	hash = kine_hash_bytes(hash, &draw.baseColor.pixels, sizeof(draw.baseColor.pixels));
	hash = kine_hash_bytes(hash, &draw.normalMap.pixels, sizeof(draw.normalMap.pixels));
	return hash;
}

} // namespace

struct KineRayState {
	Ray::RendererBase *renderer = nullptr;
	Ray::SceneBase *scene = nullptr;
	Ray::CameraHandle camera = Ray::InvalidCameraHandle;
	Ray::RegionContext region{{0, 0, 1, 1}};
	int width = 0;
	int height = 0;
	int samples = 0;

	std::unordered_map<uint64_t, Ray::MeshHandle> meshes;
	std::unordered_map<uint64_t, Ray::MaterialHandle> materials;
	std::vector<Ray::MeshInstanceHandle> instances;
	// Lights currently living in the scene, so they can be replaced without
	// touching the geometry.
	std::vector<Ray::LightHandle> lights;
	// Texture handles Ray handed out, keyed by the CPU buffer they were built
	// from, plus that backing storage. Both die with the scene: Ray's handles
	// are only valid for the scene that produced them.
	std::unordered_map<const void *, Ray::TextureHandle> textures;
	std::vector<std::vector<uint8_t>> texture_storage;
	// Ray keeps the index span and the instance matrix by reference only until
	// the call returns, but the buffers double as cache keys, so they stay alive.
	std::vector<std::unique_ptr<std::vector<uint32_t>>> index_buffers;
	// Vertex data with a per-instance UV tile baked in. Held alive for the same
	// reason as index_buffers: Ray only borrows the span.
	std::vector<std::unique_ptr<std::vector<float>>> vertex_buffers;
	std::vector<float> instance_matrices;

	uint64_t structure_hash = 0;
	uint64_t transform_hash = 0;
	uint64_t camera_hash = 0;
	uint64_t light_hash = 0;

	KineRayProperties properties = kine_ray_default_properties();
	KineRayCamera last_camera{};
	bool has_camera = false;
	// Consecutive frames that arrived without any draw to trace.
	int empty_frames = 0;

	std::vector<uint8_t> pixels;
};

const char *kine_ray_last_error() { return g_error.c_str(); }

namespace {

void kine_clear_scene(KineRayState *state) {
	if (state->scene) {
		delete state->scene;
		state->scene = nullptr;
	}
	state->camera = Ray::InvalidCameraHandle;
	state->meshes.clear();
	state->materials.clear();
	state->instances.clear();
	state->lights.clear();
	state->textures.clear();
	state->texture_storage.clear();
	state->index_buffers.clear();
	state->vertex_buffers.clear();
	state->instance_matrices.clear();
	state->samples = 0;
	state->empty_frames = 0;
	state->region.iteration = 0;
}

// Uploads a CPU-side RGBA texture into the current scene. The bytes are copied
// first: Ray only borrows the span, and the Filament-side mirror can be freed
// while this scene is still being traced.
Ray::TextureHandle kine_get_texture(KineRayState *state, const KineRayTexture &tex) {
	if (!tex.valid()) {
		return Ray::InvalidTextureHandle;
	}
	auto it = state->textures.find(tex.pixels);
	if (it != state->textures.end()) {
		return it->second;
	}

	state->texture_storage.emplace_back(
		tex.pixels, tex.pixels + size_t(tex.width) * size_t(tex.height) * 4);
	const std::vector<uint8_t> &bytes = state->texture_storage.back();

	Ray::tex_desc_t desc;
	desc.format = Ray::eTextureFormat::RGBA8888;
	desc.name = "kine_texture";
	desc.data = bytes;
	desc.w = tex.width;
	desc.h = tex.height;
	desc.is_srgb = true;
	desc.generate_mipmaps = false;

	const Ray::TextureHandle handle = state->scene->AddTexture(desc);
	state->textures.emplace(tex.pixels, handle);
	return handle;
}

// Ports the Filament material onto Ray. Every branch mirrors what
// kine_apply_material_params() sets on the raster material instance for the
// same material kind, so the two renderers cannot drift apart.
Ray::MaterialHandle kine_get_material(KineRayState *state, const KineRayDraw &draw, uint64_t key) {
	auto it = state->materials.find(key);
	if (it != state->materials.end()) {
		return it->second;
	}

	const Ray::TextureHandle baseColor = kine_get_texture(state, draw.baseColor);
	const Ray::TextureHandle normalMap = kine_get_texture(state, draw.normalMap);
	Ray::MaterialHandle handle = Ray::InvalidMaterialHandle;

	switch (draw.materialKind) {
	case KINE_MAT_GLASS: {
		// Filament's glass is opaque until transmission is dialled up, so only a
		// genuinely transmissive glass should bend rays; the opaque case is a
		// tinted glossy solid.
		const bool transmissive = draw.transmission > 0.5f;
		Ray::shading_node_desc_t desc;
		desc.type = transmissive ? Ray::eShadingNode::Refractive : Ray::eShadingNode::Glossy;
		memcpy(desc.base_color.color, draw.color, sizeof(desc.base_color.color));
		desc.base_color.texture = baseColor;
		desc.ior = draw.param2 > 0.0f ? draw.param2 : 1.5f;
		desc.roughness = std::max(draw.param1, 0.0f);
		desc.tint = 1.0f;
		handle = state->scene->AddMaterial(desc);
		break;
	}
	case KINE_MAT_NEON: {
		Ray::shading_node_desc_t desc;
		desc.type = Ray::eShadingNode::Emissive;
		memcpy(desc.base_color.color, draw.color, sizeof(desc.base_color.color));
		// Filament calls the same knob "intensity"; both are plain multipliers
		// on the surface colour.
		desc.strength = draw.param1 > 0.0f ? draw.param1 : 1.0f;
		desc.importance_sample = true;
		handle = state->scene->AddMaterial(desc);
		break;
	}
	default: {
		// KINE_MAT_DEFAULT and KINE_MAT_TERRAIN are metallic/roughness materials
		// in Filament, which is exactly Ray's principled node.
		Ray::principled_mat_desc_t desc;
		memcpy(desc.base_color.color, draw.color, sizeof(desc.base_color.color));
		desc.base_color.texture = baseColor;
		desc.metallic.value = std::clamp(draw.param2, 0.0f, 1.0f);
		// Terrain falls back to a matte default in the raster pass when no
		// roughness was supplied.
		const float roughness =
			(draw.materialKind == KINE_MAT_TERRAIN && draw.param1 <= 0.0f) ? 0.9f : draw.param1;
		desc.roughness.value = std::clamp(roughness, 0.0f, 1.0f);
		desc.normal_map.texture = normalMap;
		desc.normal_map.value = normalMap != Ray::InvalidTextureHandle ? 1.0f : 0.0f;
		desc.ior = 1.45f;
		if (draw.materialKind == KINE_MAT_FADE || draw.materialKind == KINE_MAT_NEON_FADE)
			desc.alpha.value = std::clamp(draw.transmission, 0.0f, 1.0f);
		if (draw.materialKind == KINE_MAT_NEON_FADE) {
			memcpy(desc.emission.color.color, draw.color, sizeof(desc.emission.color.color));
			desc.emission.strength = draw.param1 > 0.0f ? draw.param1 : 1.0f;
			desc.emission.importance_sample = true;
		}
		handle = state->scene->AddMaterial(desc);
		break;
	}
	}

	state->materials.emplace(key, handle);
	return handle;
}

Ray::MeshHandle kine_get_mesh(KineRayState *state, const KineRayDraw &draw, uint64_t key) {
	auto it = state->meshes.find(key);
	if (it != state->meshes.end()) {
		return it->second;
	}

	auto indices = std::make_unique<std::vector<uint32_t>>(size_t(draw.indexCount));
	for (int i = 0; i < draw.indexCount; ++i) {
		(*indices)[size_t(i)] = draw.indices[i];
	}

	const Ray::MaterialHandle material = kine_get_material(state, draw, key);
	const Ray::mat_group_desc_t group(material, size_t(0), size_t(draw.indexCount));

	// One interleaved buffer holds position(3), normal(3) and uv(2) per vertex,
	// so every attribute points into the same array at its own float offset.
	// Filament tiles the default material through instanceUvScale, which Ray has
	// no equivalent for, so bake the same factor into a private copy of the
	// vertices instead.
	const int stride = draw.vertexStrideFloats;
	const float *vertexData = draw.vertexData;
	if (draw.uvScale != 1.0f && draw.uvScale > 0.0f && stride > 7 && draw.vertexCount > 0) {
		auto scaled = std::make_unique<std::vector<float>>(
			size_t(draw.vertexCount) * size_t(stride));
		memcpy(scaled->data(), draw.vertexData, scaled->size() * sizeof(float));
		for (int i = 0; i < draw.vertexCount; ++i) {
			float *vertex = scaled->data() + size_t(i) * size_t(stride);
			vertex[6] *= draw.uvScale;
			vertex[7] *= draw.uvScale;
		}
		vertexData = scaled->data();
		state->vertex_buffers.push_back(std::move(scaled));
	}

	const Ray::Span<const float> vertex_span(vertexData, draw.vertexCount * stride);
	const auto make_attribute = [&vertex_span, stride](int offset) {
		Ray::vtx_attribute_t attribute;
		attribute.data = vertex_span;
		attribute.offset = offset;
		attribute.stride = stride;
		return attribute;
	};

	Ray::mesh_desc_t desc;
	// Ray only uses this for its "Mesh '%s' preprocessed" log line; without it
	// every mesh shows up as '(unknown)', which makes the log useless.
	desc.name = "kine_mesh";
	desc.prim_type = Ray::ePrimType::TriangleList;
	desc.vtx_positions = make_attribute(0);
	desc.vtx_normals = make_attribute(3);
	desc.vtx_uvs = make_attribute(6);
	desc.vtx_indices = Ray::Span<const uint32_t>(*indices);
	desc.groups = Ray::Span<const Ray::mat_group_desc_t>(&group, 1);
	desc.bvh_quality = Ray::eBVHBuildQuality::FastBuild;

	const Ray::MeshHandle handle = state->scene->AddMesh(desc);
	state->index_buffers.push_back(std::move(indices));
	state->meshes.emplace(key, handle);
	return handle;
}

int kine_clamp_int(int value, int low, int high) { return std::clamp(value, low, high); }

float kine_clamp_float(float value, float low, float high) {
	// NaN would poison the renderer, so treat it as the low bound.
	if (!(value == value)) {
		return low;
	}
	return std::clamp(value, low, high);
}

KineRayProperties kine_sanitize_properties(const KineRayProperties &in) {
	KineRayProperties out;
	out.maxTotalDepth = kine_clamp_int(in.maxTotalDepth, 1, 32);
	out.maxDiffuseDepth = kine_clamp_int(in.maxDiffuseDepth, 0, 32);
	out.maxSpecularDepth = kine_clamp_int(in.maxSpecularDepth, 0, 32);
	out.maxRefractionDepth = kine_clamp_int(in.maxRefractionDepth, 0, 32);
	out.samplesPerFrame = kine_clamp_int(in.samplesPerFrame, 1, 64);
	out.minSamples = kine_clamp_int(in.minSamples, 0, 4096);
	out.varianceThreshold = kine_clamp_float(in.varianceThreshold, 0.0f, 1000.0f);
	out.exposure = kine_clamp_float(in.exposure, -32.0f, 32.0f);
	out.clampDirect = kine_clamp_float(in.clampDirect, 0.0f, 1.0e6f);
	out.clampIndirect = kine_clamp_float(in.clampIndirect, 0.0f, 1.0e6f);
	return out;
}

Ray::camera_desc_t kine_ray_camera_desc(const KineRayCamera &camera, const KineRayProperties &properties) {
	Ray::camera_desc_t desc;
	desc.type = Ray::eCamType::Persp;
	memcpy(desc.origin, camera.origin, sizeof(desc.origin));
	memcpy(desc.fwd, camera.forward, sizeof(desc.fwd));
	memcpy(desc.up, camera.up, sizeof(desc.up));
	// Ray's primary ray generator has no aspect term: it uses `fov` for both
	// axes and stretches the square projection over the image. Passing the
	// vertical fov keeps the vertical framing identical to Filament's.
	desc.fov = camera.fovYDegrees;
	desc.clip_start = camera.clipStart;
	desc.clip_end = camera.clipEnd;

	desc.max_total_depth = uint8_t(properties.maxTotalDepth);
	desc.max_diff_depth = uint8_t(properties.maxDiffuseDepth);
	desc.max_spec_depth = uint8_t(properties.maxSpecularDepth);
	desc.max_refr_depth = uint8_t(properties.maxRefractionDepth);
	desc.min_samples = properties.minSamples;
	desc.variance_threshold = properties.varianceThreshold;
	desc.exposure = properties.exposure;
	desc.clamp_direct = properties.clampDirect;
	desc.clamp_indirect = properties.clampIndirect;
	return desc;
}

Ray::environment_desc_t kine_ray_environment_desc(const KineRayFrame &frame) {
	Ray::environment_desc_t desc;
	for (int i = 0; i < 3; ++i) {
		desc.env_col[i] = frame.skyColor[i];
		desc.back_col[i] = frame.skyColor[i];
	}
	desc.importance_sample = false;
	return desc;
}

// Filament reports light in photometric units; Ray works in its own relative
// scale where 1.0 is roughly 10000 lux. The sun has always used this divisor,
// and the point/spot lights use it too so both stay balanced against each other.
constexpr float kine_light_unit_scale = 10000.0f;
// Ray has no analytic delta light: a sphere light of zero radius emits zero
// flux. A small radius keeps point lights reading as points while still letting
// Ray importance-sample and soft-shadow them.
constexpr float kine_light_radius = 0.1f;
constexpr float kine_radians_to_degrees = 57.29577951308232f;

// Replaces every light in the scene with the frame's sun plus its point/spot
// lights. Callers must Finalize() afterwards so Ray rebuilds its light tree.
void kine_apply_lights(KineRayState *state, const KineRayFrame &frame) {
	for (const Ray::LightHandle &light : state->lights) {
		state->scene->RemoveLight(light);
	}
	state->lights.clear();

	Ray::directional_light_desc_t sun;
	// Filament reports the sun in lux; Ray's directional lights are radiance.
	// 10000 lux per unit keeps the default 100000 lux sun at the brightness
	// Ray's own samples use.
	const float sunScale = std::max(frame.sunIntensity, 0.0f) / kine_light_unit_scale;
	for (int i = 0; i < 3; ++i) {
		sun.color[i] = frame.sunColor[i] * sunScale;
		sun.direction[i] = -frame.sunTowards[i];
	}
	sun.angle = 1.0f;
	state->lights.push_back(state->scene->AddLight(sun));

	for (int i = 0; i < frame.lightCount; ++i) {
		const KineRayLight &light = frame.lights[i];
		// A Filament light of I candela delivers I/d^2 irradiance at distance d.
		// Ray's sphere light emits col * area, so col = I / (scale * r^2) lands
		// it on the same scale as the sun above.
		const float radiance = std::max(light.intensity, 0.0f) /
			(kine_light_unit_scale * kine_light_radius * kine_light_radius);

		if (light.type == 0) {
			Ray::sphere_light_desc_t desc;
			for (int c = 0; c < 3; ++c)
				desc.color[c] = light.color[c] * radiance;
			memcpy(desc.position, light.position, sizeof(desc.position));
			desc.radius = kine_light_radius;
			desc.multiple_importance = true;
			desc.cast_shadow = light.castShadow;
			state->lights.push_back(state->scene->AddLight(desc));
			continue;
		}

		Ray::spot_light_desc_t desc;
		for (int c = 0; c < 3; ++c)
			desc.color[c] = light.color[c] * radiance;
		memcpy(desc.position, light.position, sizeof(desc.position));
		memcpy(desc.direction, light.direction, sizeof(desc.direction));
		// Ray wants the full cone angle in degrees; Filament keeps half-angles in
		// radians. Filament's inner/outer pair collapses into Ray's single blend.
		const float outer = std::max(light.outerConeRadians, 0.00873f);
		const float inner = std::clamp(light.innerConeRadians, 0.0f, outer);
		desc.spot_size = outer * 2.0f * kine_radians_to_degrees;
		desc.spot_blend = std::clamp(1.0f - (inner / outer), 0.0f, 1.0f);
		desc.radius = kine_light_radius;
		desc.multiple_importance = true;
		desc.cast_shadow = light.castShadow;
		state->lights.push_back(state->scene->AddLight(desc));
	}
}

bool kine_rebuild_scene(KineRayState *state, const KineRayFrame &frame) {
	kine_clear_scene(state);

	state->scene = state->renderer->CreateScene();
	if (!state->scene) {
		g_error = "Ray::RendererBase::CreateScene returned null";
		return false;
	}

	state->scene->SetEnvironment(kine_ray_environment_desc(frame));
	kine_apply_lights(state, frame);

	state->instance_matrices.resize(size_t(frame.drawCount) * 16);
	state->instances.reserve(size_t(frame.drawCount));
	for (int i = 0; i < frame.drawCount; ++i) {
		const KineRayDraw &draw = frame.draws[i];
		const uint64_t key = kine_draw_key(draw);
		const Ray::MeshHandle mesh = kine_get_mesh(state, draw, key);
		float *matrix = state->instance_matrices.data() + size_t(i) * 16;
		kine_transpose_row_major(draw.xform, matrix);
		const Ray::MeshInstanceHandle instance = state->scene->AddMeshInstance(mesh, matrix);
		state->instances.push_back(instance);
	}

	state->camera = state->scene->AddCamera(kine_ray_camera_desc(frame.camera, state->properties));
	state->scene->set_current_cam(state->camera);
	state->scene->Finalize();
	fprintf(stderr, "[Kine] Ray scene rebuilt: %d draw(s), %d instance(s)\n", frame.drawCount,
			(int)state->instances.size());
	state->last_camera = frame.camera;
	state->has_camera = true;

	state->structure_hash = kine_hash_draws(frame, true);
	state->transform_hash = kine_hash_draws(frame, false);
	state->camera_hash = kine_hash_camera(frame.camera);
	state->light_hash = kine_hash_lighting(frame);
	state->samples = 0;
	state->region = Ray::RegionContext{{0, 0, state->width, state->height}};
	return true;
}

bool kine_update_scene(KineRayState *state, const KineRayFrame &frame) {
	if (!state->scene) {
		return kine_rebuild_scene(state, frame);
	}

	// Some frames legitimately carry no draws: the 3D pass did not run, the dock
	// viewport was hidden, or the frame was submitted twice. Rebuilding an empty
	// scene there would wipe every instance and leave only the sky until the
	// draw list changed again, so the previous scene keeps being traced. A long
	// run of empty frames still rebuilds, so deleting every object clears it.
	if (frame.drawCount == 0) {
		if (++state->empty_frames < kine_max_empty_frames) {
			return true;
		}
	} else {
		state->empty_frames = 0;
	}

	const uint64_t structure = kine_hash_draws(frame, true);
	const uint64_t transform = kine_hash_draws(frame, false);
	const uint64_t camera = kine_hash_camera(frame.camera);
	const uint64_t light = kine_hash_lighting(frame);

	if (structure != state->structure_hash) {
		return kine_rebuild_scene(state, frame);
	}

	bool changed = false;
	if (transform != state->transform_hash) {
		if (state->instances.size() != size_t(frame.drawCount)) {
			return kine_rebuild_scene(state, frame);
		}
		for (int i = 0; i < frame.drawCount; ++i) {
			float *matrix = state->instance_matrices.data() + size_t(i) * 16;
			kine_transpose_row_major(frame.draws[i].xform, matrix);
			state->scene->SetMeshInstanceTransform(state->instances[size_t(i)], matrix);
		}
		state->transform_hash = transform;
		changed = true;
	}
	if (camera != state->camera_hash) {
		state->scene->SetCamera(state->camera, kine_ray_camera_desc(frame.camera, state->properties));
		state->camera_hash = camera;
		state->last_camera = frame.camera;
		state->has_camera = true;
		changed = true;
	}
	if (light != state->light_hash) {
		// Lights and sky sit outside the geometry, so swap them in place and
		// re-finalize instead of tearing down and re-uploading every BVH the way
		// a full rebuild would. Finalize() is what rebuilds Ray's light tree.
		state->scene->SetEnvironment(kine_ray_environment_desc(frame));
		kine_apply_lights(state, frame);
		state->scene->Finalize();
		state->light_hash = light;
		changed = true;
	}
	if (changed) {
		// Ray accumulates samples per region; a moved camera or object would
		// otherwise leave the previous image ghosting through.
		state->region.iteration = 0;
	}
	return true;
}

void kine_copy_pixels(KineRayState *state) {
	const Ray::color_data_rgba_t source = state->renderer->get_pixels_ref();
	const int pitch = source.pitch > 0 ? source.pitch : state->width;
	state->pixels.resize(size_t(state->width) * size_t(state->height) * 4);
	for (int y = 0; y < state->height; ++y) {
		const Ray::color_rgba_t *sourceRow = source.ptr + size_t(y) * size_t(pitch);
		uint8_t *targetRow = state->pixels.data() + size_t(y) * size_t(state->width) * 4;
		for (int x = 0; x < state->width; ++x) {
			for (int c = 0; c < 3; ++c) {
				const float value = std::clamp(sourceRow[x].v[c], 0.0f, 1.0f);
				targetRow[x * 4 + c] = uint8_t(value * 255.0f + 0.5f);
			}
			targetRow[x * 4 + 3] = 255;
		}
	}
}

bool kine_fill_vulkan_functions(
	const KineRayDevice &device,
	Ray::VulkanDevice &out_device,
	Ray::VulkanFunctions &out_functions) {
	auto get_instance_proc_addr =
		reinterpret_cast<Ray::PFN_vkGetInstanceProcAddr>(device.getInstanceProcAddr);
	if (!get_instance_proc_addr) {
		g_error = "Vulkan backend did not expose vkGetInstanceProcAddr";
		return false;
	}

	// Ray's handle typedefs live at global scope in VulkanFunctions.h.
	const auto instance = reinterpret_cast<VkInstance>(device.instance);
	const auto physical_device = reinterpret_cast<VkPhysicalDevice>(device.physicalDevice);
	const auto vk_device = reinterpret_cast<VkDevice>(device.device);
	auto get_device_proc_addr = reinterpret_cast<Ray::PFN_vkGetDeviceProcAddr>(
		get_instance_proc_addr(instance, "vkGetDeviceProcAddr"));
	if (!physical_device || !vk_device || !get_device_proc_addr) {
		g_error = "Vulkan backend is missing the device or vkGetDeviceProcAddr";
		return false;
	}

	out_device.instance = instance;
	out_device.physical_device = physical_device;
	out_device.device = vk_device;
	out_device.pipeline_cache = nullptr;

	out_functions = {};

	// Ray reports back through these whenever it is handed an external device,
	// so every one of them has to resolve; a single null makes Ray fall back to
	// creating its own instance and device, which is exactly what must not
	// happen here.
	int missing = 0;
#define KINE_RAY_LOAD_INSTANCE(name)                                                                                   \
	out_functions.name = reinterpret_cast<Ray::PFN_##name>(get_instance_proc_addr(instance, #name));                    \
	if (!out_functions.name)                                                                                           \
		++missing
#define KINE_RAY_LOAD_DEVICE(name)                                                                                     \
	out_functions.name = reinterpret_cast<Ray::PFN_##name>(get_device_proc_addr(vk_device, #name));                     \
	if (!out_functions.name)                                                                                           \
		++missing

	out_functions.vkGetInstanceProcAddr = get_instance_proc_addr;
	out_functions.vkGetDeviceProcAddr = get_device_proc_addr;

	KINE_RAY_LOAD_INSTANCE(vkGetPhysicalDeviceProperties);
	KINE_RAY_LOAD_INSTANCE(vkGetPhysicalDeviceMemoryProperties);
	KINE_RAY_LOAD_INSTANCE(vkGetPhysicalDeviceFormatProperties);
	KINE_RAY_LOAD_INSTANCE(vkGetPhysicalDeviceImageFormatProperties);
	KINE_RAY_LOAD_INSTANCE(vkGetPhysicalDeviceFeatures);
	KINE_RAY_LOAD_INSTANCE(vkGetPhysicalDeviceQueueFamilyProperties);
	KINE_RAY_LOAD_INSTANCE(vkEnumerateDeviceExtensionProperties);

	KINE_RAY_LOAD_DEVICE(vkGetDeviceQueue);
	KINE_RAY_LOAD_DEVICE(vkCreateCommandPool);
	KINE_RAY_LOAD_DEVICE(vkDestroyCommandPool);
	KINE_RAY_LOAD_DEVICE(vkAllocateCommandBuffers);
	KINE_RAY_LOAD_DEVICE(vkFreeCommandBuffers);
	KINE_RAY_LOAD_DEVICE(vkCreateFence);
	KINE_RAY_LOAD_DEVICE(vkResetFences);
	KINE_RAY_LOAD_DEVICE(vkDestroyFence);
	KINE_RAY_LOAD_DEVICE(vkGetFenceStatus);
	KINE_RAY_LOAD_DEVICE(vkWaitForFences);
	KINE_RAY_LOAD_DEVICE(vkCreateSemaphore);
	KINE_RAY_LOAD_DEVICE(vkDestroySemaphore);
	KINE_RAY_LOAD_DEVICE(vkCreateQueryPool);
	KINE_RAY_LOAD_DEVICE(vkDestroyQueryPool);
	KINE_RAY_LOAD_DEVICE(vkGetQueryPoolResults);
	KINE_RAY_LOAD_DEVICE(vkCreateShaderModule);
	KINE_RAY_LOAD_DEVICE(vkDestroyShaderModule);
	KINE_RAY_LOAD_DEVICE(vkCreateDescriptorSetLayout);
	KINE_RAY_LOAD_DEVICE(vkDestroyDescriptorSetLayout);
	KINE_RAY_LOAD_DEVICE(vkCreatePipelineLayout);
	KINE_RAY_LOAD_DEVICE(vkDestroyPipelineLayout);
	KINE_RAY_LOAD_DEVICE(vkCreateGraphicsPipelines);
	KINE_RAY_LOAD_DEVICE(vkCreateComputePipelines);
	KINE_RAY_LOAD_DEVICE(vkDestroyPipeline);
	KINE_RAY_LOAD_DEVICE(vkAllocateMemory);
	KINE_RAY_LOAD_DEVICE(vkFreeMemory);
	KINE_RAY_LOAD_DEVICE(vkCreateBuffer);
	KINE_RAY_LOAD_DEVICE(vkDestroyBuffer);
	KINE_RAY_LOAD_DEVICE(vkBindBufferMemory);
	KINE_RAY_LOAD_DEVICE(vkGetBufferMemoryRequirements);
	KINE_RAY_LOAD_DEVICE(vkCreateBufferView);
	KINE_RAY_LOAD_DEVICE(vkDestroyBufferView);
	KINE_RAY_LOAD_DEVICE(vkMapMemory);
	KINE_RAY_LOAD_DEVICE(vkUnmapMemory);
	KINE_RAY_LOAD_DEVICE(vkBeginCommandBuffer);
	KINE_RAY_LOAD_DEVICE(vkEndCommandBuffer);
	KINE_RAY_LOAD_DEVICE(vkResetCommandBuffer);
	KINE_RAY_LOAD_DEVICE(vkQueueSubmit);
	KINE_RAY_LOAD_DEVICE(vkQueueWaitIdle);
	KINE_RAY_LOAD_DEVICE(vkCreateImage);
	KINE_RAY_LOAD_DEVICE(vkDestroyImage);
	KINE_RAY_LOAD_DEVICE(vkGetImageMemoryRequirements);
	KINE_RAY_LOAD_DEVICE(vkBindImageMemory);
	KINE_RAY_LOAD_DEVICE(vkCreateImageView);
	KINE_RAY_LOAD_DEVICE(vkDestroyImageView);
	KINE_RAY_LOAD_DEVICE(vkCreateSampler);
	KINE_RAY_LOAD_DEVICE(vkDestroySampler);
	KINE_RAY_LOAD_DEVICE(vkCreateDescriptorPool);
	KINE_RAY_LOAD_DEVICE(vkDestroyDescriptorPool);
	KINE_RAY_LOAD_DEVICE(vkResetDescriptorPool);
	KINE_RAY_LOAD_DEVICE(vkAllocateDescriptorSets);
	KINE_RAY_LOAD_DEVICE(vkFreeDescriptorSets);
	KINE_RAY_LOAD_DEVICE(vkUpdateDescriptorSets);
	KINE_RAY_LOAD_DEVICE(vkCmdPipelineBarrier);
	KINE_RAY_LOAD_DEVICE(vkCmdBindPipeline);
	KINE_RAY_LOAD_DEVICE(vkCmdBindDescriptorSets);
	KINE_RAY_LOAD_DEVICE(vkCmdBindVertexBuffers);
	KINE_RAY_LOAD_DEVICE(vkCmdBindIndexBuffer);
	KINE_RAY_LOAD_DEVICE(vkCmdCopyBufferToImage);
	KINE_RAY_LOAD_DEVICE(vkCmdCopyImageToBuffer);
	KINE_RAY_LOAD_DEVICE(vkCmdCopyBuffer);
	KINE_RAY_LOAD_DEVICE(vkCmdFillBuffer);
	KINE_RAY_LOAD_DEVICE(vkCmdUpdateBuffer);
	KINE_RAY_LOAD_DEVICE(vkCmdPushConstants);
	KINE_RAY_LOAD_DEVICE(vkCmdBlitImage);
	KINE_RAY_LOAD_DEVICE(vkCmdClearColorImage);
	KINE_RAY_LOAD_DEVICE(vkCmdCopyImage);
	KINE_RAY_LOAD_DEVICE(vkCmdDispatch);
	KINE_RAY_LOAD_DEVICE(vkCmdDispatchIndirect);
	KINE_RAY_LOAD_DEVICE(vkCmdResetQueryPool);
	KINE_RAY_LOAD_DEVICE(vkCmdWriteTimestamp);

#undef KINE_RAY_LOAD_INSTANCE
#undef KINE_RAY_LOAD_DEVICE

	if (missing > 0) {
		g_error = "the shared Vulkan device is missing " + std::to_string(missing) +
				  " entry point(s) Ray needs";
		return false;
	}
	return true;
}

// Ray::Vk::Api::LoadExtensions resolves these through the instance and aborts on
// the first null. That abort leaves Api fields unset while Context's destructor
// still calls into them (vkDeviceWaitIdle in particular) during the exception
// unwind, which crashes at 0x0 instead of reporting the missing symbol. Probing
// here turns that combination into a readable error.
bool kine_check_instance_entry_points(const KineRayDevice &device) {
	auto get_instance_proc_addr =
		reinterpret_cast<Ray::PFN_vkGetInstanceProcAddr>(device.getInstanceProcAddr);
	const auto instance = reinterpret_cast<VkInstance>(device.instance);
	if (!get_instance_proc_addr || !instance) {
		return true; // reported by kine_fill_vulkan_functions
	}

	static const char *const required[] = {
		"vkCreateDebugReportCallbackEXT",
		"vkDestroyDebugReportCallbackEXT",
		"vkDebugReportMessageEXT",
		"vkCreateAccelerationStructureKHR",
		"vkDestroyAccelerationStructureKHR",
		"vkCmdBeginDebugUtilsLabelEXT",
		"vkCmdEndDebugUtilsLabelEXT",
		"vkSetDebugUtilsObjectNameEXT",
		"vkCmdBuildAccelerationStructuresKHR",
		"vkCmdWriteAccelerationStructuresPropertiesKHR",
		"vkCmdCopyAccelerationStructureKHR",
		"vkCmdTraceRaysKHR",
		"vkCmdTraceRaysIndirectKHR",
		"vkDeviceWaitIdle",
		"vkGetPhysicalDeviceProperties2KHR",
		"vkGetPhysicalDeviceFeatures2KHR",
		"vkGetBufferDeviceAddressKHR",
		"vkGetAccelerationStructureBuildSizesKHR",
		"vkGetAccelerationStructureDeviceAddressKHR",
		"vkGetRayTracingShaderGroupHandlesKHR",
	};

	std::string missing;
	for (const char *name : required) {
		if (!get_instance_proc_addr(instance, name)) {
			if (!missing.empty()) {
				missing += ", ";
			}
			missing += name;
		}
	}
	if (missing.empty()) {
		return true;
	}
	g_error = "the Vulkan instance does not expose " + missing +
			  " (Ray needs VK_EXT_debug_report, VK_EXT_debug_utils and "
			  "VK_KHR_get_physical_device_properties2 enabled on it)";
	return false;
}

} // namespace

KineRayState *kine_ray_create(const KineRayDevice &device, int width, int height) {
	g_error.clear();
	if (!device.instance || !device.physicalDevice || !device.device) {
		g_error = "no Vulkan device available (Vulkan backend required)";
		return nullptr;
	}
	if (width <= 0 || height <= 0) {
		g_error = "invalid Ray render size";
		return nullptr;
	}

	Ray::settings_t settings;
	settings.w = width;
	settings.h = height;
	// The shared device enables neither the hardware ray tracing extensions nor
	// descriptor indexing, so keep Ray on its portable paths.
	settings.use_hwrt = false;
	settings.use_bindless = false;
	settings.use_tex_compression = false;
	settings.validation_level = 0;

	if (!kine_fill_vulkan_functions(device, settings.vk_device, settings.vk_functions)) {
		return nullptr;
	}
	if (!kine_check_instance_entry_points(device)) {
		return nullptr;
	}

	auto state = std::make_unique<KineRayState>();
	state->width = width;
	state->height = height;
	state->region = Ray::RegionContext{{0, 0, width, height}};

	// Ray picks the first graphics+compute queue family and queue index 0 of the
	// device it is handed; when Filament owns the device that is also the queue
	// Filament submits on. Both submit from the main thread (Ray inside
	// Kine_Filament_RenderFrame, Filament in its render call), so the submissions
	// never overlap and the queue stays externally synchronized.
	if (device.graphicsQueueCount < 2) {
		fprintf(stderr,
				"[Kine] Ray: device exposes %u queue(s) in family %u; Ray shares queue 0 "
				"with Filament, serialized on the render thread\n",
				device.graphicsQueueCount,
				device.graphicsQueueFamilyIndex);
	}

	state->renderer = Ray::CreateRenderer(settings, &Ray::g_stdout_log, Ray::parallel_for_serial,
										  Ray::RendererGPU);
	if (!state->renderer) {
		g_error = "Ray could not create its Vulkan renderer on the shared device";
		return nullptr;
	}

	if (state->renderer->type() != Ray::eRendererType::Vulkan) {
		g_error = "Ray did not select the Vulkan renderer";
		delete state->renderer;
		return nullptr;
	}

	fprintf(stderr,
			"[Kine] Ray: %s renderer on the shared VkDevice (%dx%d)\n",
			std::string(state->renderer->device_name()).c_str(),
			width,
			height);

	return state.release();
}

void kine_ray_destroy(KineRayState *state) {
	if (!state) {
		return;
	}
	kine_clear_scene(state);
	delete state->renderer;
	delete state;
}

bool kine_ray_resize(KineRayState *state, int width, int height) {
	if (!state || !state->renderer || width <= 0 || height <= 0) {
		return false;
	}
	if (state->width == width && state->height == height) {
		return true;
	}
	state->width = width;
	state->height = height;
	state->renderer->Resize(width, height);
	state->region = Ray::RegionContext{{0, 0, width, height}};
	state->samples = 0;
	state->pixels.clear();
	return true;
}

KineRayProperties kine_ray_sanitize_properties(const KineRayProperties &properties) {
	return kine_sanitize_properties(properties);
}

KineRayProperties kine_ray_default_properties() {
	KineRayProperties defaults{};
	defaults.maxTotalDepth = 8;
	defaults.maxDiffuseDepth = 4;
	defaults.maxSpecularDepth = 8;
	defaults.maxRefractionDepth = 8;
	defaults.samplesPerFrame = 1;
	defaults.minSamples = 128;
	defaults.varianceThreshold = 0.0f;
	defaults.exposure = 0.0f;
	defaults.clampDirect = 0.0f;
	defaults.clampIndirect = 0.0f;
	return defaults;
}

bool kine_ray_set_properties(KineRayState *state, const KineRayProperties &properties) {
	if (!state) {
		return false;
	}
	state->properties = kine_sanitize_properties(properties);
	// Depths and exposure shape every sample, so the accumulated image is stale.
	state->region.iteration = 0;
	if (state->scene && state->has_camera && state->camera._index != 0xffffffffu) {
		state->scene->SetCamera(
			state->camera, kine_ray_camera_desc(state->last_camera, state->properties));
		state->camera_hash = kine_hash_camera(state->last_camera);
	}
	return true;
}

bool kine_ray_render(KineRayState *state, const KineRayFrame &frame) {
	if (!state || !state->renderer) {
		return false;
	}
	if (frame.width <= 0 || frame.height <= 0) {
		return false;
	}
	if (frame.width != state->width || frame.height != state->height) {
		if (!kine_ray_resize(state, frame.width, frame.height)) {
			return false;
		}
	}

	if (!kine_update_scene(state, frame)) {
		return false;
	}

	for (int i = 0; i < state->properties.samplesPerFrame; ++i) {
		state->renderer->RenderScene(*state->scene, state->region);
		++state->samples;
	}
	kine_copy_pixels(state);
	return true;
}

const uint8_t *kine_ray_pixels(const KineRayState *state) {
	return state && !state->pixels.empty() ? state->pixels.data() : nullptr;
}

int kine_ray_sample_count(const KineRayState *state) { return state ? state->samples : 0; }
