#if defined(_WIN32)
#define NOMINMAX
#define WIN32_LEAN_AND_MEAN
#endif
#include "kine_filament_shim.h"

#include "kine_default_package.h"
#include "kine_viewport_package.h"
#include "kine_viewport_clear_package.h"
#include "../../kine_skia/include/kine_skia.h"

#ifndef KINE_WITH_ASSIMP
#define KINE_WITH_ASSIMP 0
#endif
#ifndef KINE_FILAMENT_USE_VULKAN
#define KINE_FILAMENT_USE_VULKAN 0
#endif
#ifndef KINE_FILAMENT_ENABLE_VULKAN_READBACK
#define KINE_FILAMENT_ENABLE_VULKAN_READBACK 0
#endif
#ifndef KINE_WITH_RAY
#define KINE_WITH_RAY 0
#endif

#include <filamat/MaterialBuilder.h>
#include <filamat/Package.h>
#include <filament/Camera.h>
#include <filament/Color.h>
#include <filament/ColorGrading.h>
#include <filament/Engine.h>
#include <filament/IndexBuffer.h>
#include <filament/IndirectLight.h>
#include <filament/ToneMapper.h>
#include <filament-iblprefilter/IBLPrefilterContext.h>
#include "kine_ssgi_package.h"
#include <filament/InstanceBuffer.h>
#include <filament/LightManager.h>
#include <filament/Material.h>
#include <filament/MaterialInstance.h>
#include <filament/Options.h>
#include <filament/RenderTarget.h>
#include <filament/RenderableManager.h>
#include <filament/Renderer.h>
#include <filament/Scene.h>
#include <filament/Skybox.h>
#include <filament/SwapChain.h>
#include <filament/Texture.h>
#include <filament/TextureSampler.h>
#include <filament/TransformManager.h>
#include <filament/VertexBuffer.h>
#include <filament/View.h>
#include <filament/Viewport.h>

#if !defined(__ANDROID__)
#include <filament-matp/Config.h>
#include <filament-matp/MaterialParser.h>
#endif
#include <backend/DriverEnums.h>
#include <backend/Platform.h>
#if KINE_FILAMENT_USE_VULKAN
#include "kine_vulkan_compositor.h"
#include <backend/platforms/VulkanPlatform.h>

#endif
#include "kine_cloud_package.h"
#include "kine_decal_package.h"
#include "kine_gizmo_package.h"
#include "kine_glass_package.h"
#include "kine_hl_fill_package.h"
#include "kine_hl_fill_top_package.h"
#include "kine_hl_outline_package.h"
#include "kine_hl_outline_top_package.h"
#include "kine_neon_package.h"
#include "kine_outline_composite_package.h"
#include "kine_outline_mask_package.h"
#include "kine_outline_package.h"
#include "kine_particle_package.h"
#include "kine_ray_output_package.h"
#include "kine_terrain_package.h"
#include "kine_water_package.h"
#include "kine_forcefield_package.h"

#if KINE_WITH_RAY
// Ray runs on this context's Vulkan device; the bridge header keeps Ray's own
// Vulkan declarations out of this translation unit.
#include "kine_ray.h"
#endif
#include <SDL3/SDL_properties.h>
#include <SDL3/SDL_video.h>
#include <SDL3/SDL_vulkan.h>
#include <math/mat4.h>
#include <math/vec2.h>
#include <math/vec3.h>
#include <math/vec4.h>
#include <utils/Entity.h>
#include <utils/EntityManager.h>

#include <geometry/SurfaceOrientation.h>
using namespace filament::geometry;

#if KINE_FILAMENT_USE_VULKAN
struct VkInstance_T;
struct VkPhysicalDevice_T;
struct VkDevice_T;
struct VkQueue_T;
#endif

#if KINE_WITH_ASSIMP
#include <assimp/Importer.hpp>
#include <assimp/material.h>
#include <assimp/GltfMaterial.h>
#include <assimp/postprocess.h>
#include <assimp/scene.h>

#define STB_IMAGE_IMPLEMENTATION
#define STBIDEF static
#include <stb_image.h>
#undef STBIDEF
#undef STB_IMAGE_IMPLEMENTATION
#endif

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <functional>
#include <limits>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#if !defined(__ANDROID__)
class KineRuntimeMaterialConfig final : public matp::Config {
  public:
	KineRuntimeMaterialConfig() {
#if defined(__ANDROID__)
		mPlatform = Platform::MOBILE;
#else
		mPlatform = Platform::DESKTOP;
#endif
#if KINE_FILAMENT_USE_VULKAN
		mTargetApi = TargetApi::VULKAN;
#else
		mTargetApi = TargetApi::OPENGL;
#endif
		mOptimizationLevel = Optimization::PERFORMANCE;
		mFeatureLevel = filament::backend::FeatureLevel::FEATURE_LEVEL_1;
		mIncludeEssl1 = false;
		mInsertLineDirectives = false;
		mInsertLineDirectiveChecks = false;
	}

	Output *getOutput() const noexcept override { return nullptr; }
	Input *getInput() const noexcept override { return nullptr; }
	std::string toString() const noexcept override { return "Kinemium runtime material"; }
	std::string toPIISafeString() const noexcept override { return toString(); }
};
#endif

#if !KINE_FILAMENT_USE_VULKAN
#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <GL/gl.h>
#include <windows.h>
static void *kine_get_current_gl_context() { return (void *)wglGetCurrentContext(); }
#elif defined(__APPLE__)

#define GL_SILENCE_DEPRECATION
#include <OpenGL/OpenGL.h>
#include <OpenGL/gl.h>
static void *kine_get_current_gl_context() { return (void *)CGLGetCurrentContext(); }
#elif defined(__ANDROID__)
#include <EGL/egl.h>
#include <GLES3/gl3.h>
#include <GLES3/gl3ext.h>
static void *kine_get_current_gl_context() { return (void *)eglGetCurrentContext(); }
#else
#include <GL/gl.h>
#include <GL/glx.h>
static void *kine_get_current_gl_context() { return (void *)glXGetCurrentContext(); }
#endif

#ifndef GL_CLAMP_TO_EDGE
#define GL_CLAMP_TO_EDGE 0x812F
#endif
#ifndef GL_TEXTURE0
#define GL_TEXTURE0 0x84C0
#endif

#ifndef GL_FRAMEBUFFER
#define GL_FRAMEBUFFER 0x8D40
#endif
#ifndef GL_COLOR_ATTACHMENT0
#define GL_COLOR_ATTACHMENT0 0x8CE0
#endif

#ifndef APIENTRY
#define APIENTRY
#endif

typedef void(APIENTRY *PFNGLBINDFRAMEBUFFERPROC)(GLenum, GLuint);
typedef void(APIENTRY *PFNGLGETFRAMEBUFFERATTACHMENTPARAMETERIVPROC)(GLenum, GLenum, GLenum, GLint *);
typedef void(APIENTRY *PFNGLGENFRAMEBUFFERSPROC)(GLsizei, GLuint *);
typedef void(APIENTRY *PFNGLDELETEFRAMEBUFFERSPROC)(GLsizei, const GLuint *);
typedef void(APIENTRY *PFNGLFRAMEBUFFERTEXTURE2DPROC)(GLenum, GLenum, GLenum, GLuint, GLint);

#define GL_FRAMEBUFFER_ATTACHMENT_OBJECT_NAME 0x8CD1

static PFNGLBINDFRAMEBUFFERPROC kine_glBindFramebuffer = nullptr;
static PFNGLGENFRAMEBUFFERSPROC kine_glGenFramebuffers = nullptr;
static PFNGLDELETEFRAMEBUFFERSPROC kine_glDeleteFramebuffers = nullptr;
static PFNGLFRAMEBUFFERTEXTURE2DPROC kine_glFramebufferTexture2D = nullptr;

typedef void(APIENTRY *PFNGLBLITFRAMEBUFFERPROC)(GLint, GLint, GLint, GLint, GLint, GLint, GLint, GLint, GLbitfield, GLenum);
static PFNGLBLITFRAMEBUFFERPROC kine_glBlitFramebuffer = nullptr;

#ifndef GL_READ_FRAMEBUFFER
#define GL_READ_FRAMEBUFFER 0x8CA8
#endif
#ifndef GL_DRAW_FRAMEBUFFER
#define GL_DRAW_FRAMEBUFFER 0x8CA9
#endif
#ifndef GL_COLOR_BUFFER_BIT
#define GL_COLOR_BUFFER_BIT 0x4000
#endif

static void kine_init_gl_ext() {
	static bool done = false;
	if (done)
		return;
	done = true;
#if defined(_WIN32)
	kine_glBlitFramebuffer = (PFNGLBLITFRAMEBUFFERPROC)wglGetProcAddress("glBlitFramebuffer");
	kine_glBindFramebuffer = (PFNGLBINDFRAMEBUFFERPROC)wglGetProcAddress("glBindFramebuffer");
	kine_glGenFramebuffers = (PFNGLGENFRAMEBUFFERSPROC)wglGetProcAddress("glGenFramebuffers");
	kine_glDeleteFramebuffers = (PFNGLDELETEFRAMEBUFFERSPROC)wglGetProcAddress("glDeleteFramebuffers");
	kine_glFramebufferTexture2D = (PFNGLFRAMEBUFFERTEXTURE2DPROC)wglGetProcAddress("glFramebufferTexture2D");
#elif defined(__APPLE__)
	kine_glBlitFramebuffer = &glBlitFramebuffer;

	kine_glBindFramebuffer = &glBindFramebuffer;
	kine_glGenFramebuffers = &glGenFramebuffers;
	kine_glDeleteFramebuffers = &glDeleteFramebuffers;
	kine_glFramebufferTexture2D = &glFramebufferTexture2D;
#elif defined(__ANDROID__)

	kine_glBlitFramebuffer = &glBlitFramebuffer;
	kine_glBindFramebuffer = &glBindFramebuffer;
	kine_glGenFramebuffers = &glGenFramebuffers;
	kine_glDeleteFramebuffers = &glDeleteFramebuffers;
	kine_glFramebufferTexture2D = &glFramebufferTexture2D;
#else
	kine_glBlitFramebuffer = (PFNGLBLITFRAMEBUFFERPROC)glXGetProcAddress((const GLubyte *)"glBlitFramebuffer");
	kine_glBindFramebuffer = (PFNGLBINDFRAMEBUFFERPROC)glXGetProcAddress((const GLubyte *)"glBindFramebuffer");
	kine_glGenFramebuffers = (PFNGLGENFRAMEBUFFERSPROC)glXGetProcAddress((const GLubyte *)"glGenFramebuffers");
	kine_glDeleteFramebuffers = (PFNGLDELETEFRAMEBUFFERSPROC)glXGetProcAddress((const GLubyte *)"glDeleteFramebuffers");
	kine_glFramebufferTexture2D = (PFNGLFRAMEBUFFERTEXTURE2DPROC)glXGetProcAddress((const GLubyte *)"glFramebufferTexture2D");
#endif
}
#endif

using namespace filament;
using namespace utils;

struct KineVertex {
	float px, py, pz;
	float nx, ny, nz;
	float u, v;
};

struct vector3 {
	float x, y, z;
};

struct KineTerrainWeights {
	float values[8];
};

struct KineSkinVertex {
	uint8_t joints[4] = {0, 0, 0, 0};
	float weights[4] = {1.0f, 0.0f, 0.0f, 0.0f};
};

struct KineQuat {
	float x = 0.0f;
	float y = 0.0f;
	float z = 0.0f;
	float w = 1.0f;
};

struct KineVecKey {
	float time = 0.0f;
	math::float3 value{};
};

struct KineQuatKey {
	float time = 0.0f;
	KineQuat value{};
};

static KineFilamentWaterParams kine_default_water_params() {
	KineFilamentWaterParams p{};
	p.speed = 1.0f;
	p.strength = 1.0f;
	p.octaves = 6.0f;
	p.height = 1.0f;
	p.waveScale = 1.0f;
	p.foamAmount = 0.55f;
	p.absorptionR = 0.35f;
	p.absorptionG = 0.09f;
	p.absorptionB = 0.04f;
	p.clearCoat = 1.0f;
	p.clearCoatRoughness = 0.04f;
	return p;
}

struct KineBone {
	std::string name;
	int parent = -1;
	math::float3 bindTranslation{};
	KineQuat bindRotation{};
	math::float3 bindScale{1.0f, 1.0f, 1.0f};
	math::mat4f bindLocal{};
	math::mat4f inverseBind{};
};

struct KineAnimationChannel {
	int bone = -1;
	std::vector<KineVecKey> translations;
	std::vector<KineQuatKey> rotations;
	std::vector<KineVecKey> scales;
};

struct KineAnimation {
	std::string name;
	float duration = 0.0f;
	std::vector<KineAnimationChannel> channels;
};

struct KineImage {
	int width = 0, height = 0;
	std::vector<uint8_t> rgba;
};

struct KineTexHandle;

struct KineImportedMaterial {
	KineImage baseColorImage, normalImage, ormImage;
	KineTexHandle *texture = nullptr;
	math::float4 baseColor{1.0f};
	float roughness = 1.0f, metallic = 0.0f, alphaCutoff = 0.0f;
	bool doubleSided = false;
};

struct KineMeshPrimitive {
	uint32_t offset = 0, count = 0, material = 0;
	uint32_t vertexOffset = 0, vertexCount = 0;
	std::vector<uint32_t> rayIndices;
};

struct KineMesh {
	VertexBuffer *vb = nullptr;
	IndexBuffer *ib = nullptr;
	uint32_t indexCount = 0;
	std::vector<KineVertex> vertices;

	std::vector<math::float4> vertexColors;
	std::vector<KineTerrainWeights> terrainWeights;
	std::vector<KineSkinVertex> skinVertices;
	std::vector<uint32_t> indices;
	std::vector<KineMeshPrimitive> primitives;
	std::vector<KineImportedMaterial> materials;
	bool useImportedMaterials = true;
	std::vector<KineBone> bones;
	std::vector<math::mat4f> skinMatrices;
	std::vector<KineAnimation> animations;
	Box localBounds;

	bool doubleSided = false;

	KineImage baseColorImage;
	KineTexHandle *ownedTex = nullptr;
	bool ownsTexture = true;
	std::unordered_map<int, KineMesh *> refinedMeshes;
};

struct KineCpuMeshData {
	std::vector<math::float3> positions;
	std::vector<uint32_t> indices;
};

struct KineTexHandle {
	Texture *tex = nullptr;
	Texture *normalTex = nullptr;
	Texture *ormTex = nullptr;
	Texture *heightTex = nullptr;
	float heightScale = 0.0f;
	Texture *terrainLayers[6] = {};
	bool ownsTextures = true;
	// RGBA8 mirror of the base colour and normal map. Ray samples textures from
	// system memory and cannot read Filament's GPU upload, so the paths that
	// start from pixels keep one around for it. Textures imported from an
	// existing GL id have no pixels to mirror.
	std::vector<uint8_t> cpuPixels;
	int cpuWidth = 0;
	int cpuHeight = 0;
	std::vector<uint8_t> cpuNormalPixels;
	int cpuNormalWidth = 0;
	int cpuNormalHeight = 0;
	// A terrain set borrows its layer textures; Ray needs the owning handles to
	// reach their CPU mirrors.
	KineTexHandle *terrainLayerSources[6] = {};
};

constexpr size_t KINE_MAX_INSTANCE_COLORS = 64;

struct KineBatchKey {
	KineMesh *mesh = nullptr;
	KineFilamentShader *shader = nullptr;
	uint64_t streamId = 0;

	int materialKind = 0;

	float param1 = 0, param2 = 0, param3 = 0;
	float transmission = 0;
	float particleUvOffsetY = 0;

	bool castShadow = false;
	bool receiveShadow = false;
	bool culling = true;

	KineTexHandle *texture = nullptr;

	bool operator==(const KineBatchKey &o) const noexcept {
		return mesh == o.mesh && shader == o.shader && streamId == o.streamId && materialKind == o.materialKind &&
			   param1 == o.param1 && param2 == o.param2 && param3 == o.param3 &&
			   transmission == o.transmission && particleUvOffsetY == o.particleUvOffsetY &&
			   castShadow == o.castShadow && receiveShadow == o.receiveShadow &&
			   culling == o.culling && texture == o.texture;
	}
};

struct KineBatchKeyHash {
	size_t operator()(const KineBatchKey &k) const noexcept {
		size_t h = std::hash<void *>()(k.mesh);
		auto mix = [&h](size_t v) { h ^= v + 0x9e3779b97f4a7c15ULL + (h << 6) + (h >> 2); };
		mix(std::hash<void *>()(k.shader));
		mix(std::hash<uint64_t>()(k.streamId));
		mix(std::hash<int>()(k.materialKind));
		mix(std::hash<float>()(k.param1));
		mix(std::hash<float>()(k.param2));
		mix(std::hash<float>()(k.param3));
		mix(std::hash<float>()(k.transmission));
		mix(std::hash<float>()(k.particleUvOffsetY));
		mix(std::hash<bool>()(k.castShadow));
		mix(std::hash<bool>()(k.receiveShadow));
		mix(std::hash<bool>()(k.culling));
		mix(std::hash<void *>()(k.texture));
		return h;
	}
};

#if KINE_WITH_RAY
// A mesh draw captured while the frame is being queued, replayed into Ray when
// render mode 2 is active. Mirrors what Filament renders, minus the materials
// Ray has no equivalent for.
struct KineRayQueuedDraw {
	KineMesh *mesh = nullptr;
	bool importedMaterials = false;
	KineFilamentShader *shader = nullptr;
	float transform[16] = {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1};
	float color[3] = {1.0f, 1.0f, 1.0f};
	int materialKind = 0;
	// The batch key's material parameters, carried so Ray can build the surface
	// kine_apply_material_params() gives the raster pass.
	float param1 = 0.0f;
	float param2 = 0.0f;
	float param3 = 0.0f;
	float transmission = 0.0f;
	float uvScale = 1.0f;
	KineRayTexture baseColor;
	KineRayTexture normalMap;
};
#endif

struct KinePendingBatch {
	std::vector<math::mat4f> transforms;
	std::vector<math::float4> colors;

	std::vector<float> uvScales;

	uint64_t lastQueuedFrame = 0;

	// Tracked separately so a colour-only change does not force a transform
	// re-upload and vice versa.
	uint64_t transformHash = 1469598103934665603ULL;
	uint64_t colorHash = 1469598103934665603ULL;
	uint64_t uvHash = 1469598103934665603ULL;

	// Per-instance transform hashes, parallel to `transforms`. Lets the update
	// path upload only the instances that actually moved.
	std::vector<uint64_t> instanceTransformHashes;
};

struct KineBuiltBatch {
	Entity entity;
	InstanceBuffer *instanceBuffer = nullptr;
	MaterialInstance *materialInstance = nullptr;
	size_t instanceCount = 0;
	std::vector<uint64_t> instanceTransformHashes;
	std::vector<MaterialInstance *> extraMaterials;
};

struct KinePersistentBatch {
	std::vector<KineBuiltBatch> chunks;
	uint64_t lastUsedFrame = 0;
	uint64_t transformHash = 0;
	uint64_t colorHash = 0;
	uint64_t uvHash = 0;
	// A retained batch keeps its GPU objects but is detached from the scene so
	// it does not draw while unused.
	bool detached = false;
};

struct KineFilamentInstanceBatch {
	KineFilamentContext *ctx = nullptr;
	KineBatchKey key;
	std::vector<math::mat4f> transforms;
	std::vector<math::float4> colors;
	std::vector<KineBuiltBatch> chunks;
};

struct KineRetainedListState {
	uint64_t version = 0;
	bool initialized = false;
	std::vector<KineBatchKey> keys;
#if KINE_WITH_RAY
	// Ray rebuilds its draw list from scratch on every frame, while a retained
	// stream only re-queues when its version changes. Keeping the last queued
	// draws here lets them be replayed on unchanged frames -- without it a scene
	// that stops changing starves Ray into rebuilding an empty scene, which
	// presents as plain sky over the viewport.
	std::vector<KineRayQueuedDraw> rayDraws;
#endif
};

struct KineDecalResource {
	Entity entity;
	MaterialInstance *material = nullptr;
	KineMesh *mesh = nullptr;
};

struct KineFilamentShader {
	KineFilamentContext *ctx = nullptr;
	Material *material = nullptr;
	std::unordered_map<std::string, std::vector<float>> uniforms;
	std::unordered_map<std::string, Texture *> textures;
	int subdivisionLevel = 0;
	float boundsPadding = 0.0f;
};

struct KineViewportPool;
struct KineReflectionProbeState;
struct KineSsgiState;
struct KineAdvancedEffectState {bool enabled=false; float values[16]={};};
static void kine_viewport_render_queued(KineFilamentContext *ctx);
static void kine_viewport_shutdown(KineFilamentContext *ctx);
static void kine_viewport_destroy_shader_batches(KineFilamentContext *ctx, KineFilamentShader *shader);
static void kine_viewport_update_shader_uniforms(KineFilamentContext *ctx, KineFilamentShader *shader);
static void kine_viewport_invalidate_batches(KineFilamentContext *ctx, const KineMesh *mesh, const KineTexHandle *texture);

struct KineFilamentContext {
	KineAdvancedEffectState advancedEffects[7];
	KineReflectionProbeState *reflectionProbe=nullptr;
	KineSsgiState *ssgi=nullptr;
	float gradingInputs[6]={0,1,1,1,0,0};
	int toneMappingMode=4;
	float advancedExposure=0, advancedTemperature=0, advancedTint=0;
	float skyInputs[13]={};
	bool skyInputsValid=false, reflectionDirty=true;
	KineViewportPool *viewportPool = nullptr;
	bool renderWorld = true;
	Engine *engine = nullptr;
	SwapChain *swapChain = nullptr;
	Renderer *renderer = nullptr;
	Scene *scene = nullptr;
	View *view = nullptr;
	Camera *camera = nullptr;
	ColorGrading *colorGrading = nullptr;
	Entity cameraEntity;
	math::double3 cameraEye{0, 0, 0};
	float fovYDegrees = 60.0f;
	math::double3 cameraTarget{0, 0, -1};
	math::double3 cameraUp{0, 1, 0};
	Texture *colorTarget = nullptr;
	Texture *depthTarget = nullptr;
	RenderTarget *renderTarget = nullptr;
	unsigned int colorTextureId = 0;
	unsigned int readFboId = 0;
	void *nativeWindow = nullptr;
	bool renderToSwapChain = false;
	bool useFilamentOwnedCompositor = false;
	bool loggedFirstFrame = false;
#if KINE_FILAMENT_USE_VULKAN && KINE_FILAMENT_ENABLE_VULKAN_READBACK
	bool readbackReady = false;
	bool readbackPending = false;
#endif
	int viewportX = 0;
	int viewportY = 0;
	int viewportWidth = 0;
	int viewportHeight = 0;
	int width = 0;
	int height = 0;
	Texture *whiteTex = nullptr;

	Material *defaultMaterial = nullptr;
	Entity sunLight;

	Material *neonMaterial = nullptr;
	Material *glassMaterial = nullptr;
	Material *waterMaterial = nullptr;
	Material *forceFieldMaterial = nullptr;
	KineFilamentWaterParams water = kine_default_water_params();
	Material *cloudMaterial = nullptr;
	// Sun direction in world space, kept for materials that light themselves
	// (the cloud volume raymarches towards it instead of using scene lights).
	math::float3 sunDirection{0.0f, 1.0f, 0.0f};
	float sunIntensity = 100000.0f;

	// Sky cloud layer: an infinite slab drawn as a far-plane quad with the cloud
	// material. Owned by Lighting, one per context.
	Entity cloudEntity;
	MaterialInstance *cloudMI = nullptr;
	KineMesh *cloudMesh = nullptr;
	bool cloudEnabled = false;
	bool cloudInScene = false;
	float cloudCover = 0.5f;
	float cloudDensity = 0.5f;
	float cloudHeight = 700.0f;
	float cloudThickness = 220.0f;
	math::float3 cloudColor{1.0f, 1.0f, 1.0f};
	Material *decalMaterial = nullptr;
	Material *outlineMaterial = nullptr;
	Material *gizmoMaterial = nullptr;
	Material *particleMaterial = nullptr;
	Material *terrainMaterial = nullptr;
	Material *hlOutlineMaterial = nullptr;
	Material *hlOutlineTopMaterial = nullptr;
	Material *hlFillMaterial = nullptr;
	Material *hlFillTopMaterial = nullptr;
	Material *outlineMaskMaterial = nullptr;
	Material *outlineCompositeMaterial = nullptr;
	KineFilamentShader *globalShader = nullptr;
	KineFilamentShader *postProcessShader = nullptr;
	std::unordered_set<KineFilamentShader *> runtimeShaders;
	std::unordered_set<KineFilamentInstanceBatch *> instanceBatches;
	KineMesh *particleQuadMesh = nullptr;
	KineMesh *gizmoPrims[4] = {};
	KineMesh *postProcessQuadMesh = nullptr;
	Texture *postSceneColor = nullptr;
	Texture *postSceneDepth = nullptr;
	RenderTarget *postSceneTarget = nullptr;
	Scene *postScene = nullptr;
	View *postView = nullptr;
	Camera *postCamera = nullptr;
	Entity postCameraEntity;
	Entity postQuadEntity;
	MaterialInstance *postMaterialInstance = nullptr;

	Texture *outlineMaskColor = nullptr;
	Texture *outlineMaskDepth = nullptr;
	RenderTarget *outlineMaskTarget = nullptr;
	Scene *outlineMaskScene = nullptr;
	View *outlineMaskView = nullptr;
	Scene *outlineScene = nullptr;
	View *outlineView = nullptr;
	Camera *outlineCamera = nullptr;
	Entity outlineCameraEntity;
	Entity outlineQuadEntity;
	MaterialInstance *outlineCompositeMI = nullptr;
	float outlineWidthPixels = 0.0f;
	bool outlineQueued = false;
	float time = 0.0f;
	float waterTime = 0.0f;
	bool explicitWaterTime = false;

	void *hostCtx = nullptr;
	void *hostDC = nullptr;
	void *hostDisplay = nullptr;
	unsigned long hostDrawable = 0;

#if KINE_FILAMENT_USE_VULKAN
	std::unique_ptr<backend::Platform> vulkanPlatform;
	backend::VulkanPlatform::VulkanSharedContext vulkanSharedContext;
	void *vulkanCompositor = nullptr;
#endif

	Skybox *skybox = nullptr;
	Texture *skyTexture = nullptr;
	IndirectLight *indirectLight = nullptr;
	double nearPlane = 0.1;
	double farPlane = 500.0;
	void *filamentCtx = nullptr;
	math::float4 skyColor = {0.53f, 0.81f, 0.92f, 1.0f};

	std::unordered_map<KineBatchKey, KinePendingBatch, KineBatchKeyHash> pendingBatches;
	std::unordered_map<KineBatchKey, KinePersistentBatch, KineBatchKeyHash> builtBatches;
	std::unordered_map<uint64_t, KineRetainedListState> retainedLists;
	uint64_t batchFrame = 1;
	std::vector<KineDecalResource> decals;
	std::vector<Entity> lights;
#if KINE_FILAMENT_USE_VULKAN && KINE_FILAMENT_ENABLE_VULKAN_READBACK
	std::vector<unsigned char> readbackPixels;
#endif

#if KINE_WITH_RAY
	// Ray path tracer (render mode 2). The path tracer itself lives in
	// kine_ray_shim.cpp; everything here is the Filament side of the bridge.
	void *rayState = nullptr;
	int renderMode = KINE_RENDER_MODE_FILAMENT;
	// Kept here as well so settings survive a NewRay/DestroyRay cycle and can be
	// set before the path tracer exists.
	KineRayProperties rayProperties = kine_ray_default_properties();
	std::vector<KineRayQueuedDraw> rayDraws;
	std::vector<KineRayDraw> rayFrameDraws;
	// KineMesh stores 16-bit indices; Ray needs 32-bit. Converting once per mesh
	// keeps per-frame cost independent of the instance count.
	std::unordered_map<KineMesh *, std::vector<uint32_t>> rayIndexCache;
	Texture *rayTexture = nullptr;
	Material *rayMaterial = nullptr;
	MaterialInstance *rayMaterialInstance = nullptr;
	Scene *rayScene = nullptr;
	View *rayView = nullptr;
	Camera *rayCamera = nullptr;
	Entity rayCameraEntity;
	Entity rayQuadEntity;
	ColorGrading *rayColorGrading = nullptr;
	int rayTextureWidth = 0;
	int rayTextureHeight = 0;
#endif
};

#if KINE_FILAMENT_USE_VULKAN
struct KineFilamentCompositorSwapChain : backend::Platform::SwapChain {};


// Non-owning external image import: the atlas pool owns the allocation, while
// Filament and Skia only keep GPU views of it. No pixel copies or new devices.
struct KineViewportExternalImage : backend::Platform::ExternalImage {
    VkImage image = VK_NULL_HANDLE;
    uint32_t size = 0;
    ~KineViewportExternalImage() noexcept override = default;
};

using KineFilamentVulkanPlatformBase = backend::VulkanPlatform;

// Queries the loader for instance extensions before the instance exists, which
// is the only moment they can be added.
static bool kine_instance_extension_available(const char *name) {
	auto getInstanceProcAddr =
			reinterpret_cast<PFN_vkGetInstanceProcAddr>(SDL_Vulkan_GetVkGetInstanceProcAddr());
	if (!getInstanceProcAddr || !name)
		return false;
	auto enumerate = reinterpret_cast<PFN_vkEnumerateInstanceExtensionProperties>(
			getInstanceProcAddr(nullptr, "vkEnumerateInstanceExtensionProperties"));
	if (!enumerate)
		return false;
	uint32_t count = 0;
	if (enumerate(nullptr, &count, nullptr) != VK_SUCCESS || count == 0)
		return false;
	std::vector<VkExtensionProperties> properties(count);
	if (enumerate(nullptr, &count, properties.data()) != VK_SUCCESS)
		return false;
	for (uint32_t i = 0; i < count; ++i) {
		if (std::strcmp(properties[i].extensionName, name) == 0)
			return true;
	}
	return false;
}

class KineFilamentCompositorVulkanPlatform final : public KineFilamentVulkanPlatformBase {
  public:
	KineFilamentCompositorVulkanPlatform(void *sdlWindow, int width, int height)
		: mSdlWindow(sdlWindow),
		  mWidth(width),
		  mHeight(height) {}

	~KineFilamentCompositorVulkanPlatform() override {
		this->destroyCompositor();
	}


    ExternalImageMetadata extractExternalImageMetadata(ExternalImageHandleRef handle) const override {
        auto *image = static_cast<const KineViewportExternalImage *>(handle.get());
        ExternalImageMetadata out{};
        out.filamentFormat = backend::TextureFormat::RGBA8;
        out.filamentUsage = backend::TextureUsage::COLOR_ATTACHMENT | backend::TextureUsage::SAMPLEABLE;
        out.width = out.height = image->size; out.layers = 1;
        out.samples = VK_SAMPLE_COUNT_1_BIT; out.format = VK_FORMAT_R8G8B8A8_UNORM;
        out.usage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT;
        return out;
    }
    ImageData createVkImageFromExternal(ExternalImageHandleRef handle, uint32_t, uint32_t) const override {
        ImageData out{};
        out.internal.image = static_cast<const KineViewportExternalImage *>(handle.get())->image;
        // A null memory handle leaves ownership with the atlas pool.
        return out;
    }

	KineVulkanCompositor *compositor() const noexcept {
		return mCompositor;
	}

	void setExtent(int width, int height) noexcept {
		mWidth = width;
		mHeight = height;
	}

	void destroyCompositor() noexcept {
		if (mCompositor) {
			Kine_VulkanCompositor_Destroy(mCompositor);
			mCompositor = nullptr;
		}
	}

	Customization getCustomization() const noexcept override {
		Customization customization{};
		customization.transitionSwapChainImageLayoutForPresent = false;
		return customization;
	}

	SwapChainBundle getSwapChainBundle(SwapChainPtr handle) override {
		(void)handle;
		SwapChainBundle bundle{};
		if (!mCompositor) {
			return bundle;
		}

		KineVulkanCompositorInfo info{};
		if (!Kine_VulkanCompositor_GetInfo(mCompositor, &info)) {
			return bundle;
		}

		uint32_t count = Kine_VulkanCompositor_GetSwapchainImages(mCompositor, nullptr, 0);
		std::vector<void *> images(count);
		if (count > 0) {
			Kine_VulkanCompositor_GetSwapchainImages(mCompositor, images.data(), count);
		}

		bundle.colors = utils::FixedCapacityVector<VkImage>::with_capacity(count);
		for (uint32_t i = 0; i < count; ++i) {
			bundle.colors.push_back(reinterpret_cast<VkImage>(images[i]));
		}

		void *depthImage = nullptr;
		uint32_t depthFormat = 0;
		if (Kine_VulkanCompositor_GetDepthAttachment(mCompositor, &depthImage, &depthFormat)) {
			bundle.depth = reinterpret_cast<VkImage>(depthImage);
			bundle.depthFormat = static_cast<VkFormat>(depthFormat);
		}
		bundle.colorFormat = static_cast<VkFormat>(info.swapchainFormat);
		bundle.extent = {info.width, info.height};
		bundle.layerCount = 1;
		bundle.isProtected = false;
		if (!mLoggedBundle) {
			fprintf(stderr,
					"[Kine] Filament compositor bundle: colors=%u colorFormat=%u depth=%p depthFormat=%u extent=%ux%u\n",
					count,
					static_cast<uint32_t>(bundle.colorFormat),
					static_cast<void *>(bundle.depth),
					static_cast<uint32_t>(bundle.depthFormat),
					bundle.extent.width,
					bundle.extent.height);
			mLoggedBundle = true;
		}
		return bundle;
	}

	VkResult acquire(SwapChainPtr handle, ImageSyncData *outImageSyncData) override {
		(void)handle;
		if (!outImageSyncData || !mCompositor) {
			return VK_ERROR_INITIALIZATION_FAILED;
		}

		void *imageReadySemaphore = nullptr;
		uint32_t imageIndex = ImageSyncData::INVALID_IMAGE_INDEX;
		VkResult result = static_cast<VkResult>(Kine_VulkanCompositor_FilamentAcquire(
			mCompositor,
			&imageIndex,
			&imageReadySemaphore));
		if (result == VK_SUCCESS) {
			outImageSyncData->imageIndex = imageIndex;
			outImageSyncData->imageReadySemaphore = reinterpret_cast<VkSemaphore>(imageReadySemaphore);
			if (!mLoggedAcquire) {
				fprintf(stderr,
						"[Kine] Filament compositor acquire: image=%u readySemaphore=%p\n",
						imageIndex,
						imageReadySemaphore);
				mLoggedAcquire = true;
			}
		}
		return result;
	}

	VkResult present(SwapChainPtr handle, uint32_t index, VkSemaphore finishedDrawing) override {
		(void)handle;
		if (!mCompositor) {
			return VK_ERROR_INITIALIZATION_FAILED;
		}
		if (!mLoggedPresent) {
			fprintf(stderr,
					"[Kine] Filament compositor present hook: image=%u finishedSemaphore=%p\n",
					index,
					static_cast<void *>(finishedDrawing));
			mLoggedPresent = true;
		}
		return static_cast<VkResult>(Kine_VulkanCompositor_FilamentPresent(
			mCompositor,
			index,
			reinterpret_cast<void *>(finishedDrawing)));
	}

	bool hasResized(SwapChainPtr handle) override {
		(void)handle;
		return false;
	}

	bool isProtected(SwapChainPtr handle) override {
		(void)handle;
		return false;
	}

	VkResult recreate(SwapChainPtr handle) override {
		(void)handle;
		return VK_SUCCESS;
	}

	SwapChainPtr createSwapChain(void *nativeWindow, uint64_t flags = 0,
								 VkExtent2D extent = {0, 0}) override {
		(void)nativeWindow;
		(void)flags;
		if (extent.width > 0 && extent.height > 0) {
			mWidth = static_cast<int>(extent.width);
			mHeight = static_cast<int>(extent.height);
		}
		if (!mCompositor && mSdlWindow && mWidth > 0 && mHeight > 0) {
			auto getInstanceProcAddr = reinterpret_cast<PFN_vkGetInstanceProcAddr>(
				SDL_Vulkan_GetVkGetInstanceProcAddr());
			PFN_vkGetDeviceProcAddr getDeviceProcAddr = nullptr;
			if (getInstanceProcAddr && this->getInstance()) {
				getDeviceProcAddr = reinterpret_cast<PFN_vkGetDeviceProcAddr>(
					getInstanceProcAddr(this->getInstance(), "vkGetDeviceProcAddr"));
			}

			KineVulkanCompositorBackend backend{};
			backend.instance = this->getInstance();
			backend.physicalDevice = this->getPhysicalDevice();
			backend.device = this->getDevice();
			backend.queue = this->getGraphicsQueue();
			backend.graphicsQueueFamilyIndex = this->getGraphicsQueueFamilyIndex();
			backend.maxApiVersion = VK_API_VERSION_1_1;
			backend.getInstanceProcAddr = reinterpret_cast<void *>(getInstanceProcAddr);
			backend.getDeviceProcAddr = reinterpret_cast<void *>(getDeviceProcAddr);

			fprintf(stderr,
					"[Kine] creating compositor from Filament Vulkan device queueFamily=%u queueIndex=%u size=%dx%d\n",
					this->getGraphicsQueueFamilyIndex(),
					this->getGraphicsQueueIndex(),
					mWidth,
					mHeight);
			mCompositor = Kine_VulkanCompositor_CreateForSDLWindowWithBackend(
				mSdlWindow,
				mWidth,
				mHeight,
				&backend);
			if (!Kine_VulkanCompositor_IsReady(mCompositor)) {
				const char *error = Kine_VulkanCompositor_GetLastError(mCompositor);
				fprintf(stderr,
						"[Kine] compositor-from-Filament creation failed: %s\n",
						error && error[0] ? error : "unknown error");
				Kine_VulkanCompositor_Destroy(mCompositor);
				mCompositor = nullptr;
				return nullptr;
			}
		} else if (mCompositor &&
				   !Kine_VulkanCompositor_Resize(mCompositor, mWidth, mHeight)) {
			const char *error = Kine_VulkanCompositor_GetLastError(mCompositor);
			fprintf(stderr,
					"[Kine] compositor resize failed: %s\n",
					error && error[0] ? error : "unknown error");
			return nullptr;
		}
		return new KineFilamentCompositorSwapChain();
	}

	void destroy(SwapChainPtr handle) override {
		delete static_cast<KineFilamentCompositorSwapChain *>(handle);
	}

  protected:
	ExtensionSet getSwapchainInstanceExtensions() const override {
		ExtensionSet extensions;
		uint32_t count = 0;
		char const *const *required = SDL_Vulkan_GetInstanceExtensions(&count);
		if (required) {
			for (uint32_t i = 0; i < count; ++i) {
				if (required[i]) {
					extensions.emplace(utils::CString(required[i]));
				}
			}
		}
#if defined(__APPLE__)
		extensions.emplace(utils::CString("VK_KHR_portability_enumeration"));
#endif
		return extensions;
	}

	SurfaceBundle createVkSurfaceKHR(void *nativeWindow, VkInstance instance,
									 uint64_t flags) const noexcept override {
		(void)nativeWindow;
		(void)instance;
		(void)flags;
		return {VK_NULL_HANDLE, {0, 0}};
	}

	VkInstance createVkInstance(VkInstanceCreateInfo const &createInfo) noexcept override {
		std::vector<const char *> extensions;
		if (createInfo.enabledExtensionCount > 0 && createInfo.ppEnabledExtensionNames) {
			extensions.assign(
				createInfo.ppEnabledExtensionNames,
				createInfo.ppEnabledExtensionNames + createInfo.enabledExtensionCount);
		}
#if defined(__APPLE__)
		if (std::none_of(extensions.begin(), extensions.end(), [](const char *extension) {
				return extension && std::strcmp(extension, "VK_KHR_portability_enumeration") == 0;
			})) {
			extensions.push_back("VK_KHR_portability_enumeration");
		}
#endif

		// Ray loads the VK_EXT_debug_report and VK_EXT_debug_utils entry points
		// unconditionally when it initializes against this instance, and
		// vkGetInstanceProcAddr only returns them for an instance that enabled the
		// extensions. Filament never asks for either, so they are added here when
		// the loader knows them.
		{
			constexpr const char *rayInstanceExtensions[] = {
					"VK_EXT_debug_report",
					"VK_EXT_debug_utils",
					// Owns vkGetPhysicalDeviceProperties2KHR/Features2KHR, which are
					// instance commands: the loader only hands their KHR aliases out
					// when this extension is enabled, even on a Vulkan 1.x instance
					// where the unsuffixed forms are already core.
					"VK_KHR_get_physical_device_properties2",
			};
			for (const char *required : rayInstanceExtensions) {
				const bool present = std::any_of(
						extensions.begin(), extensions.end(), [required](const char *extension) {
							return extension && std::strcmp(extension, required) == 0;
						});
				if (present) {
					continue;
				}
				if (kine_instance_extension_available(required)) {
					extensions.push_back(required);
				} else {
					fprintf(stderr,
							"[Kine] Vulkan loader does not advertise %s; the Ray path tracer "
							"cannot initialize on this instance\n",
							required);
				}
			}
		}

		VkInstanceCreateInfo compositorCreateInfo = createInfo;
		compositorCreateInfo.enabledExtensionCount = static_cast<uint32_t>(extensions.size());
		compositorCreateInfo.ppEnabledExtensionNames = extensions.data();
#if defined(__APPLE__) && defined(VK_KHR_portability_enumeration)
		compositorCreateInfo.flags |= VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;
#endif
		fprintf(stderr,
				"[Kine] Filament Vulkan creating instance with %u extensions\n",
				compositorCreateInfo.enabledExtensionCount);
		VkInstance instance = KineFilamentVulkanPlatformBase::createVkInstance(compositorCreateInfo);
		fprintf(stderr, "[Kine] Filament Vulkan instance created: %p\n",
				static_cast<void *>(instance));
		return instance;
	}

	VkDevice createVkDevice(VkDeviceCreateInfo const &createInfo) noexcept override {
		std::vector<const char *> extensions;
		if (createInfo.enabledExtensionCount > 0 && createInfo.ppEnabledExtensionNames) {
			extensions.assign(
				createInfo.ppEnabledExtensionNames,
				createInfo.ppEnabledExtensionNames + createInfo.enabledExtensionCount);
		}
		const bool hasSwapchain = std::any_of(
			extensions.begin(),
			extensions.end(),
			[](const char *extension) {
				return extension &&
					   strcmp(extension, VK_KHR_SWAPCHAIN_EXTENSION_NAME) == 0;
			});
		if (!hasSwapchain) {
			extensions.push_back(VK_KHR_SWAPCHAIN_EXTENSION_NAME);
		}
#if defined(__APPLE__)
		const bool hasPortabilitySubset = std::any_of(
			extensions.begin(),
			extensions.end(),
			[](const char *extension) {
				return extension && std::strcmp(extension, "VK_KHR_portability_subset") == 0;
			});
		if (!hasPortabilitySubset) {
			extensions.push_back("VK_KHR_portability_subset");
		}
#endif

		// Ray, the path tracer embedded in this shim, runs on this device and needs
		// features Filament never asks for:
		//   - descriptor indexing, because every descriptor set layout it builds
		//     carries VK_DESCRIPTOR_BINDING_PARTIALLY_BOUND_BIT;
		//   - shaderFloat16 + 16-bit storage, because it selects its precompiled
		//     fp16 filter kernels whenever the physical device advertises
		//     shaderFloat16, and those kernels declare float16_t storage buffers.
		// Filament and Skia use none of them, so each is only enabled when the
		// physical device supports it.
		VkPhysicalDeviceDescriptorIndexingFeaturesEXT indexingFeatures{};
		VkPhysicalDevice16BitStorageFeatures storage16Features{};
		VkPhysicalDeviceShaderFloat16Int8Features fp16Features{};
		bool enableDescriptorIndexing = false;
		bool enableStorage16 = false;
		bool enableShaderFloat16 = false;
		{
			const VkInstance instance = this->getInstance();
			const VkPhysicalDevice physicalDevice = this->getPhysicalDevice();
			auto getInstanceProcAddr = reinterpret_cast<PFN_vkGetInstanceProcAddr>(
					SDL_Vulkan_GetVkGetInstanceProcAddr());
			auto getPhysicalDeviceFeatures2 =
					(instance && getInstanceProcAddr)
							? reinterpret_cast<PFN_vkGetPhysicalDeviceFeatures2>(
									  getInstanceProcAddr(instance, "vkGetPhysicalDeviceFeatures2"))
							: nullptr;
			auto getPhysicalDeviceProperties =
					(instance && getInstanceProcAddr)
							? reinterpret_cast<PFN_vkGetPhysicalDeviceProperties>(
									  getInstanceProcAddr(instance, "vkGetPhysicalDeviceProperties"))
							: nullptr;
			// The 16-bit and float16 structs are core in Vulkan 1.1/1.2, so they can
			// only be chained onto a device created at those API versions.
			uint32_t apiVersion = VK_API_VERSION_1_0;
			if (getPhysicalDeviceProperties && physicalDevice) {
				VkPhysicalDeviceProperties properties{};
				getPhysicalDeviceProperties(physicalDevice, &properties);
				apiVersion = properties.apiVersion;
			}
			if (getPhysicalDeviceFeatures2 && physicalDevice) {
				indexingFeatures.sType =
						VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_INDEXING_FEATURES_EXT;
				storage16Features.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_16BIT_STORAGE_FEATURES;
				fp16Features.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_FLOAT16_INT8_FEATURES;
				indexingFeatures.pNext = &storage16Features;
				storage16Features.pNext = &fp16Features;
				fp16Features.pNext = nullptr;

				VkPhysicalDeviceFeatures2 features2{};
				features2.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2;
				features2.pNext = &indexingFeatures;
				getPhysicalDeviceFeatures2(physicalDevice, &features2);

				enableDescriptorIndexing =
						indexingFeatures.descriptorBindingPartiallyBound == VK_TRUE;
				enableStorage16 = apiVersion >= VK_API_VERSION_1_1 &&
						storage16Features.storageBuffer16BitAccess == VK_TRUE;
				enableShaderFloat16 = apiVersion >= VK_API_VERSION_1_2 &&
						fp16Features.shaderFloat16 == VK_TRUE;
			}
			if (enableDescriptorIndexing) {
				const bool hasDescriptorIndexing = std::any_of(
						extensions.begin(),
						extensions.end(),
						[](const char *extension) {
							return extension &&
								   strcmp(extension, VK_EXT_DESCRIPTOR_INDEXING_EXTENSION_NAME) == 0;
						});
				if (!hasDescriptorIndexing) {
					extensions.push_back(VK_EXT_DESCRIPTOR_INDEXING_EXTENSION_NAME);
				}
			}
		}

		VkDeviceCreateInfo compositorCreateInfo = createInfo;
		compositorCreateInfo.enabledExtensionCount =
			static_cast<uint32_t>(extensions.size());
		compositorCreateInfo.ppEnabledExtensionNames = extensions.data();
		if (enableDescriptorIndexing) {
			// pEnabledFeatures may stay set: only VkPhysicalDeviceFeatures2 in the
			// chain is mutually exclusive with it.
			void *chain = const_cast<void *>(compositorCreateInfo.pNext);
			indexingFeatures.sType =
					VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_INDEXING_FEATURES_EXT;
			indexingFeatures.pNext = chain;
			chain = &indexingFeatures;
			if (enableStorage16) {
				storage16Features.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_16BIT_STORAGE_FEATURES;
				storage16Features.pNext = chain;
				chain = &storage16Features;
			}
			if (enableShaderFloat16) {
				fp16Features.sType =
						VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_FLOAT16_INT8_FEATURES;
				fp16Features.pNext = chain;
				chain = &fp16Features;
			}
			compositorCreateInfo.pNext = chain;
			fprintf(stderr,
					"[Kine] Filament Vulkan: enabled descriptor indexing for Ray "
					"(16-bit storage %s, shaderFloat16 %s)\n",
					enableStorage16 ? "on" : "off",
					enableShaderFloat16 ? "on" : "off");
		}

		fprintf(stderr,
				"[Kine] Filament Vulkan creating device with %u extensions and %u queue groups\n",
				compositorCreateInfo.enabledExtensionCount,
				compositorCreateInfo.queueCreateInfoCount);
		VkDevice device = KineFilamentVulkanPlatformBase::createVkDevice(compositorCreateInfo);
		fprintf(stderr, "[Kine] Filament Vulkan device created: %p\n",
				static_cast<void *>(device));
		return device;
	}

  private:
	KineVulkanCompositor *mCompositor = nullptr;
	void *mSdlWindow = nullptr;
	int mWidth = 0;
	int mHeight = 0;
	bool mLoggedBundle = false;
	bool mLoggedAcquire = false;
	bool mLoggedPresent = false;
};
#endif

#if !KINE_FILAMENT_USE_VULKAN
static void kine_capture_host_context(KineFilamentContext *ctx) {
#if defined(_WIN32)
	ctx->hostCtx = (void *)wglGetCurrentContext();
	ctx->hostDC = (void *)wglGetCurrentDC();
#elif defined(__ANDROID__)
	ctx->hostCtx = (void *)eglGetCurrentContext();
	ctx->hostDisplay = (void *)eglGetCurrentDisplay();
	ctx->hostDrawable = (unsigned long)eglGetCurrentSurface(EGL_DRAW);
#elif defined(__APPLE__)
	ctx->hostCtx = (void *)CGLGetCurrentContext();
#else
	ctx->hostCtx = (void *)glXGetCurrentContext();
	ctx->hostDisplay = (void *)glXGetCurrentDisplay();
	ctx->hostDrawable = (unsigned long)glXGetCurrentDrawable();
#endif
}

static void kine_release_current_gl_context() {
#if defined(_WIN32)
	wglMakeCurrent(nullptr, nullptr);
#elif defined(__ANDROID__)
	EGLDisplay dpy = eglGetCurrentDisplay();
	if (dpy != EGL_NO_DISPLAY)
		eglMakeCurrent(dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
#elif defined(__APPLE__)
	CGLSetCurrentContext(nullptr);
#else
	Display *dpy = glXGetCurrentDisplay();
	if (dpy)
		glXMakeCurrent(dpy, None, nullptr);
#endif
}

static void kine_restore_host_context(KineFilamentContext *ctx) {
	if (!ctx || !ctx->hostCtx)
		return;
#if defined(_WIN32)
	wglMakeCurrent((HDC)ctx->hostDC, (HGLRC)ctx->hostCtx);
#elif defined(__ANDROID__)
	if (ctx->hostDisplay) {
		EGLSurface surf = (EGLSurface)ctx->hostDrawable;
		eglMakeCurrent((EGLDisplay)ctx->hostDisplay, surf, surf,
					   (EGLContext)ctx->hostCtx);
	}
#elif defined(__APPLE__)
	CGLSetCurrentContext((CGLContextObj)ctx->hostCtx);
#else
	if (ctx->hostDisplay)
		glXMakeCurrent((Display *)ctx->hostDisplay,
					   (GLXDrawable)ctx->hostDrawable,
					   (GLXContext)ctx->hostCtx);
#endif
}
#endif

namespace {

#if !KINE_FILAMENT_USE_VULKAN
static unsigned int createGLColorTexture(int width, int height) {
	GLuint id = 0;
	glGenTextures(1, &id);
	if (id == 0)
		return 0;
	glBindTexture(GL_TEXTURE_2D, id);
	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
	glBindTexture(GL_TEXTURE_2D, 0);
	return (unsigned int)id;
}
#endif

bool rebuildRenderTarget(KineFilamentContext *ctx, int width, int height) {
#if !KINE_FILAMENT_USE_VULKAN
	if (ctx->readFboId) {
		GLuint f = (GLuint)ctx->readFboId;
		kine_glDeleteFramebuffers(1, &f);
		ctx->readFboId = 0;
	}
#endif
	if (ctx->renderTarget) {
		ctx->engine->destroy(ctx->renderTarget);
		ctx->renderTarget = nullptr;
	}
	if (ctx->colorTarget) {
		ctx->engine->destroy(ctx->colorTarget);
		ctx->colorTarget = nullptr;
	}
	if (ctx->depthTarget) {
		ctx->engine->destroy(ctx->depthTarget);
		ctx->depthTarget = nullptr;
	}

	ctx->engine->flushAndWait();

#if !KINE_FILAMENT_USE_VULKAN
	if (ctx->colorTextureId) {
		GLuint old = (GLuint)ctx->colorTextureId;
		glDeleteTextures(1, &old);
		ctx->colorTextureId = 0;
	}
#endif

#if KINE_FILAMENT_USE_VULKAN
	ctx->colorTarget = Texture::Builder()
						   .width(uint32_t(width))
						   .height(uint32_t(height))
						   .levels(1)
						   .usage(Texture::Usage::COLOR_ATTACHMENT | Texture::Usage::SAMPLEABLE |
								  Texture::Usage::BLIT_SRC)
						   .format(Texture::InternalFormat::RGBA8)
						   .build(*ctx->engine);
#else
	unsigned int glId = createGLColorTexture(width, height);
	if (glId == 0)
		return false;
	ctx->colorTarget = Texture::Builder()
						   .width(uint32_t(width))
						   .height(uint32_t(height))
						   .levels(1)
						   .usage(Texture::Usage::COLOR_ATTACHMENT | Texture::Usage::SAMPLEABLE)
						   .format(Texture::InternalFormat::RGBA8)
						   .import(glId)
						   .build(*ctx->engine);
#endif
	if (!ctx->colorTarget)
		return false;

	ctx->depthTarget = Texture::Builder()
						   .width(uint32_t(width))
						   .height(uint32_t(height))
						   .levels(1)
						   .usage(Texture::Usage::DEPTH_ATTACHMENT | Texture::Usage::SAMPLEABLE)
						   .format(Texture::InternalFormat::DEPTH24)
						   .build(*ctx->engine);
	if (!ctx->depthTarget)
		return false;

	ctx->renderTarget = RenderTarget::Builder()
							.texture(RenderTarget::AttachmentPoint::COLOR, ctx->colorTarget)
							.texture(RenderTarget::AttachmentPoint::DEPTH, ctx->depthTarget)
							.build(*ctx->engine);
	if (!ctx->renderTarget)
		return false;

	ctx->view->setRenderTarget(ctx->renderTarget);
	ctx->view->setViewport({0, 0, uint32_t(width), uint32_t(height)});
	ctx->viewportX = 0;
	ctx->viewportY = 0;
	ctx->viewportWidth = width;
	ctx->viewportHeight = height;
#if KINE_FILAMENT_USE_VULKAN
	ctx->colorTextureId = 0;
#else
	ctx->colorTextureId = glId;
#endif
	ctx->width = width;
	ctx->height = height;
	return true;
}

static bool useDefaultSwapChainRenderTarget(KineFilamentContext *ctx, int width, int height) {
	if (!ctx || !ctx->view) {
		return false;
	}

	if (ctx->readFboId) {
#if !KINE_FILAMENT_USE_VULKAN
		GLuint f = (GLuint)ctx->readFboId;
		kine_glDeleteFramebuffers(1, &f);
#endif
		ctx->readFboId = 0;
	}
	if (ctx->renderTarget) {
		ctx->engine->destroy(ctx->renderTarget);
		ctx->renderTarget = nullptr;
	}
	if (ctx->colorTarget) {
		ctx->engine->destroy(ctx->colorTarget);
		ctx->colorTarget = nullptr;
	}
	if (ctx->depthTarget) {
		ctx->engine->destroy(ctx->depthTarget);
		ctx->depthTarget = nullptr;
	}
	if (ctx->colorTextureId) {
#if !KINE_FILAMENT_USE_VULKAN
		GLuint old = (GLuint)ctx->colorTextureId;
		glDeleteTextures(1, &old);
#endif
		ctx->colorTextureId = 0;
	}

	ctx->view->setRenderTarget(nullptr);
	ctx->view->setViewport({0, 0, uint32_t(width), uint32_t(height)});
	ctx->viewportX = 0;
	ctx->viewportY = 0;
	ctx->viewportWidth = width;
	ctx->viewportHeight = height;
	ctx->width = width;
	ctx->height = height;
	return true;
}

static void *getFilamentNativeWindowFromSDL(void *sdlWindow) {
	if (!sdlWindow) {
		return nullptr;
	}

	Uint64 flags = SDL_GetWindowFlags((SDL_Window *)sdlWindow);
	SDL_PropertiesID props = SDL_GetWindowProperties((SDL_Window *)sdlWindow);
	if (!props) {
		fprintf(stderr, "[Kine] SDL_GetWindowProperties failed for Vulkan window, flags=0x%llx\n",
				(unsigned long long)flags);
		return nullptr;
	}

#if defined(_WIN32)
	void *hwnd = SDL_GetPointerProperty(props, SDL_PROP_WINDOW_WIN32_HWND_POINTER, nullptr);
	if (hwnd) {
		fprintf(stderr, "[Kine] SDL Vulkan native window: flags=0x%llx hwnd=%p\n",
				(unsigned long long)flags, hwnd);
		return hwnd;
	}
	void *hdc = SDL_GetPointerProperty(props, SDL_PROP_WINDOW_WIN32_HDC_POINTER, nullptr);
	fprintf(stderr, "[Kine] SDL Vulkan native window missing HWND, flags=0x%llx hdc=%p\n",
			(unsigned long long)flags, hdc);
	return nullptr;
#elif defined(__ANDROID__)
	void *nativeWindow = SDL_GetPointerProperty(props, SDL_PROP_WINDOW_ANDROID_WINDOW_POINTER, nullptr);
	fprintf(stderr, "[Kine] SDL Vulkan native window: flags=0x%llx androidWindow=%p\n",
			(unsigned long long)flags, nativeWindow);
	return nativeWindow;
#elif defined(__APPLE__)
	void *cocoaWindow = SDL_GetPointerProperty(props, SDL_PROP_WINDOW_COCOA_WINDOW_POINTER, nullptr);
	fprintf(stderr, "[Kine] SDL Vulkan native window: flags=0x%llx cocoaWindow=%p\n",
			(unsigned long long)flags, cocoaWindow);
	return cocoaWindow;
#else
	void *waylandSurface = SDL_GetPointerProperty(props, SDL_PROP_WINDOW_WAYLAND_SURFACE_POINTER, nullptr);
	if (waylandSurface) {
		fprintf(stderr, "[Kine] SDL Vulkan native window: flags=0x%llx waylandSurface=%p\n",
				(unsigned long long)flags, waylandSurface);
		return waylandSurface;
	}
	Sint64 x11Window = SDL_GetNumberProperty(props, SDL_PROP_WINDOW_X11_WINDOW_NUMBER, 0);
	fprintf(stderr, "[Kine] SDL Vulkan native window: flags=0x%llx x11Window=0x%llx\n",
			(unsigned long long)flags, (unsigned long long)x11Window);
	return x11Window ? (void *)(uintptr_t)x11Window : nullptr;
#endif
}

static KineMesh *buildCube() {
	auto *m = new KineMesh();

	const float n = 0.5f;
	struct Face {
		float nx, ny, nz;
		float ax, ay, az;
		float bx, by, bz;
	};
	Face faces[6] = {
		{0, 0, 1, 1, 0, 0, 0, 1, 0},
		{0, 0, -1, -1, 0, 0, 0, 1, 0},
		{1, 0, 0, 0, 1, 0, 0, 0, 1},
		{-1, 0, 0, 0, 1, 0, 0, 0, -1},
		{0, 1, 0, 1, 0, 0, 0, 0, -1},
		{0, -1, 0, 1, 0, 0, 0, 0, 1},
	};

	for (int f = 0; f < 6; f++) {
		uint32_t base = (uint32_t)(m->vertices.size());
		float nx = faces[f].nx, ny = faces[f].ny, nz = faces[f].nz;
		float ax = faces[f].ax, ay = faces[f].ay, az = faces[f].az;
		float bx = faces[f].bx, by = faces[f].by, bz = faces[f].bz;

		float cx = nx * n, cy = ny * n, cz = nz * n;

		float signs[4][2] = {{-1, -1}, {1, -1}, {1, 1}, {-1, 1}};
		for (auto &s : signs) {
			KineVertex v;
			v.px = cx + s[0] * ax * n + s[1] * bx * n;
			v.py = cy + s[0] * ay * n + s[1] * by * n;
			v.pz = cz + s[0] * az * n + s[1] * bz * n;
			v.nx = nx;
			v.ny = ny;
			v.nz = nz;
			v.u = (s[0] + 1) * 0.5f;
			v.v = (s[1] + 1) * 0.5f;
			m->vertices.push_back(v);
		}
		m->indices.push_back(base + 0);
		m->indices.push_back(base + 1);
		m->indices.push_back(base + 2);
		m->indices.push_back(base + 0);
		m->indices.push_back(base + 2);
		m->indices.push_back(base + 3);
	}
	m->indexCount = (uint32_t)m->indices.size();
	return m;
}

static KineMesh *buildDisplacedCube(int segments = 48) {
	auto *m = new KineMesh();
	const float n = 0.5f;
	struct Face {
		float nx, ny, nz;
		float ax, ay, az;
		float bx, by, bz;
	};
	const Face faces[6] = {
		{0, 0, 1, 1, 0, 0, 0, 1, 0},
		{0, 0, -1, -1, 0, 0, 0, 1, 0},
		{1, 0, 0, 0, 1, 0, 0, 0, 1},
		{-1, 0, 0, 0, 1, 0, 0, 0, -1},
		{0, 1, 0, 1, 0, 0, 0, 0, -1},
		{0, -1, 0, 1, 0, 0, 0, 0, 1},
	};

	for (const Face &face : faces) {
		const uint32_t base = (uint32_t)m->vertices.size();
		for (int y = 0; y <= segments; ++y) {
			const float v = (float)y / (float)segments;
			const float sv = v - 0.5f;
			for (int x = 0; x <= segments; ++x) {
				const float u = (float)x / (float)segments;
				const float su = u - 0.5f;
				m->vertices.push_back({
					face.nx * n + face.ax * su + face.bx * sv,
					face.ny * n + face.ay * su + face.by * sv,
					face.nz * n + face.az * su + face.bz * sv,
					face.nx,
					face.ny,
					face.nz,
					u,
					v,
				});
			}
		}

		const int row = segments + 1;
		for (int y = 0; y < segments; ++y) {
			for (int x = 0; x < segments; ++x) {
				const uint32_t i0 = base + (uint32_t)(y * row + x);
				const uint32_t i1 = i0 + 1;
				const uint32_t i3 = base + (uint32_t)((y + 1) * row + x);
				const uint32_t i2 = i3 + 1;
				m->indices.push_back(i0);
				m->indices.push_back(i1);
				m->indices.push_back(i2);
				m->indices.push_back(i0);
				m->indices.push_back(i2);
				m->indices.push_back(i3);
			}
		}
	}
	m->indexCount = (uint32_t)m->indices.size();
	return m;
}

static KineMesh *buildWaterGrid(int segments = 32) {

	auto *m = new KineMesh();

	const int row = segments + 1;
	m->vertices.reserve((size_t)row * row);
	m->indices.reserve((size_t)segments * segments * 6);

	for (int z = 0; z <= segments; ++z) {
		const float v = (float)z / (float)segments - 0.5f;
		for (int x = 0; x <= segments; ++x) {
			const float u = (float)x / (float)segments - 0.5f;
			KineVertex vtx;
			vtx.px = u;
			vtx.py = 0.5f;
			vtx.pz = v;
			vtx.nx = 0.0f;
			vtx.ny = 1.0f;
			vtx.nz = 0.0f;
			vtx.u = u + 0.5f;
			vtx.v = v + 0.5f;
			m->vertices.push_back(vtx);
		}
	}

	for (int z = 0; z < segments; ++z) {
		for (int x = 0; x < segments; ++x) {
			const uint32_t i0 = (uint32_t)(z * row + x);
			const uint32_t i1 = i0 + 1;
			const uint32_t i3 = (uint32_t)((z + 1) * row + x);
			const uint32_t i2 = i3 + 1;

			m->indices.push_back(i0);
			m->indices.push_back(i3);
			m->indices.push_back(i1);
			m->indices.push_back(i1);
			m->indices.push_back(i3);
			m->indices.push_back(i2);
		}
	}
	m->indexCount = (uint32_t)m->indices.size();
	return m;
}

static KineMesh *buildSphere(int slices = 16, int stacks = 12) {
	auto *m = new KineMesh();
	for (int j = 0; j <= stacks; j++) {
		float phi = (float)M_PI * j / stacks;
		for (int i = 0; i <= slices; i++) {
			float theta = 2.0f * (float)M_PI * i / slices;
			KineVertex v;
			v.nx = sinf(phi) * cosf(theta);
			v.ny = cosf(phi);
			v.nz = sinf(phi) * sinf(theta);
			v.px = v.nx * 0.5f;
			v.py = v.ny * 0.5f;
			v.pz = v.nz * 0.5f;
			v.u = (float)i / slices;
			v.v = (float)j / stacks;
			m->vertices.push_back(v);
		}
	}
	for (int j = 0; j < stacks; j++) {
		for (int i = 0; i < slices; i++) {
			uint32_t a = (uint32_t)(j * (slices + 1) + i);
			uint32_t b = (uint32_t)(a + slices + 1);

			m->indices.push_back(a);
			m->indices.push_back(a + 1);
			m->indices.push_back(b);
			m->indices.push_back(b);
			m->indices.push_back(a + 1);
			m->indices.push_back(b + 1);
		}
	}
	m->indexCount = (uint32_t)m->indices.size();
	return m;
}

static KineMesh *buildCylinder(int slices = 24) {
	auto *m = new KineMesh();
	const float radius = 0.5f;
	const float halfHeight = 0.5f;

	for (int i = 0; i <= slices; ++i) {
		const float u = static_cast<float>(i) / static_cast<float>(slices);
		const float angle = u * 2.0f * static_cast<float>(M_PI);
		const float x = cosf(angle);
		const float z = sinf(angle);
		m->vertices.push_back({x * radius, -halfHeight, z * radius, x, 0.0f, z, u, 0.0f});
		m->vertices.push_back({x * radius, halfHeight, z * radius, x, 0.0f, z, u, 1.0f});
	}
	for (int i = 0; i < slices; ++i) {
		const uint32_t bottom = static_cast<uint32_t>(i * 2);
		const uint32_t top = static_cast<uint32_t>(bottom + 1);
		const uint32_t nextBottom = static_cast<uint32_t>(bottom + 2);
		const uint32_t nextTop = static_cast<uint32_t>(bottom + 3);
		m->indices.push_back(bottom);
		m->indices.push_back(top);
		m->indices.push_back(nextBottom);
		m->indices.push_back(nextBottom);
		m->indices.push_back(top);
		m->indices.push_back(nextTop);
	}

	const uint32_t topCenter = static_cast<uint32_t>(m->vertices.size());
	m->vertices.push_back({0.0f, halfHeight, 0.0f, 0.0f, 1.0f, 0.0f, 0.5f, 0.5f});
	const uint32_t topRing = static_cast<uint32_t>(m->vertices.size());
	for (int i = 0; i < slices; ++i) {
		const float angle = static_cast<float>(i) / static_cast<float>(slices) * 2.0f * static_cast<float>(M_PI);
		const float x = cosf(angle);
		const float z = sinf(angle);
		m->vertices.push_back({x * radius, halfHeight, z * radius, 0.0f, 1.0f, 0.0f,
							   x * 0.5f + 0.5f, z * 0.5f + 0.5f});
	}

	const uint32_t bottomCenter = static_cast<uint32_t>(m->vertices.size());
	m->vertices.push_back({0.0f, -halfHeight, 0.0f, 0.0f, -1.0f, 0.0f, 0.5f, 0.5f});
	const uint32_t bottomRing = static_cast<uint32_t>(m->vertices.size());
	for (int i = 0; i < slices; ++i) {
		const float angle = static_cast<float>(i) / static_cast<float>(slices) * 2.0f * static_cast<float>(M_PI);
		const float x = cosf(angle);
		const float z = sinf(angle);
		m->vertices.push_back({x * radius, -halfHeight, z * radius, 0.0f, -1.0f, 0.0f,
							   x * 0.5f + 0.5f, z * 0.5f + 0.5f});
	}

	for (int i = 0; i < slices; ++i) {
		const uint32_t currentTop = static_cast<uint32_t>(topRing + i);
		const uint32_t nextTop = static_cast<uint32_t>(topRing + (i + 1) % slices);
		m->indices.push_back(topCenter);
		m->indices.push_back(nextTop);
		m->indices.push_back(currentTop);

		const uint32_t currentBottom = static_cast<uint32_t>(bottomRing + i);
		const uint32_t nextBottom = static_cast<uint32_t>(bottomRing + (i + 1) % slices);
		m->indices.push_back(bottomCenter);
		m->indices.push_back(currentBottom);
		m->indices.push_back(nextBottom);
	}

	m->indexCount = static_cast<uint32_t>(m->indices.size());
	return m;
}

static KineMesh *buildPyramid() {
	auto *m = new KineMesh();

	const float h = 0.5f, b = 0.5f;
	float apex[3] = {0, h, 0};
	float base4[4][3] = {{-b, 0, -b}, {b, 0, -b}, {b, 0, b}, {-b, 0, b}};

	for (int i = 0; i < 4; i++) {
		float *p0 = base4[i];
		float *p1 = base4[(i + 1) % 4];

		float ax = p1[0] - p0[0], ay = p1[1] - p0[1], az = p1[2] - p0[2];
		float bx = apex[0] - p0[0], by2 = apex[1] - p0[1], bz = apex[2] - p0[2];
		float nx = ay * bz - az * by2, ny = az * bx - ax * bz, nz = ax * by2 - ay * bx;
		float len = sqrtf(nx * nx + ny * ny + nz * nz) + 1e-9f;
		nx /= len;
		ny /= len;
		nz /= len;
		uint32_t base = (uint32_t)m->vertices.size();
		m->vertices.push_back({apex[0], apex[1], apex[2], nx, ny, nz, 0.5f, 1.0f});
		m->vertices.push_back({p0[0], p0[1], p0[2], nx, ny, nz, 0.0f, 0.0f});
		m->vertices.push_back({p1[0], p1[1], p1[2], nx, ny, nz, 1.0f, 0.0f});
		m->indices.push_back(base);
		m->indices.push_back(base + 1);
		m->indices.push_back(base + 2);
	}

	uint32_t base = (uint32_t)m->vertices.size();
	for (auto &p : base4) {
		float u = (p[0] / b + 1) * 0.5f, v2 = (p[2] / b + 1) * 0.5f;
		m->vertices.push_back({p[0], p[1], p[2], 0, -1, 0, u, v2});
	}
	m->indices.push_back(base);
	m->indices.push_back(base + 2);
	m->indices.push_back(base + 1);
	m->indices.push_back(base);
	m->indices.push_back(base + 3);
	m->indices.push_back(base + 2);
	m->indexCount = (uint32_t)m->indices.size();
	return m;
}

static KineMesh *buildDecalQuad() {
	auto *m = new KineMesh();
	m->vertices = {
		{-0.5f, 0.0f, -0.5f, 0.0f, 1.0f, 0.0f, 0.0f, 0.0f},
		{0.5f, 0.0f, -0.5f, 0.0f, 1.0f, 0.0f, 1.0f, 0.0f},
		{0.5f, 0.0f, 0.5f, 0.0f, 1.0f, 0.0f, 1.0f, 1.0f},
		{-0.5f, 0.0f, 0.5f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f},
	};

	m->indices = {0, 2, 1, 0, 3, 2};
	m->indexCount = (uint32_t)m->indices.size();
	return m;
}

static KineMesh *buildParticleQuad() {
	auto *m = new KineMesh();
	m->vertices = {
		{-0.5f, -0.5f, 0.0f, 0.0f, 0.0f, 1.0f, 0.0f, 1.0f},
		{0.5f, -0.5f, 0.0f, 0.0f, 0.0f, 1.0f, 1.0f, 1.0f},
		{0.5f, 0.5f, 0.0f, 0.0f, 0.0f, 1.0f, 1.0f, 0.0f},
		{-0.5f, 0.5f, 0.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f},
	};
	m->indices = {0, 1, 2, 0, 2, 3};
	m->indexCount = (uint32_t)m->indices.size();
	return m;
}

static KineMesh *buildPostProcessQuad() {
	auto *m = new KineMesh();
	m->vertices = {
		{-0.5f, -0.5f, 0.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f},
		{0.5f, -0.5f, 0.0f, 0.0f, 0.0f, 1.0f, 1.0f, 0.0f},
		{0.5f, 0.5f, 0.0f, 0.0f, 0.0f, 1.0f, 1.0f, 1.0f},
		{-0.5f, 0.5f, 0.0f, 0.0f, 0.0f, 1.0f, 0.0f, 1.0f},
	};
	m->indices = {0, 1, 2, 0, 2, 3};
	m->indexCount = (uint32_t)m->indices.size();
	return m;
}

static void appendCuboid(KineMesh *m, float cx, float cy, float cz, float sx, float sy, float sz) {
	const float x0 = cx - sx * 0.5f, x1 = cx + sx * 0.5f;
	const float y0 = cy - sy * 0.5f, y1 = cy + sy * 0.5f;
	const float z0 = cz - sz * 0.5f, z1 = cz + sz * 0.5f;

	struct Face {
		float n[3];
		float p[4][3];
	};
	const Face faces[6] = {
		{{1, 0, 0}, {{x1, y0, z0}, {x1, y1, z0}, {x1, y1, z1}, {x1, y0, z1}}},
		{{-1, 0, 0}, {{x0, y0, z1}, {x0, y1, z1}, {x0, y1, z0}, {x0, y0, z0}}},
		{{0, 1, 0}, {{x0, y1, z0}, {x0, y1, z1}, {x1, y1, z1}, {x1, y1, z0}}},
		{{0, -1, 0}, {{x0, y0, z1}, {x0, y0, z0}, {x1, y0, z0}, {x1, y0, z1}}},
		{{0, 0, 1}, {{x0, y0, z1}, {x1, y0, z1}, {x1, y1, z1}, {x0, y1, z1}}},
		{{0, 0, -1}, {{x1, y0, z0}, {x0, y0, z0}, {x0, y1, z0}, {x1, y1, z0}}},
	};

	for (const Face &f : faces) {
		uint32_t base = (uint32_t)m->vertices.size();
		m->vertices.push_back({f.p[0][0], f.p[0][1], f.p[0][2], f.n[0], f.n[1], f.n[2], 0, 0});
		m->vertices.push_back({f.p[1][0], f.p[1][1], f.p[1][2], f.n[0], f.n[1], f.n[2], 0, 1});
		m->vertices.push_back({f.p[2][0], f.p[2][1], f.p[2][2], f.n[0], f.n[1], f.n[2], 1, 1});
		m->vertices.push_back({f.p[3][0], f.p[3][1], f.p[3][2], f.n[0], f.n[1], f.n[2], 1, 0});
		m->indices.push_back(base + 0);
		m->indices.push_back(base + 1);
		m->indices.push_back(base + 2);
		m->indices.push_back(base + 0);
		m->indices.push_back(base + 2);
		m->indices.push_back(base + 3);
	}
}

static void appendQuad(
	KineMesh *m,
	const float center[3],
	const float u[3],
	const float v[3],
	const float normal[3],
	float half) {
	const float p[4][3] = {
		{center[0] - u[0] * half - v[0] * half, center[1] - u[1] * half - v[1] * half, center[2] - u[2] * half - v[2] * half},
		{center[0] + u[0] * half - v[0] * half, center[1] + u[1] * half - v[1] * half, center[2] + u[2] * half - v[2] * half},
		{center[0] + u[0] * half + v[0] * half, center[1] + u[1] * half + v[1] * half, center[2] + u[2] * half + v[2] * half},
		{center[0] - u[0] * half + v[0] * half, center[1] - u[1] * half + v[1] * half, center[2] - u[2] * half + v[2] * half},
	};

	const uint32_t base = (uint32_t)m->vertices.size();
	m->vertices.push_back({p[0][0], p[0][1], p[0][2], normal[0], normal[1], normal[2], 0, 0});
	m->vertices.push_back({p[1][0], p[1][1], p[1][2], normal[0], normal[1], normal[2], 1, 0});
	m->vertices.push_back({p[2][0], p[2][1], p[2][2], normal[0], normal[1], normal[2], 1, 1});
	m->vertices.push_back({p[3][0], p[3][1], p[3][2], normal[0], normal[1], normal[2], 0, 1});
	m->indices.push_back(base + 0);
	m->indices.push_back(base + 1);
	m->indices.push_back(base + 2);
	m->indices.push_back(base + 0);
	m->indices.push_back(base + 2);
	m->indices.push_back(base + 3);
}

// Blender-style gizmo pieces. The gizmo material is unlit with culling and the
// depth test off, so these only need a clean silhouette: round shafts and cone
// tips read far better than the old square bars at a constant screen size.
static void appendCylinderAxis(KineMesh *m, int axis, float from, float to, float radius, int segments) {
	if (to < from) {
		const float t = from;
		from = to;
		to = t;
	}
	if (to - from <= 1e-6f || radius <= 1e-6f || segments < 3)
		return;

	const uint32_t base = (uint32_t)m->vertices.size();
	for (int i = 0; i <= segments; ++i) {
		const float a = 2.0f * (float)M_PI * (float)i / (float)segments;
		const float c = cosf(a), s = sinf(a);
		float lo[3] = {0, 0, 0}, hi[3] = {0, 0, 0};
		switch (axis) {
		case 0:
			lo[0] = from;
			lo[1] = radius * c;
			lo[2] = radius * s;
			hi[0] = to;
			hi[1] = radius * c;
			hi[2] = radius * s;
			break;
		case 1:
			lo[0] = radius * c;
			lo[1] = from;
			lo[2] = radius * s;
			hi[0] = radius * c;
			hi[1] = to;
			hi[2] = radius * s;
			break;
		default:
			lo[0] = radius * c;
			lo[1] = radius * s;
			lo[2] = from;
			hi[0] = radius * c;
			hi[1] = radius * s;
			hi[2] = to;
			break;
		}
		m->vertices.push_back({lo[0], lo[1], lo[2], 0, 0, 0, (float)i / segments, 0.0f});
		m->vertices.push_back({hi[0], hi[1], hi[2], 0, 0, 0, (float)i / segments, 1.0f});
	}
	for (int i = 0; i < segments; ++i) {
		const uint32_t a = base + (uint32_t)(i * 2);
		m->indices.push_back(a);
		m->indices.push_back(a + 1);
		m->indices.push_back(a + 2);
		m->indices.push_back(a + 2);
		m->indices.push_back(a + 1);
		m->indices.push_back(a + 3);
	}

	// End caps so the tube is closed when seen straight down its axis.
	for (int end = 0; end < 2; ++end) {
		const float along = end == 0 ? from : to;
		const uint32_t center = (uint32_t)m->vertices.size();
		float cp[3] = {0, 0, 0};
		cp[axis] = along;
		m->vertices.push_back({cp[0], cp[1], cp[2], 0, 0, 0, 0.5f, 0.5f});
		const uint32_t ring = (uint32_t)m->vertices.size();
		for (int i = 0; i < segments; ++i) {
			const float a = 2.0f * (float)M_PI * (float)i / (float)segments;
			const float c = cosf(a), s = sinf(a);
			float p[3] = {0, 0, 0};
			switch (axis) {
			case 0:
				p[0] = along;
				p[1] = radius * c;
				p[2] = radius * s;
				break;
			case 1:
				p[0] = radius * c;
				p[1] = along;
				p[2] = radius * s;
				break;
			default:
				p[0] = radius * c;
				p[1] = radius * s;
				p[2] = along;
				break;
			}
			m->vertices.push_back({p[0], p[1], p[2], 0, 0, 0, c * 0.5f + 0.5f, s * 0.5f + 0.5f});
		}
		for (int i = 0; i < segments; ++i) {
			const uint32_t cur = ring + (uint32_t)i;
			const uint32_t nxt = ring + (uint32_t)((i + 1) % segments);
			m->indices.push_back(center);
			m->indices.push_back(cur);
			m->indices.push_back(nxt);
		}
	}
}

static void appendCone(KineMesh *m, int axis, float base, float tip, float radius, int segments) {
	if (tip <= base || radius <= 1e-6f || segments < 3)
		return;

	const uint32_t apex = (uint32_t)m->vertices.size();
	float ap[3] = {0, 0, 0};
	ap[axis] = tip;
	m->vertices.push_back({ap[0], ap[1], ap[2], 0, 0, 0, 0.5f, 1.0f});

	const uint32_t ring = (uint32_t)m->vertices.size();
	for (int i = 0; i <= segments; ++i) {
		const float a = 2.0f * (float)M_PI * (float)i / (float)segments;
		const float c = cosf(a), s = sinf(a);
		float p[3] = {0, 0, 0};
		switch (axis) {
		case 0:
			p[0] = base;
			p[1] = radius * c;
			p[2] = radius * s;
			break;
		case 1:
			p[0] = radius * c;
			p[1] = base;
			p[2] = radius * s;
			break;
		default:
			p[0] = radius * c;
			p[1] = radius * s;
			p[2] = base;
			break;
		}
		m->vertices.push_back({p[0], p[1], p[2], 0, 0, 0, (float)i / segments, 0.0f});
	}
	for (int i = 0; i < segments; ++i) {
		m->indices.push_back(apex);
		m->indices.push_back(ring + (uint32_t)i);
		m->indices.push_back(ring + (uint32_t)(i + 1));
	}

	// Base disc, visible from behind since culling is off.
	const uint32_t center = (uint32_t)m->vertices.size();
	float cp[3] = {0, 0, 0};
	cp[axis] = base;
	m->vertices.push_back({cp[0], cp[1], cp[2], 0, 0, 0, 0.5f, 0.5f});
	const uint32_t capRing = (uint32_t)m->vertices.size();
	for (int i = 0; i <= segments; ++i) {
		const float a = 2.0f * (float)M_PI * (float)i / (float)segments;
		const float c = cosf(a), s = sinf(a);
		float p[3] = {0, 0, 0};
		switch (axis) {
		case 0:
			p[0] = base;
			p[1] = radius * c;
			p[2] = radius * s;
			break;
		case 1:
			p[0] = radius * c;
			p[1] = base;
			p[2] = radius * s;
			break;
		default:
			p[0] = radius * c;
			p[1] = radius * s;
			p[2] = base;
			break;
		}
		m->vertices.push_back({p[0], p[1], p[2], 0, 0, 0, c * 0.5f + 0.5f, s * 0.5f + 0.5f});
	}
	for (int i = 0; i < segments; ++i) {
		m->indices.push_back(center);
		m->indices.push_back(capRing + (uint32_t)i);
		m->indices.push_back(capRing + (uint32_t)(i + 1));
	}
}

static void appendBall(KineMesh *m, float radius, int slices, int stacks) {
	const uint32_t base = (uint32_t)m->vertices.size();
	for (int j = 0; j <= stacks; ++j) {
		const float phi = (float)M_PI * (float)j / (float)stacks;
		for (int i = 0; i <= slices; ++i) {
			const float theta = 2.0f * (float)M_PI * (float)i / (float)slices;
			const float nx = sinf(phi) * cosf(theta);
			const float ny = cosf(phi);
			const float nz = sinf(phi) * sinf(theta);
			m->vertices.push_back(
				{nx * radius, ny * radius, nz * radius, 0, 0, 0, (float)i / slices, (float)j / stacks});
		}
	}
	for (int j = 0; j < stacks; ++j) {
		for (int i = 0; i < slices; ++i) {
			const uint32_t a = base + (uint32_t)(j * (slices + 1) + i);
			const uint32_t b = a + (uint32_t)(slices + 1);
			m->indices.push_back(a);
			m->indices.push_back(a + 1);
			m->indices.push_back(b);
			m->indices.push_back(b);
			m->indices.push_back(a + 1);
			m->indices.push_back(b + 1);
		}
	}
}

static KineMesh *buildMoveGizmo() {
	auto *m = new KineMesh();
	appendCuboid(m, 0.55f, 0.0f, 0.0f, 1.10f, 0.045f, 0.045f);
	appendCuboid(m, 1.17f, 0.0f, 0.0f, 0.22f, 0.16f, 0.16f);
	appendCuboid(m, 0.0f, 0.55f, 0.0f, 0.045f, 1.10f, 0.045f);
	appendCuboid(m, 0.0f, 1.17f, 0.0f, 0.16f, 0.22f, 0.16f);
	appendCuboid(m, 0.0f, 0.0f, 0.55f, 0.045f, 0.045f, 1.10f);
	appendCuboid(m, 0.0f, 0.0f, 1.17f, 0.16f, 0.16f, 0.22f);
	appendCuboid(m, 0.0f, 0.0f, 0.0f, 0.13f, 0.13f, 0.13f);
	m->indexCount = (uint32_t)m->indices.size();
	return m;
}

struct KineGizmoAxisMeshes {
	KineMesh *x = nullptr;
	KineMesh *y = nullptr;
	KineMesh *z = nullptr;
	KineMesh *center = nullptr;

	KineMesh *planes[3] = {nullptr, nullptr, nullptr};
};

} // namespace

struct KineFilamentGizmo {
	int type = KINE_GIZMO_MOVE;
	KineGizmoAxisMeshes axes;
};

namespace {

static const float KINE_GIZMO_PLANE_OFFSET = 0.72f;
static const float KINE_GIZMO_PLANE_HALF = 0.13f;

static void buildPlaneHandles(KineGizmoAxisMeshes &g) {
	// Thin flat plates instead of single quads, so they read as solid squares (and
	// stay visible from any side) now that all three are always drawn.
	const float o = KINE_GIZMO_PLANE_OFFSET;
	const float size = KINE_GIZMO_PLANE_HALF * 2.0f;
	const float thickness = KINE_GIZMO_PLANE_HALF * 0.18f;

	g.planes[0] = new KineMesh();
	appendCuboid(g.planes[0], o, o, 0.0f, size, size, thickness);
	g.planes[0]->indexCount = (uint32_t)g.planes[0]->indices.size();

	g.planes[1] = new KineMesh();
	appendCuboid(g.planes[1], 0.0f, o, o, thickness, size, size);
	g.planes[1]->indexCount = (uint32_t)g.planes[1]->indices.size();

	g.planes[2] = new KineMesh();
	appendCuboid(g.planes[2], o, 0.0f, o, size, thickness, size);
	g.planes[2]->indexCount = (uint32_t)g.planes[2]->indices.size();
}

static KineGizmoAxisMeshes buildMoveGizmoAxes() {
	const float shaft = 0.022f;
	KineGizmoAxisMeshes g;

	g.x = new KineMesh();
	appendCylinderAxis(g.x, 0, 0.10f, 0.88f, shaft, 16);
	appendCone(g.x, 0, 0.82f, 1.18f, 0.085f, 24);
	g.x->indexCount = (uint32_t)g.x->indices.size();

	g.y = new KineMesh();
	appendCylinderAxis(g.y, 1, 0.10f, 0.88f, shaft, 16);
	appendCone(g.y, 1, 0.82f, 1.18f, 0.085f, 24);
	g.y->indexCount = (uint32_t)g.y->indices.size();

	g.z = new KineMesh();
	appendCylinderAxis(g.z, 2, 0.10f, 0.88f, shaft, 16);
	appendCone(g.z, 2, 0.82f, 1.18f, 0.085f, 24);
	g.z->indexCount = (uint32_t)g.z->indices.size();

	g.center = new KineMesh();
	appendBall(g.center, 0.085f, 18, 12);
	g.center->indexCount = (uint32_t)g.center->indices.size();

	buildPlaneHandles(g);

	return g;
}

static KineMesh *buildScaleGizmo() {
	auto *m = new KineMesh();
	appendCuboid(m, 0.50f, 0.0f, 0.0f, 1.00f, 0.04f, 0.04f);
	appendCuboid(m, 1.08f, 0.0f, 0.0f, 0.20f, 0.20f, 0.20f);
	appendCuboid(m, 0.0f, 0.50f, 0.0f, 0.04f, 1.00f, 0.04f);
	appendCuboid(m, 0.0f, 1.08f, 0.0f, 0.20f, 0.20f, 0.20f);
	appendCuboid(m, 0.0f, 0.0f, 0.50f, 0.04f, 0.04f, 1.00f);
	appendCuboid(m, 0.0f, 0.0f, 1.08f, 0.20f, 0.20f, 0.20f);
	appendCuboid(m, 0.0f, 0.0f, 0.0f, 0.13f, 0.13f, 0.13f);
	m->indexCount = (uint32_t)m->indices.size();
	return m;
}

static KineGizmoAxisMeshes buildScaleGizmoAxes() {
	const float shaft = 0.022f;
	KineGizmoAxisMeshes g;

	g.x = new KineMesh();
	appendCylinderAxis(g.x, 0, 0.10f, 0.92f, shaft, 16);
	appendCuboid(g.x, 1.02f, 0.0f, 0.0f, 0.17f, 0.17f, 0.17f);
	g.x->indexCount = (uint32_t)g.x->indices.size();

	g.y = new KineMesh();
	appendCylinderAxis(g.y, 1, 0.10f, 0.92f, shaft, 16);
	appendCuboid(g.y, 0.0f, 1.02f, 0.0f, 0.17f, 0.17f, 0.17f);
	g.y->indexCount = (uint32_t)g.y->indices.size();

	g.z = new KineMesh();
	appendCylinderAxis(g.z, 2, 0.10f, 0.92f, shaft, 16);
	appendCuboid(g.z, 0.0f, 0.0f, 1.02f, 0.17f, 0.17f, 0.17f);
	g.z->indexCount = (uint32_t)g.z->indices.size();

	g.center = new KineMesh();
	appendBall(g.center, 0.08f, 18, 12);
	g.center->indexCount = (uint32_t)g.center->indices.size();

	buildPlaneHandles(g);

	return g;
}

static void appendTorus(KineMesh *m, int axis, float radius, float tubeRadius, int segments, int sides) {
	uint32_t base = (uint32_t)m->vertices.size();
	for (int i = 0; i < segments; ++i) {
		float a = 2.0f * (float)M_PI * (float)i / (float)segments;
		float ca = cosf(a), sa = sinf(a);
		for (int j = 0; j < sides; ++j) {
			float b = 2.0f * (float)M_PI * (float)j / (float)sides;
			float cb = cosf(b), sb = sinf(b);
			float r = radius + tubeRadius * cb;
			float p[3] = {0, 0, 0};
			float n[3] = {0, 0, 0};
			if (axis == 0) {
				p[0] = tubeRadius * sb;
				p[1] = r * ca;
				p[2] = r * sa;
				n[0] = sb;
				n[1] = cb * ca;
				n[2] = cb * sa;
			} else if (axis == 1) {
				p[0] = r * ca;
				p[1] = tubeRadius * sb;
				p[2] = r * sa;
				n[0] = cb * ca;
				n[1] = sb;
				n[2] = cb * sa;
			} else {
				p[0] = r * ca;
				p[1] = r * sa;
				p[2] = tubeRadius * sb;
				n[0] = cb * ca;
				n[1] = cb * sa;
				n[2] = sb;
			}
			m->vertices.push_back({p[0], p[1], p[2], n[0], n[1], n[2], (float)i / segments, (float)j / sides});
		}
	}

	for (int i = 0; i < segments; ++i) {
		int ni = (i + 1) % segments;
		for (int j = 0; j < sides; ++j) {
			int nj = (j + 1) % sides;
			uint32_t a = base + (uint32_t)(i * sides + j);
			uint32_t b = base + (uint32_t)(ni * sides + j);
			uint32_t c = base + (uint32_t)(ni * sides + nj);
			uint32_t d = base + (uint32_t)(i * sides + nj);
			m->indices.push_back(a);
			m->indices.push_back(b);
			m->indices.push_back(c);
			m->indices.push_back(a);
			m->indices.push_back(c);
			m->indices.push_back(d);
		}
	}
}

static KineMesh *buildRotateGizmo() {
	auto *m = new KineMesh();
	appendTorus(m, 0, 0.85f, 0.018f, 64, 8);
	appendTorus(m, 1, 0.85f, 0.018f, 64, 8);
	appendTorus(m, 2, 0.85f, 0.018f, 64, 8);
	appendCuboid(m, 0.0f, 0.0f, 0.0f, 0.07f, 0.07f, 0.07f);
	m->indexCount = (uint32_t)m->indices.size();
	return m;
}

static KineGizmoAxisMeshes buildRotateGizmoAxes() {
	KineGizmoAxisMeshes g;

	g.x = new KineMesh();
	appendTorus(g.x, 0, 0.85f, 0.018f, 64, 8);
	g.x->indexCount = (uint32_t)g.x->indices.size();

	g.y = new KineMesh();
	appendTorus(g.y, 1, 0.85f, 0.018f, 64, 8);
	g.y->indexCount = (uint32_t)g.y->indices.size();

	g.z = new KineMesh();
	appendTorus(g.z, 2, 0.85f, 0.018f, 64, 8);
	g.z->indexCount = (uint32_t)g.z->indices.size();

	return g;
}

#if KINE_WITH_ASSIMP
static math::mat4f kine_from_assimp(const aiMatrix4x4 &m) {
	return math::mat4f(
		math::float4{m.a1, m.b1, m.c1, m.d1},
		math::float4{m.a2, m.b2, m.c2, m.d2},
		math::float4{m.a3, m.b3, m.c3, m.d3},
		math::float4{m.a4, m.b4, m.c4, m.d4});
}

static KineQuat kine_from_assimp(const aiQuaternion &q) {
	return {q.x, q.y, q.z, q.w};
}

static void kine_collect_assimp_nodes(
	aiNode *node,
	const aiMatrix4x4 &parentGlobal,
	std::unordered_map<std::string, aiNode *> &nodes,
	std::unordered_map<aiNode *, aiMatrix4x4> &globals) {
	if (!node)
		return;
	const aiMatrix4x4 global = parentGlobal * node->mTransformation;
	nodes[node->mName.C_Str()] = node;
	globals[node] = global;
	for (unsigned int i = 0; i < node->mNumChildren; ++i) {
		kine_collect_assimp_nodes(node->mChildren[i], global, nodes, globals);
	}
}

static void kine_add_vertex_influence(KineSkinVertex &skin, uint8_t joint, float weight) {
	if (weight <= 0.0f)
		return;
	int slot = -1;
	for (int i = 0; i < 4; ++i) {
		if (skin.weights[i] == 0.0f) {
			slot = i;
			break;
		}
	}
	if (slot < 0) {
		slot = 0;
		for (int i = 1; i < 4; ++i) {
			if (skin.weights[i] < skin.weights[slot])
				slot = i;
		}
		if (weight <= skin.weights[slot])
			return;
	}
	skin.joints[slot] = joint;
	skin.weights[slot] = weight;
}

static bool kine_append_assimp_node(
	KineMesh *out,
	const aiScene *scene,
	aiNode *node,
	const aiMatrix4x4 &parentGlobal,
	const std::unordered_map<std::string, int> &boneIndices) {
	if (!out || !scene || !node)
		return false;
	const aiMatrix4x4 global = parentGlobal * node->mTransformation;
	const bool skinnedModel = !out->bones.empty();

	for (unsigned int nodeMeshIndex = 0; nodeMeshIndex < node->mNumMeshes; ++nodeMeshIndex) {
		const unsigned int sceneMeshIndex = node->mMeshes[nodeMeshIndex];
		if (sceneMeshIndex >= scene->mNumMeshes)
			continue;
		const aiMesh *src = scene->mMeshes[sceneMeshIndex];
		if (!src || src->mNumVertices == 0 || src->mNumFaces == 0)
			continue;
		if (uint64_t(out->vertices.size()) + src->mNumVertices > INT32_MAX ||
			uint64_t(out->indices.size()) + uint64_t(src->mNumFaces) * 3 > INT32_MAX)
			return false;

		const uint32_t base = (uint32_t)out->vertices.size();
		aiMatrix3x3 normalMatrix(global);
		normalMatrix.Inverse().Transpose();
		for (unsigned int i = 0; i < src->mNumVertices; ++i) {
			aiVector3D p = src->mVertices[i];
			aiVector3D n = src->HasNormals() ? src->mNormals[i] : aiVector3D(0.0f, 1.0f, 0.0f);
			if (!skinnedModel) {
				p = global * p;
				n = normalMatrix * n;
				n.Normalize();
			}
			const aiVector3D uv = src->HasTextureCoords(0)
									  ? src->mTextureCoords[0][i]
									  : aiVector3D(0.0f, 0.0f, 0.0f);
			out->vertices.push_back({p.x, p.y, p.z, n.x, n.y, n.z, uv.x, uv.y});
			if (skinnedModel) {
				KineSkinVertex skin;
				for (float &value : skin.weights)
					value = 0.0f;
				out->skinVertices.push_back(skin);
			}
		}

		if (skinnedModel) {
			for (unsigned int srcBoneIndex = 0; srcBoneIndex < src->mNumBones; ++srcBoneIndex) {
				const aiBone *srcBone = src->mBones[srcBoneIndex];
				if (!srcBone)
					continue;
				const auto found = boneIndices.find(srcBone->mName.C_Str());
				if (found == boneIndices.end())
					continue;
				for (unsigned int weightIndex = 0; weightIndex < srcBone->mNumWeights; ++weightIndex) {
					const aiVertexWeight &influence = srcBone->mWeights[weightIndex];
					if (influence.mVertexId >= src->mNumVertices)
						continue;
					kine_add_vertex_influence(
						out->skinVertices[(size_t)base + influence.mVertexId],
						(uint8_t)found->second,
						influence.mWeight);
				}
			}
			for (unsigned int i = 0; i < src->mNumVertices; ++i) {
				KineSkinVertex &skin = out->skinVertices[(size_t)base + i];
				float total = 0.0f;
				for (float weight : skin.weights)
					total += weight;
				if (total <= 0.000001f) {
					skin.joints[0] = 0;
					skin.weights[0] = 1.0f;
				} else {
					for (float &weight : skin.weights)
						weight /= total;
				}
			}
		}

		const uint32_t firstIndex = uint32_t(out->indices.size());
		for (unsigned int i = 0; i < src->mNumFaces; ++i) {
			const aiFace &face = src->mFaces[i];
			if (face.mNumIndices != 3)
				continue;
			if (face.mIndices[0] >= src->mNumVertices || face.mIndices[1] >= src->mNumVertices || face.mIndices[2] >= src->mNumVertices) return false;
			out->indices.push_back(base + (uint32_t)face.mIndices[0]);
			out->indices.push_back(base + (uint32_t)face.mIndices[1]);
			out->indices.push_back(base + (uint32_t)face.mIndices[2]);
		}
		out->primitives.push_back({firstIndex, uint32_t(out->indices.size()) - firstIndex, src->mMaterialIndex, base, src->mNumVertices});
	}

	for (unsigned int i = 0; i < node->mNumChildren; ++i) {
		if (!kine_append_assimp_node(out, scene, node->mChildren[i], global, boneIndices))
			return false;
	}
	return true;
}

static constexpr unsigned int KINE_ASSIMP_FLAGS =
	aiProcess_Triangulate |
	aiProcess_JoinIdenticalVertices |
	aiProcess_GenSmoothNormals |
	aiProcess_ImproveCacheLocality |
	aiProcess_RemoveRedundantMaterials |
	aiProcess_SortByPType;

static bool kine_decode_image(const uint8_t *data, size_t size, KineImage &out) {
	if (!data || size == 0 || size > (size_t)INT32_MAX)
		return false;

	int w = 0, h = 0, c = 0;
	stbi_uc *px = stbi_load_from_memory(data, (int)size, &w, &h, &c, 4);
	if (!px)
		return false;
	if (w <= 0 || h <= 0) {
		stbi_image_free(px);
		return false;
	}

	out.width = w;
	out.height = h;
	out.rgba.assign(px, px + (size_t)w * h * 4);
	stbi_image_free(px);
	return true;
}

static bool kine_load_assimp_texture(
	const aiScene *scene,
	const aiMaterial *mat,
	const std::string &baseDir,
	KineImage &out, std::initializer_list<aiTextureType> types) {
	if (!scene || !mat)
		return false;

	aiString path;
	bool found = false;

	for (aiTextureType t : types) {
		if (mat->GetTextureCount(t) > 0 &&
			mat->GetTexture(t, 0, &path) == AI_SUCCESS) {
			found = true;
			break;
		}
	}
	if (!found)
		return false;

	if (const aiTexture *emb = scene->GetEmbeddedTexture(path.C_Str())) {
		if (emb->mHeight == 0) {

			return kine_decode_image(
				reinterpret_cast<const uint8_t *>(emb->pcData), emb->mWidth, out);
		}

		if (!emb->pcData || emb->mWidth == 0 || emb->mHeight == 0)
			return false;
		out.width = (int)emb->mWidth;
		out.height = (int)emb->mHeight;
		out.rgba.resize((size_t)out.width * out.height * 4);
		for (size_t i = 0; i < (size_t)out.width * out.height; ++i) {
			out.rgba[i * 4 + 0] = emb->pcData[i].r;
			out.rgba[i * 4 + 1] = emb->pcData[i].g;
			out.rgba[i * 4 + 2] = emb->pcData[i].b;
			out.rgba[i * 4 + 3] = emb->pcData[i].a;
		}
		return true;
	}

	std::string rel = path.C_Str();
	std::replace(rel.begin(), rel.end(), '\\', '/');
	const std::string full = baseDir + rel;

	int w = 0, h = 0, c = 0;
	stbi_uc *px = stbi_load(full.c_str(), &w, &h, &c, 4);
	if (!px) {
		fprintf(stderr, "[Kine] could not load texture '%s'\n", full.c_str());
		return false;
	}

	out.width = w;
	out.height = h;
	out.rgba.assign(px, px + (size_t)w * h * 4);
	stbi_image_free(px);
	return true;
}

static KineMesh *buildMeshFromAssimpScene(
	const aiScene *scene,
	const char *sourceName,
	const std::string &baseDir = "", bool loadMaterials = true) {
	if (!scene || !scene->HasMeshes()) {
		return nullptr;
	}

	fprintf(
		stderr,
		"[Kine] loading %s: %u meshes\n",
		sourceName ? sourceName : "<memory>",
		scene->mNumMeshes);

	auto *m = new KineMesh();
	m->doubleSided = true;

	std::unordered_map<std::string, int> boneIndices;
	std::unordered_map<std::string, aiMatrix4x4> inverseBinds;

	for (unsigned int meshIndex = 0; meshIndex < scene->mNumMeshes; ++meshIndex) {
		const aiMesh *src = scene->mMeshes[meshIndex];
		if (!src)
			continue;

		for (unsigned int srcBoneIndex = 0;
			 srcBoneIndex < src->mNumBones;
			 ++srcBoneIndex) {
			const aiBone *srcBone = src->mBones[srcBoneIndex];
			if (!srcBone)
				continue;

			const std::string name = srcBone->mName.C_Str();

			if (boneIndices.find(name) == boneIndices.end()) {
				if (boneIndices.size() >= 255) {
					fprintf(
						stderr,
						"[Kine] Assimp mesh '%s' exceeds Filament's 255 bone limit\n",
						sourceName ? sourceName : "<memory>");

					delete m;
					return nullptr;
				}

				boneIndices[name] = (int)boneIndices.size();
				inverseBinds[name] = srcBone->mOffsetMatrix;
			}
		}
	}

	std::unordered_map<std::string, aiNode *> nodes;
	std::unordered_map<aiNode *, aiMatrix4x4> globals;

	kine_collect_assimp_nodes(
		scene->mRootNode,
		aiMatrix4x4(),
		nodes,
		globals);

	aiMatrix4x4 rootInverse = scene->mRootNode->mTransformation;
	rootInverse.Inverse();

	m->bones.resize(boneIndices.size());

	for (const auto &entry : boneIndices) {
		const std::string &name = entry.first;
		const int index = entry.second;

		KineBone &bone = m->bones[index];
		bone.name = name;
		bone.inverseBind = kine_from_assimp(inverseBinds[name]);

		aiNode *node = nullptr;

		const auto nodeIt = nodes.find(name);
		if (nodeIt != nodes.end()) {
			node = nodeIt->second;
		}

		aiNode *parent = node ? node->mParent : nullptr;

		while (parent) {
			const auto parentIt =
				boneIndices.find(parent->mName.C_Str());

			if (parentIt != boneIndices.end()) {
				bone.parent = parentIt->second;
				break;
			}

			parent = parent->mParent;
		}

		aiMatrix4x4 local;

		if (node) {
			const aiMatrix4x4 boneGlobal =
				rootInverse * globals[node];

			if (bone.parent >= 0) {
				aiMatrix4x4 parentGlobal =
					rootInverse * globals[parent];

				parentGlobal.Inverse();
				local = parentGlobal * boneGlobal;
			} else {
				local = boneGlobal;
			}
		}

		aiVector3D scaling(1.0f, 1.0f, 1.0f);
		aiVector3D position(0.0f, 0.0f, 0.0f);
		aiQuaternion rotation;

		local.Decompose(
			scaling,
			rotation,
			position);

		bone.bindTranslation = {
			position.x,
			position.y,
			position.z};

		bone.bindRotation =
			kine_from_assimp(rotation);

		bone.bindScale = {
			scaling.x,
			scaling.y,
			scaling.z};

		bone.bindLocal =
			kine_from_assimp(local);
	}

	if (!kine_append_assimp_node(
			m,
			scene,
			scene->mRootNode,
			aiMatrix4x4(),
			boneIndices)) {
		fprintf(
			stderr,
			"[Kine] Assimp mesh '%s' exceeds supported mesh counts\n",
			sourceName ? sourceName : "<memory>");

		delete m;
		return nullptr;
	}

	if (m->vertices.empty() || m->indices.empty()) {
		delete m;
		return nullptr;
	}

	m->indexCount =
		(uint32_t)m->indices.size();

	if (!m->bones.empty()) {
		m->skinMatrices.resize(m->bones.size());

		std::vector<math::mat4f> globalsByBone(
			m->bones.size());

		for (size_t i = 0; i < m->bones.size(); ++i) {
			globalsByBone[i] =
				m->bones[i].parent >= 0
					? globalsByBone[(size_t)m->bones[i].parent] * m->bones[i].bindLocal
					: m->bones[i].bindLocal;

			m->skinMatrices[i] =
				globalsByBone[i] *
				m->bones[i].inverseBind;
		}
	}

	for (unsigned int animationIndex = 0;
		 animationIndex < scene->mNumAnimations;
		 ++animationIndex) {
		const aiAnimation *sourceAnimation =
			scene->mAnimations[animationIndex];

		if (!sourceAnimation)
			continue;

		const double ticksPerSecond =
			sourceAnimation->mTicksPerSecond > 0.0
				? sourceAnimation->mTicksPerSecond
				: 25.0;

		KineAnimation animation;

		animation.name =
			sourceAnimation->mName.length > 0
				? sourceAnimation->mName.C_Str()
				: (
					  "Animation" +
					  std::to_string(animationIndex + 1));

		animation.duration =
			(float)(sourceAnimation->mDuration /
					ticksPerSecond);

		for (unsigned int channelIndex = 0;
			 channelIndex < sourceAnimation->mNumChannels;
			 ++channelIndex) {
			const aiNodeAnim *sourceChannel =
				sourceAnimation->mChannels[channelIndex];

			if (!sourceChannel)
				continue;

			const auto boneIt =
				boneIndices.find(
					sourceChannel->mNodeName.C_Str());

			if (boneIt == boneIndices.end()) {
				continue;
			}

			KineAnimationChannel channel;
			channel.bone = boneIt->second;

			channel.translations.reserve(
				sourceChannel->mNumPositionKeys);

			channel.rotations.reserve(
				sourceChannel->mNumRotationKeys);

			channel.scales.reserve(
				sourceChannel->mNumScalingKeys);

			for (unsigned int i = 0;
				 i < sourceChannel->mNumPositionKeys;
				 ++i) {
				const aiVectorKey &key =
					sourceChannel->mPositionKeys[i];

				channel.translations.push_back({(float)(key.mTime /
														ticksPerSecond),
												{key.mValue.x,
												 key.mValue.y,
												 key.mValue.z}});
			}

			for (unsigned int i = 0;
				 i < sourceChannel->mNumRotationKeys;
				 ++i) {
				const aiQuatKey &key =
					sourceChannel->mRotationKeys[i];

				channel.rotations.push_back({(float)(key.mTime /
													 ticksPerSecond),
											 kine_from_assimp(key.mValue)});
			}

			for (unsigned int i = 0;
				 i < sourceChannel->mNumScalingKeys;
				 ++i) {
				const aiVectorKey &key =
					sourceChannel->mScalingKeys[i];

				channel.scales.push_back({(float)(key.mTime /
												  ticksPerSecond),
										  {key.mValue.x,
										   key.mValue.y,
										   key.mValue.z}});
			}

			animation.channels.push_back(
				std::move(channel));
		}

		m->animations.push_back(
			std::move(animation));
	}

	if (loadMaterials) {
		m->materials.resize(scene->mNumMaterials);
		for (unsigned int i = 0; i < scene->mNumMaterials; ++i) {
			const auto *src = scene->mMaterials[i];
			auto &dst = m->materials[i];
			aiColor4D color(1,1,1,1);
			if (src->Get(AI_MATKEY_BASE_COLOR, color) != AI_SUCCESS) src->Get(AI_MATKEY_COLOR_DIFFUSE, color);
			dst.baseColor = {color.r,color.g,color.b,color.a};
			src->Get(AI_MATKEY_ROUGHNESS_FACTOR, dst.roughness);
			src->Get(AI_MATKEY_METALLIC_FACTOR, dst.metallic);
			int twoSided = 0; src->Get(AI_MATKEY_TWOSIDED, twoSided); dst.doubleSided = twoSided != 0;
			aiString alphaMode;
			if (src->Get(AI_MATKEY_GLTF_ALPHAMODE, alphaMode) == AI_SUCCESS && std::string(alphaMode.C_Str()) == "MASK") {
				dst.alphaCutoff = 0.5f; src->Get(AI_MATKEY_GLTF_ALPHACUTOFF, dst.alphaCutoff);
			}
			kine_load_assimp_texture(scene,src,baseDir,dst.baseColorImage,{aiTextureType_BASE_COLOR,aiTextureType_DIFFUSE});
			kine_load_assimp_texture(scene,src,baseDir,dst.normalImage,{aiTextureType_NORMALS});
			// glTF packs roughness and metalness in G/B. The red channel is not AO.
			if (kine_load_assimp_texture(scene,src,baseDir,dst.ormImage,{aiTextureType_UNKNOWN})) {
				for (size_t p = 0; p < dst.ormImage.rgba.size(); p += 4) dst.ormImage.rgba[p] = 255;
			}
		}
	}

	return m;
}

static KineMesh *loadMeshWithAssimp(const char *path, bool loadMaterials = true) {
	Assimp::Importer importer;

	const aiScene *scene = importer.ReadFile(
		path,
		KINE_ASSIMP_FLAGS);

	if (!scene || !scene->HasMeshes()) {
		fprintf(
			stderr,
			"[Kine] Assimp failed to load mesh '%s': %s\n",
			path,
			importer.GetErrorString());
		return nullptr;
	}

	std::string baseDir = path;
	const size_t slash = baseDir.find_last_of("/\\");
	baseDir = (slash == std::string::npos) ? "" : baseDir.substr(0, slash + 1);
	return buildMeshFromAssimpScene(scene, path, baseDir, loadMaterials);
}

static KineMesh *loadMeshWithAssimpMemory(
	const void *data,
	size_t dataSize,
	const char *formatHint) {
	if (!data || dataSize == 0) {
		return nullptr;
	}

	Assimp::Importer importer;

	const char *hint =
		(formatHint && formatHint[0] != '\0')
			? formatHint
			: nullptr;

	const aiScene *scene = importer.ReadFileFromMemory(
		data,
		dataSize,
		KINE_ASSIMP_FLAGS,
		hint);

	if (!scene || !scene->HasMeshes()) {
		fprintf(
			stderr,
			"[Kine] Assimp failed to load mesh from memory: %s\n",
			importer.GetErrorString());
		return nullptr;
	}

	return buildMeshFromAssimpScene(
		scene,
		hint ? hint : "<memory>");
}
#endif

static void uploadMesh(KineMesh *m, Engine *engine) {
	if (!m || m->vertices.empty())
		return;

	math::float3 boundsMin{
		std::numeric_limits<float>::max(),
		std::numeric_limits<float>::max(),
		std::numeric_limits<float>::max()};
	math::float3 boundsMax{
		std::numeric_limits<float>::lowest(),
		std::numeric_limits<float>::lowest(),
		std::numeric_limits<float>::lowest()};
	for (const KineVertex &vertex : m->vertices) {
		boundsMin.x = std::min(boundsMin.x, vertex.px);
		boundsMin.y = std::min(boundsMin.y, vertex.py);
		boundsMin.z = std::min(boundsMin.z, vertex.pz);
		boundsMax.x = std::max(boundsMax.x, vertex.px);
		boundsMax.y = std::max(boundsMax.y, vertex.py);
		boundsMax.z = std::max(boundsMax.z, vertex.pz);
	}
	m->localBounds.set(boundsMin, boundsMax);

	size_t vsize = m->vertices.size() * sizeof(KineVertex);
	size_t isize = m->indices.size() * sizeof(uint32_t);

	std::vector<math::float3> positions(m->vertices.size());
	std::vector<math::float3> normals(m->vertices.size());
	std::vector<math::float2> uvs(m->vertices.size());
	for (size_t i = 0; i < m->vertices.size(); ++i) {
		const KineVertex &vertex = m->vertices[i];
		positions[i] = {vertex.px, vertex.py, vertex.pz};
		normals[i] = {vertex.nx, vertex.ny, vertex.nz};
		uvs[i] = {vertex.u, vertex.v};
	}

	std::vector<math::short4> quats(m->vertices.size());
	auto orientation = SurfaceOrientation::Builder()
						   .vertexCount((uint32_t)m->vertices.size())
						   .normals(normals.data())
						   .uvs(uvs.data())
						   .positions(positions.data())
						   .triangleCount(m->indices.size() / 3)
						   .triangles(reinterpret_cast<const math::uint3 *>(m->indices.data()))
						   .build();
	if (!orientation) {
		fprintf(stderr, "[Kine] UV tangent generation failed; using normal-derived frames\n");
		orientation = SurfaceOrientation::Builder()
						  .vertexCount((uint32_t)m->vertices.size())
						  .normals(normals.data())
						  .build();
		if (!orientation)
			return;
	}
	orientation->getQuats(quats.data(), (uint32_t)m->vertices.size());

	delete orientation;

	const bool hasTerrainWeights = m->terrainWeights.size() == m->vertices.size();
	const bool hasSkin = !m->bones.empty() && m->skinVertices.size() == m->vertices.size();
	const bool hasVertexColors = !m->vertexColors.empty() && m->vertexColors.size() == m->vertices.size();

	int bufferCount = 2;
	if (hasTerrainWeights || hasSkin)
		bufferCount = 3;
	if (hasVertexColors)
		bufferCount += 1;

	const bool needsColorAttr = true;
	if (needsColorAttr && !hasVertexColors)
		bufferCount += 1;
	VertexBuffer::Builder vertexBufferBuilder;
	vertexBufferBuilder
		.vertexCount((uint32_t)m->vertices.size())
		.bufferCount(bufferCount)
		.attribute(VertexAttribute::POSITION, 0, VertexBuffer::AttributeType::FLOAT3, offsetof(KineVertex, px), sizeof(KineVertex))
		.attribute(VertexAttribute::UV0, 0, VertexBuffer::AttributeType::FLOAT2, offsetof(KineVertex, u), sizeof(KineVertex))
		.attribute(VertexAttribute::TANGENTS, 1, VertexBuffer::AttributeType::SHORT4, 0, sizeof(math::short4))
		.normalized(VertexAttribute::TANGENTS);
	if (hasVertexColors || needsColorAttr) {

		const int colorBuf = (hasTerrainWeights || hasSkin) ? 3 : 2;
		vertexBufferBuilder
			.attribute(VertexAttribute::COLOR, colorBuf, VertexBuffer::AttributeType::FLOAT4, 0, sizeof(math::float4));
	}
	if (hasTerrainWeights) {
		vertexBufferBuilder
			.attribute(VertexAttribute::CUSTOM0, 2, VertexBuffer::AttributeType::FLOAT4, 0, sizeof(KineTerrainWeights))
			.attribute(VertexAttribute::CUSTOM1, 2, VertexBuffer::AttributeType::FLOAT4, 4 * sizeof(float), sizeof(KineTerrainWeights));
	} else if (hasSkin) {
		vertexBufferBuilder
			.attribute(VertexAttribute::BONE_INDICES, 2, VertexBuffer::AttributeType::UBYTE4,
					   offsetof(KineSkinVertex, joints), sizeof(KineSkinVertex))
			.attribute(VertexAttribute::BONE_WEIGHTS, 2, VertexBuffer::AttributeType::FLOAT4,
					   offsetof(KineSkinVertex, weights), sizeof(KineSkinVertex));
	}
	m->vb = vertexBufferBuilder.build(*engine);

	void *vcopy = malloc(vsize);
	memcpy(vcopy, m->vertices.data(), vsize);
	m->vb->setBufferAt(*engine, 0,
					   VertexBuffer::BufferDescriptor(vcopy, vsize, [](void *buf, size_t, void *) { free(buf); }, nullptr));

	size_t qsize = quats.size() * sizeof(math::short4);
	void *qcopy = malloc(qsize);
	memcpy(qcopy, quats.data(), qsize);
	m->vb->setBufferAt(*engine, 1,
					   VertexBuffer::BufferDescriptor(qcopy, qsize, [](void *buf, size_t, void *) { free(buf); }, nullptr));

	if (hasTerrainWeights) {
		const size_t weightSize = m->terrainWeights.size() * sizeof(KineTerrainWeights);
		void *weightCopy = malloc(weightSize);
		memcpy(weightCopy, m->terrainWeights.data(), weightSize);
		m->vb->setBufferAt(*engine, 2,
						   VertexBuffer::BufferDescriptor(weightCopy, weightSize, [](void *buf, size_t, void *) { free(buf); }, nullptr));
	} else if (hasSkin) {
		const size_t skinSize = m->skinVertices.size() * sizeof(KineSkinVertex);
		void *skinCopy = malloc(skinSize);
		memcpy(skinCopy, m->skinVertices.data(), skinSize);
		m->vb->setBufferAt(*engine, 2,
						   VertexBuffer::BufferDescriptor(skinCopy, skinSize, [](void *buf, size_t, void *) { free(buf); }, nullptr));
	}

	if (hasVertexColors) {
		const int colorBuf = (hasTerrainWeights || hasSkin) ? 3 : 2;
		const size_t csize = m->vertexColors.size() * sizeof(math::float4);
		void *ccopy = malloc(csize);
		memcpy(ccopy, m->vertexColors.data(), csize);
		m->vb->setBufferAt(*engine, colorBuf,
						   VertexBuffer::BufferDescriptor(ccopy, csize, [](void *buf, size_t, void *) { free(buf); }, nullptr));
	} else if (needsColorAttr) {

		const int colorBuf = (hasTerrainWeights || hasSkin) ? 3 : 2;
		const size_t n = m->vertices.size();
		const size_t csize = n * sizeof(math::float4);
		auto *white = (math::float4 *)malloc(csize);
		for (size_t i = 0; i < n; ++i)
			white[i] = {1.0f, 1.0f, 1.0f, 1.0f};
		m->vb->setBufferAt(*engine, colorBuf,
						   VertexBuffer::BufferDescriptor(white, csize, [](void *buf, size_t, void *) { free(buf); }, nullptr));
	}

	m->ib = IndexBuffer::Builder()
				.indexCount(m->indexCount)
				.bufferType(IndexBuffer::IndexType::UINT)
				.build(*engine);

	void *icopy = malloc(isize);
	memcpy(icopy, m->indices.data(), isize);
	m->ib->setBuffer(*engine,
					 IndexBuffer::BufferDescriptor(icopy, isize, [](void *buf, size_t, void *) { free(buf); }, nullptr));
}

bool rebuildRenderTarget(KineFilamentContext *ctx, unsigned int textureId, int width, int height) {
	if (ctx->renderTarget) {
		ctx->engine->destroy(ctx->renderTarget);
		ctx->renderTarget = nullptr;
	}
	if (ctx->colorTarget) {
		ctx->engine->destroy(ctx->colorTarget);
		ctx->colorTarget = nullptr;
	}

	ctx->engine->flushAndWait();

	ctx->colorTarget = Texture::Builder()
						   .width(uint32_t(width))
						   .height(uint32_t(height))
						   .levels(1)
						   .usage(Texture::Usage::COLOR_ATTACHMENT | Texture::Usage::SAMPLEABLE)
						   .format(Texture::InternalFormat::RGBA8)
						   .import(textureId)
						   .build(*ctx->engine);

	if (!ctx->colorTarget)
		return false;

	ctx->renderTarget = RenderTarget::Builder()
							.texture(RenderTarget::AttachmentPoint::COLOR, ctx->colorTarget)
							.build(*ctx->engine);

	if (!ctx->renderTarget)
		return false;

	ctx->view->setRenderTarget(ctx->renderTarget);
	ctx->view->setViewport({0, 0, uint32_t(width), uint32_t(height)});

	ctx->width = width;
	ctx->height = height;
	return true;
}

static void kine_apply_material_params(KineFilamentContext *ctx, MaterialInstance *mi, const KineBatchKey &key, bool inheritGlobalShader = true) {
	KineFilamentShader *runtimeShader = key.shader ? key.shader : (inheritGlobalShader ? ctx->globalShader : nullptr);
	if (runtimeShader && runtimeShader->material) {
		TextureSampler sampler(TextureSampler::MinFilter::LINEAR_MIPMAP_LINEAR, TextureSampler::MagFilter::LINEAR,
			TextureSampler::WrapMode::REPEAT);
		sampler.setAnisotropy(8.0f);
		for (const auto &[name, texture] : runtimeShader->textures)
			mi->setParameter(name.c_str(), texture, sampler);
		for (const auto &[name, values] : runtimeShader->uniforms) {
			switch (values.size()) {
			case 1:
				mi->setParameter(name.c_str(), values[0]);
				break;
			case 2:
				mi->setParameter(name.c_str(), math::float2{values[0], values[1]});
				break;
			case 3:
				mi->setParameter(name.c_str(), math::float3{values[0], values[1], values[2]});
				break;
			case 4:
				mi->setParameter(name.c_str(), math::float4{values[0], values[1], values[2], values[3]});
				break;
			default:
				break;
			}
		}
		return;
	}
	const float time = ctx->time;
	Texture *whiteTex = ctx->whiteTex;
	if (key.materialKind == KINE_MAT_GLASS) {

		mi->setParameter("roughness", key.param1);
		mi->setParameter("ior", key.param2);
		mi->setParameter("thickness", key.param3);
		mi->setParameter("transmission", key.transmission);
	} else if (key.materialKind == KINE_MAT_FORCEFIELD) {
		mi->setParameter("time",time);
		mi->setParameter("hasTexture",key.texture && key.texture->tex ? 1.0f : 0.0f);
		mi->setParameter("baseColorMap",key.texture && key.texture->tex ? key.texture->tex : whiteTex,TextureSampler(TextureSampler::MinFilter::LINEAR_MIPMAP_LINEAR,TextureSampler::MagFilter::LINEAR,TextureSampler::WrapMode::REPEAT));
	} else if (key.materialKind == KINE_MAT_NEON) {

		mi->setParameter("intensity", key.param1);
	} else if (key.materialKind == KINE_MAT_WATER) {
		const KineFilamentWaterParams &w = ctx->water;
		mi->setParameter("roughness", key.param1);
		mi->setParameter("ior", key.param2);
		mi->setParameter("thickness", key.param3);
		mi->setParameter("transmission", key.transmission);
		mi->setParameter("time", ctx->explicitWaterTime ? ctx->waterTime : time);
		mi->setParameter("waveScale", w.waveScale);
		mi->setParameter("speed", w.speed);
		mi->setParameter("strength", w.strength);
		mi->setParameter("octaves", w.octaves);
		mi->setParameter("height", w.height);
		mi->setParameter("foamAmount", w.foamAmount);
		mi->setParameter("absorption", math::float3{w.absorptionR, w.absorptionG, w.absorptionB});
		mi->setParameter("clearCoat", w.clearCoat);
		mi->setParameter("clearCoatRoughness", w.clearCoatRoughness);
	} else if (key.materialKind == KINE_MAT_OUTLINE) {
		mi->setParameter("thickness", key.param1);
	} else if (key.materialKind == KINE_MAT_HIGHLIGHT_OUTLINE ||
			   key.materialKind == KINE_MAT_HIGHLIGHT_OUTLINE_TOP) {
		mi->setParameter("thickness", key.param1);
	} else if (key.materialKind == KINE_MAT_HIGHLIGHT_FILL ||
			   key.materialKind == KINE_MAT_HIGHLIGHT_FILL_TOP) {
		mi->setParameter("depthBias", key.param1);
	} else if (key.materialKind == KINE_MAT_OUTLINE_MASK) {

		mi->setParameter("maskValue", key.param1 > 0.0f ? key.param1 : 1.0f);
	} else if (key.materialKind == KINE_MAT_GIZMO) {

	} else if (key.materialKind == KINE_MAT_PARTICLE) {

		mi->setParameter("uvScale", math::float2{key.param1, key.param2});
		mi->setParameter("uvOffset", math::float2{key.param3, key.particleUvOffsetY});

		TextureSampler clampSampler(
			TextureSampler::MinFilter::LINEAR,
			TextureSampler::MagFilter::LINEAR,
			TextureSampler::WrapMode::CLAMP_TO_EDGE);

		if (key.texture && key.texture->tex) {
			mi->setParameter("hasTexture", 1.0f);
			mi->setParameter("baseColorMap", key.texture->tex, clampSampler);
		} else {
			mi->setParameter("hasTexture", 0.0f);
			mi->setParameter("baseColorMap", whiteTex, clampSampler);
		}
	} else if (key.materialKind == KINE_MAT_TERRAIN) {
		TextureSampler repeatSampler(
			TextureSampler::MinFilter::LINEAR,
			TextureSampler::MagFilter::LINEAR,
			TextureSampler::WrapMode::REPEAT);
		static const char *layerNames[6] = {
			"layer0", "layer1", "layer2", "layer3", "layer4", "layer5"};
		for (size_t i = 0; i < 6; ++i) {
			Texture *layer = key.texture ? key.texture->terrainLayers[i] : nullptr;
			mi->setParameter(layerNames[i], layer ? layer : whiteTex, repeatSampler);
		}
		mi->setParameter("roughness", key.param1 > 0.0f ? key.param1 : 0.9f);
		mi->setParameter("tileScale", key.param3 > 0.0f ? key.param3 : 0.25f);
	} else {
		TextureSampler repeatSampler(
			TextureSampler::MinFilter::LINEAR_MIPMAP_LINEAR,
			TextureSampler::MagFilter::LINEAR,
			TextureSampler::WrapMode::REPEAT);

		mi->setParameter("roughness", key.param1);
		mi->setParameter("metallic", key.param2);
		mi->setParameter("baseColorFactor", math::float4{1.0f});
		mi->setParameter("alphaCutoff", 0.0f);
		mi->setDoubleSided(false);
		mi->setCullingMode(MaterialInstance::CullingMode::BACK);
		mi->setParameter("shadowStrength", 0.4f);

		mi->setParameter("uvScale", math::float2{1.0f, 1.0f});

		if (key.texture && key.texture->tex) {
			mi->setParameter("hasTexture", 1.0f);
			mi->setParameter("baseColorMap", key.texture->tex, repeatSampler);
		} else {
			mi->setParameter("hasTexture", 0.0f);
			mi->setParameter("baseColorMap", whiteTex, repeatSampler);
		}

		if (key.texture && key.texture->normalTex) {
			mi->setParameter("hasNormalMap", 1.0f);
			mi->setParameter("normalMap", key.texture->normalTex, repeatSampler);
		} else {
			mi->setParameter("hasNormalMap", 0.0f);
			mi->setParameter("normalMap", whiteTex, repeatSampler);
		}

		if (key.texture && key.texture->ormTex) {
			mi->setParameter("hasOrmMap", 1.0f);
			mi->setParameter("ormMap", key.texture->ormTex, repeatSampler);
		} else {
			mi->setParameter("hasOrmMap", 0.0f);
			mi->setParameter("ormMap", whiteTex, repeatSampler);
		}

		if (key.texture && key.texture->heightTex) {
			mi->setParameter("hasHeightMap", 1.0f);
			mi->setParameter("heightMap", key.texture->heightTex, repeatSampler);
			mi->setParameter("heightScale", key.texture->heightScale);
		} else {
			mi->setParameter("hasHeightMap", 0.0f);
			mi->setParameter("heightMap", whiteTex, repeatSampler);
			mi->setParameter("heightScale", 0.0f);
		}
	}
}

#include "kine_material_geometry.inc"

static Box kine_compute_batch_bounds(
	const KineMesh *mesh,
	const math::mat4f *transforms,
	size_t count, const KineFilamentShader *shader = nullptr, float displacementPadding = 0.0f) {
	Box bounds = rigidTransform(mesh->localBounds, transforms[0]);
	for (size_t i = 1; i < count; i++) {
		bounds.unionSelf(rigidTransform(mesh->localBounds, transforms[i]));
	}
	if (shader) bounds.halfExtent += math::float3{shader->boundsPadding};
	bounds.halfExtent += math::float3{displacementPadding};
	return bounds;
}

static Box kine_compute_dynamic_batch_bounds(
	const KineMesh *mesh,
	const math::mat4f *transforms,
	size_t count, const KineFilamentShader *shader = nullptr, float displacementPadding = 0.0f) {
	constexpr float cellSize = 64.0f;
	Box exact = kine_compute_batch_bounds(mesh, transforms, count, shader, displacementPadding);
	const math::float3 minPoint = exact.center - exact.halfExtent;
	const math::float3 maxPoint = exact.center + exact.halfExtent;
	const math::float3 snappedMin{
		std::floor(minPoint.x / cellSize) * cellSize,
		std::floor(minPoint.y / cellSize) * cellSize,
		std::floor(minPoint.z / cellSize) * cellSize,
	};
	const math::float3 snappedMax{
		std::ceil(maxPoint.x / cellSize) * cellSize,
		std::ceil(maxPoint.y / cellSize) * cellSize,
		std::ceil(maxPoint.z / cellSize) * cellSize,
	};
	return Box{(snappedMin + snappedMax) * 0.5f, (snappedMax - snappedMin) * 0.5f};
}

static bool kine_material_is_highlight(int materialKind) {
	return materialKind == KINE_MAT_HIGHLIGHT_OUTLINE ||
		   materialKind == KINE_MAT_HIGHLIGHT_FILL ||
		   materialKind == KINE_MAT_HIGHLIGHT_OUTLINE_TOP ||
		   materialKind == KINE_MAT_HIGHLIGHT_FILL_TOP;
}

static bool kine_material_is_highlight_outline(int materialKind) {
	return materialKind == KINE_MAT_HIGHLIGHT_OUTLINE ||
		   materialKind == KINE_MAT_HIGHLIGHT_OUTLINE_TOP;
}

static bool kine_material_is_outline_mask(int materialKind) {
	return materialKind == KINE_MAT_OUTLINE_MASK;
}

// Materials the path tracer can represent. Water, clouds, decals, particles and
// gizmos are screen-space or editor effects with no Ray scene equivalent, and
// the Highlight kinds paint into a private mask instead of the scene.
static bool kine_material_is_path_traced(int materialKind) {
	return materialKind == KINE_MAT_DEFAULT ||
		   materialKind == KINE_MAT_GLASS ||
		   materialKind == KINE_MAT_NEON ||
		   materialKind == KINE_MAT_TERRAIN;
}

static bool kine_material_uses_instance_alpha(int materialKind) {
	return materialKind == KINE_MAT_PARTICLE ||
		   materialKind == KINE_MAT_HIGHLIGHT_OUTLINE ||
		   materialKind == KINE_MAT_HIGHLIGHT_FILL ||
		   materialKind == KINE_MAT_HIGHLIGHT_OUTLINE_TOP ||
		   materialKind == KINE_MAT_HIGHLIGHT_FILL_TOP ||
		   materialKind == KINE_MAT_OUTLINE_MASK;
}

static Material *kine_select_material(
	KineFilamentContext *ctx, int materialKind, KineFilamentShader *shader = nullptr, bool inheritGlobalShader = true) {
	if (shader && shader->ctx == ctx && shader->material)
		return shader->material;
	if (inheritGlobalShader && ctx->globalShader && ctx->globalShader->material)
		return ctx->globalShader->material;
	if (materialKind == KINE_MAT_GLASS)
		return ctx->glassMaterial;
	if (materialKind == KINE_MAT_NEON)
		return ctx->neonMaterial;
	if (materialKind == KINE_MAT_WATER)
		return ctx->waterMaterial;
	if (materialKind == KINE_MAT_FORCEFIELD)
		return ctx->forceFieldMaterial;
	if (materialKind == KINE_MAT_OUTLINE)
		return ctx->outlineMaterial;
	if (materialKind == KINE_MAT_GIZMO)
		return ctx->gizmoMaterial;
	if (materialKind == KINE_MAT_PARTICLE)
		return ctx->particleMaterial;
	if (materialKind == KINE_MAT_TERRAIN)
		return ctx->terrainMaterial;
	if (materialKind == KINE_MAT_HIGHLIGHT_OUTLINE)
		return ctx->hlOutlineMaterial;
	if (materialKind == KINE_MAT_HIGHLIGHT_FILL)
		return ctx->hlFillMaterial;
	if (materialKind == KINE_MAT_HIGHLIGHT_OUTLINE_TOP)
		return ctx->hlOutlineTopMaterial;
	if (materialKind == KINE_MAT_HIGHLIGHT_FILL_TOP)
		return ctx->hlFillTopMaterial;
	if (materialKind == KINE_MAT_OUTLINE_MASK)
		return ctx->outlineMaskMaterial;
	return ctx->defaultMaterial;
}

static KineBatchKey kine_draw_item_key(const KineFilamentDrawItem &item, uint64_t streamId = 0) {
	KineBatchKey key;
	key.mesh = (KineMesh *)item.mesh;
	key.shader = item.shader;
	if (key.shader) key.mesh = kine_refine_material_mesh(key.shader->ctx, key.mesh, key.shader->subdivisionLevel);
	key.streamId = streamId;
	key.materialKind = item.materialKind;
	key.param1 = item.param1;
	key.param2 = item.param2;

	key.param3 = (item.materialKind == KINE_MAT_DEFAULT) ? 0.0f : item.param3;
	key.transmission = item.transmission;
	key.castShadow = (item.flags & KINE_FILAMENT_DRAW_CAST_SHADOWS) != 0;
	key.receiveShadow = (item.flags & KINE_FILAMENT_DRAW_RECEIVE_SHADOWS) != 0;

	const KineMesh *cullMesh = (const KineMesh *)item.mesh;
	key.culling = (item.flags & KINE_FILAMENT_DRAW_CULLING) != 0 && !(cullMesh && cullMesh->doubleSided);

	KineMesh *itemMesh = (KineMesh *)item.mesh;
	key.texture = item.tex
					  ? (KineTexHandle *)item.tex
					  : (itemMesh && itemMesh->useImportedMaterials ? itemMesh->ownedTex : nullptr);
	return key;
}

static math::mat4f kine_draw_item_transform(const KineFilamentDrawItem &item) {
	const float *mat4 = item.transform;

	return math::mat4f(
		math::float4{mat4[0], mat4[4], mat4[8], mat4[12]},
		math::float4{mat4[1], mat4[5], mat4[9], mat4[13]},
		math::float4{mat4[2], mat4[6], mat4[10], mat4[14]},
		math::float4{mat4[3], mat4[7], mat4[11], mat4[15]});
}

static size_t kine_max_chunk_instances(KineFilamentContext *ctx) {
	size_t maxInstances = ctx->engine->getMaxAutomaticInstances();
	if (maxInstances == 0)
		maxInstances = 1;

	return std::min(maxInstances, KINE_MAX_INSTANCE_COLORS);
}

static void kine_set_chunk_colors(
	MaterialInstance *mi,
	const math::float4 *colors,
	size_t count) {
	if (!mi || !colors || count == 0 || !mi->getMaterial()->hasParameter("instanceColors"))
		return;
	count = std::min(count, KINE_MAX_INSTANCE_COLORS);
	mi->setParameter("instanceColors", colors, count);
}

static void kine_set_chunk_uvs(
	MaterialInstance *mi,
	const float *scales,
	size_t count) {
	if (!mi || !scales || count == 0 || !mi->getMaterial()->hasParameter("instanceUvScale"))
		return;
	count = std::min(count, KINE_MAX_INSTANCE_COLORS);
	mi->setParameter("instanceUvScale", scales, count);
}

static bool kine_ensure_outline_pipeline(KineFilamentContext *ctx);

#include "kine_imported_materials.inc"

static Scene *kine_scene_for_kind(KineFilamentContext *ctx, int materialKind) {
	if (!kine_material_is_outline_mask(materialKind))
		return ctx->scene;
	return ctx->outlineMaskScene;
}

static void kine_destroy_instance_batch_chunks(KineFilamentInstanceBatch *batch) {
	if (!batch || !batch->ctx || !batch->ctx->engine)
		return;
	KineFilamentContext *ctx = batch->ctx;
	Scene *scene = kine_scene_for_kind(ctx, batch->key.materialKind);
	for (KineBuiltBatch &chunk : batch->chunks) {
		if (!chunk.entity.isNull()) {
			if (scene)
				scene->remove(chunk.entity);
			ctx->engine->destroy(chunk.entity);
			EntityManager::get().destroy(chunk.entity);
		}
		if (chunk.instanceBuffer) {
			ctx->engine->destroy(chunk.instanceBuffer);
		}
		if (chunk.materialInstance) {
			ctx->engine->destroy(chunk.materialInstance);
		}
		kine_destroy_extra_materials(ctx,chunk.extraMaterials);
	}
	batch->chunks.clear();
}

static bool kine_rebuild_instance_batch(KineFilamentInstanceBatch *batch) {
	if (!batch || !batch->ctx || !batch->ctx->engine || batch->transforms.empty())
		return false;
	KineFilamentContext *ctx = batch->ctx;
	KineMesh *mesh = batch->key.mesh;
	if (!mesh || !mesh->vb || !mesh->ib)
		return false;

	Material *base = kine_select_material(ctx, batch->key.materialKind, batch->key.shader);
	if (!base)
		return false;
	if (kine_material_is_outline_mask(batch->key.materialKind)) {
		ctx->outlineQueued = true;
		if (batch->key.param2 > 0.0f)
			ctx->outlineWidthPixels = batch->key.param2;
		if (!kine_ensure_outline_pipeline(ctx)) {
			return false;
		}
	}

	kine_destroy_instance_batch_chunks(batch);

	size_t maxInstances = kine_max_chunk_instances(ctx);

	size_t offset = 0;
	while (offset < batch->transforms.size()) {
		const size_t count = std::min(maxInstances, batch->transforms.size() - offset);
		const math::mat4f *chunkTransforms = batch->transforms.data() + offset;
		const math::float4 *chunkColors = batch->colors.empty()
											  ? nullptr
											  : batch->colors.data() + offset;
		const Box bounds = kine_compute_dynamic_batch_bounds(mesh, chunkTransforms, count, batch->key.shader,
			batch->key.materialKind == KINE_MAT_WATER ? 0.65f*ctx->water.strength*ctx->water.height : 0.0f);

		MaterialInstance *mi = base->createInstance();
		kine_apply_material_params(ctx, mi, batch->key);
		kine_set_chunk_colors(mi, chunkColors, count);

		InstanceBuffer *instanceBuffer = InstanceBuffer::Builder(count).build(*ctx->engine);
		instanceBuffer->setLocalTransforms(chunkTransforms, count, 0);

		Entity entity = EntityManager::get().create();
		std::vector<MaterialInstance *> extraMaterials;
		RenderableManager::Builder renderableBuilder(kine_mesh_primitive_count(ctx,batch->key));
		kine_bind_mesh_geometry(ctx,renderableBuilder,batch->key,base,mi,extraMaterials,chunkColors,nullptr,count);
		renderableBuilder.boundingBox(bounds)
			.culling(batch->key.culling)
			.receiveShadows(batch->key.receiveShadow)
			.layerMask(0xff,kine_scene_geometry_layer(batch->key.materialKind))
			.castShadows(batch->key.castShadow)
			.instances(count, instanceBuffer);
		if (!mesh->bones.empty() && mesh->skinMatrices.size() == mesh->bones.size()) {
			renderableBuilder.skinning(mesh->skinMatrices.size(), mesh->skinMatrices.data());
		}
		if (batch->key.materialKind == KINE_MAT_GLASS) {

			renderableBuilder.channel(2).priority(0);
		} else if (kine_material_is_highlight(batch->key.materialKind)) {

			renderableBuilder.channel(3).priority(
				kine_material_is_highlight_outline(batch->key.materialKind) ? 0 : 1);
		}
		renderableBuilder.build(*ctx->engine, entity);

		Scene *targetScene = kine_scene_for_kind(ctx, batch->key.materialKind);
		if (!targetScene) {
			ctx->engine->destroy(entity);
			EntityManager::get().destroy(entity);
			ctx->engine->destroy(instanceBuffer);
			ctx->engine->destroy(mi);
			kine_destroy_extra_materials(ctx,extraMaterials);
			return false;
		}
		targetScene->addEntity(entity);
		batch->chunks.push_back({entity, instanceBuffer, mi, count});
		batch->chunks.back().extraMaterials=std::move(extraMaterials);
		offset += count;
	}

	return true;
}

static void kine_destroy_built_batches(KineFilamentContext *ctx);

static bool kine_switch_global_shader(KineFilamentContext *ctx, KineFilamentShader *shader) {
	if (!ctx || (shader && shader->ctx != ctx))
		return false;
	if (ctx->globalShader == shader)
		return true;

	kine_destroy_built_batches(ctx);
	ctx->globalShader = shader;

	bool rebuilt = true;
	for (KineFilamentInstanceBatch *batch : ctx->instanceBatches) {
		if (!batch)
			continue;
		kine_destroy_instance_batch_chunks(batch);
		rebuilt = kine_rebuild_instance_batch(batch) && rebuilt;
	}
	return rebuilt;
}

static void kine_destroy_post_process_pipeline(KineFilamentContext *ctx) {
	if (!ctx || !ctx->engine)
		return;
	if (ctx->view) {
		const int viewportWidth = ctx->viewportWidth > 0 ? ctx->viewportWidth : ctx->width;
		const int viewportHeight = ctx->viewportHeight > 0 ? ctx->viewportHeight : ctx->height;
		const int filamentY = std::clamp(
			ctx->height - ctx->viewportY - viewportHeight,
			0,
			std::max(0, ctx->height - 1));
		ctx->view->setRenderTarget(ctx->renderTarget);
		ctx->view->setViewport({int32_t(ctx->viewportX), int32_t(filamentY),
								uint32_t(viewportWidth), uint32_t(viewportHeight)});
	}
	if (ctx->postScene && !ctx->postQuadEntity.isNull()) {
		ctx->postScene->remove(ctx->postQuadEntity);
	}
	if (!ctx->postQuadEntity.isNull()) {
		ctx->engine->destroy(ctx->postQuadEntity);
		EntityManager::get().destroy(ctx->postQuadEntity);
		ctx->postQuadEntity.clear();
	}
	if (ctx->postMaterialInstance) {
		ctx->engine->destroy(ctx->postMaterialInstance);
		ctx->postMaterialInstance = nullptr;
	}
	if (!ctx->postCameraEntity.isNull()) {
		ctx->engine->destroyCameraComponent(ctx->postCameraEntity);
		EntityManager::get().destroy(ctx->postCameraEntity);
		ctx->postCameraEntity.clear();
		ctx->postCamera = nullptr;
	}
	if (ctx->postView) {
		ctx->engine->destroy(ctx->postView);
		ctx->postView = nullptr;
	}
	if (ctx->postScene) {
		ctx->engine->destroy(ctx->postScene);
		ctx->postScene = nullptr;
	}
	if (ctx->postSceneTarget) {
		ctx->engine->destroy(ctx->postSceneTarget);
		ctx->postSceneTarget = nullptr;
	}
	if (ctx->postSceneColor) {
		ctx->engine->destroy(ctx->postSceneColor);
		ctx->postSceneColor = nullptr;
	}
	if (ctx->postSceneDepth) {
		ctx->engine->destroy(ctx->postSceneDepth);
		ctx->postSceneDepth = nullptr;
	}
}

static void kine_apply_shader_uniforms(MaterialInstance *instance, KineFilamentShader *shader) {
	if (!instance || !shader)
		return;
	TextureSampler sampler(TextureSampler::MinFilter::LINEAR_MIPMAP_LINEAR, TextureSampler::MagFilter::LINEAR,
		TextureSampler::WrapMode::REPEAT);
	sampler.setAnisotropy(8.0f);
	for (const auto &[name, texture] : shader->textures)
		instance->setParameter(name.c_str(), texture, sampler);
	for (const auto &[name, values] : shader->uniforms) {
		switch (values.size()) {
		case 1:
			instance->setParameter(name.c_str(), values[0]);
			break;
		case 2:
			instance->setParameter(name.c_str(), math::float2{values[0], values[1]});
			break;
		case 3:
			instance->setParameter(name.c_str(), math::float3{values[0], values[1], values[2]});
			break;
		case 4:
			instance->setParameter(name.c_str(), math::float4{values[0], values[1], values[2], values[3]});
			break;
		default:
			break;
		}
	}
}

static void kine_composite_quad_bounds(
	const KineFilamentContext *ctx,
	float *left, float *right, float *bottom, float *top) {
	const int viewportWidth = ctx->viewportWidth > 0 ? ctx->viewportWidth : ctx->width;
	const int viewportHeight = ctx->viewportHeight > 0 ? ctx->viewportHeight : ctx->height;
	const int filamentY = std::clamp(
		ctx->height - ctx->viewportY - viewportHeight,
		0,
		std::max(0, ctx->height - 1));
	const int surfaceWidth = ctx->width > 0 ? ctx->width : 1;
	const int surfaceHeight = ctx->height > 0 ? ctx->height : 1;
	*left = -0.5f - float(ctx->viewportX) / float(viewportWidth);
	*right = *left + float(surfaceWidth) / float(viewportWidth);
	*bottom = -0.5f - float(filamentY) / float(viewportHeight);
	*top = *bottom + float(surfaceHeight) / float(viewportHeight);
}

static bool kine_build_post_process_pipeline(KineFilamentContext *ctx) {
	if (!ctx || !ctx->engine || !ctx->postProcessShader || !ctx->postProcessShader->material ||
		!ctx->postProcessQuadMesh || !ctx->postProcessQuadMesh->vb || !ctx->postProcessQuadMesh->ib)
		return false;
	Material *material = ctx->postProcessShader->material;
	if (!material->isSampler("inputTexture"))
		return false;

	kine_destroy_post_process_pipeline(ctx);
	const int viewportWidth = ctx->viewportWidth > 0 ? ctx->viewportWidth : ctx->width;
	const int viewportHeight = ctx->viewportHeight > 0 ? ctx->viewportHeight : ctx->height;
	const int filamentY = std::clamp(
		ctx->height - ctx->viewportY - viewportHeight,
		0,
		std::max(0, ctx->height - 1));
	ctx->postSceneColor = Texture::Builder()
							  .width(uint32_t(viewportWidth))
							  .height(uint32_t(viewportHeight))
							  .levels(1)
							  .usage(Texture::Usage::COLOR_ATTACHMENT | Texture::Usage::SAMPLEABLE)
							  .format(Texture::InternalFormat::RGBA8)
							  .build(*ctx->engine);
	ctx->postSceneDepth = Texture::Builder()
							  .width(uint32_t(viewportWidth))
							  .height(uint32_t(viewportHeight))
							  .levels(1)
							  .usage(Texture::Usage::DEPTH_ATTACHMENT)
							  .format(Texture::InternalFormat::DEPTH24)
							  .build(*ctx->engine);
	if (!ctx->postSceneColor || !ctx->postSceneDepth) {
		kine_destroy_post_process_pipeline(ctx);
		return false;
	}
	ctx->postSceneTarget = RenderTarget::Builder()
							   .texture(RenderTarget::AttachmentPoint::COLOR, ctx->postSceneColor)
							   .texture(RenderTarget::AttachmentPoint::DEPTH, ctx->postSceneDepth)
							   .build(*ctx->engine);
	ctx->postScene = ctx->engine->createScene();
	ctx->postView = ctx->engine->createView();
	ctx->postCameraEntity = EntityManager::get().create();
	ctx->postCamera = ctx->engine->createCamera(ctx->postCameraEntity);
	ctx->postMaterialInstance = material->createInstance();
	if (!ctx->postSceneTarget || !ctx->postScene || !ctx->postView || !ctx->postCamera || !ctx->postMaterialInstance) {
		kine_destroy_post_process_pipeline(ctx);
		return false;
	}

	TextureSampler sampler(TextureSampler::MinFilter::LINEAR, TextureSampler::MagFilter::LINEAR,
						   TextureSampler::WrapMode::CLAMP_TO_EDGE);
	ctx->postMaterialInstance->setParameter("inputTexture", ctx->postSceneColor, sampler);
	kine_apply_shader_uniforms(ctx->postMaterialInstance, ctx->postProcessShader);
	if (material->hasParameter("intensity") &&
		ctx->postProcessShader->uniforms.find("intensity") == ctx->postProcessShader->uniforms.end()) {
		ctx->postMaterialInstance->setParameter("intensity", 1.0f);
	}

	ctx->postQuadEntity = EntityManager::get().create();
	RenderableManager::Builder(1)
		.boundingBox({{0, 0, 0}, {1, 1, 0.1f}})
		.material(0, ctx->postMaterialInstance)
		.geometry(0, RenderableManager::PrimitiveType::TRIANGLES,
				  ctx->postProcessQuadMesh->vb, ctx->postProcessQuadMesh->ib, 0, ctx->postProcessQuadMesh->indexCount)
		.culling(false)
		.castShadows(false)
		.receiveShadows(false)
		.build(*ctx->engine, ctx->postQuadEntity);
	ctx->postScene->addEntity(ctx->postQuadEntity);
	float postQuadLeft, postQuadRight, postQuadBottom, postQuadTop;
	kine_composite_quad_bounds(ctx, &postQuadLeft, &postQuadRight, &postQuadBottom, &postQuadTop);
	ctx->postCamera->setProjection(Camera::Projection::ORTHO, postQuadLeft, postQuadRight, postQuadBottom, postQuadTop, 0.1, 10.0);
	ctx->postCamera->lookAt({0, 0, 1}, {0, 0, 0}, {0, 1, 0});
	ctx->postView->setScene(ctx->postScene);
	ctx->postView->setCamera(ctx->postCamera);
	ctx->postView->setRenderTarget(ctx->renderTarget);
	ctx->postView->setViewport({0, 0,
								uint32_t(ctx->width > 0 ? ctx->width : 1),
								uint32_t(ctx->height > 0 ? ctx->height : 1)});
	ctx->postView->setPostProcessingEnabled(false);
	ctx->view->setRenderTarget(ctx->postSceneTarget);
	ctx->view->setViewport({0, 0, uint32_t(viewportWidth), uint32_t(viewportHeight)});
	return true;
}

static void kine_destroy_batch_chunks(
	KineFilamentContext *ctx,
	const KineBatchKey &key,
	KinePersistentBatch &batch);
static void kine_destroy_persistent_batch(
	KineFilamentContext *ctx,
	const KineBatchKey &key,
	KinePersistentBatch &batch);

static void kine_destroy_outline_pipeline(KineFilamentContext *ctx) {
	if (!ctx || !ctx->engine)
		return;

	for (auto it = ctx->builtBatches.begin(); it != ctx->builtBatches.end();) {
		if (kine_material_is_outline_mask(it->first.materialKind)) {
			kine_destroy_persistent_batch(ctx, it->first, it->second);
			it = ctx->builtBatches.erase(it);
		} else {
			++it;
		}
	}
	for (KineFilamentInstanceBatch *batch : ctx->instanceBatches) {
		if (batch && kine_material_is_outline_mask(batch->key.materialKind)) {
			kine_destroy_instance_batch_chunks(batch);
		}
	}

	if (ctx->outlineScene && !ctx->outlineQuadEntity.isNull()) {
		ctx->outlineScene->remove(ctx->outlineQuadEntity);
	}
	if (!ctx->outlineQuadEntity.isNull()) {
		ctx->engine->destroy(ctx->outlineQuadEntity);
		EntityManager::get().destroy(ctx->outlineQuadEntity);
		ctx->outlineQuadEntity.clear();
	}
	if (ctx->outlineCompositeMI) {
		ctx->engine->destroy(ctx->outlineCompositeMI);
		ctx->outlineCompositeMI = nullptr;
	}
	if (!ctx->outlineCameraEntity.isNull()) {
		ctx->engine->destroyCameraComponent(ctx->outlineCameraEntity);
		EntityManager::get().destroy(ctx->outlineCameraEntity);
		ctx->outlineCameraEntity.clear();
		ctx->outlineCamera = nullptr;
	}
	if (ctx->outlineView) {
		ctx->engine->destroy(ctx->outlineView);
		ctx->outlineView = nullptr;
	}
	if (ctx->outlineScene) {
		ctx->engine->destroy(ctx->outlineScene);
		ctx->outlineScene = nullptr;
	}
	if (ctx->outlineMaskView) {
		ctx->engine->destroy(ctx->outlineMaskView);
		ctx->outlineMaskView = nullptr;
	}
	if (ctx->outlineMaskScene) {
		ctx->engine->destroy(ctx->outlineMaskScene);
		ctx->outlineMaskScene = nullptr;
	}
	if (ctx->outlineMaskTarget) {
		ctx->engine->destroy(ctx->outlineMaskTarget);
		ctx->outlineMaskTarget = nullptr;
	}
	if (ctx->outlineMaskColor) {
		ctx->engine->destroy(ctx->outlineMaskColor);
		ctx->outlineMaskColor = nullptr;
	}
	if (ctx->outlineMaskDepth) {
		ctx->engine->destroy(ctx->outlineMaskDepth);
		ctx->outlineMaskDepth = nullptr;
	}
	ctx->outlineWidthPixels = 0.0f;
}

static bool kine_build_outline_pipeline(KineFilamentContext *ctx) {
	if (!ctx || !ctx->engine || !ctx->camera ||
		!ctx->outlineMaskMaterial || !ctx->outlineCompositeMaterial ||
		!ctx->postProcessQuadMesh || !ctx->postProcessQuadMesh->vb || !ctx->postProcessQuadMesh->ib) {
		return false;
	}

	kine_destroy_outline_pipeline(ctx);
	const int viewportWidth = ctx->viewportWidth > 0 ? ctx->viewportWidth : ctx->width;
	const int viewportHeight = ctx->viewportHeight > 0 ? ctx->viewportHeight : ctx->height;

	ctx->outlineMaskColor = Texture::Builder()
								.width(uint32_t(viewportWidth))
								.height(uint32_t(viewportHeight))
								.levels(1)
								.usage(Texture::Usage::COLOR_ATTACHMENT | Texture::Usage::SAMPLEABLE)
								.format(Texture::InternalFormat::RGBA8)
								.build(*ctx->engine);
	ctx->outlineMaskDepth = Texture::Builder()
								.width(uint32_t(viewportWidth))
								.height(uint32_t(viewportHeight))
								.levels(1)
								.usage(Texture::Usage::DEPTH_ATTACHMENT)
								.format(Texture::InternalFormat::DEPTH24)
								.build(*ctx->engine);
	if (!ctx->outlineMaskColor || !ctx->outlineMaskDepth) {
		kine_destroy_outline_pipeline(ctx);
		return false;
	}
	ctx->outlineMaskTarget = RenderTarget::Builder()
								 .texture(RenderTarget::AttachmentPoint::COLOR, ctx->outlineMaskColor)
								 .texture(RenderTarget::AttachmentPoint::DEPTH, ctx->outlineMaskDepth)
								 .build(*ctx->engine);

	ctx->outlineMaskScene = ctx->engine->createScene();
	ctx->outlineMaskView = ctx->engine->createView();
	ctx->outlineScene = ctx->engine->createScene();
	ctx->outlineView = ctx->engine->createView();
	ctx->outlineCameraEntity = EntityManager::get().create();
	ctx->outlineCamera = ctx->engine->createCamera(ctx->outlineCameraEntity);
	ctx->outlineCompositeMI = ctx->outlineCompositeMaterial->createInstance();
	if (!ctx->outlineMaskTarget || !ctx->outlineMaskScene || !ctx->outlineMaskView ||
		!ctx->outlineScene || !ctx->outlineView || !ctx->outlineCamera ||
		!ctx->outlineCompositeMI) {
		kine_destroy_outline_pipeline(ctx);
		return false;
	}

	ctx->outlineMaskView->setScene(ctx->outlineMaskScene);
	ctx->outlineMaskView->setCamera(ctx->camera);
	ctx->outlineMaskView->setRenderTarget(ctx->outlineMaskTarget);
	ctx->outlineMaskView->setViewport({0, 0, uint32_t(viewportWidth), uint32_t(viewportHeight)});
	// Preserve mask alpha, including the zero-alpha background, through any
	// intermediate buffers used by Filament.
	ctx->outlineMaskView->setBlendMode(View::BlendMode::TRANSLUCENT);
	ctx->outlineMaskView->setPostProcessingEnabled(false);
	ctx->outlineMaskView->setShadowingEnabled(false);
	ctx->outlineMaskView->setAntiAliasing(AntiAliasing::NONE);

	TextureSampler sampler(TextureSampler::MinFilter::NEAREST, TextureSampler::MagFilter::NEAREST,
						   TextureSampler::WrapMode::CLAMP_TO_EDGE);
	ctx->outlineCompositeMI->setParameter("mask", ctx->outlineMaskColor, sampler);
	ctx->outlineCompositeMI->setParameter("texel",
										  math::float2{1.0f / float(viewportWidth), 1.0f / float(viewportHeight)});

	ctx->outlineQuadEntity = EntityManager::get().create();
	RenderableManager::Builder(1)
		.boundingBox({{0, 0, 0}, {1, 1, 0.1f}})
		.material(0, ctx->outlineCompositeMI)
		.geometry(0, RenderableManager::PrimitiveType::TRIANGLES,
				  ctx->postProcessQuadMesh->vb, ctx->postProcessQuadMesh->ib, 0, ctx->postProcessQuadMesh->indexCount)
		.culling(false)
		.castShadows(false)
		.receiveShadows(false)
		.build(*ctx->engine, ctx->outlineQuadEntity);
	ctx->outlineScene->addEntity(ctx->outlineQuadEntity);
	float quadLeft, quadRight, quadBottom, quadTop;
	kine_composite_quad_bounds(ctx, &quadLeft, &quadRight, &quadBottom, &quadTop);
	ctx->outlineCamera->setProjection(Camera::Projection::ORTHO, quadLeft, quadRight, quadBottom, quadTop, 0.1, 10.0);
	ctx->outlineCamera->lookAt({0, 0, 1}, {0, 0, 0}, {0, 1, 0});
	ctx->outlineView->setScene(ctx->outlineScene);
	ctx->outlineView->setCamera(ctx->outlineCamera);
	ctx->outlineView->setBlendMode(View::BlendMode::TRANSLUCENT);

	ctx->outlineView->setRenderTarget(ctx->renderTarget);

	ctx->outlineView->setViewport({0, 0,
								   uint32_t(ctx->width > 0 ? ctx->width : 1),
								   uint32_t(ctx->height > 0 ? ctx->height : 1)});
	ctx->outlineView->setPostProcessingEnabled(false);
	return true;
}

static bool kine_ensure_outline_pipeline(KineFilamentContext *ctx) {
	if (!ctx || !ctx->engine)
		return false;
	if (ctx->outlineView && ctx->outlineMaskView && ctx->outlineCompositeMI)
		return true;
	return kine_build_outline_pipeline(ctx);
}

static void kine_destroy_batch_chunks(
	KineFilamentContext *ctx,
	const KineBatchKey &key,
	KinePersistentBatch &batch) {
	Scene *scene = kine_scene_for_kind(ctx, key.materialKind);
	for (KineBuiltBatch &chunk : batch.chunks) {
		if (!chunk.entity.isNull()) {
			if (scene)
				scene->remove(chunk.entity);
			ctx->engine->destroy(chunk.entity);
			EntityManager::get().destroy(chunk.entity);
		}
		if (chunk.instanceBuffer) {
			ctx->engine->destroy(chunk.instanceBuffer);
		}
		if (chunk.materialInstance) {
			ctx->engine->destroy(chunk.materialInstance);
		}
		kine_destroy_extra_materials(ctx,chunk.extraMaterials);
	}
	batch.chunks.clear();
}

static void kine_destroy_persistent_batch(
	KineFilamentContext *ctx,
	const KineBatchKey &key,
	KinePersistentBatch &batch) {
	kine_destroy_batch_chunks(ctx, key, batch);
}

static void kine_update_batches(KineFilamentContext *ctx) {
	size_t maxInstances = kine_max_chunk_instances(ctx);

	std::vector<std::pair<KineBatchKey, KinePendingBatch *>> sortedBatches;
	sortedBatches.reserve(ctx->pendingBatches.size());
	for (auto &kv : ctx->pendingBatches) {
		if (kv.second.lastQueuedFrame == ctx->batchFrame &&
			!kv.second.transforms.empty() && kv.first.mesh) {
			sortedBatches.push_back({kv.first, &kv.second});
		}
	}
	std::sort(sortedBatches.begin(), sortedBatches.end(),
			  [](const auto &a, const auto &b) {
				  return a.first.materialKind < b.first.materialKind;
			  });

	for (auto &[key, pending] : sortedBatches) {
		KineMesh *m = key.mesh;
		if (!m->vb || !m->ib)
			continue;

		Material *base = kine_select_material(ctx, key.materialKind, key.shader);
		if (!base)
			continue;
		if (kine_material_is_outline_mask(key.materialKind)) {

			ctx->outlineQueued = true;
			if (key.param2 > 0.0f)
				ctx->outlineWidthPixels = key.param2;
			if (!kine_ensure_outline_pipeline(ctx)) {
				continue;
			}
		}

		KinePersistentBatch &batch = ctx->builtBatches[key];
		batch.lastUsedFrame = ctx->batchFrame;

		std::vector<math::mat4f> &transforms = pending->transforms;
		std::vector<math::float4> &colors = pending->colors;
		std::vector<float> &uvScales = pending->uvScales;
		const size_t requiredChunks = (transforms.size() + maxInstances - 1) / maxInstances;
		bool rebuildChunks = batch.chunks.size() != requiredChunks;
		if (!rebuildChunks) {
			for (size_t chunkIndex = 0; chunkIndex < requiredChunks; chunkIndex++) {
				const size_t offset = chunkIndex * maxInstances;
				const size_t count = std::min(maxInstances, transforms.size() - offset);
				if (batch.chunks[chunkIndex].instanceCount != count) {
					rebuildChunks = true;
					break;
				}
			}
		}

		if (rebuildChunks) {
			kine_destroy_batch_chunks(ctx, key, batch);
		}
		const bool transformsChanged = rebuildChunks || batch.transformHash != pending->transformHash;
		const bool colorsChanged = rebuildChunks || batch.colorHash != pending->colorHash;
		const bool uvsChanged = rebuildChunks || batch.uvHash != pending->uvHash;

		// A batch retained (and detached) on a previous frame is being used
		// again: hook its entities back into the scene.
		if (!rebuildChunks && batch.detached) {
			Scene *reattachScene = kine_scene_for_kind(ctx, key.materialKind);
			if (reattachScene) {
				for (KineBuiltBatch &chunk : batch.chunks) {
					if (!chunk.entity.isNull())
						reattachScene->addEntity(chunk.entity);
				}
			}
			batch.detached = false;
		}

		size_t offset = 0;
		size_t chunkIndex = 0;
		while (offset < transforms.size()) {
			const size_t count = std::min(maxInstances, transforms.size() - offset);
			const math::mat4f *chunkTransforms = transforms.data() + offset;
			const math::float4 *chunkColors = colors.data() + offset;
			const float *chunkUvs = uvScales.size() == transforms.size()
										? uvScales.data() + offset
										: nullptr;
			if (rebuildChunks) {
				const Box bounds = kine_compute_batch_bounds(m, chunkTransforms, count, key.shader,
					key.materialKind == KINE_MAT_WATER ? 0.65f*ctx->water.strength*ctx->water.height : 0.0f);
				MaterialInstance *mi = base->createInstance();
				kine_apply_material_params(ctx, mi, key);
				kine_set_chunk_colors(mi, chunkColors, count);
				kine_set_chunk_uvs(mi, chunkUvs, count);

				InstanceBuffer *instanceBuffer = InstanceBuffer::Builder(count).build(*ctx->engine);
				instanceBuffer->setLocalTransforms(chunkTransforms, count, 0);

				Entity entity = EntityManager::get().create();
				std::vector<MaterialInstance *> extraMaterials;
				RenderableManager::Builder renderableBuilder(kine_mesh_primitive_count(ctx,key));
				kine_bind_mesh_geometry(ctx,renderableBuilder,key,base,mi,extraMaterials,chunkColors,chunkUvs,count);
				renderableBuilder.boundingBox(bounds)
					.culling(key.culling)
					.receiveShadows(key.receiveShadow)
					.layerMask(0xff,kine_scene_geometry_layer(key.materialKind))
					.castShadows(key.castShadow)
					.instances(count, instanceBuffer);
				if (!m->bones.empty() && m->skinMatrices.size() == m->bones.size()) {
					renderableBuilder.skinning(m->skinMatrices.size(), m->skinMatrices.data());
				}
				if (key.materialKind == KINE_MAT_GLASS) {

					renderableBuilder.channel(2).priority(0);
				} else if (kine_material_is_highlight(key.materialKind)) {

					renderableBuilder.channel(3).priority(
						kine_material_is_highlight_outline(key.materialKind) ? 0 : 1);
				}
				renderableBuilder.build(*ctx->engine, entity);

				Scene *targetScene = kine_scene_for_kind(ctx, key.materialKind);
				if (!targetScene) {
					ctx->engine->destroy(entity);
					EntityManager::get().destroy(entity);
					ctx->engine->destroy(instanceBuffer);
					ctx->engine->destroy(mi);
					kine_destroy_extra_materials(ctx,extraMaterials);
					continue;
				}
				targetScene->addEntity(entity);
				batch.chunks.push_back({entity, instanceBuffer, mi, count});
				batch.chunks.back().extraMaterials=std::move(extraMaterials);
				batch.chunks.back().instanceTransformHashes.assign(
					pending->instanceTransformHashes.begin() + offset,
					pending->instanceTransformHashes.begin() + offset + count);
			} else if (transformsChanged || colorsChanged || uvsChanged) {
				KineBuiltBatch &chunk = batch.chunks[chunkIndex];
				if (transformsChanged) {
					// Upload only the instances whose transform actually moved.
					// The bounds are still a union over the whole chunk, so they
					// are recomputed whenever anything in it changed.
					const bool hashSizeMismatch = chunk.instanceTransformHashes.size() != count;
					size_t firstDirty = count;
					size_t lastDirty = 0;
					for (size_t i = 0; i < count; ++i) {
						if (hashSizeMismatch ||
							chunk.instanceTransformHashes[i] !=
								pending->instanceTransformHashes[offset + i]) {
							if (firstDirty == count)
								firstDirty = i;
							lastDirty = i;
						}
					}
					if (firstDirty < count) {
						const Box bounds = kine_compute_batch_bounds(m, chunkTransforms, count, key.shader,
							key.materialKind == KINE_MAT_WATER ? 0.65f*ctx->water.strength*ctx->water.height : 0.0f);
						chunk.instanceBuffer->setLocalTransforms(
							chunkTransforms + firstDirty, lastDirty - firstDirty + 1, firstDirty);
						RenderableManager &rm = ctx->engine->getRenderableManager();
						RenderableManager::Instance renderable = rm.getInstance(chunk.entity);
						if (renderable.isValid()) {
							rm.setAxisAlignedBoundingBox(renderable, bounds);
						}
					}
					chunk.instanceTransformHashes.assign(
						pending->instanceTransformHashes.begin() + offset,
						pending->instanceTransformHashes.begin() + offset + count);
				}
				if (colorsChanged) {
					kine_set_chunk_colors(chunk.materialInstance, chunkColors, count);
					for (auto *mi : chunk.extraMaterials) kine_set_chunk_colors(mi,chunkColors,count);
				}
				if (uvsChanged) {
					if (!kine_uses_imported_materials(ctx,key)) kine_set_chunk_uvs(chunk.materialInstance, chunkUvs, count);
				}
			}

			offset += count;
			chunkIndex++;
		}
		batch.transformHash = pending->transformHash;
		batch.colorHash = pending->colorHash;
		batch.uvHash = pending->uvHash;
	}

	for (auto &[key, batch] : ctx->builtBatches) {
		if (batch.lastUsedFrame == ctx->batchFrame &&
			key.materialKind == KINE_MAT_WATER) {
			for (KineBuiltBatch &chunk : batch.chunks) {
				if (chunk.materialInstance) {
					kine_apply_material_params(ctx, chunk.materialInstance, key);
				}
			}
		}
	}

	// Keep a batch's GPU objects for a couple of frames after it stops being
	// drawn, but detach it immediately so it does not render stale geometry.
	// Frustum culling can drop a batch for a single frame at an edge; rebuilding
	// the entity, instance buffer and material instance for that is pure churn.
	constexpr uint64_t KINE_BATCH_RETENTION_FRAMES = 2;
	for (auto it = ctx->builtBatches.begin(); it != ctx->builtBatches.end();) {
		KinePersistentBatch &batch = it->second;
		if (batch.lastUsedFrame == ctx->batchFrame) {
			++it;
			continue;
		}
		if (ctx->batchFrame - batch.lastUsedFrame <= KINE_BATCH_RETENTION_FRAMES) {
			if (!batch.detached) {
				Scene *scene = kine_scene_for_kind(ctx, it->first.materialKind);
				if (scene) {
					for (KineBuiltBatch &chunk : batch.chunks) {
						if (!chunk.entity.isNull())
							scene->remove(chunk.entity);
					}
				}
				batch.detached = true;
			}
			++it;
			continue;
		}
		kine_destroy_persistent_batch(ctx, it->first, it->second);
		it = ctx->builtBatches.erase(it);
	}
}

static void kine_finish_batch_frame(KineFilamentContext *ctx) {
	ctx->batchFrame++;

	ctx->outlineQueued = false;
	for (auto it = ctx->pendingBatches.begin(); it != ctx->pendingBatches.end();) {
		if (ctx->batchFrame - it->second.lastQueuedFrame > 120) {
			it = ctx->pendingBatches.erase(it);
		} else {
			++it;
		}
	}
}

static void kine_destroy_built_batches(KineFilamentContext *ctx) {
	for (auto &[key, batch] : ctx->builtBatches) {
		kine_destroy_persistent_batch(ctx, key, batch);
	}
	ctx->builtBatches.clear();
}

static void kine_invalidate_batches(
	KineFilamentContext *ctx,
	const KineMesh *mesh,
	const KineTexHandle *texture) {
	if (mesh) {
		kine_destroy_refined_meshes(ctx, const_cast<KineMesh *>(mesh));
	}
	kine_viewport_invalidate_batches(ctx, mesh, texture);
	auto matches = [mesh, texture](const KineBatchKey &key) {
		return (mesh && key.mesh == mesh) || (texture && key.texture == texture);
	};

	for (auto it = ctx->builtBatches.begin(); it != ctx->builtBatches.end();) {
		if (matches(it->first)) {
			kine_destroy_persistent_batch(ctx, it->first, it->second);
			it = ctx->builtBatches.erase(it);
		} else {
			++it;
		}
	}
	for (auto it = ctx->pendingBatches.begin(); it != ctx->pendingBatches.end();) {
		if (matches(it->first)) {
			it = ctx->pendingBatches.erase(it);
		} else {
			++it;
		}
	}
	for (auto &[streamId, state] : ctx->retainedLists) {
		(void)streamId;
#if KINE_WITH_RAY
		if (mesh) {
			state.rayDraws.erase(std::remove_if(state.rayDraws.begin(),state.rayDraws.end(),
				[mesh](const KineRayQueuedDraw &draw) {return draw.mesh == mesh;}),state.rayDraws.end());
		}
#endif
		const size_t oldSize = state.keys.size();
		state.keys.erase(
			std::remove_if(state.keys.begin(), state.keys.end(), matches),
			state.keys.end());
		if (state.keys.size() != oldSize) {
			state.initialized = false;
		}
	}
#if KINE_WITH_RAY
	if (mesh) {
		ctx->rayDraws.erase(std::remove_if(ctx->rayDraws.begin(),ctx->rayDraws.end(),
			[mesh](const KineRayQueuedDraw &draw) {return draw.mesh == mesh;}),ctx->rayDraws.end());
		ctx->rayIndexCache.erase(const_cast<KineMesh *>(mesh));
	}
#endif
}

static void kine_destroy_decal(KineFilamentContext *ctx, KineDecalResource &decal) {
	if (!decal.entity.isNull()) {
		ctx->scene->remove(decal.entity);
		ctx->engine->destroy(decal.entity);
		EntityManager::get().destroy(decal.entity);
		decal.entity = {};
	}
	if (decal.material) {
		ctx->engine->destroy(decal.material);
		decal.material = nullptr;
	}
	if (decal.mesh) {
		if (decal.mesh->vb)
			ctx->engine->destroy(decal.mesh->vb);
		if (decal.mesh->ib)
			ctx->engine->destroy(decal.mesh->ib);
		delete decal.mesh;
		decal.mesh = nullptr;
	}
}

} // namespace

static Material *buildDefaultMaterial(Engine *engine) {
	return Material::Builder()
		.package(KINE_DEFAULT_PACKAGE_KINE_DEFAULT_DATA, KINE_DEFAULT_PACKAGE_KINE_DEFAULT_SIZE)
		.build(*engine);
}

static Material *buildWaterMaterial(Engine *engine) {
	return Material::Builder()
		.package(KINE_WATER_PACKAGE_KINE_WATER_DATA, KINE_WATER_PACKAGE_KINE_WATER_SIZE)
		.build(*engine);
}

static Material *buildCloudMaterial(Engine *engine) {
	return Material::Builder()
		.package(KINE_CLOUD_PACKAGE_KINE_CLOUD_DATA, KINE_CLOUD_PACKAGE_KINE_CLOUD_SIZE)
		.build(*engine);
}

// ---------------------------------------------------------------------------
// Sky cloud layer
//
// An infinite horizontal slab raymarched by kine_cloud. The only geometry is a
// quad parked on the far plane, so the layer has no horizontal edge and is
// depth-tested against the scene; Lighting drives it through
// Kine_Filament_SetClouds and the shim owns the entity.
// ---------------------------------------------------------------------------

static bool kine_ensure_cloud_layer(KineFilamentContext *ctx) {
	if (ctx->cloudMI)
		return true;
	if (!ctx->cloudMaterial || !ctx->engine || !ctx->scene)
		return false;

	if (!ctx->cloudMesh) {
		// Unit quad in the XY plane, sized into the far plane by the transform.
		auto *mesh = new KineMesh();
		mesh->vertices = {
			{-1.0f, -1.0f, 0.0f, 0.0f, 0.0f, 1.0f, 0.0f, 1.0f},
			{1.0f, -1.0f, 0.0f, 0.0f, 0.0f, 1.0f, 1.0f, 1.0f},
			{1.0f, 1.0f, 0.0f, 0.0f, 0.0f, 1.0f, 1.0f, 0.0f},
			{-1.0f, 1.0f, 0.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f},
		};
		mesh->indices = {0, 1, 2, 0, 2, 3};
		mesh->indexCount = static_cast<uint32_t>(mesh->indices.size());
		uploadMesh(mesh, ctx->engine);
		if (!mesh->vb || !mesh->ib) {
			delete mesh;
			return false;
		}
		ctx->cloudMesh = mesh;
	}

	ctx->cloudMI = ctx->cloudMaterial->createInstance();
	if (!ctx->cloudMI)
		return false;

	ctx->cloudEntity = EntityManager::get().create();
	RenderableManager::Builder(1)
		.boundingBox({{-1.0f, -1.0f, -1.0f}, {1.0f, 1.0f, 1.0f}})
		.material(0, ctx->cloudMI)
		.geometry(0, RenderableManager::PrimitiveType::TRIANGLES, ctx->cloudMesh->vb,
				  ctx->cloudMesh->ib)
		// The camera lives inside the box, so frustum culling is decided by
		// the transform instead of a sky-sized bounding sphere.
		.culling(false)
		.castShadows(false)
		.receiveShadows(false)
		.build(*ctx->engine, ctx->cloudEntity);
	return true;
}

static void kine_update_cloud_layer(KineFilamentContext *ctx) {
	if (!ctx || !ctx->cloudEnabled || !ctx->camera)
		return;
	if (!kine_ensure_cloud_layer(ctx))
		return;

	if (!ctx->cloudInScene) {
		ctx->scene->addEntity(ctx->cloudEntity);
		ctx->cloudInScene = true;
	}

	const float thickness = std::max(ctx->cloudThickness, 1.0f);

	// Use the camera's real pose and projection, not cached copies.
	const math::mat4 modelD = ctx->camera->getModelMatrix();
	const math::mat4 projD = ctx->camera->getProjectionMatrix();

	const math::float3 eye{(float)modelD[3].x, (float)modelD[3].y, (float)modelD[3].z};
	const math::float3 right{(float)modelD[0].x, (float)modelD[0].y, (float)modelD[0].z};
	const math::float3 up{(float)modelD[1].x, (float)modelD[1].y, (float)modelD[1].z};
	const math::float3 forward{-(float)modelD[2].x, -(float)modelD[2].y, -(float)modelD[2].z};

	const double focalX = projD[0].x; // column-major: x focal
	const double focalY = projD[1].y; // y focal
	if (!(focalX > 1e-6) || !(focalY > 1e-6))
		return;

	const float distance = (float)ctx->camera->getCullingFar() * 0.98f;
	// Slight overscan so edges and TAA jitter never reveal the border.
	const float halfWidth = (float)(distance / focalX) * 1.05f;
	const float halfHeight = (float)(distance / focalY) * 1.05f;
	const math::float3 centre = eye + forward * distance;

	const math::mat4f transform{
		math::float4{right.x * halfWidth, right.y * halfWidth, right.z * halfWidth, 0.0f},
		math::float4{up.x * halfHeight, up.y * halfHeight, up.z * halfHeight, 0.0f},
		math::float4{forward.x, forward.y, forward.z, 0.0f},
		math::float4{centre.x, centre.y, centre.z, 1.0f}};

	TransformManager &tm = ctx->engine->getTransformManager();
	auto instance = tm.getInstance(ctx->cloudEntity);
	if (!instance.isValid()) {
		tm.create(ctx->cloudEntity);
		instance = tm.getInstance(ctx->cloudEntity);
	}
	if (instance.isValid())
		tm.setTransform(instance, transform);

	MaterialInstance *mi = ctx->cloudMI;
	mi->setParameter("time", ctx->time);
	mi->setParameter("cover", ctx->cloudCover);
	mi->setParameter("density", ctx->cloudDensity);
	mi->setParameter("detail", 1.0f);
	mi->setParameter("noiseScale", std::max(thickness * 1.6f, 40.0f));
	mi->setParameter("absorption", 1.4f);
	mi->setParameter("slabCentre", math::float3{0.0f, ctx->cloudHeight - eye.y, 0.0f});
	mi->setParameter("halfThickness", thickness * 0.5f);
	mi->setParameter("cameraPosition", eye);
	mi->setParameter("scattering", 1.1f);
	mi->setParameter("windSpeed", 1.0f);
	mi->setParameter("sunDirection", ctx->sunDirection);
	mi->setParameter("sunColor", math::float3{1.0f, 0.97f, 0.92f});
	mi->setParameter("cloudColor", ctx->cloudColor);
}

KINE_API void Kine_Filament_SetClouds(
	KineFilamentContext *ctx,
	bool enabled,
	float cover,
	float density,
	float height,
	float thickness,
	float r, float g, float b) {
	if (!ctx || !ctx->engine || !ctx->scene)
		return;
	if(ctx->cloudEnabled!=enabled || ctx->cloudCover!=cover || ctx->cloudDensity!=density ||
	   ctx->cloudHeight!=height || ctx->cloudThickness!=thickness ||
	   ctx->cloudColor!=math::float3{r,g,b})ctx->reflectionDirty=true;

	ctx->cloudEnabled = enabled;
	ctx->cloudCover = std::clamp(cover, 0.0f, 1.0f);
	ctx->cloudDensity = std::clamp(density, 0.0f, 1.0f);
	ctx->cloudHeight = height;
	ctx->cloudThickness = std::max(thickness, 1.0f);
	ctx->cloudColor = math::float3{std::max(r, 0.0f), std::max(g, 0.0f), std::max(b, 0.0f)};

	if (!enabled) {
		if (ctx->cloudInScene) {
			ctx->scene->remove(ctx->cloudEntity);
			ctx->cloudInScene = false;
		}
		return;
	}

	kine_update_cloud_layer(ctx);
}

KINE_API void Kine_Filament_SetWaterTime(KineFilamentContext *ctx, float time) {
	if (ctx && std::isfinite(time)) {ctx->waterTime = time; ctx->explicitWaterTime = true;}
}

KINE_API void Kine_Filament_SetWaterParams(
	KineFilamentContext *ctx, const KineFilamentWaterParams *params) {
	if (!ctx || !params)
		return;

	KineFilamentWaterParams w = *params;
	w.speed = std::clamp(w.speed, 0.0f, 10.0f);
	w.strength = std::clamp(w.strength, 0.0f, 10.0f);
	w.octaves = std::clamp(w.octaves, 1.0f, 32.0f);
	w.height = std::clamp(w.height, 0.0f, 10.0f);
	w.waveScale = std::max(w.waveScale, 0.0f);
	w.foamAmount = std::clamp(w.foamAmount, 0.0f, 1.0f);
	w.absorptionR = std::max(w.absorptionR, 0.0f);
	w.absorptionG = std::max(w.absorptionG, 0.0f);
	w.absorptionB = std::max(w.absorptionB, 0.0f);
	w.clearCoat = std::clamp(w.clearCoat, 0.0f, 1.0f);
	w.clearCoatRoughness = std::clamp(w.clearCoatRoughness, 0.0f, 1.0f);
	ctx->water = w;

	for (auto &[key, batch] : ctx->builtBatches) {
		if (key.materialKind != KINE_MAT_WATER)
			continue;
		for (KineBuiltBatch &chunk : batch.chunks) {
			if (chunk.materialInstance)
				kine_apply_material_params(ctx, chunk.materialInstance, key);
		}
	}
	for (KineFilamentInstanceBatch *batch : ctx->instanceBatches) {
		if (!batch || batch->key.materialKind != KINE_MAT_WATER)
			continue;
		for (KineBuiltBatch &chunk : batch->chunks) {
			if (chunk.materialInstance)
				kine_apply_material_params(ctx, chunk.materialInstance, batch->key);
		}
	}
}

KINE_API bool Kine_Filament_GetWaterParams(
	KineFilamentContext *ctx, KineFilamentWaterParams *out) {
	if (!ctx || !out)
		return false;
	*out = ctx->water;
	return true;
}

static Material *buildNeonMaterial(Engine *engine) {
	return Material::Builder()
		.package(KINE_NEON_PACKAGE_KINE_NEON_DATA, KINE_NEON_PACKAGE_KINE_NEON_SIZE)
		.build(*engine);
}

static Material *buildGlassMaterial(Engine *engine) {
	return Material::Builder()
		.package(KINE_GLASS_PACKAGE_KINE_GLASS_DATA, KINE_GLASS_PACKAGE_KINE_GLASS_SIZE)
		.build(*engine);
}

static Material *buildDecalMaterial(Engine *engine) {
	return Material::Builder()
		.package(KINE_DECAL_PACKAGE_KINE_DECAL_DATA, KINE_DECAL_PACKAGE_KINE_DECAL_SIZE)
		.build(*engine);
}

static Material *buildOutlineMaterial(Engine *engine) {
	return Material::Builder()
		.package(KINE_OUTLINE_PACKAGE_KINE_OUTLINE_DATA, KINE_OUTLINE_PACKAGE_KINE_OUTLINE_SIZE)
		.build(*engine);
}

static Material *buildGizmoMaterial(Engine *engine) {
	return Material::Builder()
		.package(KINE_GIZMO_PACKAGE_KINE_GIZMO_DATA, KINE_GIZMO_PACKAGE_KINE_GIZMO_SIZE)
		.build(*engine);
}

static Material *buildParticleMaterial(Engine *engine) {
	return Material::Builder()
		.package(KINE_PARTICLE_PACKAGE_KINE_PARTICLE_DATA, KINE_PARTICLE_PACKAGE_KINE_PARTICLE_SIZE)
		.build(*engine);
}

static Material *buildTerrainMaterial(Engine *engine) {
	return Material::Builder()
		.package(KINE_TERRAIN_PACKAGE_KINE_TERRAIN_DATA, KINE_TERRAIN_PACKAGE_KINE_TERRAIN_SIZE)
		.build(*engine);
}

static Material *buildHighlightOutlineMaterial(Engine *engine) {
	return Material::Builder()
		.package(KINE_HL_OUTLINE_PACKAGE_KINE_HL_OUTLINE_DATA, KINE_HL_OUTLINE_PACKAGE_KINE_HL_OUTLINE_SIZE)
		.build(*engine);
}

static Material *buildHighlightOutlineTopMaterial(Engine *engine) {
	return Material::Builder()
		.package(KINE_HL_OUTLINE_TOP_PACKAGE_KINE_HL_OUTLINE_TOP_DATA, KINE_HL_OUTLINE_TOP_PACKAGE_KINE_HL_OUTLINE_TOP_SIZE)
		.build(*engine);
}

static Material *buildHighlightFillMaterial(Engine *engine) {
	return Material::Builder()
		.package(KINE_HL_FILL_PACKAGE_KINE_HL_FILL_DATA, KINE_HL_FILL_PACKAGE_KINE_HL_FILL_SIZE)
		.build(*engine);
}

static Material *buildHighlightFillTopMaterial(Engine *engine) {
	return Material::Builder()
		.package(KINE_HL_FILL_TOP_PACKAGE_KINE_HL_FILL_TOP_DATA, KINE_HL_FILL_TOP_PACKAGE_KINE_HL_FILL_TOP_SIZE)
		.build(*engine);
}

static Material *buildOutlineMaskMaterial(Engine *engine) {
	return Material::Builder()
		.package(KINE_OUTLINE_MASK_PACKAGE_KINE_OUTLINE_MASK_DATA, KINE_OUTLINE_MASK_PACKAGE_KINE_OUTLINE_MASK_SIZE)
		.build(*engine);
}

static Material *buildOutlineCompositeMaterial(Engine *engine) {
	return Material::Builder()
		.package(KINE_OUTLINE_COMPOSITE_PACKAGE_KINE_OUTLINE_COMPOSITE_DATA, KINE_OUTLINE_COMPOSITE_PACKAGE_KINE_OUTLINE_COMPOSITE_SIZE)
		.build(*engine);
}

// Ray samples textures from system memory and cannot read Filament's GPU
// upload, so every path that starts from pixels keeps an RGBA8 mirror for it.
// rowBytes may exceed width*4, so rows are copied individually.
static void kine_keep_cpu_copy(
	std::vector<uint8_t> &out,
	int &outWidth,
	int &outHeight,
	int width,
	int height,
	int rowBytes,
	const void *pixels) {
	if (!pixels || width <= 0 || height <= 0 || rowBytes < width * 4)
		return;
	const size_t rowBytesOut = size_t(width) * 4;
	outWidth = width;
	outHeight = height;
	out.resize(rowBytesOut * size_t(height));
	const uint8_t *source = static_cast<const uint8_t *>(pixels);
	for (int y = 0; y < height; ++y) {
		memcpy(out.data() + rowBytesOut * size_t(y),
			   source + size_t(rowBytes) * size_t(y), rowBytesOut);
	}
}

static Texture *kine_create_uploaded_rgba_texture(
	Engine *engine,
	int width, int height,
	int rowBytes,
	const void *pixelsRGBA8, bool srgb = false, bool mipmaps = false) {
	if (!engine || !pixelsRGBA8 || width <= 0 || height <= 0 || rowBytes <= 0)
		return nullptr;

	size_t bytes = (size_t)rowBytes * height;
	uint8_t *copy = (uint8_t *)malloc(bytes);
	if (!copy)
		return nullptr;
	memcpy(copy, pixelsRGBA8, bytes);

	Texture *tex = Texture::Builder()
					   .width((uint32_t)width)
					   .height((uint32_t)height)
					   .levels(mipmaps ? 0xff : 1)
					   .usage(Texture::Usage::UPLOADABLE | Texture::Usage::SAMPLEABLE |
						   (mipmaps ? Texture::Usage::GEN_MIPMAPPABLE : Texture::Usage{}))
					   .format(srgb ? Texture::InternalFormat::SRGB8_A8 : Texture::InternalFormat::RGBA8)
					   .build(*engine);

	if (!tex) {
		free(copy);
		return nullptr;
	}

	uint32_t strideTexels = (uint32_t)(rowBytes / 4);
	Texture::PixelBufferDescriptor pb(
		copy, bytes,
		Texture::Format::RGBA, Texture::Type::UBYTE,
		1, 0, 0, strideTexels,
		[](void *buffer, size_t, void *) { free(buffer); });

	tex->setImage(*engine, 0, 0, 0,
				  (uint32_t)width, (uint32_t)height, std::move(pb));
	if (mipmaps) tex->generateMipmaps(*engine);
	return tex;
}

static void kine_attach_mesh_texture(KineFilamentContext *ctx, KineMesh *m) {
    if (!ctx || !ctx->engine || !m) return;
    for (auto &material : m->materials) {
        if (material.texture) continue;
        auto *handle = new KineTexHandle();
        auto upload = [&](KineImage &image, bool srgb) -> Texture * {
            if (image.rgba.empty()) return nullptr;
            return kine_create_uploaded_rgba_texture(ctx->engine,image.width,image.height,image.width*4,image.rgba.data(),srgb,true);
        };
        handle->tex=upload(material.baseColorImage,true);
        handle->normalTex=upload(material.normalImage,false);
        handle->ormTex=upload(material.ormImage,false);
        handle->cpuPixels=std::move(material.baseColorImage.rgba);
        handle->cpuWidth=material.baseColorImage.width; handle->cpuHeight=material.baseColorImage.height;
        handle->cpuNormalPixels=std::move(material.normalImage.rgba);
        handle->cpuNormalWidth=material.normalImage.width; handle->cpuNormalHeight=material.normalImage.height;
        material.baseColorImage={};material.normalImage={};material.ormImage={};
        material.texture=handle;
    }
    if (!m->materials.empty()) {
        const auto first=m->primitives.empty() ? 0 : m->primitives[0].material;
        if (first<m->materials.size()) m->ownedTex=m->materials[first].texture;
        m->ownsTexture=false; // The material palette owns these textures.
    }
}

static QualityLevel kine_quality_from_int(int quality) {
	switch (quality) {
	case 0:
		return QualityLevel::LOW;
	case 1:
		return QualityLevel::MEDIUM;
	case 2:
		return QualityLevel::HIGH;
	case 3:
		return QualityLevel::ULTRA;
	default:
		return QualityLevel::MEDIUM;
	}
}

static uint8_t kine_clamp_u8(int value, int minValue, int maxValue) {
	return (uint8_t)std::clamp(value, minValue, maxValue);
}

static uint32_t kine_next_power_of_two(uint32_t value) {
	if (value <= 8u)
		return 8u;
	value--;
	value |= value >> 1u;
	value |= value >> 2u;
	value |= value >> 4u;
	value |= value >> 8u;
	value |= value >> 16u;
	value++;
	return std::clamp(value, 8u, 8192u);
}

static LightManager::ShadowOptions kine_make_sun_shadow_options(
	int mapSize,
	int cascades,
	float shadowFar,
	float shadowNearHint,
	float shadowFarHint,
	bool stable,
	bool contactShadows) {
	LightManager::ShadowOptions options;
	options.mapSize = kine_next_power_of_two((uint32_t)std::max(mapSize, 8));
	options.shadowCascades = kine_clamp_u8(cascades, 1, 4);
	LightManager::ShadowCascades::computePracticalSplits(
		options.cascadeSplitPositions,
		options.shadowCascades,
		1.0f,
		std::max(shadowFar > 0.0f ? shadowFar : shadowFarHint, 2.0f),
		0.65f);
	options.shadowFar = std::max(shadowFar, 0.0f);
	options.shadowNearHint = std::max(shadowNearHint, 0.001f);
	options.shadowFarHint = std::max(shadowFarHint, options.shadowNearHint + 0.001f);
	options.stable = stable;
	options.lispsm = !stable;

	options.constantBias = 0.004f;
	options.normalBias = 1.25f;
	options.polygonOffsetConstant = 0.75f;
	options.polygonOffsetSlope = 2.5f;
	options.screenSpaceContactShadows = contactShadows;
	options.stepCount = 16;
	options.maxShadowDistance = 0.75f;
	return options;
}

extern "C" {

#if KINE_WITH_RAY
// Defined next to Kine_Filament_RenderFrame, but also used by the teardown and
// resize paths below it.
static void kine_ray_display_destroy(KineFilamentContext *ctx);
#endif

static Engine::Config kine_engine_config() {
	Engine::Config config;
	config.driverHandleArenaSizeMB = 64;
	return config;
}

static KineFilamentContext *Kine_Filament_CreateInternal(
	int width,
	int height,
	void *nativeWindow,
	void *vulkanCompositor = nullptr,
	bool useFilamentOwnedCompositor = false) {
	setvbuf(stderr, nullptr, _IONBF, 0);
	if (width <= 0 || height <= 0)
		return nullptr;

	auto *ctx = new KineFilamentContext();
	ctx->nativeWindow = nativeWindow;
	ctx->useFilamentOwnedCompositor = useFilamentOwnedCompositor;
	ctx->renderToSwapChain = nativeWindow != nullptr || vulkanCompositor != nullptr ||
							 useFilamentOwnedCompositor;

#if KINE_FILAMENT_USE_VULKAN
	if (useFilamentOwnedCompositor) {
		ctx->vulkanPlatform = std::make_unique<KineFilamentCompositorVulkanPlatform>(
			nativeWindow,
			width,
			height);
		fprintf(stderr, "[Kine] creating Filament-owned Vulkan compositor engine\n");
		Engine::Config engineConfig = kine_engine_config();
		ctx->engine = Engine::create(
			backend::Backend::VULKAN,
			ctx->vulkanPlatform.get(),
			nullptr,
			&engineConfig);
	} else if (vulkanCompositor) {
		ctx->vulkanCompositor = vulkanCompositor;
		KineVulkanCompositorInfo info{};
		if (!Kine_VulkanCompositor_GetInfo(
				reinterpret_cast<KineVulkanCompositor *>(vulkanCompositor),
				&info)) {
			delete ctx;
			return nullptr;
		}

		ctx->vulkanSharedContext.instance = reinterpret_cast<VkInstance>(info.instance);
		ctx->vulkanSharedContext.physicalDevice = reinterpret_cast<VkPhysicalDevice>(info.physicalDevice);
		ctx->vulkanSharedContext.logicalDevice = reinterpret_cast<VkDevice>(info.device);
		ctx->vulkanSharedContext.graphicsQueueFamilyIndex = info.graphicsQueueFamilyIndex;
		ctx->vulkanSharedContext.graphicsQueueIndex = info.graphicsQueueCount > 1 ? 1 : 0;
		ctx->vulkanPlatform = nullptr;
		fprintf(stderr,
				"[Kine] creating Filament shared Vulkan engine queueFamily=%u queueIndex=%u queueCount=%u\n",
				ctx->vulkanSharedContext.graphicsQueueFamilyIndex,
				ctx->vulkanSharedContext.graphicsQueueIndex,
				info.graphicsQueueCount);
		Engine::Config engineConfig = kine_engine_config();
		ctx->engine = Engine::create(
			backend::Backend::VULKAN,
			ctx->vulkanPlatform.get(),
			&ctx->vulkanSharedContext,
			&engineConfig);
	} else {
		Engine::Config engineConfig = kine_engine_config();
		ctx->engine = Engine::create(backend::Backend::VULKAN, nullptr, nullptr, &engineConfig);
	}
	if (!ctx->engine) {
		delete ctx;
		return nullptr;
	}
#else
	(void)vulkanCompositor;
	void *sharedGLContext = kine_get_current_gl_context();
	if (!sharedGLContext) {
		delete ctx;
		return nullptr;
	}

	kine_capture_host_context(ctx);

	kine_release_current_gl_context();

	Engine::Config engineConfig = kine_engine_config();
	ctx->engine = Engine::create(backend::Backend::OPENGL, nullptr, sharedGLContext, &engineConfig);
	if (!ctx->engine) {
		delete ctx;
		return nullptr;
	}

#if !KINE_FILAMENT_USE_VULKAN
	kine_restore_host_context(ctx);
#endif

	kine_init_gl_ext();
#endif

	if (ctx->useFilamentOwnedCompositor) {
		fprintf(stderr, "[Kine] creating Filament-owned compositor swapchain size=%dx%d\n", width, height);

		ctx->swapChain = ctx->engine->createSwapChain(nativeWindow);
		ctx->engine->flushAndWait();
#if KINE_FILAMENT_USE_VULKAN
		if (ctx->vulkanPlatform) {
			auto *platform = static_cast<KineFilamentCompositorVulkanPlatform *>(ctx->vulkanPlatform.get());
			ctx->vulkanCompositor = platform->compositor();
		}
#endif
	} else if (ctx->renderToSwapChain && ctx->nativeWindow) {
		fprintf(stderr, "[Kine] creating Filament native swapchain for window=%p size=%dx%d\n",
				ctx->nativeWindow, width, height);
		ctx->swapChain = ctx->engine->createSwapChain(ctx->nativeWindow);
	} else if (vulkanCompositor) {
		fprintf(stderr, "[Kine] creating Filament compositor swapchain size=%dx%d\n", width, height);
		ctx->swapChain = ctx->engine->createSwapChain(width, height);
	} else {
		fprintf(stderr, "[Kine] creating Filament headless swapchain size=%dx%d\n", width, height);
		ctx->swapChain = ctx->engine->createSwapChain(width, height);
	}
	if (!ctx->swapChain) {
		fprintf(stderr, "[Kine] createSwapChain failed\n");
		Kine_Filament_Destroy(ctx);
		return nullptr;
	}
	ctx->renderer = ctx->engine->createRenderer();
	ctx->scene = ctx->engine->createScene();
	ctx->view = ctx->engine->createView();

	ctx->cameraEntity = EntityManager::get().create();
	ctx->camera = ctx->engine->createCamera(ctx->cameraEntity);
	ctx->camera->setProjection(60.0, double(width) / double(height), ctx->nearPlane, ctx->farPlane);

	ctx->view->setScene(ctx->scene);
	ctx->view->setVisibleLayers(0xff,0xff);
	ctx->view->setCamera(ctx->camera);
	ctx->view->setPostProcessingEnabled(true);

	ctx->view->setDynamicLightingOptions(0.1f, 500.0f);

	Renderer::ClearOptions clearOptions;
	clearOptions.clearColor = ctx->skyColor;
	clearOptions.clear = !ctx->useFilamentOwnedCompositor;
	clearOptions.discard = !ctx->useFilamentOwnedCompositor;
	ctx->renderer->setClearOptions(clearOptions);

	ctx->defaultMaterial = buildDefaultMaterial(ctx->engine);
	ctx->neonMaterial = buildNeonMaterial(ctx->engine);
	ctx->glassMaterial = buildGlassMaterial(ctx->engine);
	ctx->waterMaterial = buildWaterMaterial(ctx->engine);
	ctx->forceFieldMaterial = Material::Builder().package(KINE_FORCEFIELD_PACKAGE_KINE_FORCEFIELD_DATA,KINE_FORCEFIELD_PACKAGE_KINE_FORCEFIELD_SIZE).build(*ctx->engine);
	ctx->cloudMaterial = buildCloudMaterial(ctx->engine);
	ctx->decalMaterial = buildDecalMaterial(ctx->engine);
	ctx->outlineMaterial = buildOutlineMaterial(ctx->engine);
	ctx->gizmoMaterial = buildGizmoMaterial(ctx->engine);
	ctx->particleMaterial = buildParticleMaterial(ctx->engine);
	ctx->terrainMaterial = buildTerrainMaterial(ctx->engine);
	ctx->hlOutlineMaterial = buildHighlightOutlineMaterial(ctx->engine);
	ctx->hlOutlineTopMaterial = buildHighlightOutlineTopMaterial(ctx->engine);
	ctx->hlFillMaterial = buildHighlightFillMaterial(ctx->engine);
	ctx->hlFillTopMaterial = buildHighlightFillTopMaterial(ctx->engine);
	ctx->outlineMaskMaterial = buildOutlineMaskMaterial(ctx->engine);
	ctx->outlineCompositeMaterial = buildOutlineCompositeMaterial(ctx->engine);
	ctx->particleQuadMesh = buildParticleQuad();
	uploadMesh(ctx->particleQuadMesh, ctx->engine);
	ctx->postProcessQuadMesh = buildPostProcessQuad();
	uploadMesh(ctx->postProcessQuadMesh, ctx->engine);

	static const uint8_t whitePixel[4] = {255, 255, 255, 255};
	ctx->whiteTex = Texture::Builder()
						.width(1)
						.height(1)
						.levels(1)
						.format(Texture::InternalFormat::RGBA8)
						.build(*ctx->engine);

	Texture::PixelBufferDescriptor pb(
		whitePixel, 4, Texture::Format::RGBA, Texture::Type::UBYTE);
	ctx->whiteTex->setImage(*ctx->engine, 0, std::move(pb));

	ctx->sunLight = EntityManager::get().create();
	math::float3 sunDir = normalize(math::float3{0.5f, -1.0f, 0.8f});
	LightManager::Builder(LightManager::Type::SUN)
		.color(Color::toLinear<ACCURATE>({1.0f, 0.98f, 0.95f}))
		.intensity(100000.0f)
		.direction(sunDir)
		.sunAngularRadius(1.9f)
		.shadowOptions(kine_make_sun_shadow_options(4096, 4, 0.0f, 0.5f, 160.0f, true, true))
		.castShadows(true)
		.build(*ctx->engine, ctx->sunLight);
	ctx->scene->addEntity(ctx->sunLight);

	if (ctx->renderToSwapChain) {
		fprintf(stderr, "[Kine] using native swapchain render target\n");
		if (!useDefaultSwapChainRenderTarget(ctx, width, height)) {
			fprintf(stderr, "[Kine] native swapchain render target setup failed\n");
			Kine_Filament_Destroy(ctx);
			return nullptr;
		}
	} else {
		fprintf(stderr, "[Kine] calling rebuildRenderTarget\n");
		if (!rebuildRenderTarget(ctx, width, height)) {
			fprintf(stderr, "[Kine] rebuildRenderTarget failed\n");
			Kine_Filament_Destroy(ctx);
			return nullptr;
		}
	}

#if !KINE_FILAMENT_USE_VULKAN
	kine_restore_host_context(ctx);
#endif

	fprintf(stderr, "[Kine] Create succeeded, colorTextureId=%u\n", ctx->colorTextureId);
	return ctx;
}

KINE_API KineFilamentContext *Kine_Filament_Create(int width, int height) {
	return Kine_Filament_CreateInternal(width, height, nullptr);
}

KINE_API KineFilamentContext *Kine_Filament_CreateForSDLWindow(void *sdlWindow, int width, int height) {
#if KINE_FILAMENT_USE_VULKAN
	void *nativeWindow = getFilamentNativeWindowFromSDL(sdlWindow);
	if (!nativeWindow) {
		fprintf(stderr, "[Kine] failed to resolve SDL native window for Filament Vulkan swapchain\n");
		return nullptr;
	}
	return Kine_Filament_CreateInternal(width, height, nativeWindow);
#else
	(void)sdlWindow;
	return Kine_Filament_CreateInternal(width, height, nullptr);
#endif
}

KINE_API KineFilamentContext *Kine_Filament_CreateForVulkanCompositor(
	void *vulkanCompositor,
	int width,
	int height) {
#if KINE_FILAMENT_USE_VULKAN
	if (!vulkanCompositor) {
		return nullptr;
	}
	return Kine_Filament_CreateInternal(width, height, nullptr, vulkanCompositor);
#else
	(void)vulkanCompositor;
	(void)width;
	(void)height;
	return nullptr;
#endif
}

KINE_API KineFilamentContext *Kine_Filament_CreateForVulkanCompositorWindow(
	void *sdlWindow,
	int width,
	int height) {
#if KINE_FILAMENT_USE_VULKAN
	if (!sdlWindow) {
		return nullptr;
	}
	return Kine_Filament_CreateInternal(width, height, sdlWindow, nullptr, true);
#else
	(void)sdlWindow;
	(void)width;
	(void)height;
	return nullptr;
#endif
}

KINE_API void *Kine_Filament_GetVulkanCompositor(KineFilamentContext *ctx) {
#if KINE_FILAMENT_USE_VULKAN
	return ctx ? ctx->vulkanCompositor : nullptr;
#else
	(void)ctx;
	return nullptr;
#endif
}

KINE_API unsigned int Kine_Filament_GetColorTextureId(KineFilamentContext *ctx) {
	return ctx ? ctx->colorTextureId : 0;
}

KINE_API bool Kine_Filament_GetVulkanBackend(KineFilamentContext *ctx, KineFilamentVulkanBackend *outBackend) {
	if (!outBackend) {
		return false;
	}
	memset(outBackend, 0, sizeof(*outBackend));

#if KINE_FILAMENT_USE_VULKAN
	if (!ctx || !ctx->engine || ctx->engine->getBackend() != backend::Backend::VULKAN) {
		return false;
	}

	backend::Platform *platform = ctx->engine->getPlatform();
	if (!platform) {
		return false;
	}

	auto *vulkanPlatform = reinterpret_cast<backend::VulkanPlatform *>(platform);
	void *getInstanceProcAddr = (void *)SDL_Vulkan_GetVkGetInstanceProcAddr();
	if (!getInstanceProcAddr) {
		return false;
	}

	outBackend->instance = vulkanPlatform->getInstance();
	outBackend->physicalDevice = vulkanPlatform->getPhysicalDevice();
	outBackend->device = vulkanPlatform->getDevice();
	outBackend->queue = vulkanPlatform->getGraphicsQueue();
	outBackend->graphicsQueueFamilyIndex = vulkanPlatform->getGraphicsQueueFamilyIndex();
	outBackend->maxApiVersion = VK_API_VERSION_1_1;
	outBackend->getInstanceProcAddr = getInstanceProcAddr;
	outBackend->getDeviceProcAddr = nullptr;

	return outBackend->instance && outBackend->physicalDevice &&
		   outBackend->device && outBackend->queue;
#else
	(void)ctx;
	return false;
#endif
}

KINE_API void Kine_Filament_CreateSky(KineFilamentContext *ctx, float r, float g, float b, float a) {
	ctx->skybox = Skybox::Builder()
					  .color({r, g, b, a})
					  .build(*ctx->engine);
	ctx->scene->setSkybox(ctx->skybox);
}

KINE_API void Kine_Filament_SetPostProcessing(KineFilamentContext *ctx, bool enabled) {
	if (!ctx || !ctx->view)
		return;
	ctx->view->setPostProcessingEnabled(enabled);
}

KINE_API void Kine_Filament_SetBloom(
	KineFilamentContext *ctx,
	bool enabled,
	float strength,
	int resolution,
	int levels,
	bool threshold,
	bool lensFlare) {
	if (!ctx || !ctx->view)
		return;

	BloomOptions options = ctx->view->getBloomOptions();
	options.enabled = enabled;
	options.strength = std::clamp(strength, 0.0f, 1.0f);
	options.resolution = (uint32_t)std::clamp(resolution, 8, 4096);
	options.levels = kine_clamp_u8(levels, 1, 11);
	options.threshold = threshold;
	options.lensFlare = lensFlare;
	ctx->view->setBloomOptions(options);
}

KINE_API void Kine_Filament_SetAmbientOcclusion(
	KineFilamentContext *ctx,
	bool enabled,
	float radius,
	float power,
	float intensity,
	int quality,
	int aoType) {
	if (!ctx || !ctx->view)
		return;

	AmbientOcclusionOptions options = ctx->view->getAmbientOcclusionOptions();
	options.enabled = enabled;
	options.radius = std::clamp(radius, 0.0f, 10.0f);
	options.power = std::max(power, 0.001f);
	options.intensity = std::max(intensity, 0.0f);
	options.quality = kine_quality_from_int(quality);
	options.aoType = aoType == 1
						 ? AmbientOcclusionOptions::AmbientOcclusionType::GTAO
						 : AmbientOcclusionOptions::AmbientOcclusionType::SAO;
	ctx->view->setAmbientOcclusionOptions(options);
}

KINE_API void Kine_Filament_SetAntiAliasing(
	KineFilamentContext *ctx,
	bool fxaa,
	bool taa,
	bool msaa,
	int sampleCount) {
	if (!ctx || !ctx->view)
		return;

	ctx->view->setAntiAliasing(fxaa ? AntiAliasing::FXAA : AntiAliasing::NONE);

	TemporalAntiAliasingOptions taaOptions = ctx->view->getTemporalAntiAliasingOptions();
	taaOptions.enabled = taa;
	ctx->view->setTemporalAntiAliasingOptions(taaOptions);

	MultiSampleAntiAliasingOptions msaaOptions = ctx->view->getMultiSampleAntiAliasingOptions();
	msaaOptions.enabled = msaa;
	msaaOptions.sampleCount = kine_clamp_u8(sampleCount, 1, 8);
	ctx->view->setMultiSampleAntiAliasingOptions(msaaOptions);
}

KINE_API void Kine_Filament_SetDynamicResolution(
	KineFilamentContext *ctx,
	bool enabled,
	float minScale,
	float maxScale,
	int quality,
	float sharpness) {
	if (!ctx || !ctx->view)
		return;

	minScale = std::clamp(minScale, 0.1f, 1.0f);
	maxScale = std::clamp(maxScale, minScale, 2.0f);

	DynamicResolutionOptions options = ctx->view->getDynamicResolutionOptions();
	options.enabled = enabled;
	options.minScale = {minScale, minScale};
	options.maxScale = {maxScale, maxScale};
	options.quality = kine_quality_from_int(quality);
	options.sharpness = std::clamp(sharpness, 0.0f, 1.0f);
	options.homogeneousScaling = true;
	ctx->view->setDynamicResolutionOptions(options);
}

KINE_API void Kine_Filament_SetDepthOfField(
	KineFilamentContext *ctx,
	bool enabled,
	float cocScale,
	float cocAspectRatio,
	float maxApertureDiameter,
	int maxForegroundCOC,
	int maxBackgroundCOC) {
	if (!ctx || !ctx->view)
		return;

	DepthOfFieldOptions options = ctx->view->getDepthOfFieldOptions();
	options.enabled = enabled;
	options.cocScale = std::max(cocScale, 0.0f);
	options.cocAspectRatio = std::max(cocAspectRatio, 0.001f);
	options.maxApertureDiameter = std::max(maxApertureDiameter, 0.0f);
	options.maxForegroundCOC = (uint16_t)std::clamp(maxForegroundCOC, 0, 32);
	options.maxBackgroundCOC = (uint16_t)std::clamp(maxBackgroundCOC, 0, 32);
	ctx->view->setDepthOfFieldOptions(options);
}

KINE_API void Kine_Filament_SetFocusDistance(KineFilamentContext *ctx, float distance) {
	if (!ctx || !ctx->camera)
		return;
	ctx->camera->setFocusDistance(std::max(distance, 0.001f));
}

KINE_API void Kine_Filament_SetVignette(
	KineFilamentContext *ctx,
	bool enabled,
	float midPoint,
	float roundness,
	float feather,
	float r,
	float g,
	float b,
	float a) {
	if (!ctx || !ctx->view)
		return;

	VignetteOptions options = ctx->view->getVignetteOptions();
	options.enabled = enabled;
	options.midPoint = std::clamp(midPoint, 0.0f, 1.0f);
	options.roundness = std::clamp(roundness, 0.0f, 1.0f);
	options.feather = std::clamp(feather, 0.0f, 1.0f);
	options.color = {
		std::max(r, 0.0f),
		std::max(g, 0.0f),
		std::max(b, 0.0f),
		std::clamp(a, 0.0f, 1.0f),
	};
	ctx->view->setVignetteOptions(options);
}

KINE_API void Kine_Filament_SetScreenSpaceReflections(
	KineFilamentContext *ctx,
	bool enabled,
	float thickness,
	float bias,
	float maxDistance,
	float stride) {
	if (!ctx || !ctx->view)
		return;

	ScreenSpaceReflectionsOptions options = ctx->view->getScreenSpaceReflectionsOptions();
	options.enabled = enabled;
	options.thickness = std::max(thickness, 0.0f);
	options.bias = std::max(bias, 0.0f);
	options.maxDistance = std::max(maxDistance, 0.0f);
	options.stride = std::max(stride, 0.001f);
	ctx->view->setScreenSpaceReflectionsOptions(options);
}

KINE_API void Kine_Filament_SetColorGrading(
	KineFilamentContext *ctx,
	float exposure,
	float contrast,
	float saturation,
	float vibrance,
	float temperature,
	float tint) {
	if (!ctx || !ctx->engine || !ctx->view)
		return;

	ctx->gradingInputs[0]=exposure;ctx->gradingInputs[1]=contrast;ctx->gradingInputs[2]=saturation;
	ctx->gradingInputs[3]=vibrance;ctx->gradingInputs[4]=temperature;ctx->gradingInputs[5]=tint;
	std::unique_ptr<ToneMapper> mapper;
	switch(ctx->toneMappingMode) {
	case 0: mapper=std::make_unique<ACESToneMapper>();break;
	case 2: mapper=std::make_unique<AgxToneMapper>();break;
	case 3: mapper=std::make_unique<LinearToneMapper>();break;
	case 1: mapper=std::make_unique<FilmicToneMapper>();break;
	default: mapper=std::make_unique<ACESLegacyToneMapper>();break;
	}
	ColorGrading *grading = ColorGrading::Builder()
								.toneMapper(mapper.get())
								.exposure(exposure+ctx->advancedExposure)
								.contrast(std::max(contrast, 0.001f))
								.saturation(std::max(saturation, 0.0f))
								.vibrance(std::max(vibrance, 0.0f))
								.whiteBalance(temperature+ctx->advancedTemperature, tint+ctx->advancedTint)
								.build(*ctx->engine);

	if (!grading)
		return;

	if (ctx->colorGrading) {
		ctx->view->setColorGrading(nullptr);
		ctx->engine->destroy(ctx->colorGrading);
	}
	ctx->colorGrading = grading;
	ctx->view->setColorGrading(ctx->colorGrading);
}

KINE_API void Kine_Filament_ClearColorGrading(KineFilamentContext *ctx) {
	if (!ctx || !ctx->engine || !ctx->view)
		return;
	const float neutral[]={0,1,1,1,0,0};
	std::copy(std::begin(neutral),std::end(neutral),ctx->gradingInputs);
	if(ctx->toneMappingMode!=4 || ctx->advancedExposure!=0 || ctx->advancedTemperature!=0 || ctx->advancedTint!=0) {
		Kine_Filament_SetColorGrading(ctx,0,1,1,1,0,0);
		return;
	}
	if(!ctx->colorGrading)return;

	ctx->view->setColorGrading(nullptr);
	ctx->engine->destroy(ctx->colorGrading);
	ctx->colorGrading = nullptr;
}

KINE_API bool Kine_Filament_SetDecalColor(
	KineFilamentContext *ctx,
	int decal,
	float r,
	float g,
	float b,
	float a) {
	if (!ctx || !ctx->engine)
		return false;

	Entity entity = Entity::import(decal);

	if (entity.isNull())
		return false;

	RenderableManager &rm =
		ctx->engine->getRenderableManager();

	auto instance =
		rm.getInstance(entity);

	if (!instance.isValid())
		return false;

	MaterialInstance *material =
		rm.getMaterialInstanceAt(
			instance,
			0);

	if (!material)
		return false;

	material->setParameter(
		"baseColor",
		RgbaType::LINEAR,
		math::float4{
			std::clamp(r, 0.0f, 1.0f),
			std::clamp(g, 0.0f, 1.0f),
			std::clamp(b, 0.0f, 1.0f),
			std::clamp(a, 0.0f, 1.0f),
		});

	return true;
}

KINE_API void Kine_Filament_SetRenderQuality(KineFilamentContext *ctx, int hdrQuality) {
	if (!ctx || !ctx->view)
		return;

	RenderQuality quality = ctx->view->getRenderQuality();
	quality.hdrColorBuffer = kine_quality_from_int(hdrQuality);
	ctx->view->setRenderQuality(quality);
}

KINE_API void Kine_Filament_SetDithering(KineFilamentContext *ctx, bool enabled) {
	if (!ctx || !ctx->view)
		return;
	ctx->view->setDithering(enabled ? Dithering::TEMPORAL : Dithering::NONE);
}

KINE_API void Kine_Filament_SetShadowOptions(KineFilamentContext *ctx, bool enabled, int shadowType) {
	if (!ctx || !ctx->view)
		return;

	ctx->view->setShadowingEnabled(enabled);
	switch (shadowType) {
	case 1:
		ctx->view->setShadowType(ShadowType::VSM);
		break;
	case 2:
		ctx->view->setShadowType(ShadowType::DPCF);
		break;
	case 3:
		ctx->view->setShadowType(ShadowType::PCSS);
		break;
	default:
		ctx->view->setShadowType(ShadowType::PCF);
		break;
	}
}

KINE_API void Kine_Filament_SetSunShadowOptions(
	KineFilamentContext *ctx,
	int mapSize,
	int cascades,
	float shadowFar,
	float shadowNearHint,
	float shadowFarHint,
	bool stable,
	bool contactShadows) {
	if (!ctx || !ctx->engine || ctx->sunLight.isNull())
		return;

	auto &lm = ctx->engine->getLightManager();
	auto inst = lm.getInstance(ctx->sunLight);
	if (!inst.isValid())
		return;

	lm.setShadowOptions(
		inst,
		kine_make_sun_shadow_options(
			mapSize,
			cascades,
			shadowFar,
			shadowNearHint,
			shadowFarHint,
			stable,
			contactShadows));
}

KINE_API void Kine_Filament_SetSunRays(
	KineFilamentContext *ctx,
	bool enabled,
	float distance,
	float cutOffDistance,
	float maximumOpacity,
	float height,
	float heightFalloff,
	float density,
	float inScatteringStart,
	float inScatteringSize,
	float r,
	float g,
	float b,
	bool fogColorFromIbl) {
	if (!ctx || !ctx->view)
		return;

	FogOptions options = ctx->view->getFogOptions();
	options.enabled = enabled;
	options.distance = std::max(distance, 0.0f);
	options.cutOffDistance = cutOffDistance > 0.0f
								 ? std::max(cutOffDistance, options.distance)
								 : std::numeric_limits<float>::infinity();
	options.maximumOpacity = std::clamp(maximumOpacity, 0.0f, 1.0f);
	options.height = height;
	options.heightFalloff = std::max(heightFalloff, 0.0f);
	options.density = std::max(density, 0.0f);
	options.inScatteringStart = std::max(inScatteringStart, 0.0f);
	options.inScatteringSize = enabled ? std::max(inScatteringSize, 0.001f) : -1.0f;
	options.color = {
		std::max(r, 0.0f),
		std::max(g, 0.0f),
		std::max(b, 0.0f),
	};
	options.fogColorFromIbl = fogColorFromIbl;
	ctx->view->setFogOptions(options);
}

KINE_API void Kine_Filament_SetSkyAtmosphere(
	KineFilamentContext *ctx,
	float sunDirX, float sunDirY, float sunDirZ,
	float skyR, float skyG, float skyB,
	float horizonR, float horizonG, float horizonB,
	float groundR, float groundG, float groundB,
	float sunIntensity) {
	if (!ctx || !ctx->engine)
		return;
	const float inputs[]={sunDirX,sunDirY,sunDirZ,skyR,skyG,skyB,horizonR,horizonG,horizonB,groundR,groundG,groundB,sunIntensity};
	if(ctx->skyInputsValid && ctx->skyTexture && std::equal(std::begin(inputs),std::end(inputs),ctx->skyInputs))return;
	std::copy(std::begin(inputs),std::end(inputs),ctx->skyInputs);ctx->skyInputsValid=true;ctx->reflectionDirty=true;

	float len = sqrtf(sunDirX * sunDirX + sunDirY * sunDirY + sunDirZ * sunDirZ);
	if (len < 1e-6f) {
		sunDirX = 0.f;
		sunDirY = 1.f;
		sunDirZ = 0.f;
	} else {
		sunDirX /= len;
		sunDirY /= len;
		sunDirZ /= len;
	}

	float lightDirX = -sunDirX;
	float lightDirY = -sunDirY;
	float lightDirZ = -sunDirZ;

	ctx->sunDirection = math::float3{sunDirX, sunDirY, sunDirZ};
	ctx->sunIntensity = sunIntensity;

	if (!ctx->sunLight.isNull()) {
		auto &lm = ctx->engine->getLightManager();
		auto inst = lm.getInstance(ctx->sunLight);
		if (inst.isValid()) {
			lm.setDirection(inst, {lightDirX, lightDirY, lightDirZ});
			float elevFactor = (sunDirY + 0.05f) / 0.15f;
			if (elevFactor < 0.f)
				elevFactor = 0.f;
			if (elevFactor > 1.f)
				elevFactor = 1.f;
			lm.setIntensity(inst, sunIntensity * elevFactor);
		}
	}

	float elev = sunDirY;
	float fr, fg, fb;
	if (elev >= 0.0f) {

		float t = std::pow(std::clamp(elev, 0.0f, 1.0f), 0.45f);
		fr = horizonR + t * (skyR - horizonR);
		fg = horizonG + t * (skyG - horizonG);
		fb = horizonB + t * (skyB - horizonB);
	} else if (elev >= -0.10f) {
		float t = (elev + 0.10f) / 0.10f;
		fr = groundR + t * (horizonR - groundR);
		fg = groundG + t * (horizonG - groundG);
		fb = groundB + t * (horizonB - groundB);
	} else {
		fr = groundR;
		fg = groundG;
		fb = groundB;
	}

	auto clamp01 = [](float v) { return v < 0.f ? 0.f : v > 1.f ? 1.f
																: v; };
	ctx->skyColor = {clamp01(fr), clamp01(fg), clamp01(fb), 1.0f};

	const uint32_t faceSize = 32;
	const size_t faceBytes = faceSize * faceSize * 4;
	const size_t totalBytes = 6 * faceBytes;

	uint8_t *pixels = (uint8_t *)malloc(totalBytes);
	if (!pixels)
		return;

	auto evalSky = [&](float dy) {
		float r, g, b;
		if (dy >= 0.0f) {
			float t = std::pow(std::clamp(dy, 0.0f, 1.0f), 0.45f);
			r = horizonR + t * (skyR - horizonR);
			g = horizonG + t * (skyG - horizonG);
			b = horizonB + t * (skyB - horizonB);
		} else if (dy >= -0.10f) {
			float t = (dy + 0.10f) / 0.10f;
			r = groundR + t * (horizonR - groundR);
			g = groundG + t * (horizonG - groundG);
			b = groundB + t * (horizonB - groundB);
		} else {
			r = groundR;
			g = groundG;
			b = groundB;
		}
		return std::make_tuple(clamp01(r), clamp01(g), clamp01(b));
	};

	for (int face = 0; face < 6; ++face) {
		uint8_t *facePixels = pixels + face * faceBytes;
		for (uint32_t y = 0; y < faceSize; ++y) {
			for (uint32_t x = 0; x < faceSize; ++x) {

				float u = (2.0f * (x + 0.5f) / faceSize) - 1.0f;

				float v = 1.0f - (2.0f * (y + 0.5f) / faceSize);

				float dx = 0, dy = 0, dz = 0;
				switch (face) {
				case 0:
					dx = 1.0f;
					dy = v;
					dz = -u;
					break;
				case 1:
					dx = -1.0f;
					dy = v;
					dz = u;
					break;
				case 2:
					dx = u;
					dy = 1.0f;
					dz = -v;
					break;
				case 3:
					dx = u;
					dy = -1.0f;
					dz = v;
					break;
				case 4:
					dx = u;
					dy = v;
					dz = 1.0f;
					break;
				case 5:
					dx = -u;
					dy = v;
					dz = -1.0f;
					break;
				}

				float dlen = sqrtf(dx * dx + dy * dy + dz * dz);
				dy /= dlen;

				auto [pr, pg, pb] = evalSky(dy);

				size_t idx = (y * faceSize + x) * 4;
				facePixels[idx + 0] = (uint8_t)(pr * 255.0f);
				facePixels[idx + 1] = (uint8_t)(pg * 255.0f);
				facePixels[idx + 2] = (uint8_t)(pb * 255.0f);
				facePixels[idx + 3] = 255;
			}
		}
	}

	if (ctx->skybox) {
		ctx->scene->setSkybox(nullptr);
		ctx->engine->destroy(ctx->skybox);
		ctx->skybox = nullptr;
	}

	if (ctx->skyTexture) {
		ctx->engine->destroy(ctx->skyTexture);
	}

	ctx->skyTexture = Texture::Builder()
						  .width(faceSize)
						  .height(faceSize)
						  .levels(1)
						  .sampler(Texture::Sampler::SAMPLER_CUBEMAP)
						  .format(Texture::InternalFormat::SRGB8_A8)
						  .build(*ctx->engine);

	Texture::PixelBufferDescriptor pb(
		pixels, totalBytes,
		Texture::Format::RGBA, Texture::Type::UBYTE,
		[](void *buffer, size_t size, void *user) { free(buffer); });

	ctx->skyTexture->setImage(*ctx->engine, 0, 0, 0, 0, faceSize, faceSize, 6, std::move(pb));

	if (ctx->skybox) {
		ctx->engine->destroy(ctx->skybox);
		ctx->skybox = nullptr;
	}

	ctx->skybox = Skybox::Builder()
					  .environment(ctx->skyTexture)
					  .intensity(15000.0f)
					  .showSun(true)
					  .build(*ctx->engine);

	ctx->scene->setSkybox(ctx->skybox);

	if (ctx->indirectLight) {
		ctx->scene->setIndirectLight(nullptr);
		ctx->engine->destroy(ctx->indirectLight);
		ctx->indirectLight = nullptr;
	}

	math::float3 sh[9] = {};
	sh[0] = {ctx->skyColor.r, ctx->skyColor.g, ctx->skyColor.b};

	ctx->indirectLight = IndirectLight::Builder()
							 .reflections(ctx->skyTexture)
							 .irradiance(1, sh)
							 .intensity(15000.0f)
							 .build(*ctx->engine);

	ctx->scene->setIndirectLight(ctx->indirectLight);
}

KINE_API void Kine_Filament_CreateSkyboxCubemap(
	KineFilamentContext *ctx,
	const KineGLTextureInfo *texPosX, const KineGLTextureInfo *texNegX,
	const KineGLTextureInfo *texPosY, const KineGLTextureInfo *texNegY,
	const KineGLTextureInfo *texPosZ, const KineGLTextureInfo *texNegZ) {
#if KINE_FILAMENT_USE_VULKAN
	(void)ctx;
	(void)texPosX;
	(void)texNegX;
	(void)texPosY;
	(void)texNegY;
	(void)texPosZ;
	(void)texNegZ;
	fprintf(stderr,
			"[Kine] CreateSkyboxCubemap cannot import OpenGL texture IDs on the Vulkan backend.\n");
#else
	if (!ctx || !ctx->engine)
		return;

	const KineGLTextureInfo *textures[6] = {
		texPosX, texNegX,
		texPosY, texNegY,
		texPosZ, texNegZ};

	int width = textures[0] ? textures[0]->width : 0;
	int height = textures[0] ? textures[0]->height : 0;
	if (width <= 0 || height <= 0 || width != height) {
		fprintf(stderr, "[Kine] CreateSkyboxCubemap: Faces must be square and > 0.\n");
		return;
	}
	for (int i = 1; i < 6; ++i) {
		if (!textures[i] || textures[i]->width != width || textures[i]->height != height) {
			fprintf(stderr, "[Kine] CreateSkyboxCubemap: All faces must have identical square dimensions.\n");
			return;
		}
	}

	size_t faceBytes = (size_t)width * height * 4;
	size_t totalBytes = faceBytes * 6;
	uint8_t *pixels = (uint8_t *)malloc(totalBytes);
	if (!pixels)
		return;

	for (int i = 0; i < 6; ++i) {
		glBindTexture(GL_TEXTURE_2D, textures[i]->id);
#if defined(__ANDROID__)
		glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, pixels + i * faceBytes);
#else
#if defined(__ANDROID__)
		glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, pixels + i * faceBytes);
#else
		glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, pixels + i * faceBytes);
#endif
#endif
	}
	glBindTexture(GL_TEXTURE_2D, 0);

	if (ctx->skyTexture) {
		ctx->engine->destroy(ctx->skyTexture);
	}

	ctx->skyTexture = Texture::Builder()
						  .width(width)
						  .height(height)
						  .levels(1)
						  .sampler(Texture::Sampler::SAMPLER_CUBEMAP)
						  .format(Texture::InternalFormat::RGBA8)
						  .build(*ctx->engine);

	Texture::PixelBufferDescriptor pb(
		pixels, totalBytes,
		Texture::Format::RGBA, Texture::Type::UBYTE,
		[](void *buffer, size_t size, void *user) { free(buffer); });

	ctx->skyTexture->setImage(*ctx->engine, 0, 0, 0, 0, width, height, 6, std::move(pb));

	if (ctx->skybox) {
		ctx->engine->destroy(ctx->skybox);
	}

	ctx->skybox = Skybox::Builder()
					  .environment(ctx->skyTexture)
					  .showSun(true)
					  .build(*ctx->engine);

	ctx->scene->setSkybox(ctx->skybox);
#endif
}

KINE_API void Kine_Filament_SetSun(
	KineFilamentContext *ctx,
	float sunDirX, float sunDirY, float sunDirZ,
	float sunIntensity) {
	if (!ctx || !ctx->engine || ctx->sunLight.isNull())
		return;

	float len = sqrtf(sunDirX * sunDirX + sunDirY * sunDirY + sunDirZ * sunDirZ);
	if (len < 1e-6f) {
		sunDirX = 0.f;
		sunDirY = 1.f;
		sunDirZ = 0.f;
	} else {
		sunDirX /= len;
		sunDirY /= len;
		sunDirZ /= len;
	}

	float lightDirX = -sunDirX;
	float lightDirY = -sunDirY;
	float lightDirZ = -sunDirZ;

	ctx->sunDirection = math::float3{sunDirX, sunDirY, sunDirZ};
	ctx->sunIntensity = sunIntensity;

	auto &lm = ctx->engine->getLightManager();
	auto inst = lm.getInstance(ctx->sunLight);
	if (inst.isValid()) {
		lm.setDirection(inst, {lightDirX, lightDirY, lightDirZ});
		lm.setIntensity(inst, sunIntensity);
	}
}

#include "kine_advanced_lighting.inc"

KINE_API void Kine_Filament_Destroy(KineFilamentContext *ctx) {
	if (ctx && ctx->engine) kine_viewport_shutdown(ctx);
	if (!ctx)
		return;

#if !KINE_FILAMENT_USE_VULKAN
	kine_restore_host_context(ctx);
#endif

	if (ctx->engine) {
        kine_destroy_ssgi(ctx);
        kine_destroy_reflection_probe(ctx);
#if KINE_WITH_RAY
		// Ray has to go before the engine tears the device down.
		kine_ray_display_destroy(ctx);
		if (ctx->rayState) {
			kine_ray_destroy((KineRayState *)ctx->rayState);
			ctx->rayState = nullptr;
		}
		ctx->rayIndexCache.clear();
		ctx->rayDraws.clear();
		ctx->rayFrameDraws.clear();
		if (ctx->rayMaterial) {
			ctx->engine->destroy(ctx->rayMaterial);
			ctx->rayMaterial = nullptr;
		}
#endif
		kine_destroy_post_process_pipeline(ctx);
		ctx->postProcessShader = nullptr;
		kine_destroy_outline_pipeline(ctx);
		kine_destroy_built_batches(ctx);
		ctx->pendingBatches.clear();
		for (KineFilamentInstanceBatch *batch : ctx->instanceBatches) {
			if (!batch)
				continue;
			kine_destroy_instance_batch_chunks(batch);
			batch->ctx = nullptr;
		}
		ctx->instanceBatches.clear();
		for (auto &decal : ctx->decals) {
			kine_destroy_decal(ctx, decal);
		}
		ctx->decals.clear();
		for (Entity light : ctx->lights) {
			if (ctx->scene && ctx->scene->hasEntity(light))
				ctx->scene->remove(light);
			ctx->engine->destroy(light);
			EntityManager::get().destroy(light);
		}
		ctx->lights.clear();

		ctx->engine->flushAndWait();
		ctx->globalShader = nullptr;
		for (KineFilamentShader *shader : ctx->runtimeShaders) {
			if (!shader)
				continue;
			if (shader->material)
				ctx->engine->destroy(shader->material);
			for (const auto &[name, texture] : shader->textures) ctx->engine->destroy(texture);
			shader->textures.clear();
			shader->material = nullptr;
			shader->ctx = nullptr;
		}
		ctx->runtimeShaders.clear();

		if (!ctx->sunLight.isNull()) {
			ctx->scene->remove(ctx->sunLight);
			ctx->engine->destroy(ctx->sunLight);
			EntityManager::get().destroy(ctx->sunLight);
		}
		if (ctx->skybox) {
			ctx->scene->setSkybox(nullptr);
			ctx->engine->destroy(ctx->skybox);
			ctx->skybox = nullptr;
		}
		if (ctx->indirectLight) {
			ctx->scene->setIndirectLight(nullptr);
			ctx->engine->destroy(ctx->indirectLight);
			ctx->indirectLight = nullptr;
		}
		if (ctx->skyTexture) {
			ctx->engine->destroy(ctx->skyTexture);
			ctx->skyTexture = nullptr;
		}
		if (ctx->colorGrading) {
			if (ctx->view) {
				ctx->view->setColorGrading(nullptr);
			}
			ctx->engine->destroy(ctx->colorGrading);
			ctx->colorGrading = nullptr;
		}
		if (ctx->renderTarget)
			ctx->engine->destroy(ctx->renderTarget);
		if (ctx->colorTarget)
			ctx->engine->destroy(ctx->colorTarget);
		if (ctx->depthTarget)
			ctx->engine->destroy(ctx->depthTarget);
		if (ctx->whiteTex)
			ctx->engine->destroy(ctx->whiteTex);
		if (ctx->particleQuadMesh) {
			kine_invalidate_batches(ctx, ctx->particleQuadMesh, nullptr);
			if (ctx->particleQuadMesh->vb)
				ctx->engine->destroy(ctx->particleQuadMesh->vb);
			if (ctx->particleQuadMesh->ib)
				ctx->engine->destroy(ctx->particleQuadMesh->ib);
			delete ctx->particleQuadMesh;
			ctx->particleQuadMesh = nullptr;
		}
		if (ctx->postProcessQuadMesh) {
			if (ctx->postProcessQuadMesh->vb)
				ctx->engine->destroy(ctx->postProcessQuadMesh->vb);
			if (ctx->postProcessQuadMesh->ib)
				ctx->engine->destroy(ctx->postProcessQuadMesh->ib);
			delete ctx->postProcessQuadMesh;
			ctx->postProcessQuadMesh = nullptr;
		}
		for (KineMesh *&prim : ctx->gizmoPrims) {
			if (!prim)
				continue;
			kine_invalidate_batches(ctx, prim, nullptr);
			if (prim->vb)
				ctx->engine->destroy(prim->vb);
			if (prim->ib)
				ctx->engine->destroy(prim->ib);
			delete prim;
			prim = nullptr;
		}
		if (ctx->defaultMaterial)
			ctx->engine->destroy(ctx->defaultMaterial);
		if (ctx->neonMaterial)
			ctx->engine->destroy(ctx->neonMaterial);
		if (ctx->glassMaterial)
			ctx->engine->destroy(ctx->glassMaterial);
		if (ctx->waterMaterial)
			ctx->engine->destroy(ctx->waterMaterial);
		if (ctx->forceFieldMaterial)
			ctx->engine->destroy(ctx->forceFieldMaterial);
		if (!ctx->cloudEntity.isNull()) {
			if (ctx->cloudInScene)
				ctx->scene->remove(ctx->cloudEntity);
			ctx->engine->destroy(ctx->cloudEntity);
			EntityManager::get().destroy(ctx->cloudEntity);
			ctx->cloudEntity = Entity{};
			ctx->cloudInScene = false;
		}
		if (ctx->cloudMI) {
			ctx->engine->destroy(ctx->cloudMI);
			ctx->cloudMI = nullptr;
		}
		if (ctx->cloudMesh) {
			if (ctx->cloudMesh->vb)
				ctx->engine->destroy(ctx->cloudMesh->vb);
			if (ctx->cloudMesh->ib)
				ctx->engine->destroy(ctx->cloudMesh->ib);
			delete ctx->cloudMesh;
			ctx->cloudMesh = nullptr;
		}
		if (ctx->cloudMaterial)
			ctx->engine->destroy(ctx->cloudMaterial);
		if (ctx->decalMaterial)
			ctx->engine->destroy(ctx->decalMaterial);
		if (ctx->outlineMaterial)
			ctx->engine->destroy(ctx->outlineMaterial);
		if (ctx->gizmoMaterial)
			ctx->engine->destroy(ctx->gizmoMaterial);
		if (ctx->particleMaterial)
			ctx->engine->destroy(ctx->particleMaterial);
		if (ctx->terrainMaterial)
			ctx->engine->destroy(ctx->terrainMaterial);
		if (ctx->hlOutlineMaterial)
			ctx->engine->destroy(ctx->hlOutlineMaterial);
		if (ctx->hlOutlineTopMaterial)
			ctx->engine->destroy(ctx->hlOutlineTopMaterial);
		if (ctx->hlFillMaterial)
			ctx->engine->destroy(ctx->hlFillMaterial);
		if (ctx->hlFillTopMaterial)
			ctx->engine->destroy(ctx->hlFillTopMaterial);
		if (ctx->outlineMaskMaterial)
			ctx->engine->destroy(ctx->outlineMaskMaterial);
		if (ctx->outlineCompositeMaterial)
			ctx->engine->destroy(ctx->outlineCompositeMaterial);
		if (ctx->colorTextureId) {
#if !KINE_FILAMENT_USE_VULKAN
			GLuint id = (GLuint)ctx->colorTextureId;
			glDeleteTextures(1, &id);
#endif
			ctx->colorTextureId = 0;
		}
		if (!ctx->cameraEntity.isNull()) {
			ctx->engine->destroyCameraComponent(ctx->cameraEntity);
			EntityManager::get().destroy(ctx->cameraEntity);
		}
		if (ctx->view)
			ctx->engine->destroy(ctx->view);
		if (ctx->scene)
			ctx->engine->destroy(ctx->scene);
		if (ctx->renderer)
			ctx->engine->destroy(ctx->renderer);
		if (ctx->swapChain) {
			ctx->engine->destroy(ctx->swapChain);
			ctx->swapChain = nullptr;
		}
		ctx->engine->flushAndWait();
#if KINE_FILAMENT_USE_VULKAN
		if (ctx->useFilamentOwnedCompositor && ctx->vulkanPlatform) {
			auto *platform = static_cast<KineFilamentCompositorVulkanPlatform *>(ctx->vulkanPlatform.get());
			platform->destroyCompositor();
			ctx->vulkanCompositor = nullptr;
		}
#endif
		Engine::destroy(&ctx->engine);
	}

	delete ctx;
}

KINE_API void Kine_Filament_DebugPrintPixel(KineFilamentContext *ctx) {
#if KINE_FILAMENT_USE_VULKAN
	fprintf(stderr, "[Kine] DebugPrintPixel uses the OpenGL texture path and is unavailable on Vulkan\n");
	(void)ctx;
	return;
#else
	if (!ctx || ctx->colorTextureId == 0 || ctx->width <= 0 || ctx->height <= 0)
		return;

	std::vector<unsigned char> buf((size_t)ctx->width * ctx->height * 4);

	glBindTexture(GL_TEXTURE_2D, (GLuint)ctx->colorTextureId);
#if defined(__ANDROID__)
	glReadPixels(0, 0, ctx->width, ctx->height, GL_RGBA, GL_UNSIGNED_BYTE, buf.data());
#else
	glReadPixels(0, 0, ctx->width, ctx->height, GL_RGBA, GL_UNSIGNED_BYTE, buf.data());
#endif
	glBindTexture(GL_TEXTURE_2D, 0);

	int cx = ctx->width / 2;
	int cy = ctx->height / 2;
	size_t idx = ((size_t)cy * ctx->width + cx) * 4;

	GLenum err = glGetError();
	if (err != GL_NO_ERROR) {
		fprintf(stderr, "[Kine] glReadPixels GL error: 0x%x\n", err);
	}

	fprintf(stderr, "[Kine] center pixel RGBA = %d %d %d %d\n",
			buf[idx + 0], buf[idx + 1], buf[idx + 2], buf[idx + 3]);
#endif
}

#if KINE_WITH_RAY
// ---------------------------------------------------------------------------
// Ray path tracer presentation
//
// Ray renders into its own VkImage on the shared device and hands back the
// tonemapped pixels; those are uploaded into a Filament texture and drawn over
// the frame by a dedicated fullscreen view. The zero-copy variant would live in
// kine_vulkan_compositor, where Ray's raw image can be sampled directly.
// ---------------------------------------------------------------------------

static const char *kine_ray_error(void) {
	return kine_ray_last_error();
}

static void kine_ray_display_destroy(KineFilamentContext *ctx) {
	if (!ctx || !ctx->engine)
		return;
	if (ctx->rayScene && !ctx->rayQuadEntity.isNull()) {
		ctx->rayScene->remove(ctx->rayQuadEntity);
	}
	if (!ctx->rayQuadEntity.isNull()) {
		ctx->engine->destroy(ctx->rayQuadEntity);
		EntityManager::get().destroy(ctx->rayQuadEntity);
		ctx->rayQuadEntity.clear();
	}
	if (!ctx->rayCameraEntity.isNull()) {
		ctx->engine->destroyCameraComponent(ctx->rayCameraEntity);
		EntityManager::get().destroy(ctx->rayCameraEntity);
		ctx->rayCameraEntity.clear();
		ctx->rayCamera = nullptr;
	}
	if (ctx->rayColorGrading) {
		ctx->engine->destroy(ctx->rayColorGrading);
		ctx->rayColorGrading = nullptr;
	}
	if (ctx->rayView) {
		ctx->engine->destroy(ctx->rayView);
		ctx->rayView = nullptr;
	}
	if (ctx->rayScene) {
		ctx->engine->destroy(ctx->rayScene);
		ctx->rayScene = nullptr;
	}
	if (ctx->rayMaterialInstance) {
		ctx->engine->destroy(ctx->rayMaterialInstance);
		ctx->rayMaterialInstance = nullptr;
	}
	if (ctx->rayTexture) {
		ctx->engine->destroy(ctx->rayTexture);
		ctx->rayTexture = nullptr;
	}
	ctx->rayTextureWidth = 0;
	ctx->rayTextureHeight = 0;
}

static bool kine_ray_display_ensure(KineFilamentContext *ctx) {
	if (!ctx || !ctx->engine || !ctx->postProcessQuadMesh ||
		!ctx->postProcessQuadMesh->vb || !ctx->postProcessQuadMesh->ib)
		return false;
	if (ctx->rayView && ctx->rayScene && ctx->rayMaterialInstance && ctx->rayCamera)
		return true;

	kine_ray_display_destroy(ctx);

	if (!ctx->rayMaterial) {
		ctx->rayMaterial = Material::Builder()
							   .package(KINE_RAY_OUTPUT_PACKAGE_KINE_RAY_OUTPUT_DATA,
										KINE_RAY_OUTPUT_PACKAGE_KINE_RAY_OUTPUT_SIZE)
							   .build(*ctx->engine);
	}
	if (!ctx->rayMaterial)
		return false;

	ctx->rayMaterialInstance = ctx->rayMaterial->createInstance();
	ctx->rayScene = ctx->engine->createScene();
	ctx->rayView = ctx->engine->createView();
	ctx->rayCameraEntity = EntityManager::get().create();
	ctx->rayCamera = ctx->engine->createCamera(ctx->rayCameraEntity);
	if (!ctx->rayMaterialInstance || !ctx->rayScene || !ctx->rayView || !ctx->rayCamera) {
		kine_ray_display_destroy(ctx);
		return false;
	}

	// Ray's pixels are already tonemapped and sRGB encoded, so the view must not
	// tone map them a second time.
	ctx->rayColorGrading = ColorGrading::Builder()
							   .toneMapping(ColorGrading::ToneMapping::LINEAR)
							   .build(*ctx->engine);

	ctx->rayQuadEntity = EntityManager::get().create();
	RenderableManager::Builder(1)
		.boundingBox({{0, 0, 0}, {1, 1, 0.1f}})
		.material(0, ctx->rayMaterialInstance)
		.geometry(0, RenderableManager::PrimitiveType::TRIANGLES,
				  ctx->postProcessQuadMesh->vb, ctx->postProcessQuadMesh->ib, 0,
				  ctx->postProcessQuadMesh->indexCount)
		.culling(false)
		.castShadows(false)
		.receiveShadows(false)
		.priority(9)
		.build(*ctx->engine, ctx->rayQuadEntity);
	ctx->rayScene->addEntity(ctx->rayQuadEntity);

	float left, right, bottom, top;
	kine_composite_quad_bounds(ctx, &left, &right, &bottom, &top);
	ctx->rayCamera->setProjection(Camera::Projection::ORTHO, left, right, bottom, top, 0.1, 10.0);
	ctx->rayCamera->lookAt({0, 0, 1}, {0, 0, 0}, {0, 1, 0});
	ctx->rayView->setScene(ctx->rayScene);
	ctx->rayView->setCamera(ctx->rayCamera);
	ctx->rayView->setRenderTarget(ctx->renderTarget);
	ctx->rayView->setViewport({0, 0,
							   uint32_t(ctx->width > 0 ? ctx->width : 1),
							   uint32_t(ctx->height > 0 ? ctx->height : 1)});
	ctx->rayView->setPostProcessingEnabled(false);
	if (ctx->rayColorGrading) {
		ctx->rayView->setColorGrading(ctx->rayColorGrading);
	}
	return true;
}

static bool kine_ray_upload(KineFilamentContext *ctx, int width, int height) {
	const uint8_t *pixels = kine_ray_pixels((const KineRayState *)ctx->rayState);
	if (!pixels || width <= 0 || height <= 0)
		return false;

	if (!ctx->rayTexture || ctx->rayTextureWidth != width || ctx->rayTextureHeight != height) {
		if (ctx->rayTexture) {
			ctx->engine->destroy(ctx->rayTexture);
			ctx->rayTexture = nullptr;
		}
		// SRGB8_A8 makes the sampler hand the material linear values, so the
		// sRGB target writes back the exact bytes Ray produced.
		ctx->rayTexture = Texture::Builder()
							  .width(uint32_t(width))
							  .height(uint32_t(height))
							  .levels(1)
							  .usage(Texture::Usage::UPLOADABLE | Texture::Usage::SAMPLEABLE)
							  .format(Texture::InternalFormat::SRGB8_A8)
							  .build(*ctx->engine);
		if (!ctx->rayTexture)
			return false;
		ctx->rayTextureWidth = width;
		ctx->rayTextureHeight = height;
	}

	const size_t bytes = size_t(width) * size_t(height) * 4;
	uint8_t *copy = (uint8_t *)malloc(bytes);
	if (!copy)
		return false;
	memcpy(copy, pixels, bytes);

	Texture::PixelBufferDescriptor pb(
		copy, bytes,
		Texture::Format::RGBA, Texture::Type::UBYTE,
		[](void *buffer, size_t, void *) { free(buffer); });
	ctx->rayTexture->setImage(*ctx->engine, 0, std::move(pb));
	return true;
}

// Builds the Ray frame description from the draws queued for this frame plus
// the context camera, sun and sky.
// Filament owns the light components, so Ray reads them back the same way the
// raster pass does: one snapshot per frame, in creation order so the resulting
// light hash is stable from frame to frame.
static void kine_collect_ray_lights(KineFilamentContext *ctx, std::vector<KineRayLight> &out) {
	if (!ctx || !ctx->engine || !ctx->scene)
		return;

	LightManager &lm = ctx->engine->getLightManager();
	for (Entity entity : ctx->lights) {
		// SetEnabledLight() detaches disabled lights from the scene; they must not
		// light the path-traced image either.
		if (!ctx->scene->hasEntity(entity))
			continue;
		const LightManager::Instance instance = lm.getInstance(entity);
		if (!instance.isValid())
			continue;
		const LightManager::Type type = lm.getType(instance);
		if (type != LightManager::Type::POINT &&
			type != LightManager::Type::SPOT &&
			type != LightManager::Type::FOCUSED_SPOT)
			continue;

		KineRayLight light{};
		light.type = type == LightManager::Type::POINT ? 0 : 1;
		const math::float3 &position = lm.getPosition(instance);
		light.position[0] = position.x;
		light.position[1] = position.y;
		light.position[2] = position.z;
		const math::float3 &direction = lm.getDirection(instance);
		light.direction[0] = direction.x;
		light.direction[1] = direction.y;
		light.direction[2] = direction.z;
		const math::float3 &color = lm.getColor(instance);
		light.color[0] = color.x;
		light.color[1] = color.y;
		light.color[2] = color.z;
		// LightManager reports candela here, the same quantity its shading uses.
		light.intensity = lm.getIntensity(instance);
		light.castShadow = lm.isShadowCaster(instance);
		if (light.type == 1) {
			light.innerConeRadians = lm.getSpotLightInnerCone(instance);
			light.outerConeRadians = lm.getSpotLightOuterCone(instance);
		}
		out.push_back(light);
	}
}

static bool kine_ray_run(KineFilamentContext *ctx) {
	ctx->rayFrameDraws.clear();
	ctx->rayFrameDraws.reserve(ctx->rayDraws.size());

	auto appendQueued = [ctx](const KineRayQueuedDraw &queued) {
		KineMesh *mesh = queued.mesh;
		if (!mesh || mesh->vertices.empty() || mesh->indices.empty() || mesh->indexCount == 0)
			return;

		std::vector<uint32_t> &indices = ctx->rayIndexCache[mesh];
		if (indices.size() != mesh->indices.size()) {
			indices.resize(mesh->indices.size());
			for (size_t i = 0; i < mesh->indices.size(); ++i)
				indices[i] = mesh->indices[i];
		}

		KineRayDraw draw{};
		draw.meshKey = mesh;
		draw.shaderKey = queued.shader;
		// Skinned meshes are traced in their rest pose: Ray has no skinning and
		// baking the pose per frame is not worth it for a preview render.
		draw.vertexData = &mesh->vertices[0].px;
		draw.vertexStrideFloats = (int)(sizeof(KineVertex) / sizeof(float));
		draw.vertexCount = (int)mesh->vertices.size();
		draw.indices = indices.data();
		draw.indexCount = (int)indices.size();
		draw.xform = queued.transform;
		draw.color[0] = queued.color[0];
		draw.color[1] = queued.color[1];
		draw.color[2] = queued.color[2];
		draw.materialKind = queued.materialKind;
		draw.uvScale = queued.uvScale;
		draw.param1 = queued.param1;
		draw.param2 = queued.param2;
		draw.param3 = queued.param3;
		draw.transmission = queued.transmission;
		draw.baseColor = queued.baseColor;
		draw.normalMap = queued.normalMap;
        if (queued.importedMaterials) {
            for (auto &primitive : mesh->primitives) {
                auto section=draw;
                section.meshKey=&primitive;
                // Share the source vertex slice rather than replicating the
                // entire scene's vertices for every traced material section.
                if (primitive.rayIndices.size()!=primitive.count) {
                    primitive.rayIndices.resize(primitive.count);
                    for (size_t i=0;i<primitive.count;++i)
                        primitive.rayIndices[i]=indices[primitive.offset+i]-primitive.vertexOffset;
                }
                section.vertexData=&mesh->vertices[primitive.vertexOffset].px;
                section.vertexCount=int(primitive.vertexCount);
                section.indices=primitive.rayIndices.data();
                section.indexCount=int(primitive.count);
                if (primitive.material<mesh->materials.size()) {
                    const auto &material=mesh->materials[primitive.material];
                    for (int i=0;i<3;++i) section.color[i]*=material.baseColor[i];
                    section.param1=material.roughness;section.param2=material.metallic;section.uvScale=1;
                    section.baseColor={};section.normalMap={};
                    const auto *tex=material.texture;
                    if (tex && !tex->cpuPixels.empty()) {section.baseColor.pixels=tex->cpuPixels.data();section.baseColor.width=tex->cpuWidth;section.baseColor.height=tex->cpuHeight;}
                    if (tex && !tex->cpuNormalPixels.empty()) {section.normalMap.pixels=tex->cpuNormalPixels.data();section.normalMap.width=tex->cpuNormalWidth;section.normalMap.height=tex->cpuNormalHeight;}
                }
                ctx->rayFrameDraws.push_back(section);
            }
        } else ctx->rayFrameDraws.push_back(draw);
	};

	for (const KineRayQueuedDraw &queued : ctx->rayDraws) {
		appendQueued(queued);
	}

	// Retained streams only re-queue when their version changes, so replay what
	// they queued last time. Skipping this would hand Ray an empty frame on any
	// frame where the scene did not change, and an empty scene traces to plain
	// sky. Stream ids are walked in ascending order so the resulting draw order
	// -- and therefore the structure hash -- stays identical frame to frame.
	std::vector<uint64_t> streamIds;
	streamIds.reserve(ctx->retainedLists.size());
	for (const auto &entry : ctx->retainedLists) {
		streamIds.push_back(entry.first);
	}
	std::sort(streamIds.begin(), streamIds.end());
	for (uint64_t streamId : streamIds) {
		for (const KineRayQueuedDraw &queued : ctx->retainedLists[streamId].rayDraws) {
			appendQueued(queued);
		}
	}

	ctx->rayDraws.clear();

	KineRayFrame frame{};
	frame.width = ctx->viewportWidth > 0 ? ctx->viewportWidth : ctx->width;
	frame.height = ctx->viewportHeight > 0 ? ctx->viewportHeight : ctx->height;
	frame.draws = ctx->rayFrameDraws.data();
	frame.drawCount = (int)ctx->rayFrameDraws.size();

	double forwardX = ctx->cameraTarget.x - ctx->cameraEye.x;
	double forwardY = ctx->cameraTarget.y - ctx->cameraEye.y;
	double forwardZ = ctx->cameraTarget.z - ctx->cameraEye.z;
	const double forwardLength =
		std::sqrt(forwardX * forwardX + forwardY * forwardY + forwardZ * forwardZ);
	if (forwardLength < 1e-6) {
		forwardX = 0.0;
		forwardY = 0.0;
		forwardZ = -1.0;
	} else {
		forwardX /= forwardLength;
		forwardY /= forwardLength;
		forwardZ /= forwardLength;
	}
	frame.camera.origin[0] = (float)ctx->cameraEye.x;
	frame.camera.origin[1] = (float)ctx->cameraEye.y;
	frame.camera.origin[2] = (float)ctx->cameraEye.z;
	frame.camera.forward[0] = (float)forwardX;
	frame.camera.forward[1] = (float)forwardY;
	frame.camera.forward[2] = (float)forwardZ;
	frame.camera.up[0] = (float)ctx->cameraUp.x;
	frame.camera.up[1] = (float)ctx->cameraUp.y;
	frame.camera.up[2] = (float)ctx->cameraUp.z;
	frame.camera.fovYDegrees = ctx->fovYDegrees;
	frame.camera.clipStart = (float)ctx->nearPlane;
	frame.camera.clipEnd = (float)ctx->farPlane;

	frame.sunTowards[0] = ctx->sunDirection.x;
	frame.sunTowards[1] = ctx->sunDirection.y;
	frame.sunTowards[2] = ctx->sunDirection.z;
	frame.sunColor[0] = 1.0f;
	frame.sunColor[1] = 0.98f;
	frame.sunColor[2] = 0.95f;
	frame.sunIntensity = ctx->sunIntensity;
	frame.skyColor[0] = ctx->skyColor.x;
	frame.skyColor[1] = ctx->skyColor.y;
	frame.skyColor[2] = ctx->skyColor.z;

	std::vector<KineRayLight> rayLights;
	kine_collect_ray_lights(ctx, rayLights);
	frame.lights = rayLights.data();
	frame.lightCount = (int)rayLights.size();

	if (!kine_ray_render((KineRayState *)ctx->rayState, frame)) {
		fprintf(stderr, "[Kine] Ray render failed: %s\n", kine_ray_error());
		return false;
	}
	return kine_ray_upload(ctx, frame.width, frame.height);
}
#endif

KINE_API void Kine_Filament_RenderFrame(KineFilamentContext *ctx, float deltaTime) {
	if (!ctx || !ctx->engine)
		return;
#if KINE_FILAMENT_USE_VULKAN && KINE_FILAMENT_ENABLE_VULKAN_READBACK
	if (!ctx->renderToSwapChain)
		ctx->engine->pumpMessageQueues();
#endif
	ctx->time += deltaTime;
	// Retained static geometry still needs its animated ForceField uniforms.
	for (auto &[key,batch] : ctx->builtBatches) {
		if (key.materialKind != KINE_MAT_FORCEFIELD) continue;
		for (auto &chunk : batch.chunks) if (chunk.materialInstance) chunk.materialInstance->setParameter("time",ctx->time);
	}
	for (auto *batch : ctx->instanceBatches) {
		if (!batch || batch->key.materialKind != KINE_MAT_FORCEFIELD) continue;
		for (auto &chunk : batch->chunks) if (chunk.materialInstance) chunk.materialInstance->setParameter("time",ctx->time);
	}
	kine_update_cloud_layer(ctx);

#if !KINE_FILAMENT_USE_VULKAN
	glEnable(GL_DEPTH_TEST);
	glDepthMask(GL_TRUE);
#endif

#if KINE_FILAMENT_USE_VULKAN
	if (ctx->useFilamentOwnedCompositor && ctx->vulkanCompositor) {
		if (!Kine_VulkanCompositor_PrepareFilament(
				static_cast<KineVulkanCompositor *>(ctx->vulkanCompositor))) {
			const char *error = Kine_VulkanCompositor_GetLastError(
				static_cast<KineVulkanCompositor *>(ctx->vulkanCompositor));
			fprintf(stderr, "[Kine] compositor prepare for Filament failed: %s\n",
					error && error[0] ? error : "unknown error");
			kine_finish_batch_frame(ctx);
			return;
		}
	}
#endif

	kine_update_batches(ctx);
    kine_capture_reflection_probe(ctx);
    kine_prepare_ssgi(ctx);

	if (ctx->renderer->beginFrame(ctx->swapChain)) {
		if (!ctx->loggedFirstFrame) {
			fprintf(stderr, "[Kine] Filament beginFrame OK (%s swapchain, %dx%d)\n",
					ctx->renderToSwapChain ? "native" : "headless",
					ctx->width, ctx->height);
			ctx->loggedFirstFrame = true;
		}

		const bool outlineActive = ctx->renderWorld && ctx->outlineQueued && ctx->outlineMaskView && ctx->outlineView;
		Renderer::ClearOptions clearOptions;

		if (outlineActive) {
			clearOptions.clearColor = {0, 0, 0, 0};
			clearOptions.clear = true;
			clearOptions.discard = true;
			ctx->renderer->setClearOptions(clearOptions);
			ctx->renderer->render(ctx->outlineMaskView);
		}

		clearOptions.clearColor = ctx->skyColor;
		const bool hasPostProcess =
			ctx->renderWorld && ctx->postProcessShader && ctx->postView && ctx->postMaterialInstance;

		clearOptions.clear = hasPostProcess || !ctx->useFilamentOwnedCompositor;
		clearOptions.discard = hasPostProcess || !ctx->useFilamentOwnedCompositor;
		ctx->renderer->setClearOptions(clearOptions);

		if (ctx->renderWorld && ctx->ssgi) ctx->renderer->render(ctx->ssgi->depthView);
		if (ctx->renderWorld) ctx->renderer->render(ctx->view);
        if (ctx->renderWorld && ctx->ssgi) {
            clearOptions.clear=false;clearOptions.discard=false;ctx->renderer->setClearOptions(clearOptions);
            ctx->renderer->render(ctx->ssgi->view);
        }
		if (hasPostProcess) {
			kine_apply_shader_uniforms(ctx->postMaterialInstance, ctx->postProcessShader);
			if (ctx->postProcessShader->material->hasParameter("time")) {
				ctx->postMaterialInstance->setParameter("time", ctx->time);
			}
			if (ctx->postProcessShader->material->hasParameter("resolution")) {
				ctx->postMaterialInstance->setParameter("resolution",
														math::float2{
															float(ctx->viewportWidth > 0 ? ctx->viewportWidth : ctx->width),
															float(ctx->viewportHeight > 0 ? ctx->viewportHeight : ctx->height)});
			}

			clearOptions.clear = false;
			clearOptions.discard = false;
			ctx->renderer->setClearOptions(clearOptions);
			ctx->renderer->render(ctx->postView);
		}

		if (outlineActive && ctx->outlineCompositeMI) {
			if (ctx->outlineCompositeMaterial->hasParameter("width")) {
				const float ringWidth = ctx->outlineWidthPixels > 0.0f ? ctx->outlineWidthPixels : 1.0f;
				ctx->outlineCompositeMI->setParameter("width", ringWidth);
			}
			clearOptions.clear = false;
			clearOptions.discard = false;
			ctx->renderer->setClearOptions(clearOptions);
			ctx->renderer->render(ctx->outlineView);
		}

		kine_viewport_render_queued(ctx);

#if KINE_WITH_RAY
		// Render mode 2: trace one Ray sample and paint it over the frame.
		if (ctx->renderWorld && ctx->renderMode == KINE_RENDER_MODE_RAY && ctx->rayState) {
			if (kine_ray_run(ctx) && kine_ray_display_ensure(ctx) && ctx->rayTexture) {
				TextureSampler sampler(TextureSampler::MinFilter::LINEAR, TextureSampler::MagFilter::LINEAR,
									   TextureSampler::WrapMode::CLAMP_TO_EDGE);
				ctx->rayMaterialInstance->setParameter("inputTexture", ctx->rayTexture, sampler);
				clearOptions.clear = false;
				clearOptions.discard = false;
				ctx->renderer->setClearOptions(clearOptions);
				ctx->renderer->render(ctx->rayView);
			}
		}
#endif
#if KINE_FILAMENT_USE_VULKAN && KINE_FILAMENT_ENABLE_VULKAN_READBACK

		if (!ctx->renderToSwapChain && ctx->renderTarget &&
			!ctx->readbackPending && !ctx->readbackReady) {
			ctx->readbackPixels.resize((size_t)ctx->width * (size_t)ctx->height * 4);
			ctx->readbackReady = false;
			ctx->readbackPending = true;
			backend::PixelBufferDescriptor pb(
				ctx->readbackPixels.data(),
				ctx->readbackPixels.size(),
				backend::PixelDataFormat::RGBA,
				backend::PixelDataType::UBYTE,
				[](void *, size_t, void *user) {
					auto *readbackCtx = static_cast<KineFilamentContext *>(user);
					readbackCtx->readbackPending = false;
					readbackCtx->readbackReady = true;
				},
				ctx);
			ctx->renderer->readPixels(ctx->renderTarget, 0, 0,
									  (uint32_t)ctx->width, (uint32_t)ctx->height, std::move(pb));
		}
#endif
		ctx->renderer->endFrame();
#if KINE_FILAMENT_USE_VULKAN
		if (ctx->useFilamentOwnedCompositor) {

			ctx->engine->flushAndWait();
		}
#endif
	} else {
		fprintf(stderr, "[Kine] beginFrame FAILED this frame\n");
#if KINE_FILAMENT_USE_VULKAN
		if (ctx->useFilamentOwnedCompositor && ctx->vulkanCompositor) {

			auto *compositor = static_cast<KineVulkanCompositor *>(ctx->vulkanCompositor);
			ctx->engine->flushAndWait();
			uint32_t imageIndex = 0;
			if (Kine_VulkanCompositor_FilamentAcquire(compositor, &imageIndex, nullptr) == VK_SUCCESS) {
				Kine_VulkanCompositor_FilamentPresent(compositor, imageIndex, nullptr);
			}
		}
#endif
	}

	kine_finish_batch_frame(ctx);

#if KINE_WITH_RAY
	// Draws recorded for the path tracer are consumed by kine_ray_run(); drop
	// anything left over so the queue cannot grow while mode 1 is active.
	ctx->rayDraws.clear();
#endif

#if !KINE_FILAMENT_USE_VULKAN
	if (kine_glBindFramebuffer) {
		kine_glBindFramebuffer(GL_FRAMEBUFFER, 0);
	}
	glViewport(0, 0, ctx->width, ctx->height);
	glDisable(GL_DEPTH_TEST);
	glDisable(GL_CULL_FACE);
	glDisable(GL_SCISSOR_TEST);
	glEnable(GL_BLEND);
	glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
	kine_restore_host_context(ctx);
#endif
}

KINE_API void Kine_Filament_Resize(KineFilamentContext *ctx, int width, int height) {
	if (!ctx || !ctx->engine)
		return;
	if (width <= 0 || height <= 0)
		return;
#if KINE_FILAMENT_USE_VULKAN
	if (ctx->width == width && ctx->height == height &&
		(!ctx->useFilamentOwnedCompositor || !Kine_VulkanCompositor_NeedsResize(
												 static_cast<KineVulkanCompositor *>(ctx->vulkanCompositor))))
		return;
#else
	if (ctx->width == width && ctx->height == height)
		return;
#endif

	ctx->engine->flushAndWait();

	if (ctx->swapChain) {
		ctx->engine->destroy(ctx->swapChain);
		ctx->swapChain = nullptr;
	}
#if KINE_FILAMENT_USE_VULKAN
	if (ctx->useFilamentOwnedCompositor) {
		fprintf(stderr, "[Kine] recreating Filament-owned compositor swapchain size=%dx%d\n",
				width, height);
		auto *platform = static_cast<KineFilamentCompositorVulkanPlatform *>(ctx->vulkanPlatform.get());
		platform->setExtent(width, height);
		ctx->swapChain = ctx->engine->createSwapChain(ctx->nativeWindow);
		ctx->engine->flushAndWait();
		if (ctx->vulkanPlatform) {
			ctx->vulkanCompositor = platform->compositor();
		}
		useDefaultSwapChainRenderTarget(ctx, width, height);
	} else
#endif
		if (ctx->renderToSwapChain && ctx->nativeWindow) {
		fprintf(stderr, "[Kine] recreating Filament native swapchain for window=%p size=%dx%d\n",
				ctx->nativeWindow, width, height);
		ctx->swapChain = ctx->engine->createSwapChain(ctx->nativeWindow);
		useDefaultSwapChainRenderTarget(ctx, width, height);
	} else {
		fprintf(stderr, "[Kine] recreating Filament headless swapchain size=%dx%d\n", width, height);
		ctx->swapChain = ctx->engine->createSwapChain(width, height);
		rebuildRenderTarget(ctx, width, height);
	}
	ctx->loggedFirstFrame = false;
	ctx->camera->setProjection(60.0, double(width) / double(height), ctx->nearPlane, ctx->farPlane);
	if (ctx->postProcessShader && !kine_build_post_process_pipeline(ctx)) {
		fprintf(stderr, "[Kine] failed to rebuild custom post-process pipeline after resize\n");
		ctx->postProcessShader = nullptr;
	}

	if ((ctx->outlineView || ctx->outlineQueued) && !kine_build_outline_pipeline(ctx)) {
		fprintf(stderr, "[Kine] failed to rebuild outline pipeline after resize\n");
	}

#if KINE_WITH_RAY
	if (ctx->rayState) {
		// The presentation quad is sized from the surface extent.
		kine_ray_display_destroy(ctx);
		kine_ray_resize((KineRayState *)ctx->rayState, width, height);
	}
#endif
}

KINE_API void Kine_Filament_SetViewport(KineFilamentContext *ctx, int x, int y, int width, int height) {
	if (!ctx || !ctx->view)
		return;

	if (width <= 0 || height <= 0) {
		x = 0;
		y = 0;
		width = ctx->width;
		height = ctx->height;
	}

	int clampedX = std::clamp(x, 0, std::max(0, ctx->width - 1));
	int clampedY = std::clamp(y, 0, std::max(0, ctx->height - 1));
	int clampedWidth = std::clamp(width, 1, std::max(1, ctx->width - clampedX));
	int clampedHeight = std::clamp(height, 1, std::max(1, ctx->height - clampedY));

	int filamentY = ctx->height - clampedY - clampedHeight;
	filamentY = std::clamp(filamentY, 0, std::max(0, ctx->height - 1));

	const bool viewportChanged =
		ctx->viewportX != clampedX || ctx->viewportY != clampedY ||
		ctx->viewportWidth != clampedWidth || ctx->viewportHeight != clampedHeight;
	ctx->viewportX = clampedX;
	ctx->viewportY = clampedY;
	ctx->viewportWidth = clampedWidth;
	ctx->viewportHeight = clampedHeight;

	ctx->camera->setProjection(60.0, double(clampedWidth) / double(clampedHeight), ctx->nearPlane, ctx->farPlane);

	if (viewportChanged && (ctx->outlineView || ctx->outlineQueued)) {
		if (!kine_build_outline_pipeline(ctx)) {
			fprintf(stderr, "[Kine] failed to rebuild outline pipeline for viewport\n");
		}
	}

#if KINE_WITH_RAY
	if (viewportChanged && ctx->rayState) {
		// The presentation quad is sized from the viewport extent.
		kine_ray_display_destroy(ctx);
	}
#endif

	if (ctx->postProcessShader) {
		if (viewportChanged && !kine_build_post_process_pipeline(ctx)) {
			fprintf(stderr, "[Kine] failed to rebuild custom post-process pipeline for viewport\n");
			ctx->postProcessShader = nullptr;
		}
		return;
	}

	ctx->view->setViewport({(int32_t)clampedX,
							(int32_t)filamentY,
							(uint32_t)clampedWidth,
							(uint32_t)clampedHeight});
}

KINE_API void *Kine_Filament_GetEngine(KineFilamentContext *ctx) { return ctx ? (void *)ctx->engine : nullptr; }
KINE_API void *Kine_Filament_GetScene(KineFilamentContext *ctx) { return ctx ? (void *)ctx->scene : nullptr; }
KINE_API void *Kine_Filament_GetView(KineFilamentContext *ctx) { return ctx ? (void *)ctx->view : nullptr; }
KINE_API void *Kine_Filament_GetCamera(KineFilamentContext *ctx) { return ctx ? (void *)ctx->camera : nullptr; }

KINE_API void Kine_Filament_SetCameraLookAt(
	KineFilamentContext *ctx,
	float eyeX, float eyeY, float eyeZ,
	float targetX, float targetY, float targetZ,
	float upX, float upY, float upZ) {
	if (!ctx || !ctx->camera)
		return;
	ctx->cameraEye = {eyeX, eyeY, eyeZ};
	ctx->cameraTarget = {targetX, targetY, targetZ};
	ctx->cameraUp = {upX, upY, upZ};
	ctx->camera->lookAt(ctx->cameraEye, ctx->cameraTarget, ctx->cameraUp);
}

KINE_API bool Kine_Filament_BlitToScreen(KineFilamentContext *ctx, int dstX, int dstY, int dstWidth, int dstHeight) {
#if KINE_FILAMENT_USE_VULKAN
	(void)ctx;
	(void)dstX;
	(void)dstY;
	(void)dstWidth;
	(void)dstHeight;
	return false;
#else
	if (!ctx || !ctx->engine || ctx->colorTextureId == 0)
		return false;
	if (!kine_glBindFramebuffer || !kine_glGenFramebuffers ||
		!kine_glFramebufferTexture2D || !kine_glBlitFramebuffer)
		return false;

	if (ctx->readFboId == 0) {
		GLuint fbo = 0;
		kine_glGenFramebuffers(1, &fbo);
		kine_glBindFramebuffer(GL_FRAMEBUFFER, fbo);
		kine_glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
									GL_TEXTURE_2D, (GLuint)ctx->colorTextureId, 0);
		ctx->readFboId = (unsigned int)fbo;
		kine_glBindFramebuffer(GL_FRAMEBUFFER, 0);
	}

	kine_glBindFramebuffer(GL_READ_FRAMEBUFFER, (GLuint)ctx->readFboId);
	kine_glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0);
	kine_glBlitFramebuffer(0, 0, ctx->width, ctx->height,
						   dstX, dstY, dstX + dstWidth, dstY + dstHeight,
						   GL_COLOR_BUFFER_BIT, GL_NEAREST);
	kine_glBindFramebuffer(GL_FRAMEBUFFER, 0);
	return true;
#endif
}

KINE_API void Kine_Filament_SetCameraPosition(KineFilamentContext *ctx, float x, float y, float z) {
	if (!ctx || !ctx->camera)
		return;
	ctx->cameraEye = {x, y, z};
	ctx->camera->lookAt(ctx->cameraEye, ctx->cameraTarget, ctx->cameraUp);
}

KINE_API void Kine_Filament_SetCameraDirection(KineFilamentContext *ctx, float dx, float dy, float dz) {
	if (!ctx || !ctx->camera)
		return;
	ctx->cameraTarget = ctx->cameraEye + math::double3{dx, dy, dz};
	ctx->camera->lookAt(ctx->cameraEye, ctx->cameraTarget, ctx->cameraUp);
}

KINE_API int Kine_Filament_CreateLight(
	KineFilamentContext *ctx,
	float px, float py, float pz,
	float cr, float cg, float cb,
	float intensity,
	float falloff) {
	return Kine_Filament_CreateLightEx(
		ctx, 0,
		px, py, pz,
		0.0f, -1.0f, 0.0f,
		cr, cg, cb,
		intensity, falloff,
		0.35f, 0.785398163f,
		false, true);
}

KINE_API int Kine_Filament_CreateLightEx(
	KineFilamentContext *ctx,
	int lightType,
	float px, float py, float pz,
	float dx, float dy, float dz,
	float cr, float cg, float cb,
	float intensity,
	float falloff,
	float innerConeRadians,
	float outerConeRadians,
	bool castShadows,
	bool enabled) {
	if (!ctx || !ctx->engine || !ctx->scene)
		return -1;

	LightManager::Type type = LightManager::Type::POINT;
	if (lightType == 1)
		type = LightManager::Type::SPOT;
	else if (lightType == 2)
		type = LightManager::Type::FOCUSED_SPOT;

	float directionLength = sqrtf(dx * dx + dy * dy + dz * dz);
	if (directionLength < 1e-6f) {
		dx = 0.0f;
		dy = -1.0f;
		dz = 0.0f;
	} else {
		dx /= directionLength;
		dy /= directionLength;
		dz /= directionLength;
	}
	outerConeRadians = std::clamp(outerConeRadians, 0.00873f, 1.570796327f);
	innerConeRadians = std::clamp(innerConeRadians, 0.00873f, outerConeRadians);

	Entity entity = EntityManager::get().create();
	LightManager::Builder builder(type);
	builder.color({std::max(0.0f, cr), std::max(0.0f, cg), std::max(0.0f, cb)})
		.intensity(std::max(0.0f, intensity))
		.position({px, py, pz})
		.falloff(std::max(0.001f, falloff));
	if (type != LightManager::Type::POINT) {
		builder.direction({dx, dy, dz})
			.spotLightCone(innerConeRadians, outerConeRadians)
			.castShadows(castShadows);
	}
	if (builder.build(*ctx->engine, entity) != LightManager::Builder::Success) {
		EntityManager::get().destroy(entity);
		return -1;
	}

	if (enabled)
		ctx->scene->addEntity(entity);
	ctx->lights.push_back(entity);
	return static_cast<int>(entity.getId());
}

KINE_API int Kine_Filament_CreateDecal(
	KineFilamentContext *ctx,
	float width,
	float height,
	KineFilamentTex *texture,
	float offsetStudsU,
	float offsetStudsV,
	float studsPerTileU,
	float studsPerTileV,
	bool culling,
	bool castShadows,
	bool receiveShadows) {
	auto *texHandle = (KineTexHandle *)texture;
	if (!ctx || !ctx->engine || !ctx->scene || !texHandle || !texHandle->tex ||
		width <= 0.0f || height <= 0.0f)
		return -1;

	Entity entity = EntityManager::get().create();

	MaterialInstance *material = ctx->decalMaterial->createInstance();

	if (!material) {
		EntityManager::get().destroy(entity);
		return -1;
	}

	TextureSampler sampler(
		TextureSampler::MinFilter::LINEAR,
		TextureSampler::MagFilter::LINEAR,
		TextureSampler::WrapMode::REPEAT);

	math::float2 uvScale{
		studsPerTileU > 0.0f ? width / studsPerTileU : 1.0f,
		studsPerTileV > 0.0f ? height / studsPerTileV : 1.0f};
	math::float2 uvOffset{
		studsPerTileU > 0.0f ? offsetStudsU / studsPerTileU : 0.0f,
		studsPerTileV > 0.0f ? offsetStudsV / studsPerTileV : 0.0f};

	material->setParameter("baseColor", RgbaType::LINEAR, math::float4{1.0f, 1.0f, 1.0f, 1.0f});
	material->setParameter("hasTexture", 1.0f);
	material->setParameter("baseColorMap", texHandle->tex, sampler);
	material->setParameter("uvScale", uvScale);
	material->setParameter("uvOffset", uvOffset);

	KineMesh *mesh = buildDecalQuad();
	uploadMesh(mesh, ctx->engine);

	RenderableManager::Builder(1)
		.boundingBox({{-width * 0.5f, -height * 0.5f, -0.01f},
					  {width * 0.5f, height * 0.5f, 0.01f}})
		.material(0, material)
		.geometry(
			0,
			RenderableManager::PrimitiveType::TRIANGLES,
			mesh->vb,
			mesh->ib,
			0,
			mesh->indexCount)
		.culling(culling)
		.castShadows(castShadows)
		.receiveShadows(receiveShadows)
		.build(*ctx->engine, entity);

	ctx->scene->addEntity(entity);
	ctx->decals.push_back({entity, material, mesh});

	return static_cast<int>(entity.getId());
}

static void kine_compute_decal_uv(
	float width, float height,
	float offsetStudsU, float offsetStudsV,
	float studsPerTileU, float studsPerTileV,
	math::float2 &outScale, math::float2 &outOffset) {
	outScale = {
		studsPerTileU > 0.0f ? width / studsPerTileU : 1.0f,
		studsPerTileV > 0.0f ? height / studsPerTileV : 1.0f};
	outOffset = {
		studsPerTileU > 0.0f ? offsetStudsU / studsPerTileU : 0.0f,
		studsPerTileV > 0.0f ? offsetStudsV / studsPerTileV : 0.0f};
}

KINE_API bool Kine_Filament_SetDecalTiling(
	KineFilamentContext *ctx, int decal,
	float width, float height,
	float offsetStudsU, float offsetStudsV,
	float studsPerTileU, float studsPerTileV) {
	if (!ctx || !ctx->engine)
		return false;

	Entity entity = Entity::import(decal);
	if (entity.isNull())
		return false;

	RenderableManager &rm = ctx->engine->getRenderableManager();
	auto instance = rm.getInstance(entity);
	if (!instance.isValid())
		return false;

	MaterialInstance *mi = rm.getMaterialInstanceAt(instance, 0);
	if (!mi)
		return false;

	math::float2 uvScale, uvOffset;
	kine_compute_decal_uv(width, height, offsetStudsU, offsetStudsV,
						  studsPerTileU, studsPerTileV, uvScale, uvOffset);

	mi->setParameter("uvScale", uvScale);
	mi->setParameter("uvOffset", uvOffset);
	return true;
}

KINE_API bool Kine_Filament_SetDecalTransform(KineFilamentContext *ctx, int decal, float *mat4) {
	if (!ctx || !ctx->engine || !mat4)
		return false;

	Entity entity = Entity::import(decal);
	if (entity.isNull())
		return false;

	RenderableManager &rm = ctx->engine->getRenderableManager();
	if (!rm.hasComponent(entity))
		return false;

	math::mat4f transform(
		math::float4{mat4[0], mat4[4], mat4[8], mat4[12]},
		math::float4{mat4[1], mat4[5], mat4[9], mat4[13]},
		math::float4{mat4[2], mat4[6], mat4[10], mat4[14]},
		math::float4{mat4[3], mat4[7], mat4[11], mat4[15]});

	TransformManager &tm = ctx->engine->getTransformManager();
	auto instance = tm.getInstance(entity);
	if (!instance.isValid()) {
		tm.create(entity);
		instance = tm.getInstance(entity);
	}
	if (!instance.isValid())
		return false;

	tm.setTransform(instance, transform);
	return true;
}

KINE_API void Kine_Filament_RemoveDecal(KineFilamentContext *ctx, int decal) {
	if (!ctx || !ctx->engine || !ctx->scene)
		return;

	Entity entity = Entity::import(decal);
	if (entity.isNull())
		return;

	auto it = std::find_if(ctx->decals.begin(), ctx->decals.end(),
						   [entity](const KineDecalResource &decal) {
							   return decal.entity == entity;
						   });
	if (it != ctx->decals.end()) {
		kine_destroy_decal(ctx, *it);
		ctx->decals.erase(it);
		return;
	}

	if (ctx->engine->getRenderableManager().hasComponent(entity)) {
		ctx->scene->remove(entity);
		ctx->engine->destroy(entity);
	}
	EntityManager::get().destroy(entity);
}

KINE_API bool Kine_Filament_EditDecal(
	KineFilamentContext *ctx,
	int decal,
	float width,
	float height,
	bool culling,
	bool castShadows,
	bool receiveShadows) {
	if (!ctx || !ctx->engine || !ctx->scene ||
		width <= 0.0f || height <= 0.0f)
		return false;

	Entity entity = Entity::import(decal);
	if (entity.isNull())
		return false;

	RenderableManager &rm = ctx->engine->getRenderableManager();

	if (!rm.hasComponent(entity))
		return false;

	auto instance = rm.getInstance(entity);

	rm.setCastShadows(instance, castShadows);
	rm.setReceiveShadows(instance, receiveShadows);
	rm.setCulling(instance, culling);

	rm.setLayerMask(instance, 0x01, 0x01);

	rm.setAxisAlignedBoundingBox(
		instance,
		{{-width * 0.5f, -height * 0.5f, -0.01f},
		 {width * 0.5f, height * 0.5f, 0.01f}});

	return true;
}

KINE_API void Kine_Filament_SetColorLight(KineFilamentContext *ctx, int light, float r, float g, float b) {
	if (!ctx || !ctx->engine)
		return;
	auto &lm = ctx->engine->getLightManager();
	auto instance = lm.getInstance(Entity::import(light));
	if (!instance.isValid())
		return;
	lm.setColor(instance, {r, g, b});
}

KINE_API void Kine_Filament_SetIntensityLight(KineFilamentContext *ctx, int light, float intensity) {
	if (!ctx || !ctx->engine)
		return;
	auto &lm = ctx->engine->getLightManager();
	auto instance = lm.getInstance(Entity::import(light));
	if (!instance.isValid())
		return;
	lm.setIntensity(instance, intensity);
}

KINE_API void Kine_Filament_SetFalloffLight(KineFilamentContext *ctx, int light, float falloff) {
	if (!ctx || !ctx->engine)
		return;
	auto &lm = ctx->engine->getLightManager();
	auto instance = lm.getInstance(Entity::import(light));
	if (!instance.isValid())
		return;
	lm.setFalloff(instance, falloff);
}

KINE_API void Kine_Filament_SetPositionLight(KineFilamentContext *ctx, int light, float x, float y, float z) {
	if (!ctx || !ctx->engine)
		return;
	auto &lm = ctx->engine->getLightManager();
	auto instance = lm.getInstance(Entity::import(light));
	if (!instance.isValid())
		return;
	lm.setPosition(instance, {x, y, z});
}

KINE_API void Kine_Filament_SetDirectionLight(KineFilamentContext *ctx, int light, float x, float y, float z) {
	if (!ctx || !ctx->engine)
		return;
	float length = sqrtf(x * x + y * y + z * z);
	if (length < 1e-6f)
		return;
	auto &lm = ctx->engine->getLightManager();
	auto instance = lm.getInstance(Entity::import(light));
	if (!instance.isValid())
		return;
	lm.setDirection(instance, {x / length, y / length, z / length});
}

KINE_API void Kine_Filament_SetConeLight(
	KineFilamentContext *ctx, int light, float innerRadians, float outerRadians) {
	if (!ctx || !ctx->engine)
		return;
	auto &lm = ctx->engine->getLightManager();
	auto instance = lm.getInstance(Entity::import(light));
	if (!instance.isValid() || lm.getType(instance) == LightManager::Type::POINT)
		return;
	outerRadians = std::clamp(outerRadians, 0.00873f, 1.570796327f);
	innerRadians = std::clamp(innerRadians, 0.00873f, outerRadians);
	lm.setSpotLightCone(instance, innerRadians, outerRadians);
}

KINE_API void Kine_Filament_SetShadowLight(KineFilamentContext *ctx, int light, bool castShadows) {
	if (!ctx || !ctx->engine)
		return;
	auto &lm = ctx->engine->getLightManager();
	auto instance = lm.getInstance(Entity::import(light));
	if (!instance.isValid() || lm.getType(instance) == LightManager::Type::POINT)
		return;
	lm.setShadowCaster(instance, castShadows);
}

KINE_API void Kine_Filament_SetEnabledLight(KineFilamentContext *ctx, int light, bool enabled) {
	if (!ctx || !ctx->engine || !ctx->scene)
		return;
	Entity entity = Entity::import(light);
	if (!ctx->engine->getLightManager().hasComponent(entity))
		return;
	bool active = ctx->scene->hasEntity(entity);
	if (enabled && !active)
		ctx->scene->addEntity(entity);
	else if (!enabled && active)
		ctx->scene->remove(entity);
}

KINE_API void Kine_Filament_RemoveLight(KineFilamentContext *ctx, int light) {
	if (!ctx || !ctx->engine || !ctx->scene)
		return;
	Entity entity = Entity::import(light);
	auto it = std::find(ctx->lights.begin(), ctx->lights.end(), entity);
	if (it == ctx->lights.end())
		return;
	if (ctx->scene->hasEntity(entity))
		ctx->scene->remove(entity);
	ctx->engine->destroy(entity);
	EntityManager::get().destroy(entity);
	ctx->lights.erase(it);
}

KINE_API void Kine_Filament_SetCameraPerspective(
	KineFilamentContext *ctx,
	double fovYDegrees, double aspect, double nearPlane, double farPlane) {
	if (!ctx || !ctx->camera)
		return;
	ctx->fovYDegrees = static_cast<float>(fovYDegrees);
	ctx->nearPlane = nearPlane;
	ctx->farPlane = farPlane;
	ctx->camera->setProjection(fovYDegrees, aspect, nearPlane, farPlane);
	if (ctx->view) {
		ctx->view->setDynamicLightingOptions(
			static_cast<float>(std::max(nearPlane, 0.01)),
			static_cast<float>(std::max(farPlane, nearPlane + 0.01)));
	}
}

extern "C++" {

static math::mat4f kine_from_row_major(const float *m) {
	return math::mat4f(
		math::float4{m[0], m[4], m[8], m[12]},
		math::float4{m[1], m[5], m[9], m[13]},
		math::float4{m[2], m[6], m[10], m[14]},
		math::float4{m[3], m[7], m[11], m[15]});
}

static void kine_to_row_major(const math::mat4f &m, float *out) {
	for (int row = 0; row < 4; ++row) {
		for (int column = 0; column < 4; ++column) {
			out[row * 4 + column] = m[column][row];
		}
	}
}

static math::float3 kine_lerp(const math::float3 &a, const math::float3 &b, float t) {
	return a + (b - a) * t;
}

static KineQuat kine_normalize_quat(KineQuat q) {
	const float length = std::sqrt(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w);
	if (length <= 0.000001f)
		return {};
	q.x /= length;
	q.y /= length;
	q.z /= length;
	q.w /= length;
	return q;
}

static KineQuat kine_slerp(KineQuat a, KineQuat b, float t) {
	a = kine_normalize_quat(a);
	b = kine_normalize_quat(b);
	float dot = a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;
	if (dot < 0.0f) {
		dot = -dot;
		b.x = -b.x;
		b.y = -b.y;
		b.z = -b.z;
		b.w = -b.w;
	}
	if (dot > 0.9995f) {
		return kine_normalize_quat({a.x + (b.x - a.x) * t,
									a.y + (b.y - a.y) * t,
									a.z + (b.z - a.z) * t,
									a.w + (b.w - a.w) * t});
	}
	const float angle = std::acos(std::clamp(dot, -1.0f, 1.0f));
	const float denominator = std::sin(angle);
	const float aWeight = std::sin((1.0f - t) * angle) / denominator;
	const float bWeight = std::sin(t * angle) / denominator;
	return {
		a.x * aWeight + b.x * bWeight,
		a.y * aWeight + b.y * bWeight,
		a.z * aWeight + b.z * bWeight,
		a.w * aWeight + b.w * bWeight};
}

static math::mat4f kine_compose_trs(
	const math::float3 &translation, KineQuat rotation, const math::float3 &scale) {
	rotation = kine_normalize_quat(rotation);
	const float x = rotation.x, y = rotation.y, z = rotation.z, w = rotation.w;
	const float xx = x * x, yy = y * y, zz = z * z;
	const float xy = x * y, xz = x * z, yz = y * z;
	const float wx = w * x, wy = w * y, wz = w * z;
	return math::mat4f(
		math::float4{(1.0f - 2.0f * (yy + zz)) * scale.x,
					 (2.0f * (xy + wz)) * scale.x,
					 (2.0f * (xz - wy)) * scale.x, 0.0f},
		math::float4{(2.0f * (xy - wz)) * scale.y,
					 (1.0f - 2.0f * (xx + zz)) * scale.y,
					 (2.0f * (yz + wx)) * scale.y, 0.0f},
		math::float4{(2.0f * (xz + wy)) * scale.z,
					 (2.0f * (yz - wx)) * scale.z,
					 (1.0f - 2.0f * (xx + yy)) * scale.z, 0.0f},
		math::float4{translation.x, translation.y, translation.z, 1.0f});
}

static math::float3 kine_sample_vec(
	const std::vector<KineVecKey> &keys, float time, const math::float3 &fallback) {
	if (keys.empty())
		return fallback;
	if (keys.size() == 1 || time <= keys.front().time)
		return keys.front().value;
	if (time >= keys.back().time)
		return keys.back().value;
	auto upper = std::upper_bound(keys.begin(), keys.end(), time,
								  [](float value, const KineVecKey &key) { return value < key.time; });
	const KineVecKey &b = *upper;
	const KineVecKey &a = *(upper - 1);
	const float span = b.time - a.time;
	return kine_lerp(a.value, b.value, span > 0.0f ? (time - a.time) / span : 0.0f);
}

static KineQuat kine_sample_quat(
	const std::vector<KineQuatKey> &keys, float time, const KineQuat &fallback) {
	if (keys.empty())
		return fallback;
	if (keys.size() == 1 || time <= keys.front().time)
		return keys.front().value;
	if (time >= keys.back().time)
		return keys.back().value;
	auto upper = std::upper_bound(keys.begin(), keys.end(), time,
								  [](float value, const KineQuatKey &key) { return value < key.time; });
	const KineQuatKey &b = *upper;
	const KineQuatKey &a = *(upper - 1);
	const float span = b.time - a.time;
	return kine_slerp(a.value, b.value, span > 0.0f ? (time - a.time) / span : 0.0f);
}

static bool kine_eval_bone_global(
	size_t index,
	const KineMesh *mesh,
	const std::vector<math::mat4f> &locals,
	std::vector<math::mat4f> &globals,
	std::vector<uint8_t> &states) {
	if (states[index] == 2)
		return true;
	if (states[index] == 1)
		return false;
	states[index] = 1;
	const int parent = mesh->bones[index].parent;
	if (parent >= 0 && (size_t)parent < mesh->bones.size()) {
		if (!kine_eval_bone_global((size_t)parent, mesh, locals, globals, states))
			return false;
		globals[index] = globals[(size_t)parent] * locals[index];
	} else {
		globals[index] = locals[index];
	}
	states[index] = 2;
	return true;
}

static void kine_upload_skin_pose(KineFilamentContext *ctx, KineMesh *mesh) {
	if (!ctx || !ctx->engine || !mesh || mesh->skinMatrices.empty())
		return;
	RenderableManager &manager = ctx->engine->getRenderableManager();
	auto updateChunks = [&](const std::vector<KineBuiltBatch> &chunks) {
		for (const KineBuiltBatch &chunk : chunks) {
			const RenderableManager::Instance instance = manager.getInstance(chunk.entity);
			if (instance.isValid()) {
				manager.setBones(instance, mesh->skinMatrices.data(), mesh->skinMatrices.size());
			}
		}
	};
	for (KineFilamentInstanceBatch *batch : ctx->instanceBatches) {
		if (batch && batch->key.mesh == mesh)
			updateChunks(batch->chunks);
	}
	for (auto &entry : ctx->builtBatches) {
		if (entry.first.mesh == mesh)
			updateChunks(entry.second.chunks);
	}
}
}

KineFilamentMesh *Kine_Filament_CreateCustomMesh(
	KineFilamentContext *ctx,
	const float *vertexData,
	int vertexCount,
	const uint16_t *indices,
	int indexCount) {
	if (!ctx || !ctx->engine || !vertexData || vertexCount <= 0 || !indices || indexCount <= 0)
		return nullptr;
	if (vertexCount > 65535) {
		fprintf(stderr, "[Kine] CreateCustomMesh: %d verts exceeds uint16 index range\n", vertexCount);
		return nullptr;
	}
	auto *m = new KineMesh();
	m->vertices.resize(vertexCount);
	memcpy(m->vertices.data(), vertexData, vertexCount * sizeof(KineVertex));
	m->indices.assign(indices, indices + indexCount);
	m->indexCount = (uint32_t)indexCount;
	uploadMesh(m, ctx->engine);
	return (KineFilamentMesh *)m;
}

KINE_API KineFilamentMesh *Kine_Filament_CreateCustomMesh32(
	KineFilamentContext *ctx,
	const float *vertexData,
	int vertexCount,
	const uint32_t *indices,
	int indexCount) {
	if (!ctx || !ctx->engine || !vertexData || vertexCount <= 0 || !indices || indexCount <= 0)
		return nullptr;

	if (indexCount % 3 != 0) return nullptr;
	for (int i = 0; i < indexCount; ++i) if (indices[i] >= uint32_t(vertexCount)) return nullptr;
	auto *m = new KineMesh();
	m->vertices.resize(vertexCount);
	memcpy(m->vertices.data(), vertexData, vertexCount * sizeof(KineVertex));
	m->indices.assign(indices, indices + indexCount);
	m->indexCount = (uint32_t)indexCount;
	uploadMesh(m, ctx->engine);
	return (KineFilamentMesh *)m;
}

KINE_API KineFilamentMesh *Kine_Filament_CreateCustomMeshEx(
	KineFilamentContext *ctx,
	const float *vertexData,
	const float *colorData,
	int vertexCount,
	const uint16_t *indices,
	int indexCount) {
	if (!ctx || !ctx->engine || !vertexData || vertexCount <= 0 || !indices || indexCount <= 0)
		return nullptr;
	if (vertexCount > 65535) {
		fprintf(stderr, "[Kine] CreateCustomMeshEx: %d verts exceeds uint16 index range\n", vertexCount);
		return nullptr;
	}
	auto *m = new KineMesh();
	m->vertices.resize(vertexCount);
	memcpy(m->vertices.data(), vertexData, vertexCount * sizeof(KineVertex));
	if (colorData) {
		m->vertexColors.resize(vertexCount);
		memcpy(m->vertexColors.data(), colorData, vertexCount * sizeof(math::float4));
	}
	m->indices.assign(indices, indices + indexCount);
	m->indexCount = (uint32_t)indexCount;
	uploadMesh(m, ctx->engine);
	return (KineFilamentMesh *)m;
}

KINE_API KineFilamentMesh *Kine_Filament_CreateCustomMeshEx32(
	KineFilamentContext *ctx,
	const float *vertexData,
	const float *colorData,
	int vertexCount,
	const uint32_t *indices,
	int indexCount) {
	if (!ctx || !ctx->engine || !vertexData || vertexCount <= 0 || !indices || indexCount <= 0)
		return nullptr;

	if (indexCount % 3 != 0) return nullptr;
	for (int i = 0; i < indexCount; ++i) if (indices[i] >= uint32_t(vertexCount)) return nullptr;
	auto *m = new KineMesh();
	m->vertices.resize(vertexCount);
	memcpy(m->vertices.data(), vertexData, vertexCount * sizeof(KineVertex));
	if (colorData) {
		m->vertexColors.resize(vertexCount);
		memcpy(m->vertexColors.data(), colorData, vertexCount * sizeof(math::float4));
	}
	m->indices.assign(indices, indices + indexCount);
	m->indexCount = (uint32_t)indexCount;
	uploadMesh(m, ctx->engine);
	return (KineFilamentMesh *)m;
}

KINE_API KineFilamentMesh *Kine_Filament_CreateTerrainMesh(
	KineFilamentContext *ctx,
	const float *vertexData,
	const float *materialWeights,
	int vertexCount,
	const uint16_t *indices,
	int indexCount) {
	if (!ctx || !ctx->engine || !vertexData || !materialWeights || vertexCount <= 0 ||
		!indices || indexCount <= 0) {
		return nullptr;
	}
	if (vertexCount > 65535) {
		fprintf(stderr, "[Kine] CreateTerrainMesh: %d verts exceeds uint16 index range\n", vertexCount);
		return nullptr;
	}

	auto *m = new KineMesh();
	m->vertices.resize(vertexCount);
	memcpy(m->vertices.data(), vertexData, vertexCount * sizeof(KineVertex));
	m->terrainWeights.resize(vertexCount);
	memcpy(m->terrainWeights.data(), materialWeights, vertexCount * sizeof(KineTerrainWeights));
	m->indices.assign(indices, indices + indexCount);
	m->indexCount = (uint32_t)indexCount;
	uploadMesh(m, ctx->engine);
	return (KineFilamentMesh *)m;
}

bool Kine_Filament_UpdateCustomMesh(
	KineFilamentContext *ctx,
	KineFilamentMesh *mesh,
	const float *vertexData,
	int vertexCount) {
	auto *m = (KineMesh *)mesh;
	if (!ctx || !ctx->engine || !m || !m->vb || !vertexData || vertexCount <= 0 ||
		(size_t)vertexCount != m->vertices.size()) {
		return false;
	}

	memcpy(m->vertices.data(), vertexData, m->vertices.size() * sizeof(KineVertex));

	math::float3 boundsMin{
		std::numeric_limits<float>::max(),
		std::numeric_limits<float>::max(),
		std::numeric_limits<float>::max()};
	math::float3 boundsMax{
		std::numeric_limits<float>::lowest(),
		std::numeric_limits<float>::lowest(),
		std::numeric_limits<float>::lowest()};
	std::vector<math::float3> positions(m->vertices.size());
	std::vector<math::float3> normals(m->vertices.size());
	std::vector<math::float2> uvs(m->vertices.size());
	for (size_t i = 0; i < m->vertices.size(); ++i) {
		const KineVertex &vertex = m->vertices[i];
		boundsMin.x = std::min(boundsMin.x, vertex.px);
		boundsMin.y = std::min(boundsMin.y, vertex.py);
		boundsMin.z = std::min(boundsMin.z, vertex.pz);
		boundsMax.x = std::max(boundsMax.x, vertex.px);
		boundsMax.y = std::max(boundsMax.y, vertex.py);
		boundsMax.z = std::max(boundsMax.z, vertex.pz);
		positions[i] = {vertex.px, vertex.py, vertex.pz};
		normals[i] = {vertex.nx, vertex.ny, vertex.nz};
		uvs[i] = {vertex.u, vertex.v};
	}
	m->localBounds.set(boundsMin, boundsMax);

	std::vector<math::short4> quats(m->vertices.size());
	auto orientation = SurfaceOrientation::Builder()
						   .vertexCount((uint32_t)m->vertices.size())
						   .normals(normals.data())
						   .uvs(uvs.data())
						   .positions(positions.data())
						   .triangleCount(m->indices.size() / 3)
						   .triangles(reinterpret_cast<const math::uint3 *>(m->indices.data()))
						   .build();
	if (!orientation) {
		fprintf(stderr, "[Kine] UV tangent regeneration failed; using normal-derived frames\n");
		orientation = SurfaceOrientation::Builder()
						  .vertexCount((uint32_t)m->vertices.size())
						  .normals(normals.data())
						  .build();
		if (!orientation)
			return false;
	}
	orientation->getQuats(quats.data(), (uint32_t)m->vertices.size());
	delete orientation;

	const size_t vertexBytes = m->vertices.size() * sizeof(KineVertex);
	void *vertexCopy = malloc(vertexBytes);
	memcpy(vertexCopy, m->vertices.data(), vertexBytes);
	m->vb->setBufferAt(*ctx->engine, 0,
					   VertexBuffer::BufferDescriptor(vertexCopy, vertexBytes, [](void *buffer, size_t, void *) { free(buffer); }, nullptr));

	const size_t tangentBytes = quats.size() * sizeof(math::short4);
	void *tangentCopy = malloc(tangentBytes);
	memcpy(tangentCopy, quats.data(), tangentBytes);
	m->vb->setBufferAt(*ctx->engine, 1,
					   VertexBuffer::BufferDescriptor(tangentCopy, tangentBytes, [](void *buffer, size_t, void *) { free(buffer); }, nullptr));

	return true;
}

KINE_API KineFilamentGizmo *Kine_Filament_CreateGizmo(KineFilamentContext *ctx, int gizmoType) {
	if (!ctx || !ctx->engine)
		return nullptr;

	auto *gizmo = new KineFilamentGizmo();
	gizmo->type = gizmoType;

	switch (gizmoType) {
	case KINE_GIZMO_ROTATE:
		gizmo->axes = buildRotateGizmoAxes();
		break;
	case KINE_GIZMO_SCALE:
		gizmo->axes = buildScaleGizmoAxes();
		break;
	default:
		gizmo->axes = buildMoveGizmoAxes();
		break;
	}

	KineMesh *meshes[7] = {
		gizmo->axes.x,
		gizmo->axes.y,
		gizmo->axes.z,
		gizmo->axes.center,
		gizmo->axes.planes[0],
		gizmo->axes.planes[1],
		gizmo->axes.planes[2],
	};
	for (KineMesh *mesh : meshes) {
		if (mesh)
			uploadMesh(mesh, ctx->engine);
	}

	return gizmo;
}

KINE_API void Kine_Filament_DestroyGizmo(KineFilamentContext *ctx, KineFilamentGizmo *gizmo) {
	if (!ctx || !ctx->engine || !gizmo)
		return;

	KineMesh *meshes[7] = {
		gizmo->axes.x,
		gizmo->axes.y,
		gizmo->axes.z,
		gizmo->axes.center,
		gizmo->axes.planes[0],
		gizmo->axes.planes[1],
		gizmo->axes.planes[2],
	};
	for (KineMesh *mesh : meshes) {
		if (!mesh)
			continue;
		kine_invalidate_batches(ctx, mesh, nullptr);
		if (mesh->vb)
			ctx->engine->destroy(mesh->vb);
		if (mesh->ib)
			ctx->engine->destroy(mesh->ib);
		delete mesh;
	}

	delete gizmo;
}

KINE_API KineFilamentMesh *Kine_Filament_CreateMesh(KineFilamentContext *ctx, int shape) {
	if (!ctx || !ctx->engine)
		return nullptr;

	KineMesh *m = nullptr;
	switch (shape) {
	case 10:
		m = buildMoveGizmo();
		break;
	case 11:
		m = buildRotateGizmo();
		break;
	case 12:
		m = buildScaleGizmo();
		break;
	case 5:
		m = buildDisplacedCube();
		break;
	case 4:
		m = buildParticleQuad();
		break;
	case 6:
		m = buildCylinder();
		break;
	case 2:
		m = buildSphere();
		break;
	case 3:
		m = buildPyramid();
		break;
	case 7:
		m = buildWaterGrid();
		break;
	default:
		m = buildCube();
		break;
	}
	uploadMesh(m, ctx->engine);
	return (KineFilamentMesh *)m;
}

KINE_API KineFilamentMesh *Kine_Filament_CreateMeshFromPath(KineFilamentContext *ctx, const char *path) {
	if (!ctx || !ctx->engine || !path || path[0] == '\0')
		return nullptr;

#if KINE_WITH_ASSIMP
	KineMesh *m = loadMeshWithAssimp(path);
	if (!m)
		return nullptr;
	uploadMesh(m, ctx->engine);
	kine_attach_mesh_texture(ctx, m);
	return (KineFilamentMesh *)m;
#else
	fprintf(stderr, "[Kine] CreateMeshFromPath requires KINE_WITH_ASSIMP=ON and assimp::assimp at build time\n");
	return nullptr;
#endif
}

KINE_API KineFilamentMesh *Kine_Filament_CreateMeshFromMemory(
	KineFilamentContext *ctx,
	const void *data,
	size_t dataSize,
	const char *formatHint) {
	if (!ctx || !ctx->engine || !data || dataSize == 0) {
		return nullptr;
	}

#if KINE_WITH_ASSIMP
	KineMesh *m = loadMeshWithAssimpMemory(
		data,
		dataSize,
		formatHint);

	if (!m) {
		return nullptr;
	}

	uploadMesh(m, ctx->engine);
	kine_attach_mesh_texture(ctx, m);

	return reinterpret_cast<KineFilamentMesh *>(m);
#else
	fprintf(
		stderr,
		"[Kine] CreateMeshFromMemory requires "
		"KINE_WITH_ASSIMP=ON and assimp::assimp at build time\n");

	return nullptr;
#endif
}

KINE_API int Kine_Filament_GetMeshBoneCount(const KineFilamentMesh *mesh) {
	const auto *m = reinterpret_cast<const KineMesh *>(mesh);
	return m ? (int)m->bones.size() : 0;
}

KINE_API KineFilamentTex *Kine_Filament_GetMeshTexture(const KineFilamentMesh *mesh) {
	const auto *m = reinterpret_cast<const KineMesh *>(mesh);
	if (!m || !m->useImportedMaterials || !m->ownedTex)
		return nullptr;
	return reinterpret_cast<KineFilamentTex *>(m->ownedTex);
}

KINE_API bool Kine_Filament_GetMeshBounds(const KineFilamentMesh *mesh, float *center, float *halfExtent) {
    const auto *m=reinterpret_cast<const KineMesh *>(mesh);
    if (!m || !center || !halfExtent) return false;
    for (int i=0;i<3;++i) {center[i]=m->localBounds.center[i]; halfExtent[i]=m->localBounds.halfExtent[i];}
    return true;
}
KINE_API void Kine_Filament_SetUseImportedMaterials(KineFilamentContext *ctx, KineFilamentMesh *mesh, bool enabled) {
    auto *m=reinterpret_cast<KineMesh *>(mesh);
    if (!ctx || !m || m->useImportedMaterials == enabled) return;
    kine_invalidate_batches(ctx,m,nullptr);
    m->useImportedMaterials=enabled;
}
KINE_API int Kine_Filament_GetMeshMaterialCount(const KineFilamentMesh *mesh) {
    const auto *m=reinterpret_cast<const KineMesh *>(mesh);
    return m ? int(m->materials.size()) : 0;
}
KINE_API KineFilamentTex *Kine_Filament_GetMeshMaterialTexture(const KineFilamentMesh *mesh, int index) {
    const auto *m=reinterpret_cast<const KineMesh *>(mesh);
    return m && index>=0 && size_t(index)<m->materials.size() ? reinterpret_cast<KineFilamentTex *>(m->materials[index].texture) : nullptr;
}

KINE_API const char *Kine_Filament_GetMeshBoneName(const KineFilamentMesh *mesh, int boneIndex) {
	const auto *m = reinterpret_cast<const KineMesh *>(mesh);
	if (!m || boneIndex < 0 || (size_t)boneIndex >= m->bones.size())
		return nullptr;
	return m->bones[(size_t)boneIndex].name.c_str();
}

KINE_API int Kine_Filament_GetMeshBoneParent(const KineFilamentMesh *mesh, int boneIndex) {
	const auto *m = reinterpret_cast<const KineMesh *>(mesh);
	if (!m || boneIndex < 0 || (size_t)boneIndex >= m->bones.size())
		return -1;
	return m->bones[(size_t)boneIndex].parent;
}

KINE_API bool Kine_Filament_CopyMeshBoneBindTransform(
	const KineFilamentMesh *mesh, int boneIndex, float *outTransform16) {
	const auto *m = reinterpret_cast<const KineMesh *>(mesh);
	if (!m || !outTransform16 || boneIndex < 0 || (size_t)boneIndex >= m->bones.size())
		return false;
	kine_to_row_major(m->bones[(size_t)boneIndex].bindLocal, outTransform16);
	return true;
}

KINE_API bool Kine_Filament_SetMeshBoneTransforms(
	KineFilamentContext *ctx, KineFilamentMesh *mesh,
	const float *boneTransforms16, int boneCount) {
	auto *m = reinterpret_cast<KineMesh *>(mesh);
	if (!ctx || !m || !boneTransforms16 || boneCount != (int)m->bones.size() || boneCount <= 0)
		return false;
	m->skinMatrices.resize((size_t)boneCount);
	for (int i = 0; i < boneCount; ++i) {
		m->skinMatrices[(size_t)i] =
			kine_from_row_major(boneTransforms16 + (size_t)i * 16u) * m->bones[(size_t)i].inverseBind;
	}
	kine_upload_skin_pose(ctx, m);
	return true;
}

KINE_API int Kine_Filament_GetMeshAnimationCount(const KineFilamentMesh *mesh) {
	const auto *m = reinterpret_cast<const KineMesh *>(mesh);
	return m ? (int)m->animations.size() : 0;
}

KINE_API const char *Kine_Filament_GetMeshAnimationName(
	const KineFilamentMesh *mesh, int animationIndex) {
	const auto *m = reinterpret_cast<const KineMesh *>(mesh);
	if (!m || animationIndex < 0 || (size_t)animationIndex >= m->animations.size())
		return nullptr;
	return m->animations[(size_t)animationIndex].name.c_str();
}

KINE_API float Kine_Filament_GetMeshAnimationDuration(
	const KineFilamentMesh *mesh, int animationIndex) {
	const auto *m = reinterpret_cast<const KineMesh *>(mesh);
	if (!m || animationIndex < 0 || (size_t)animationIndex >= m->animations.size())
		return 0.0f;
	return m->animations[(size_t)animationIndex].duration;
}

KINE_API bool Kine_Filament_ApplyMeshAnimation(
	KineFilamentContext *ctx, KineFilamentMesh *mesh,
	int animationIndex, float timeSeconds, bool loop) {
	auto *m = reinterpret_cast<KineMesh *>(mesh);
	if (!ctx || !m || m->bones.empty() || animationIndex < 0 ||
		(size_t)animationIndex >= m->animations.size())
		return false;
	const KineAnimation &animation = m->animations[(size_t)animationIndex];
	float sampleTime = std::max(timeSeconds, 0.0f);
	if (animation.duration > 0.0f) {
		sampleTime = loop ? std::fmod(sampleTime, animation.duration)
						  : std::min(sampleTime, animation.duration);
	}

	std::vector<math::float3> translations(m->bones.size());
	std::vector<KineQuat> rotations(m->bones.size());
	std::vector<math::float3> scales(m->bones.size());
	for (size_t i = 0; i < m->bones.size(); ++i) {
		translations[i] = m->bones[i].bindTranslation;
		rotations[i] = m->bones[i].bindRotation;
		scales[i] = m->bones[i].bindScale;
	}
	for (const KineAnimationChannel &channel : animation.channels) {
		if (channel.bone < 0 || (size_t)channel.bone >= m->bones.size())
			continue;
		const size_t bone = (size_t)channel.bone;
		translations[bone] = kine_sample_vec(channel.translations, sampleTime, translations[bone]);
		rotations[bone] = kine_sample_quat(channel.rotations, sampleTime, rotations[bone]);
		scales[bone] = kine_sample_vec(channel.scales, sampleTime, scales[bone]);
	}

	std::vector<math::mat4f> locals(m->bones.size());
	std::vector<math::mat4f> globals(m->bones.size());
	std::vector<uint8_t> states(m->bones.size(), 0);
	m->skinMatrices.resize(m->bones.size());
	for (size_t i = 0; i < m->bones.size(); ++i) {
		locals[i] = kine_compose_trs(translations[i], rotations[i], scales[i]);
	}
	for (size_t i = 0; i < m->bones.size(); ++i) {
		if (!kine_eval_bone_global(i, m, locals, globals, states))
			return false;
		m->skinMatrices[i] = globals[i] * m->bones[i].inverseBind;
	}
	kine_upload_skin_pose(ctx, m);
	return true;
}

KINE_API KineFilamentMeshData *Kine_Filament_LoadMeshDataFromPath(const char *path) {
	if (!path || path[0] == '\0')
		return nullptr;

#if KINE_WITH_ASSIMP
	KineMesh *source = loadMeshWithAssimp(path,false);
	if (!source)
		return nullptr;

	auto *result = new KineCpuMeshData();
	result->positions.reserve(source->vertices.size());
	result->indices.reserve(source->indices.size());
	for (const KineVertex &vertex : source->vertices) {
		result->positions.push_back({vertex.px, vertex.py, vertex.pz});
	}
	for (uint32_t index : source->indices) {
		result->indices.push_back((uint32_t)index);
	}
	delete source;
	return reinterpret_cast<KineFilamentMeshData *>(result);
#else
	fprintf(stderr, "[Kine] LoadMeshDataFromPath requires KINE_WITH_ASSIMP=ON and assimp::assimp at build time\n");
	return nullptr;
#endif
}

KINE_API int Kine_Filament_GetMeshDataVertexCount(const KineFilamentMeshData *meshData) {
	const auto *data = reinterpret_cast<const KineCpuMeshData *>(meshData);
	return data ? (int)data->positions.size() : 0;
}

KINE_API int Kine_Filament_GetMeshDataIndexCount(const KineFilamentMeshData *meshData) {
	const auto *data = reinterpret_cast<const KineCpuMeshData *>(meshData);
	return data ? (int)data->indices.size() : 0;
}

KINE_API bool Kine_Filament_CopyMeshDataPositions(
	const KineFilamentMeshData *meshData, float *outPositions, int positionFloatCapacity) {
	const auto *data = reinterpret_cast<const KineCpuMeshData *>(meshData);
	const size_t required = data ? data->positions.size() * 3u : 0u;
	if (!data || !outPositions || positionFloatCapacity < 0 || (size_t)positionFloatCapacity < required)
		return false;
	for (size_t i = 0; i < data->positions.size(); ++i) {
		outPositions[i * 3u] = data->positions[i].x;
		outPositions[i * 3u + 1u] = data->positions[i].y;
		outPositions[i * 3u + 2u] = data->positions[i].z;
	}
	return true;
}

KINE_API bool Kine_Filament_CopyMeshDataIndices(
	const KineFilamentMeshData *meshData, uint32_t *outIndices, int indexCapacity) {
	const auto *data = reinterpret_cast<const KineCpuMeshData *>(meshData);
	const size_t required = data ? data->indices.size() : 0u;
	if (!data || !outIndices || indexCapacity < 0 || (size_t)indexCapacity < required)
		return false;
	std::copy(data->indices.begin(), data->indices.end(), outIndices);
	return true;
}

KINE_API void Kine_Filament_DestroyMeshData(KineFilamentMeshData *meshData) {
	delete reinterpret_cast<KineCpuMeshData *>(meshData);
}

KINE_API KineFilamentTex *Kine_Filament_CreateTexFromPixels(
	KineFilamentContext *ctx,
	int width, int height,
	int rowBytes,
	const void *pixelsRGBA8) {
	auto *th = new KineTexHandle();
	kine_keep_cpu_copy(th->cpuPixels, th->cpuWidth, th->cpuHeight, width, height, rowBytes, pixelsRGBA8);
	th->tex = ctx ? kine_create_uploaded_rgba_texture(ctx->engine, width, height, rowBytes, pixelsRGBA8) : nullptr;
	if (!th->tex) {
		delete th;
		return nullptr;
	}

	return (KineFilamentTex *)th;
}

KINE_API bool Kine_Filament_UpdateTexFromPixels(
	KineFilamentContext *ctx,
	KineFilamentTex *tex,
	int width, int height,
	int rowBytes,
	const void *pixelsRGBA8) {
	if (!ctx || !ctx->engine || !tex || !pixelsRGBA8 || width <= 0 || height <= 0 || rowBytes < width * 4)
		return false;

	auto *th = (KineTexHandle *)tex;
	if (!th->tex || th->tex->getWidth(0) != (uint32_t)width || th->tex->getHeight(0) != (uint32_t)height)
		return false;

	kine_keep_cpu_copy(th->cpuPixels, th->cpuWidth, th->cpuHeight, width, height, rowBytes, pixelsRGBA8);

	const size_t bytes = (size_t)rowBytes * (size_t)height;
	uint8_t *copy = (uint8_t *)malloc(bytes);
	if (!copy)
		return false;
	memcpy(copy, pixelsRGBA8, bytes);

	Texture::PixelBufferDescriptor pb(
		copy, bytes,
		Texture::Format::RGBA, Texture::Type::UBYTE,
		1, 0, 0, (uint32_t)(rowBytes / 4),
		[](void *buffer, size_t, void *) { free(buffer); });

	th->tex->setImage(*ctx->engine, 0, 0, 0,
					  (uint32_t)width, (uint32_t)height, std::move(pb));
	return true;
}

KINE_API KineFilamentTex *Kine_Filament_CreatePbrTexFromPixels(
	KineFilamentContext *ctx,
	int width, int height,
	int albedoRowBytes,
	const void *albedoRGBA8,
	int normalWidth, int normalHeight,
	int normalRowBytes,
	const void *normalRGBA8,
	int ormWidth, int ormHeight,
	int ormRowBytes,
	const void *ormRGBA8,
	int heightWidth, int heightHeight,
	int heightRowBytes,
	const void *heightRGBA8,
	float heightScale) {
	if (!ctx || !ctx->engine)
		return nullptr;

	auto *th = new KineTexHandle();
	kine_keep_cpu_copy(th->cpuPixels, th->cpuWidth, th->cpuHeight,
					   width, height, albedoRowBytes, albedoRGBA8);
	kine_keep_cpu_copy(th->cpuNormalPixels, th->cpuNormalWidth, th->cpuNormalHeight,
					   normalWidth, normalHeight, normalRowBytes, normalRGBA8);
	th->tex = kine_create_uploaded_rgba_texture(ctx->engine, width, height, albedoRowBytes, albedoRGBA8);
	if (!th->tex) {
		delete th;
		return nullptr;
	}

	th->normalTex = kine_create_uploaded_rgba_texture(
		ctx->engine, normalWidth, normalHeight, normalRowBytes, normalRGBA8);
	th->ormTex = kine_create_uploaded_rgba_texture(
		ctx->engine, ormWidth, ormHeight, ormRowBytes, ormRGBA8);
	th->heightTex = kine_create_uploaded_rgba_texture(
		ctx->engine, heightWidth, heightHeight, heightRowBytes, heightRGBA8);
	th->heightScale = heightScale;

	return (KineFilamentTex *)th;
}

KINE_API KineFilamentTex *Kine_Filament_CreateTerrainTextureSet(
	KineFilamentContext *ctx,
	KineFilamentTex *layer0,
	KineFilamentTex *layer1,
	KineFilamentTex *layer2,
	KineFilamentTex *layer3,
	KineFilamentTex *layer4,
	KineFilamentTex *layer5) {
	if (!ctx || !ctx->engine)
		return nullptr;

	KineFilamentTex *layers[6] = {layer0, layer1, layer2, layer3, layer4, layer5};
	auto *set = new KineTexHandle();
	set->ownsTextures = false;
	for (size_t i = 0; i < 6; ++i) {
		auto *source = (KineTexHandle *)layers[i];
		set->terrainLayers[i] = source ? source->tex : nullptr;
		set->terrainLayerSources[i] = source;
	}
	return (KineFilamentTex *)set;
}

KINE_API void Kine_Filament_DestroyMesh(KineFilamentContext *ctx, KineFilamentMesh *mesh) {
	if (!ctx || !mesh)
		return;
	auto *m = (KineMesh *)mesh;

	kine_invalidate_batches(ctx, m, m->ownedTex ? m->ownedTex : nullptr);
	if (m->vb)
		ctx->engine->destroy(m->vb);
	if (m->ib)
		ctx->engine->destroy(m->ib);
	if (m->ownedTex && m->ownsTexture) {
		if (m->ownedTex->tex)
			ctx->engine->destroy(m->ownedTex->tex);
		delete m->ownedTex;
		m->ownedTex = nullptr;
	}
	for (auto &material : m->materials) {
        auto *texture=material.texture;
        if (!texture) continue;
        if (texture->tex) ctx->engine->destroy(texture->tex);
        if (texture->normalTex) ctx->engine->destroy(texture->normalTex);
        if (texture->ormTex) ctx->engine->destroy(texture->ormTex);
        delete texture;
    }
	delete m;
}

KINE_API KineFilamentTex *Kine_Filament_CreateTex(KineFilamentContext *ctx, const KineGLTextureInfo *texture) {
	if (!ctx || !texture)
		return nullptr;

	if (texture->id == 0)
		return nullptr;

	auto *th = new KineTexHandle();

	th->tex = Texture::Builder()
				  .width((uint32_t)texture->width)
				  .height((uint32_t)texture->height)
				  .levels(1)
				  .usage(Texture::Usage::SAMPLEABLE)
				  .format(Texture::InternalFormat::RGBA8)
				  .import(texture->id)
				  .build(*ctx->engine);

	if (!th->tex) {
		delete th;
		return nullptr;
	}

	return (KineFilamentTex *)th;
}

KINE_API void Kine_Filament_DestroyTex(KineFilamentContext *ctx, KineFilamentTex *tex) {
	if (!ctx || !tex)
		return;
	auto *th = (KineTexHandle *)tex;
	kine_invalidate_batches(ctx, nullptr, th);
	if (th->ownsTextures) {
		if (th->tex)
			ctx->engine->destroy(th->tex);
		if (th->normalTex)
			ctx->engine->destroy(th->normalTex);
		if (th->ormTex)
			ctx->engine->destroy(th->ormTex);
		if (th->heightTex)
			ctx->engine->destroy(th->heightTex);
	}
	delete th;
}

static void kine_queue_mesh(
	KineFilamentContext *ctx,
	KineFilamentMesh *mesh,
	int materialKind,
	float r, float g, float b,
	float param1,
	float param2,
	float param3,
	float transmission,
	const float *mat4,
	bool castShadow,
	bool receiveShadow,
	bool culling,
	KineFilamentTex *tex,
	KineFilamentShader *shader = nullptr,
	uint64_t streamId = 0,
	float particleUvOffsetY = 0.0f,
	KineBatchKey *outKey = nullptr) {
	if (!ctx || !mesh || !mat4)
		return;

	if (kine_material_is_outline_mask(materialKind)) {

		ctx->outlineQueued = true;
		if (param2 > 0.0f)
			ctx->outlineWidthPixels = param2;
	}

	const bool perInstanceUv = (materialKind == KINE_MAT_DEFAULT);

	KineBatchKey key;
	key.mesh = (KineMesh *)mesh;
	key.shader = shader && shader->ctx == ctx ? shader : nullptr;
	if (key.shader) key.mesh = kine_refine_material_mesh(ctx, key.mesh, key.shader->subdivisionLevel);
	key.streamId = streamId;
	key.materialKind = materialKind;
	key.param1 = param1;
	key.param2 = param2;
	key.param3 = perInstanceUv ? 0.0f : param3;
	key.transmission = transmission;
	key.particleUvOffsetY = particleUvOffsetY;
	key.castShadow = castShadow;
	key.receiveShadow = receiveShadow;

	key.culling = culling && !((KineMesh *)mesh)->doubleSided;

	KineMesh *keyMesh = (KineMesh *)mesh;
	key.texture = tex ? (KineTexHandle *)tex : (keyMesh && keyMesh->useImportedMaterials ? keyMesh->ownedTex : nullptr);
	if (outKey) {
		*outKey = key;
	}

#if KINE_WITH_RAY
	// Record the draw for the path tracer while the transform is still ours to
	// copy. Overlays (gizmos, highlights, decals, water, clouds, particles) have
	// no Ray equivalent and stay out of the ray scene.
	if (ctx->rayState && kine_material_is_path_traced(materialKind)) {
		KineRayQueuedDraw queued;
		queued.mesh = keyMesh;
		queued.importedMaterials=kine_uses_imported_materials(ctx,key);
		queued.shader = key.shader;
		memcpy(queued.transform, mat4, sizeof(queued.transform));
		queued.color[0] = r;
		queued.color[1] = g;
		queued.color[2] = b;
		queued.materialKind = materialKind;
		// Same factor Filament feeds to instanceUvScale (see kine_default.mat):
		// only the default material retiles, by its stud-scale parameter.
		queued.uvScale = perInstanceUv ? (param3 > 0.0f ? param3 : 1.0f) : 1.0f;
		queued.param1 = param1;
		queued.param2 = param2;
		queued.param3 = param3;
		queued.transmission = transmission;
		// A terrain set only carries borrowed layer textures, so reach through it
		// to the handle that owns the pixels. Layer 0 is what the raster pass
		// falls back to when nothing else is blended in.
		const KineTexHandle *source = key.texture;
		if (source && materialKind == KINE_MAT_TERRAIN && source->terrainLayerSources[0])
			source = source->terrainLayerSources[0];
		if (source && !source->cpuPixels.empty()) {
			queued.baseColor.pixels = source->cpuPixels.data();
			queued.baseColor.width = source->cpuWidth;
			queued.baseColor.height = source->cpuHeight;
		}
		if (source && !source->cpuNormalPixels.empty()) {
			queued.normalMap.pixels = source->cpuNormalPixels.data();
			queued.normalMap.width = source->cpuNormalWidth;
			queued.normalMap.height = source->cpuNormalHeight;
		}
		// A retained stream owns its draws across frames, so they live with the
		// stream's other retained state instead of in the per-frame queue.
		if (streamId != 0) {
			ctx->retainedLists[streamId].rayDraws.push_back(queued);
		} else {
			ctx->rayDraws.push_back(queued);
		}
	}
#endif

	KinePendingBatch &pending = ctx->pendingBatches[key];
	if (pending.lastQueuedFrame != ctx->batchFrame) {
		pending.transforms.clear();
		pending.colors.clear();
		pending.uvScales.clear();
		pending.instanceTransformHashes.clear();
		pending.lastQueuedFrame = ctx->batchFrame;
		pending.transformHash = 1469598103934665603ULL;
		pending.colorHash = 1469598103934665603ULL;
		pending.uvHash = 1469598103934665603ULL;
		// clear() keeps capacity, so only a key's first sighting needs a hint.
		if (pending.transforms.capacity() == 0) {
			constexpr size_t KINE_BATCH_CAPACITY_HINT = 16;
			pending.transforms.reserve(KINE_BATCH_CAPACITY_HINT);
			pending.colors.reserve(KINE_BATCH_CAPACITY_HINT);
			pending.uvScales.reserve(KINE_BATCH_CAPACITY_HINT);
			pending.instanceTransformHashes.reserve(KINE_BATCH_CAPACITY_HINT);
		}
	}
	uint64_t instanceTransformHash = 1469598103934665603ULL;
	for (size_t offset = 0; offset < 16; ++offset) {
		uint32_t bits = 0;
		memcpy(&bits, mat4 + offset, sizeof(bits));
		pending.transformHash ^= bits;
		pending.transformHash *= 1099511628211ULL;
		instanceTransformHash ^= bits;
		instanceTransformHash *= 1099511628211ULL;
	}
	pending.transforms.emplace_back(
		math::float4{mat4[0], mat4[4], mat4[8], mat4[12]},
		math::float4{mat4[1], mat4[5], mat4[9], mat4[13]},
		math::float4{mat4[2], mat4[6], mat4[10], mat4[14]},
		math::float4{mat4[3], mat4[7], mat4[11], mat4[15]});
	pending.instanceTransformHashes.emplace_back(instanceTransformHash);

	const math::float4 color{r, g, b,
							 kine_material_uses_instance_alpha(materialKind) ? transmission : 1.0f};
	for (size_t offset = 0; offset < 4; ++offset) {
		uint32_t bits = 0;
		memcpy(&bits, &color[offset], sizeof(bits));
		pending.colorHash ^= bits;
		pending.colorHash *= 1099511628211ULL;
	}
	pending.colors.emplace_back(color);

	const float uvScale = perInstanceUv
							  ? (param3 > 0.0f ? param3 : 1.0f)
							  : 1.0f;
	{
		uint32_t bits = 0;
		memcpy(&bits, &uvScale, sizeof(bits));
		pending.uvHash ^= bits;
		pending.uvHash *= 1099511628211ULL;
	}
	pending.uvScales.emplace_back(uvScale);
}

KINE_API void Kine_Filament_DrawMeshEx(
	KineFilamentContext *ctx,
	KineFilamentMesh *mesh,
	int materialKind,
	float r, float g, float b,
	float param1,
	float param2,
	float param3,
	float transmission,
	float *mat4,
	bool castshadow,
	bool receiveShadow,
	bool culling,
	KineFilamentTex *tex) {
	kine_queue_mesh(
		ctx, mesh, materialKind,
		r, g, b,
		param1, param2, param3, transmission,
		mat4,
		castshadow, receiveShadow, culling,
		tex);
}

KINE_API void Kine_Filament_DrawMeshList(
	KineFilamentContext *ctx,
	const KineFilamentDrawItem *items,
	uint32_t itemCount) {
	static_assert(sizeof(KineFilamentDrawItem) == 128,
				  "KineFilamentDrawItem ABI must match filament/structs.luau");
	static_assert(offsetof(KineFilamentDrawItem, transform) == 16 &&
					  offsetof(KineFilamentDrawItem, materialKind) == 108 &&
					  offsetof(KineFilamentDrawItem, flags) == 112 &&
					  offsetof(KineFilamentDrawItem, shader) == 120,
				  "KineFilamentDrawItem field offsets must match filament/structs.luau");

	if (!ctx || !items || itemCount == 0)
		return;

	for (uint32_t i = 0; i < itemCount; ++i) {
		const KineFilamentDrawItem &item = items[i];
		kine_queue_mesh(
			ctx, item.mesh, item.materialKind,
			item.r, item.g, item.b,
			item.param1, item.param2, item.param3, item.transmission,
			item.transform,
			(item.flags & KINE_FILAMENT_DRAW_CAST_SHADOWS) != 0,
			(item.flags & KINE_FILAMENT_DRAW_RECEIVE_SHADOWS) != 0,
			(item.flags & KINE_FILAMENT_DRAW_CULLING) != 0,
			item.tex,
			item.shader);
	}
}

KINE_API void Kine_Filament_DrawParticles(
	KineFilamentContext *ctx,
	KineFilamentTex *texture,
	const KineFilamentParticleItem *items,
	uint32_t itemCount,
	float uvScaleX,
	float uvScaleY,
	float uvOffsetX,
	float uvOffsetY,
	bool castShadows,
	bool culling) {
	static_assert(sizeof(KineFilamentParticleItem) == 68,
				  "KineFilamentParticleItem ABI must match filament/funcs.luau");
	static_assert(offsetof(KineFilamentParticleItem, r) == 64,
				  "KineFilamentParticleItem color offset must match filament/funcs.luau");

	if (!ctx || !ctx->particleQuadMesh || !items || itemCount == 0)
		return;

	const float sx = uvScaleX > 0.0f ? uvScaleX : 1.0f;
	const float sy = uvScaleY > 0.0f ? uvScaleY : 1.0f;
	for (uint32_t i = 0; i < itemCount; ++i) {
		const KineFilamentParticleItem &item = items[i];
		if (item.a == 0)
			continue;

		kine_queue_mesh(
			ctx,
			reinterpret_cast<KineFilamentMesh *>(ctx->particleQuadMesh),
			KINE_MAT_PARTICLE,
			item.r / 255.0f,
			item.g / 255.0f,
			item.b / 255.0f,
			sx,
			sy,
			uvOffsetX,
			item.a / 255.0f,
			item.transform,

			false,
			false,
			culling,
			texture,
			nullptr,
			0,
			uvOffsetY);
	}
}

KINE_API void Kine_Filament_DrawMeshListVersioned(
	KineFilamentContext *ctx,
	const KineFilamentDrawItem *items,
	uint32_t itemCount,
	uint64_t streamId,
	uint64_t version) {
	if (!ctx || streamId == 0)
		return;

	KineRetainedListState &state = ctx->retainedLists[streamId];
	if (state.initialized && state.version == version) {
		for (const KineBatchKey &key : state.keys) {
			auto built = ctx->builtBatches.find(key);
			if (built != ctx->builtBatches.end()) {
				built->second.lastUsedFrame = ctx->batchFrame;

				if (kine_material_is_outline_mask(key.materialKind)) {
					ctx->outlineQueued = true;
					if (key.param2 > 0.0f)
						ctx->outlineWidthPixels = key.param2;
				}
			}
		}
		return;
	}

	state.initialized = true;
	state.version = version;
	state.keys.clear();
#if KINE_WITH_RAY
	state.rayDraws.clear();
#endif
	if (!items || itemCount == 0)
		return;

	std::unordered_set<KineBatchKey, KineBatchKeyHash> uniqueKeys;
	for (uint32_t i = 0; i < itemCount; ++i) {
		const KineFilamentDrawItem &item = items[i];
		KineBatchKey key;
		kine_queue_mesh(
			ctx, item.mesh, item.materialKind,
			item.r, item.g, item.b,
			item.param1, item.param2, item.param3, item.transmission,
			item.transform,
			(item.flags & KINE_FILAMENT_DRAW_CAST_SHADOWS) != 0,
			(item.flags & KINE_FILAMENT_DRAW_RECEIVE_SHADOWS) != 0,
			(item.flags & KINE_FILAMENT_DRAW_CULLING) != 0,
			item.tex,
			item.shader,
			streamId,
			0.0f,
			&key);
		if (uniqueKeys.insert(key).second) {
			state.keys.push_back(key);
		}
	}
}

KINE_API KineFilamentInstanceBatch *Kine_Filament_CreateInstanceBatch(
	KineFilamentContext *ctx,
	const KineFilamentDrawItem *items,
	uint32_t itemCount) {
	if (!ctx || !ctx->engine || !items || itemCount == 0)
		return nullptr;

	KineBatchKey key = kine_draw_item_key(items[0]);
	if (!key.mesh)
		return nullptr;

	auto *batch = new KineFilamentInstanceBatch();
	batch->ctx = ctx;
	batch->key = key;
	batch->transforms.reserve(itemCount);
	batch->colors.reserve(itemCount);

	for (uint32_t i = 0; i < itemCount; ++i) {
		const KineFilamentDrawItem &item = items[i];
		const KineBatchKey itemKey = kine_draw_item_key(item);
		if (!(itemKey == key)) {
			delete batch;
			return nullptr;
		}
		batch->transforms.push_back(kine_draw_item_transform(item));

		batch->colors.emplace_back(
			item.r, item.g, item.b,
			kine_material_uses_instance_alpha(key.materialKind) ? item.transmission : 1.0f);
	}

	if (!kine_rebuild_instance_batch(batch)) {
		Kine_Filament_DestroyInstanceBatch(batch);
		return nullptr;
	}

	ctx->instanceBatches.insert(batch);
	return batch;
}

KINE_API void Kine_Filament_DestroyInstanceBatch(KineFilamentInstanceBatch *batch) {
	if (!batch)
		return;
	kine_destroy_instance_batch_chunks(batch);
	KineFilamentContext *ctx = batch->ctx;
	if (ctx) {
		ctx->instanceBatches.erase(batch);
	}
	delete batch;
}

KINE_API void Kine_Filament_UpdateInstanceTransforms(
	KineFilamentInstanceBatch *batch,
	const uint32_t *indices,
	const float *transforms,
	uint32_t dirtyCount) {
	if (!batch || !batch->ctx || !batch->ctx->engine || !indices || !transforms || dirtyCount == 0)
		return;

	size_t maxInstances = kine_max_chunk_instances(batch->ctx);

	std::vector<uint32_t> dirtyIndices;
	dirtyIndices.reserve(dirtyCount);

	for (uint32_t i = 0; i < dirtyCount; ++i) {
		const uint32_t index = indices[i];
		if (index >= batch->transforms.size())
			continue;

		const float *mat4 = transforms + ((size_t)i * 16);
		batch->transforms[index] = math::mat4f(
			math::float4{mat4[0], mat4[4], mat4[8], mat4[12]},
			math::float4{mat4[1], mat4[5], mat4[9], mat4[13]},
			math::float4{mat4[2], mat4[6], mat4[10], mat4[14]},
			math::float4{mat4[3], mat4[7], mat4[11], mat4[15]});
		dirtyIndices.push_back(index);
	}

	if (dirtyIndices.empty())
		return;

	std::sort(dirtyIndices.begin(), dirtyIndices.end());
	dirtyIndices.erase(std::unique(dirtyIndices.begin(), dirtyIndices.end()), dirtyIndices.end());

	size_t pos = 0;
	while (pos < dirtyIndices.size()) {
		const uint32_t first = dirtyIndices[pos];
		const size_t chunkIndex = first / maxInstances;
		const size_t chunkBase = chunkIndex * maxInstances;
		uint32_t last = first;
		pos++;

		while (pos < dirtyIndices.size()) {
			const uint32_t next = dirtyIndices[pos];
			if (next != last + 1 || next / maxInstances != chunkIndex) {
				break;
			}
			last = next;
			pos++;
		}

		if (chunkIndex >= batch->chunks.size())
			continue;
		KineBuiltBatch &chunk = batch->chunks[chunkIndex];
		if (!chunk.instanceBuffer)
			continue;

		const size_t count = (size_t)last - (size_t)first + 1;
		chunk.instanceBuffer->setLocalTransforms(
			batch->transforms.data() + first,
			count,
			first - chunkBase);
	}
}

KINE_API void Kine_Filament_DrawMeshOutline(
	KineFilamentContext *ctx,
	KineFilamentMesh *mesh,
	float r, float g, float b,
	float thickness,
	float *mat4) {
	if (!ctx || !mesh || !mat4 || thickness <= 0.0f)
		return;

	Kine_Filament_DrawMeshEx(
		ctx, mesh, KINE_MAT_OUTLINE,
		r, g, b,
		thickness, 0.0f, 0.0f,
		0.0f,
		mat4,
		false, false, false,
		nullptr);
}
}

static void kine_gizmo_axis_color(int axis, float &r, float &g, float &b) {
	switch (axis) {
	case KINE_GIZMO_AXIS_X:
		r = 0.90f;
		g = 0.15f;
		b = 0.15f;
		break;
	case KINE_GIZMO_AXIS_Y:
		r = 0.20f;
		g = 0.85f;
		b = 0.20f;
		break;
	case KINE_GIZMO_AXIS_Z:
		r = 0.20f;
		g = 0.45f;
		b = 0.95f;
		break;
	case KINE_GIZMO_AXIS_CENTER:
		r = 0.85f;
		g = 0.85f;
		b = 0.85f;
		break;

	case KINE_GIZMO_AXIS_XY:
		r = 0.20f;
		g = 0.45f;
		b = 0.95f;
		break;
	case KINE_GIZMO_AXIS_YZ:
		r = 0.90f;
		g = 0.15f;
		b = 0.15f;
		break;
	case KINE_GIZMO_AXIS_XZ:
		r = 0.20f;
		g = 0.85f;
		b = 0.20f;
		break;
	default:
		r = 1.00f;
		g = 1.00f;
		b = 1.00f;
		break;
	}
}

struct KineGizmoScreenPoint {
	double x = 0.0;
	double y = 0.0;
	bool valid = false;
};

static math::mat4 kine_gizmo_model_matrix(const float *mat4) {
	return math::mat4(
		math::double4{mat4[0], mat4[4], mat4[8], mat4[12]},
		math::double4{mat4[1], mat4[5], mat4[9], mat4[13]},
		math::double4{mat4[2], mat4[6], mat4[10], mat4[14]},
		math::double4{mat4[3], mat4[7], mat4[11], mat4[15]});
}

static KineGizmoScreenPoint kine_gizmo_project(
	KineFilamentContext *ctx,
	const math::mat4 &model,
	const math::double3 &point) {
	KineGizmoScreenPoint result;
	if (!ctx || !ctx->camera)
		return result;

	const math::double4 clip = ctx->camera->getProjectionMatrix() *
							   ctx->camera->getViewMatrix() * model * math::double4{point, 1.0};
	if (clip.w <= 1e-8)
		return result;

	const double ndcX = clip.x / clip.w;
	const double ndcY = clip.y / clip.w;
	const int viewportX = ctx->viewportWidth > 0 ? ctx->viewportX : 0;
	const int viewportY = ctx->viewportHeight > 0 ? ctx->viewportY : 0;
	const int viewportWidth = ctx->viewportWidth > 0 ? ctx->viewportWidth : ctx->width;
	const int viewportHeight = ctx->viewportHeight > 0 ? ctx->viewportHeight : ctx->height;
	result.x = viewportX + (ndcX * 0.5 + 0.5) * viewportWidth;
	result.y = viewportY + (1.0 - (ndcY * 0.5 + 0.5)) * viewportHeight;
	result.valid = true;
	return result;
}

static double kine_gizmo_segment_distance(
	double px, double py,
	const KineGizmoScreenPoint &a,
	const KineGizmoScreenPoint &b) {
	if (!a.valid || !b.valid)
		return std::numeric_limits<double>::max();
	const double vx = b.x - a.x;
	const double vy = b.y - a.y;
	const double lengthSquared = vx * vx + vy * vy;
	if (lengthSquared <= 1e-8)
		return std::hypot(px - a.x, py - a.y);
	const double t = std::clamp(((px - a.x) * vx + (py - a.y) * vy) / lengthSquared, 0.0, 1.0);
	return std::hypot(px - (a.x + vx * t), py - (a.y + vy * t));
}

static math::double3 kine_gizmo_axis_point(int axis, double distance) {
	if (axis == KINE_GIZMO_AXIS_X)
		return {distance, 0.0, 0.0};
	if (axis == KINE_GIZMO_AXIS_Y)
		return {0.0, distance, 0.0};
	return {0.0, 0.0, distance};
}

struct KineGizmoPlane {
	int id;
	int meshIndex;
	int normalAxis;
	int first;
	int second;
};

static const KineGizmoPlane KINE_GIZMO_PLANES[3] = {
	{KINE_GIZMO_AXIS_XY, 0, KINE_GIZMO_AXIS_Z, KINE_GIZMO_AXIS_X, KINE_GIZMO_AXIS_Y},
	{KINE_GIZMO_AXIS_YZ, 1, KINE_GIZMO_AXIS_X, KINE_GIZMO_AXIS_Y, KINE_GIZMO_AXIS_Z},
	{KINE_GIZMO_AXIS_XZ, 2, KINE_GIZMO_AXIS_Y, KINE_GIZMO_AXIS_X, KINE_GIZMO_AXIS_Z},
};

static const KineGizmoPlane *kine_gizmo_plane(int id) {
	for (const KineGizmoPlane &plane : KINE_GIZMO_PLANES) {
		if (plane.id == id)
			return &plane;
	}
	return nullptr;
}

static const double KINE_GIZMO_AXIS_HANDOFF = 0.92;

static const double KINE_GIZMO_TARGET_VIEWPORT_FRACTION = 0.125;

static const double KINE_GIZMO_ACTIVE_BOOST = 1.18;

static double kine_gizmo_view_scale(KineFilamentContext *ctx, double distance) {
	if (!ctx || !ctx->camera || distance <= 1e-6)
		return 1.0;

	const math::mat4 projection = ctx->camera->getProjectionMatrix();
	// Filament stores mat4 column-major, so column 1 is (0, focalY, 0, 0): the
	// vertical focal length is its y component, not its x component (which is 0
	// and would make this whole scale collapse to 1.0).
	const double focal = projection[1].y;
	if (!(focal > 1e-6))
		return 1.0;

	const int viewportHeight = ctx->viewportHeight > 0 ? ctx->viewportHeight : ctx->height;
	if (viewportHeight <= 0)
		return 1.0;

	const double targetPixels = KINE_GIZMO_TARGET_VIEWPORT_FRACTION * (double)viewportHeight;
	return (2.0 * targetPixels * distance) / ((double)viewportHeight * focal);
}

struct KineGizmoFrame {
	math::mat4 model;
	float scaled[16] = {};

	float boosted[16] = {};
	int hiddenAxis = KINE_GIZMO_AXIS_NONE;
	int activePlane = KINE_GIZMO_AXIS_NONE;
};

static void kine_gizmo_scaled_matrix(const float *mat4, double scale, float *out) {
	// The caller hands us a row-major rigid matrix, so the three basis vectors
	// live in the top-left 3x3 (indices 0,1,2 / 4,5,6 / 8,9,10). Scale only
	// those: the translation (indices 3,7,11) is the gizmo origin and must stay
	// put, otherwise the hover boost would fling the gizmo off the object.
	for (int i = 0; i < 16; ++i)
		out[i] = mat4[i];
	for (int row = 0; row < 3; ++row)
		for (int col = 0; col < 3; ++col)
			out[row * 4 + col] = (float)(mat4[row * 4 + col] * scale);
}

static KineGizmoFrame kine_gizmo_frame(KineFilamentContext *ctx, const float *mat4, int gizmoType) {
	KineGizmoFrame frame;
	frame.model = kine_gizmo_model_matrix(mat4);
	kine_gizmo_scaled_matrix(mat4, 1.0, frame.scaled);
	if (!ctx || !ctx->camera)
		return frame;

	const math::mat4 view = ctx->camera->getViewMatrix();
	const double t[3] = {view[3].x, view[3].y, view[3].z};
	const math::double3 eye{
		-(view[0].x * t[0] + view[0].y * t[1] + view[0].z * t[2]),
		-(view[1].x * t[0] + view[1].y * t[1] + view[1].z * t[2]),
		-(view[2].x * t[0] + view[2].y * t[1] + view[2].z * t[2]),
	};

	const math::double4 origin = frame.model * math::double4{0.0, 0.0, 0.0, 1.0};
	const math::double3 toGizmo{origin.x - eye.x, origin.y - eye.y, origin.z - eye.z};
	const double distance = std::sqrt(
		toGizmo.x * toGizmo.x + toGizmo.y * toGizmo.y + toGizmo.z * toGizmo.z);

	kine_gizmo_scaled_matrix(mat4, kine_gizmo_view_scale(ctx, distance), frame.scaled);
	kine_gizmo_scaled_matrix(
		mat4, kine_gizmo_view_scale(ctx, distance) * KINE_GIZMO_ACTIVE_BOOST, frame.boosted);

	frame.model = kine_gizmo_model_matrix(frame.scaled);
	if (distance <= 1e-6)
		return frame;

	const double inv = 1.0 / distance;
	const double dx = toGizmo.x * inv;
	const double dy = toGizmo.y * inv;
	const double dz = toGizmo.z * inv;
	const double weights[3] = {
		std::abs(mat4[0] * dx + mat4[4] * dy + mat4[8] * dz),
		std::abs(mat4[1] * dx + mat4[5] * dy + mat4[9] * dz),
		std::abs(mat4[2] * dx + mat4[6] * dy + mat4[10] * dz),
	};

	if (gizmoType != KINE_GIZMO_ROTATE) {
		int dominant = KINE_GIZMO_AXIS_NONE;
		double best = KINE_GIZMO_AXIS_HANDOFF;
		for (int i = 0; i < 3; ++i) {
			if (weights[i] > best) {
				best = weights[i];
				dominant = KINE_GIZMO_AXIS_X + i;
			}
		}
		if (dominant != KINE_GIZMO_AXIS_NONE) {
			frame.hiddenAxis = dominant;
			for (const KineGizmoPlane &plane : KINE_GIZMO_PLANES) {
				if (plane.normalAxis == dominant)
					frame.activePlane = plane.id;
			}
		}
	}
	return frame;
}

static math::double3 kine_gizmo_plane_corner(
	const KineGizmoPlane &plane, int corner, double half) {
	const int a = plane.first - KINE_GIZMO_AXIS_X;
	const int b = plane.second - KINE_GIZMO_AXIS_X;
	const double signA = (corner == 0 || corner == 3) ? -1.0 : 1.0;
	const double signB = (corner == 0 || corner == 1) ? -1.0 : 1.0;
	double p[3] = {0.0, 0.0, 0.0};
	p[a] = KINE_GIZMO_PLANE_OFFSET + signA * half;
	p[b] = KINE_GIZMO_PLANE_OFFSET + signB * half;
	return math::double3{p[0], p[1], p[2]};
}

static bool kine_gizmo_point_in_quad(
	double px, double py,
	const KineGizmoScreenPoint &q0,
	const KineGizmoScreenPoint &q1,
	const KineGizmoScreenPoint &q2,
	const KineGizmoScreenPoint &q3) {
	if (!q0.valid || !q1.valid || !q2.valid || !q3.valid)
		return false;
	const KineGizmoScreenPoint *quad[4] = {&q0, &q1, &q2, &q3};
	int outside = 0;
	for (int i = 0; i < 4; ++i) {
		const KineGizmoScreenPoint &a = *quad[i];
		const KineGizmoScreenPoint &b = *quad[(i + 1) & 3];
		if ((b.x - a.x) * (py - a.y) - (b.y - a.y) * (px - a.x) < 0.0)
			++outside;
	}
	return outside == 0 || outside == 4;
}

// kine_gizmo_rotate_delta turns the mouse sweep around the projected gizmo origin
// into a signed rotation angle in radians, so a grabbed ring point stays under
// the cursor. The ring is a circle around that origin, so the angle the cursor
// sweeps is the angle the object turns; its sign flips depending on whether the
// ring's world axis points toward or away from the camera.
static float kine_gizmo_rotate_delta(
	KineFilamentContext *ctx,
	const float *mat4,
	int axis,
	float startX, float startY, float currentX, float currentY) {
	const int index = axis - KINE_GIZMO_AXIS_X;
	if (index < 0 || index > 2)
		return 0.0f;

	const math::mat4 model = kine_gizmo_model_matrix(mat4);
	const KineGizmoScreenPoint center = kine_gizmo_project(ctx, model, {0.0, 0.0, 0.0});
	if (!center.valid)
		return 0.0f;

	const double v1x = (double)startX - center.x;
	const double v1y = (double)startY - center.y;
	const double v2x = (double)currentX - center.x;
	const double v2y = (double)currentY - center.y;
	if (std::hypot(v1x, v1y) < 1.0 || std::hypot(v2x, v2y) < 1.0)
		return 0.0f;

	// Screen Y points down, so a positive sweep is clockwise on screen.
	const double screenAngle = std::atan2(v1x * v2y - v1y * v2x, v1x * v2x + v1y * v2y);

	// Recover the eye from the view matrix (as kine_gizmo_frame does) and test
	// whether the ring's world axis faces the camera: rotating about an axis
	// pointing at the viewer reads the opposite way on screen.
	const math::mat4 view = ctx->camera->getViewMatrix();
	const double t[3] = {view[3].x, view[3].y, view[3].z};
	const double eye[3] = {
		-(view[0].x * t[0] + view[0].y * t[1] + view[0].z * t[2]),
		-(view[1].x * t[0] + view[1].y * t[1] + view[1].z * t[2]),
		-(view[2].x * t[0] + view[2].y * t[1] + view[2].z * t[2]),
	};
	const double axisWorld[3] = {mat4[index], mat4[4 + index], mat4[8 + index]};
	const double centerWorld[3] = {mat4[3], mat4[7], mat4[11]};
	const double facing = axisWorld[0] * (eye[0] - centerWorld[0]) +
						  axisWorld[1] * (eye[1] - centerWorld[1]) +
						  axisWorld[2] * (eye[2] - centerWorld[2]);

	return (float)(screenAngle * (facing > 0.0 ? -1.0 : 1.0));
}

// ---------------------------------------------------------------------------
// Immediate-mode debug shapes (NOT the interactive transform gizmo).
// Call every frame before Kine_Filament_RenderFrame. Matrices are row-major
// float[16] (translation at 3/7/11) like the rest of this API; null = identity.
// Shapes reuse KINE_MAT_GIZMO, so they are unlit and batched into instances.
// ---------------------------------------------------------------------------

static const float KINE_IDENTITY_4X4[16] = {
	1, 0, 0, 0,
	0, 1, 0, 0,
	0, 0, 1, 0,
	0, 0, 0, 1};

static const float KINE_DEFAULT_WIRE_THICKNESS = 0.02f;
static const size_t KINE_MAX_WIRE_MESH_EDGES = 16384;

static KineMesh *kine_dbg_prim(KineFilamentContext *ctx, int kind) {
	KineMesh *&slot = ctx->gizmoPrims[kind];
	if (!slot) {
		KineMesh *m = kind == 0	  ? buildCube()
					  : kind == 1 ? buildSphere(24, 16)
					  : kind == 2 ? buildCylinder(24)
								  : buildCylinder(8);
		uploadMesh(m, ctx->engine);
		if (!m->vb || !m->ib) {
			delete m;
			return nullptr;
		}
		slot = m;
	}
	return slot;
}

static void kine_dbg_queue(
	KineFilamentContext *ctx, KineMesh *mesh, const float *m,
	float r, float g, float b) {
	if (!mesh)
		return;
	// Same parameters Kine_Filament_DrawGizmo uses, so these share its batches.
	kine_queue_mesh(
		ctx, reinterpret_cast<KineFilamentMesh *>(mesh), KINE_MAT_GIZMO,
		r, g, b,
		1.0f, 0.0f, 1.0f,
		0.0f,
		m ? m : KINE_IDENTITY_4X4,
		false, false, false,
		nullptr);
}

static math::float3 kine_dbg_xform_point(const float *m, const math::float3 &p) {
	if (!m)
		return p;
	return {
		m[0] * p.x + m[1] * p.y + m[2] * p.z + m[3],
		m[4] * p.x + m[5] * p.y + m[6] * p.z + m[7],
		m[8] * p.x + m[9] * p.y + m[10] * p.z + m[11]};
}

static void kine_dbg_trs(float cx, float cy, float cz, float sx, float sy, float sz, float *out) {
	const float m[16] = {
		sx, 0, 0, cx,
		0, sy, 0, cy,
		0, 0, sz, cz,
		0, 0, 0, 1};
	memcpy(out, m, sizeof(m));
}

static math::float3 kine_dbg_cross(const math::float3 &a, const math::float3 &b) {
	return {
		a.y * b.z - a.z * b.y,
		a.z * b.x - a.x * b.z,
		a.x * b.y - a.y * b.x};
}

static math::float3 kine_dbg_normalize(const math::float3 &v) {
	const float l = std::sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
	return l > 1e-12f ? math::float3{v.x / l, v.y / l, v.z / l} : math::float3{0, 1, 0};
}

// One world-space segment, drawn as a stretched thin cylinder.
static void kine_dbg_line(
	KineFilamentContext *ctx,
	const math::float3 &a, const math::float3 &b,
	float thickness, float r, float g, float bl) {
	const math::float3 d = b - a;
	const float len = std::sqrt(d.x * d.x + d.y * d.y + d.z * d.z);
	if (len < 1e-6f)
		return;

	const math::float3 y = d / len;
	const math::float3 ref = std::abs(y.y) < 0.99f ? math::float3{0, 1, 0} : math::float3{1, 0, 0};
	const math::float3 x = normalize(kine_dbg_cross(y, ref));
	const math::float3 z = kine_dbg_cross(x, y);
	const math::float3 mid = (a + b) * 0.5f;
	const float t = thickness > 0.0f ? thickness : KINE_DEFAULT_WIRE_THICKNESS;

	// The unit cylinder runs along Y (height 1) with diameter 1.
	const float m[16] = {
		x.x * t, y.x * len, z.x * t, mid.x,
		x.y * t, y.y * len, z.y * t, mid.y,
		x.z * t, y.z * len, z.z * t, mid.z,
		0, 0, 0, 1};
	kine_dbg_queue(ctx, kine_dbg_prim(ctx, 3), m, r, g, bl);
}

// Circle perpendicular to local axis `normalAxis` (0=X,1=Y,2=Z), shifted
// `offset` along that axis, then transformed by m.
static void kine_dbg_wire_circle(
	KineFilamentContext *ctx, const float *m,
	int normalAxis, float offset, float radius, int segments,
	float thickness, float r, float g, float b) {
	const int a = (normalAxis + 1) % 3;
	const int c = (normalAxis + 2) % 3;
	math::float3 prev{};
	for (int i = 0; i <= segments; ++i) {
		const float ang = 2.0f * (float)M_PI * (float)i / (float)segments;
		float p[3] = {0, 0, 0};
		p[normalAxis] = offset;
		p[a] = radius * std::cos(ang);
		p[c] = radius * std::sin(ang);
		const math::float3 world = kine_dbg_xform_point(m, {p[0], p[1], p[2]});
		if (i > 0)
			kine_dbg_line(ctx, prev, world, thickness, r, g, b);
		prev = world;
	}
}

static int kine_dbg_segments(int s) {
	return s <= 0 ? 32 : std::clamp(s, 8, 128);
}

static void kine_dbg_wire_mesh(
	KineFilamentContext *ctx, const KineMesh *mesh, const float *m,
	float thickness, float r, float g, float b, float featureAngleDeg) {
	if (!mesh || mesh->indices.size() < 3 || mesh->vertices.empty())
		return;

	// Weld vertices by quantized position (1/1000 unit).
	std::unordered_map<uint64_t, uint32_t> weld;
	std::vector<math::float3> pos;
	std::vector<uint32_t> remap(mesh->vertices.size());
	for (size_t i = 0; i < mesh->vertices.size(); ++i) {
		const KineVertex &v = mesh->vertices[i];
		const uint64_t qx = (uint64_t)(int64_t)std::lround(v.px * 1000.0f) & 0x1FFFFF;
		const uint64_t qy = (uint64_t)(int64_t)std::lround(v.py * 1000.0f) & 0x1FFFFF;
		const uint64_t qz = (uint64_t)(int64_t)std::lround(v.pz * 1000.0f) & 0x1FFFFF;
		const uint64_t key = (qx << 42) | (qy << 21) | qz;
		auto it = weld.find(key);
		if (it == weld.end()) {
			it = weld.emplace(key, (uint32_t)pos.size()).first;
			pos.push_back({v.px, v.py, v.pz});
		}
		remap[i] = it->second;
	}

	struct Edge {
		uint32_t a, b;
		math::float3 n;
		int count;
		bool feature;
	};
	std::unordered_map<uint64_t, Edge> edges;
	const float cosLimit = std::cos(featureAngleDeg * (float)M_PI / 180.0f);

	for (size_t i = 0; i + 2 < mesh->indices.size(); i += 3) {
		const uint32_t t[3] = {
			mesh->indices[i], mesh->indices[i + 1], mesh->indices[i + 2]};
		if (t[0] >= remap.size() || t[1] >= remap.size() || t[2] >= remap.size())
			continue;
		const uint32_t w[3] = {remap[t[0]], remap[t[1]], remap[t[2]]};
		const math::float3 n = kine_dbg_normalize(
			kine_dbg_cross(pos[w[1]] - pos[w[0]], pos[w[2]] - pos[w[0]]));

		for (int e = 0; e < 3; ++e) {
			const uint32_t ia = w[e], ib = w[(e + 1) % 3];
			if (ia == ib)
				continue;
			const uint32_t lo = std::min(ia, ib), hi = std::max(ia, ib);
			const uint64_t key = ((uint64_t)lo << 32) | hi;
			auto it = edges.find(key);
			if (it == edges.end()) {
				if (edges.size() >= KINE_MAX_WIRE_MESH_EDGES)
					continue;
				edges.emplace(key, Edge{lo, hi, n, 1, featureAngleDeg <= 0.0f});
			} else {
				Edge &ed = it->second;
				ed.count++;
				if (n.x * ed.n.x + n.y * ed.n.y + n.z * ed.n.z < cosLimit)
					ed.feature = true;
			}
		}
	}

	for (const auto &kv : edges) {
		const Edge &ed = kv.second;
		if (ed.count == 1 || ed.feature) {
			kine_dbg_line(
				ctx,
				kine_dbg_xform_point(m, pos[ed.a]),
				kine_dbg_xform_point(m, pos[ed.b]),
				thickness, r, g, b);
		}
	}
}

extern "C" {

KINE_API void Kine_Filament_DrawGizmoLine(
	KineFilamentContext *ctx,
	float ax, float ay, float az,
	float bx, float by, float bz,
	float r, float g, float b,
	float thickness) {
	if (!ctx || !ctx->engine)
		return;
	kine_dbg_line(ctx, {ax, ay, az}, {bx, by, bz}, thickness, r, g, b);
}

// points: 6 floats per segment (ax ay az bx by bz).
KINE_API void Kine_Filament_DrawGizmoLines(
	KineFilamentContext *ctx,
	const float *points,
	uint32_t segmentCount,
	float r, float g, float b,
	float thickness) {
	if (!ctx || !ctx->engine || !points)
		return;
	for (uint32_t i = 0; i < segmentCount; ++i) {
		const float *p = points + (size_t)i * 6;
		kine_dbg_line(ctx, {p[0], p[1], p[2]}, {p[3], p[4], p[5]}, thickness, r, g, b);
	}
}

// Unit cube (edge length 1, centered at origin) transformed by mat4. Put the
// size in the matrix scale. wire=false draws a solid cube.
KINE_API void Kine_Filament_DrawGizmoCube(
	KineFilamentContext *ctx,
	const float *mat4,
	float r, float g, float b,
	bool wire,
	float thickness) {
	if (!ctx || !ctx->engine)
		return;
	if (!wire) {
		kine_dbg_queue(ctx, kine_dbg_prim(ctx, 0), mat4, r, g, b);
		return;
	}
	math::float3 c[8];
	for (int i = 0; i < 8; ++i) {
		c[i] = kine_dbg_xform_point(mat4, {(i & 1) ? 0.5f : -0.5f,
										   (i & 2) ? 0.5f : -0.5f,
										   (i & 4) ? 0.5f : -0.5f});
	}
	static const int edges[12][2] = {
		{0, 1}, {2, 3}, {4, 5}, {6, 7}, {0, 2}, {1, 3}, {4, 6}, {5, 7}, {0, 4}, {1, 5}, {2, 6}, {3, 7}};
	for (const auto &e : edges)
		kine_dbg_line(ctx, c[e[0]], c[e[1]], thickness, r, g, b);
}

KINE_API void Kine_Filament_DrawGizmoSphere(
	KineFilamentContext *ctx,
	float cx, float cy, float cz,
	float radius,
	float r, float g, float b,
	bool wire,
	float thickness,
	int segments) {
	if (!ctx || !ctx->engine || radius <= 0.0f)
		return;
	if (!wire) {
		float m[16];
		kine_dbg_trs(cx, cy, cz, radius * 2.0f, radius * 2.0f, radius * 2.0f, m);
		kine_dbg_queue(ctx, kine_dbg_prim(ctx, 1), m, r, g, b);
		return;
	}
	float m[16];
	kine_dbg_trs(cx, cy, cz, 1.0f, 1.0f, 1.0f, m);
	const int s = kine_dbg_segments(segments);
	for (int axis = 0; axis < 3; ++axis)
		kine_dbg_wire_circle(ctx, m, axis, 0.0f, radius, s, thickness, r, g, b);
}

// Unit cylinder (diameter 1, height 1 along local Y, centered) transformed by mat4.
KINE_API void Kine_Filament_DrawGizmoCylinder(
	KineFilamentContext *ctx,
	const float *mat4,
	float r, float g, float b,
	bool wire,
	float thickness,
	int segments) {
	if (!ctx || !ctx->engine)
		return;
	if (!wire) {
		kine_dbg_queue(ctx, kine_dbg_prim(ctx, 2), mat4, r, g, b);
		return;
	}
	const int s = kine_dbg_segments(segments);
	kine_dbg_wire_circle(ctx, mat4, 1, 0.5f, 0.5f, s, thickness, r, g, b);
	kine_dbg_wire_circle(ctx, mat4, 1, -0.5f, 0.5f, s, thickness, r, g, b);
	for (int i = 0; i < 4; ++i) {
		const float ang = (float)M_PI * 0.5f * (float)i;
		const float x = 0.5f * std::cos(ang), z = 0.5f * std::sin(ang);
		kine_dbg_line(ctx,
					  kine_dbg_xform_point(mat4, {x, -0.5f, z}),
					  kine_dbg_xform_point(mat4, {x, 0.5f, z}),
					  thickness, r, g, b);
	}
}

// Any mesh from CreateMesh / CreateCustomMesh / CreateMeshFromPath, drawn solid
// and unlit in a single flat color.
KINE_API void Kine_Filament_DrawGizmoMesh(
	KineFilamentContext *ctx,
	KineFilamentMesh *mesh,
	const float *mat4,
	float r, float g, float b) {
	if (!ctx || !ctx->engine || !mesh)
		return;
	KineMesh *m = reinterpret_cast<KineMesh *>(mesh);
	if (!m->vb || !m->ib)
		return;
	kine_dbg_queue(ctx, m, mat4, r, g, b);
}

// Any mesh drawn as a wireframe (unique triangle edges, capped at 16384 per
// call). Skinned meshes are drawn in their bind pose.
KINE_API void Kine_Filament_DrawGizmoWireMesh(
	KineFilamentContext *ctx,
	KineFilamentMesh *mesh,
	const float *mat4,
	float r, float g, float b,
	float thickness,
	float featureAngleDeg) {
	if (!ctx || !ctx->engine || !mesh)
		return;
	kine_dbg_wire_mesh(ctx, reinterpret_cast<const KineMesh *>(mesh), mat4,
					   thickness, r, g, b, featureAngleDeg);
}

} // extern "C"

extern "C" {

KINE_API int Kine_Filament_PickGizmo(
	KineFilamentContext *ctx,
	KineFilamentGizmo *gizmo,
	float *mat4,
	float screenX,
	float screenY) {
	if (!ctx || !ctx->camera || !gizmo || !mat4)
		return KINE_GIZMO_AXIS_NONE;

	const KineGizmoFrame frame = kine_gizmo_frame(ctx, mat4, gizmo->type);
	const KineGizmoScreenPoint center = kine_gizmo_project(ctx, frame.model, {0.0, 0.0, 0.0});
	if (center.valid && gizmo->axes.center &&
		std::hypot((double)screenX - center.x, (double)screenY - center.y) <= 10.0) {
		return KINE_GIZMO_AXIS_CENTER;
	}

	for (const KineGizmoPlane &plane : KINE_GIZMO_PLANES) {
		if (!gizmo->axes.planes[plane.meshIndex])
			continue;
		KineGizmoScreenPoint corners[4];
		for (int i = 0; i < 4; ++i) {
			corners[i] = kine_gizmo_project(
				ctx, frame.model, kine_gizmo_plane_corner(plane, i, KINE_GIZMO_PLANE_HALF));
		}
		if (kine_gizmo_point_in_quad(screenX, screenY, corners[0], corners[1], corners[2], corners[3])) {
			return plane.id;
		}
	}

	int closestAxis = KINE_GIZMO_AXIS_NONE;
	double closestDistance = 12.0;
	for (int axis = KINE_GIZMO_AXIS_X; axis <= KINE_GIZMO_AXIS_Z; ++axis) {
		if (axis == frame.hiddenAxis)
			continue;
		double distance = std::numeric_limits<double>::max();
		if (gizmo->type == KINE_GIZMO_ROTATE) {
			const double radius = axis == KINE_GIZMO_AXIS_X ? 0.85 : (axis == KINE_GIZMO_AXIS_Y ? 0.92 : 0.99);
			KineGizmoScreenPoint previous;
			constexpr int segments = 64;
			for (int i = 0; i <= segments; ++i) {
				const double angle = 2.0 * M_PI * i / segments;
				math::double3 point;
				if (axis == KINE_GIZMO_AXIS_X)
					point = {0.0, radius * cos(angle), radius * sin(angle)};
				else if (axis == KINE_GIZMO_AXIS_Y)
					point = {radius * cos(angle), 0.0, radius * sin(angle)};
				else
					point = {radius * cos(angle), radius * sin(angle), 0.0};
				const KineGizmoScreenPoint current = kine_gizmo_project(ctx, frame.model, point);
				if (i > 0) {
					distance = std::min(distance,
										kine_gizmo_segment_distance(screenX, screenY, previous, current));
				}
				previous = current;
			}
		} else {
			const KineGizmoScreenPoint start = kine_gizmo_project(
				ctx, frame.model, kine_gizmo_axis_point(axis, 0.08));
			const KineGizmoScreenPoint end = kine_gizmo_project(
				ctx, frame.model, kine_gizmo_axis_point(axis, 1.30));
			distance = kine_gizmo_segment_distance(screenX, screenY, start, end);
		}

		if (distance < closestDistance) {
			closestDistance = distance;
			closestAxis = axis;
		}
	}
	return closestAxis;
}

KINE_API float Kine_Filament_GetGizmoDragDelta(
	KineFilamentContext *ctx,
	KineFilamentGizmo *gizmo,
	float *mat4,
	int axis,
	float startX,
	float startY,
	float currentX,
	float currentY) {
	if (!ctx || !ctx->camera || !gizmo || !mat4)
		return 0.0f;
	if (gizmo->type == KINE_GIZMO_ROTATE)
		return kine_gizmo_rotate_delta(ctx, mat4, axis, startX, startY, currentX, currentY);
	if (axis == KINE_GIZMO_AXIS_CENTER || kine_gizmo_plane(axis))
		return ((currentX - startX) - (currentY - startY)) * 0.01f;

	// Project through the unscaled model: one world unit then maps to its true
	// on-screen length, so the handle tracks the cursor 1:1 at any distance
	// instead of lagging behind once the constant-screen-size scale grows.
	const math::mat4 model = kine_gizmo_model_matrix(mat4);
	const KineGizmoScreenPoint origin = kine_gizmo_project(ctx, model, {0.0, 0.0, 0.0});
	const KineGizmoScreenPoint endpoint = kine_gizmo_project(
		ctx, model, kine_gizmo_axis_point(axis, 1.0));
	if (!origin.valid || !endpoint.valid)
		return 0.0f;

	const double axisX = endpoint.x - origin.x;
	const double axisY = endpoint.y - origin.y;
	const double pixelsPerUnit = std::hypot(axisX, axisY);
	if (pixelsPerUnit <= 1e-6)
		return 0.0f;
	const double mouseX = currentX - startX;
	const double mouseY = currentY - startY;
	return (float)((mouseX * axisX + mouseY * axisY) / (pixelsPerUnit * pixelsPerUnit));
}

KINE_API int Kine_Filament_GetGizmoPlaneDragDelta(
	KineFilamentContext *ctx,
	KineFilamentGizmo *gizmo,
	float *mat4,
	int axis,
	float startX,
	float startY,
	float currentX,
	float currentY,
	float *outFirst,
	float *outSecond) {
	if (outFirst)
		*outFirst = 0.0f;
	if (outSecond)
		*outSecond = 0.0f;
	if (!ctx || !ctx->camera || !gizmo || !mat4 || !outFirst || !outSecond)
		return 0;

	const KineGizmoPlane *plane = kine_gizmo_plane(axis);
	if (!plane)
		return 0;
	if (gizmo->type == KINE_GIZMO_ROTATE)
		return 0;

	// Unscaled model again, so plane drags also track the cursor 1:1.
	const math::mat4 model = kine_gizmo_model_matrix(mat4);
	const KineGizmoScreenPoint origin = kine_gizmo_project(ctx, model, {0.0, 0.0, 0.0});
	const KineGizmoScreenPoint first = kine_gizmo_project(
		ctx, model, kine_gizmo_axis_point(plane->first, 1.0));
	const KineGizmoScreenPoint second = kine_gizmo_project(
		ctx, model, kine_gizmo_axis_point(plane->second, 1.0));
	if (!origin.valid || !first.valid || !second.valid)
		return 0;

	const double ax = first.x - origin.x;
	const double ay = first.y - origin.y;
	const double bx = second.x - origin.x;
	const double by = second.y - origin.y;
	const double determinant = ax * by - ay * bx;
	if (std::abs(determinant) <= 1e-6)
		return 0;

	const double mouseX = (double)currentX - startX;
	const double mouseY = (double)currentY - startY;
	*outFirst = (float)((mouseX * by - mouseY * bx) / determinant);
	*outSecond = (float)((ax * mouseY - ay * mouseX) / determinant);
	return 1;
}

KINE_API void Kine_Filament_DrawGizmo(
	KineFilamentContext *ctx,
	KineFilamentGizmo *gizmo,
	float *mat4,
	int hoveredAxis,
	int selectedAxis) {
	if (!ctx || !gizmo || !mat4)
		return;

	KineGizmoFrame frame = kine_gizmo_frame(ctx, mat4, gizmo->type);

	struct AxisEntry {
		int id;
		KineMesh *mesh;
	};
	AxisEntry entries[7] = {
		{KINE_GIZMO_AXIS_X, gizmo->axes.x},
		{KINE_GIZMO_AXIS_Y, gizmo->axes.y},
		{KINE_GIZMO_AXIS_Z, gizmo->axes.z},
		{KINE_GIZMO_AXIS_CENTER, gizmo->axes.center},
		{KINE_GIZMO_AXIS_XY, gizmo->axes.planes[0]},
		{KINE_GIZMO_AXIS_YZ, gizmo->axes.planes[1]},
		{KINE_GIZMO_AXIS_XZ, gizmo->axes.planes[2]},
	};

	for (const AxisEntry &entry : entries) {
		if (!entry.mesh)
			continue;

		if (entry.id == frame.hiddenAxis)
			continue;

		float r = 1.0f, g = 1.0f, b = 1.0f;
		kine_gizmo_axis_color(entry.id, r, g, b);

		const bool isActive = (entry.id == hoveredAxis || entry.id == selectedAxis);
		const bool somethingActive = (hoveredAxis != KINE_GIZMO_AXIS_NONE ||
									  selectedAxis != KINE_GIZMO_AXIS_NONE);
		if (somethingActive && !isActive) {
			r *= 0.55f;
			g *= 0.55f;
			b *= 0.55f;
		}
		if (isActive) {
			r = 1.0f;
			g = 0.85f;
			b = 0.15f;
		}

		const float *handle = isActive ? frame.boosted : frame.scaled;

		Kine_Filament_DrawMeshEx(
			ctx, (KineFilamentMesh *)entry.mesh, KINE_MAT_GIZMO,
			r, g, b,
			1.0f, 0.0f, 1.0f,
			0.0f,
			const_cast<float *>(handle),
			false, false, false,
			nullptr);
	}
}
}

extern "C" {

KINE_API void Kine_Filament_ReadPixels(KineFilamentContext *ctx, void *outPixels) {
#if KINE_FILAMENT_USE_VULKAN
#if KINE_FILAMENT_ENABLE_VULKAN_READBACK
	if (!ctx || !ctx->engine || !outPixels || ctx->readbackPixels.empty())
		return;
	ctx->engine->pumpMessageQueues();
	if (!ctx->readbackReady)
		return;
	size_t bytes = (size_t)ctx->width * (size_t)ctx->height * 4;
	if (ctx->readbackPixels.size() < bytes)
		return;
	memcpy(outPixels, ctx->readbackPixels.data(), bytes);
	ctx->readbackReady = false;
#else
	(void)ctx;
	(void)outPixels;
	static bool warned = false;
	if (!warned) {
		fprintf(stderr, "[Kine] Filament Vulkan readback is disabled. Build with KINE_FILAMENT_VULKAN_READBACK=ON for debugging only.\n");
		warned = true;
	}
#endif
#else
	if (!ctx || !outPixels || ctx->readFboId == 0)
		return;
	if (!kine_glBindFramebuffer)
		return;

	kine_glBindFramebuffer(GL_FRAMEBUFFER, (GLuint)ctx->readFboId);
	glReadPixels(0, 0, (GLsizei)ctx->width, (GLsizei)ctx->height,
				 GL_RGBA, GL_UNSIGNED_BYTE, outPixels);
	kine_glBindFramebuffer(GL_FRAMEBUFFER, 0);
#endif
}

KINE_API int Kine_Filament_GetWidth(KineFilamentContext *ctx) {
	return ctx ? ctx->width : 0;
}

KINE_API int Kine_Filament_GetHeight(KineFilamentContext *ctx) {
	return ctx ? ctx->height : 0;
}

static thread_local std::string kine_filament_shader_error;

KINE_API KineFilamentShader *Kine_Filament_Shader_Create(
	KineFilamentContext *ctx, const char *materialSource) {
#if defined(__ANDROID__)
	(void)ctx;
	(void)materialSource;
	kine_filament_shader_error = "Runtime material compilation is unavailable on Android";
	return nullptr;
#else
	kine_filament_shader_error.clear();
	if (!ctx || !ctx->engine || !materialSource || !*materialSource) {
		kine_filament_shader_error = "Filament material source is empty or no rendering context is available";
		return nullptr;
	}

	static std::once_flag filamatInit;
	std::call_once(filamatInit, [] { filamat::MaterialBuilder::init(); });

	filamat::MaterialBuilder builder;
	builder.platform(filamat::MaterialBuilder::Platform::DESKTOP)
#if KINE_FILAMENT_USE_VULKAN
		.targetApi(filamat::MaterialBuilder::TargetApi::VULKAN)
#else
		.targetApi(filamat::MaterialBuilder::TargetApi::OPENGL)
#endif
		.optimization(filamat::MaterialBuilder::Optimization::PERFORMANCE)
		.materialSource(materialSource);

	const size_t sourceLength = strlen(materialSource);
	auto mutableSource = std::make_unique<char[]>(sourceLength + 1);
	memcpy(mutableSource.get(), materialSource, sourceLength + 1);
	std::unique_ptr<const char[]> parserSource(mutableSource.release());
	ssize_t parserLength = static_cast<ssize_t>(sourceLength);
	KineRuntimeMaterialConfig parserConfig;
	matp::MaterialParser parser;
	utils::Status parseStatus = parser.parse(builder, parserConfig, parserLength, parserSource);
	if (!parseStatus.isOk()) {
		const std::string_view message = parseStatus.getMessage();
		kine_filament_shader_error = message.empty()
										 ? "Filamat could not parse the material source"
										 : std::string(message);
		return nullptr;
	}

	filamat::Package package = builder.build(ctx->engine->getJobSystem());
	if (!package.isValid()) {
		kine_filament_shader_error = "Filamat failed to compile the material source";
		return nullptr;
	}

	Material *material = Material::Builder()
							 .package(package.getData(), package.getSize())
							 .build(*ctx->engine);
	if (!material) {
		kine_filament_shader_error = "Filament rejected the compiled material package";
		return nullptr;
	}

	auto *shader = new KineFilamentShader();
	shader->ctx = ctx;
	shader->material = material;
	ctx->runtimeShaders.insert(shader);
	return shader;
#endif
}

KINE_API void Kine_Filament_Shader_Destroy(KineFilamentShader *shader) {
	if (!shader)
		return;
	KineFilamentContext *ctx = shader->ctx;
	if (ctx && ctx->engine) {
		if (ctx->globalShader == shader) {
			kine_switch_global_shader(ctx, nullptr);
		}
		if (ctx->postProcessShader == shader) {
			kine_destroy_post_process_pipeline(ctx);
			ctx->postProcessShader = nullptr;
		}

		kine_destroy_built_batches(ctx);
		ctx->retainedLists.clear();
		kine_viewport_destroy_shader_batches(ctx, shader);
		for (KineFilamentInstanceBatch *batch : ctx->instanceBatches) {
			if (!batch || batch->key.shader != shader)
				continue;
			kine_destroy_instance_batch_chunks(batch);
			batch->key.shader = nullptr;
			kine_rebuild_instance_batch(batch);
		}
		ctx->runtimeShaders.erase(shader);
		if (shader->material) {
			ctx->engine->flushAndWait();
			ctx->engine->destroy(shader->material);
		}
		for (const auto &[name, texture] : shader->textures) ctx->engine->destroy(texture);
	}
	delete shader;
}

static void kine_refresh_shader_instances(KineFilamentShader *shader) {
	KineFilamentContext *ctx = shader->ctx;
	if (ctx && ctx->engine) {
		for (auto &[key, batch] : ctx->builtBatches) {
			if (key.shader == shader || (!key.shader && ctx->globalShader == shader)) {
				for (KineBuiltBatch &chunk : batch.chunks) {
					if (chunk.materialInstance) {
						kine_apply_material_params(ctx, chunk.materialInstance, key);
					}
				}
			}
		}
		for (KineFilamentInstanceBatch *batch : ctx->instanceBatches) {
			if (!batch || (batch->key.shader != shader &&
						   (batch->key.shader || ctx->globalShader != shader))) {
				continue;
			}
			for (KineBuiltBatch &chunk : batch->chunks) {
				if (chunk.materialInstance) {
					kine_apply_material_params(ctx, chunk.materialInstance, batch->key);
				}
			}
		}
		if (ctx->postProcessShader == shader && ctx->postMaterialInstance) {
			kine_apply_shader_uniforms(ctx->postMaterialInstance, shader);
		}
		kine_viewport_update_shader_uniforms(ctx, shader);
	}
}

KINE_API bool Kine_Filament_Shader_SetUniform(
	KineFilamentShader *shader, const char *name, const float *values, int valueCount) {
	if (!shader || !shader->material || !name || !*name || !values || valueCount < 1 || valueCount > 4) {
		return false;
	}
	std::vector<Material::ParameterInfo> parameters(shader->material->getParameterCount());
	shader->material->getParameters(parameters.data(), parameters.size());
	const auto parameter = std::find_if(parameters.begin(), parameters.end(),
		[name](const Material::ParameterInfo &p) { return strcmp(p.name, name) == 0; });
	const Material::ParameterType types[] = {Material::ParameterType::FLOAT,
		Material::ParameterType::FLOAT2, Material::ParameterType::FLOAT3, Material::ParameterType::FLOAT4};
	if (parameter == parameters.end() || parameter->isSampler || parameter->isSubpass ||
		parameter->count != 1 || parameter->type != types[valueCount - 1])
		return false;
	shader->uniforms[name] = std::vector<float>(values, values + valueCount);
	kine_refresh_shader_instances(shader);
	return true;
}

KINE_API bool Kine_Filament_SetGlobalShader(KineFilamentContext *ctx, KineFilamentShader *shader) {
	return kine_switch_global_shader(ctx, shader);
}

KINE_API bool Kine_Filament_Shader_SetTextureFromPixels(
	KineFilamentShader *shader, const char *name, int width, int height,
	int rowBytes, const void *pixelsRGBA8, bool srgb) {
	if (!shader || !shader->material || !shader->ctx || !shader->ctx->engine ||
		!name || !*name || width <= 0 || height <= 0 || width > INT32_MAX / 4 ||
		rowBytes < width * 4 || !pixelsRGBA8) return false;
	std::vector<Material::ParameterInfo> parameters(shader->material->getParameterCount());
	shader->material->getParameters(parameters.data(), parameters.size());
	const auto parameter = std::find_if(parameters.begin(), parameters.end(),
		[name](const Material::ParameterInfo &p) { return strcmp(p.name, name) == 0; });
	if (parameter == parameters.end() || !parameter->isSampler ||
		parameter->samplerType != Material::SamplerType::SAMPLER_2D) return false;
	auto *texture = kine_create_uploaded_rgba_texture(shader->ctx->engine, width, height, rowBytes, pixelsRGBA8, srgb, true);
	if (!texture) return false;
	auto previous = shader->textures.find(name);
	Texture *old = previous == shader->textures.end() ? nullptr : previous->second;
	shader->textures[name] = texture;
	kine_refresh_shader_instances(shader);
	if (old) shader->ctx->engine->destroy(old);
	return true;
}

KINE_API bool Kine_Filament_Shader_SetGeometryOptions(KineFilamentShader *shader, int subdivisions, float boundsPadding) {
	if (!shader || !shader->ctx || !shader->ctx->engine || !std::isfinite(boundsPadding) || boundsPadding < 0) return false;
	subdivisions=std::clamp(subdivisions,0,4);
	if (shader->subdivisionLevel==subdivisions && shader->boundsPadding==boundsPadding) return true;
	shader->subdivisionLevel=subdivisions;
	shader->boundsPadding=boundsPadding;
	auto *ctx=shader->ctx;
	// Geometry and bounds are retained along with material instances. Rebuild
	// them on an option change even when all authored transforms stay still.
	kine_destroy_built_batches(ctx);
	ctx->retainedLists.clear();
	kine_viewport_destroy_shader_batches(ctx,shader);
	return true;
}

KINE_API void Kine_Filament_Shader_TransferTextures(KineFilamentShader *source,KineFilamentShader *destination) {
	if (!source || !destination || source==destination || source->ctx!=destination->ctx || !destination->material) return;
	std::vector<Material::ParameterInfo> parameters(destination->material->getParameterCount());
	destination->material->getParameters(parameters.data(),parameters.size());
	for (auto it=source->textures.begin();it!=source->textures.end();) {
		const bool accepts=std::any_of(parameters.begin(),parameters.end(),[&](const Material::ParameterInfo &p) {
			return p.isSampler && p.samplerType==Material::SamplerType::SAMPLER_2D && it->first==p.name;
		});
		if (accepts && destination->textures.find(it->first)==destination->textures.end()) {
			destination->textures.emplace(it->first,it->second);
			it=source->textures.erase(it);
		} else ++it;
	}
}

KINE_API bool Kine_Filament_Shader_HasTexture(KineFilamentShader *shader,const char *name) {
	return shader && name && shader->textures.find(name)!=shader->textures.end();
}

KINE_API bool Kine_Filament_SetPostProcessShader(KineFilamentContext *ctx, KineFilamentShader *shader) {
	kine_filament_shader_error.clear();
	if (!ctx || (shader && shader->ctx != ctx)) {
		kine_filament_shader_error = "Post-process material belongs to a different Filament context";
		return false;
	}
	kine_destroy_post_process_pipeline(ctx);
	ctx->postProcessShader = shader;
	if (!shader)
		return true;
	if (!shader->material || !shader->material->isSampler("inputTexture")) {
		ctx->postProcessShader = nullptr;
		kine_filament_shader_error = "Post-process material must declare sampler2d inputTexture";
		return false;
	}
	if (!kine_build_post_process_pipeline(ctx)) {
		ctx->postProcessShader = nullptr;
		kine_filament_shader_error = "Could not create the fullscreen Filament post-process pass";
		return false;
	}
	return true;
}

KINE_API const char *Kine_Filament_Shader_GetLastError(void) {
	return kine_filament_shader_error.c_str();
}

// ---------------------------------------------------------------------------
// Ray path tracer toggle (render mode 1 = Filament, 2 = Ray)
// ---------------------------------------------------------------------------

#if KINE_WITH_RAY
static std::string kine_ray_error_text;

// Ray neither creates an instance nor selects a queue family when it is handed
// an external device: it uses the first family that supports graphics and
// compute, and queue index 0 of it. Report what that resolves to so a mismatch
// with the family Filament enabled queues for is visible instead of silent.
static void kine_ray_report_queues(
	const KineFilamentVulkanBackend &backend, KineRayDevice &device) {
#if KINE_FILAMENT_USE_VULKAN
	auto get_instance_proc_addr =
		reinterpret_cast<PFN_vkGetInstanceProcAddr>(backend.getInstanceProcAddr);
	if (!get_instance_proc_addr)
		return;
	auto vkGetPhysicalDeviceQueueFamilyProperties =
		reinterpret_cast<PFN_vkGetPhysicalDeviceQueueFamilyProperties>(
			get_instance_proc_addr(reinterpret_cast<VkInstance>(backend.instance),
								   "vkGetPhysicalDeviceQueueFamilyProperties"));
	if (!vkGetPhysicalDeviceQueueFamilyProperties)
		return;

	uint32_t familyCount = 0;
	vkGetPhysicalDeviceQueueFamilyProperties(
		reinterpret_cast<VkPhysicalDevice>(backend.physicalDevice), &familyCount, nullptr);
	if (familyCount == 0)
		return;
	std::vector<VkQueueFamilyProperties> families(familyCount);
	vkGetPhysicalDeviceQueueFamilyProperties(
		reinterpret_cast<VkPhysicalDevice>(backend.physicalDevice), &familyCount, families.data());

	uint32_t rayFamily = familyCount;
	for (uint32_t i = 0; i < familyCount; ++i) {
		const VkQueueFlags required = VK_QUEUE_GRAPHICS_BIT | VK_QUEUE_COMPUTE_BIT;
		if ((families[i].queueFlags & required) == required) {
			rayFamily = i;
			break;
		}
	}
	if (rayFamily < familyCount) {
		device.graphicsQueueCount = families[rayFamily].queueCount;
	}
	if (rayFamily != backend.graphicsQueueFamilyIndex) {
		fprintf(stderr,
			"[Kine] Ray picks queue family %u but Filament created queues in family %u; "
			"Ray may fail to acquire its queue\n",
			rayFamily,
			backend.graphicsQueueFamilyIndex);
	}
#else
	(void)backend;
	(void)device;
#endif
}
#endif

KINE_API bool Kine_Filament_NewRay(KineFilamentContext *ctx, int width, int height) {
#if KINE_WITH_RAY
	if (!ctx || !ctx->engine) {
		kine_ray_error_text = "no Filament context";
		return false;
	}
	if (ctx->rayState) {
		return true;
	}

	KineFilamentVulkanBackend backend{};
	if (!Kine_Filament_GetVulkanBackend(ctx, &backend)) {
		kine_ray_error_text =
			"Ray needs the Vulkan backend and a Filament engine running on it";
		return false;
	}
	KineRayDevice device{};
	device.instance = backend.instance;
	device.physicalDevice = backend.physicalDevice;
	device.device = backend.device;
	device.getInstanceProcAddr = backend.getInstanceProcAddr;
	device.graphicsQueueFamilyIndex = backend.graphicsQueueFamilyIndex;
	device.graphicsQueueCount = 1;
	kine_ray_report_queues(backend, device);

	KineRayState *state = kine_ray_create(device, width, height);
	if (!state) {
		kine_ray_error_text = kine_ray_last_error();
		fprintf(stderr, "[Kine] Ray unavailable: %s\n", kine_ray_error_text.c_str());
		return false;
	}

	ctx->rayState = state;
	kine_ray_set_properties(state, ctx->rayProperties);
	kine_ray_error_text.clear();
	fprintf(stderr, "[Kine] Ray path tracer ready (%dx%d), render mode is still %d\n",
			width, height, ctx->renderMode);
	return true;
#else
	(void)ctx;
	(void)width;
	(void)height;
	return false;
#endif
}

KINE_API void Kine_Filament_DestroyRay(KineFilamentContext *ctx) {
#if KINE_WITH_RAY
	if (!ctx)
		return;
	if (ctx->engine) {
		kine_ray_display_destroy(ctx);
	}
	if (ctx->rayState) {
		kine_ray_destroy((KineRayState *)ctx->rayState);
		ctx->rayState = nullptr;
	}
	ctx->rayDraws.clear();
	ctx->rayFrameDraws.clear();
	ctx->rayIndexCache.clear();
	ctx->renderMode = KINE_RENDER_MODE_FILAMENT;
#else
	(void)ctx;
#endif
}

KINE_API bool Kine_Filament_SetRenderMode(KineFilamentContext *ctx, int mode) {
	if (!ctx) {
		return false;
	}
	if (mode != KINE_RENDER_MODE_FILAMENT && mode != KINE_RENDER_MODE_RAY) {
#if KINE_WITH_RAY
		kine_ray_error_text = "render mode must be 1 (Filament) or 2 (Ray)";
#endif
		return false;
	}
	if (mode == KINE_RENDER_MODE_RAY) {
#if KINE_WITH_RAY
		if (!ctx->rayState) {
			kine_ray_error_text =
				"Ray is not initialized; call Kine_Filament_NewRay before switching modes";
			return false;
		}
#else
		return false;
#endif
	}
	ctx->renderMode = mode;
#if KINE_WITH_RAY
	// The path tracer accumulates samples; coming back to Ray must start over.
	if (mode == KINE_RENDER_MODE_RAY) {
		kine_ray_error_text.clear();
	}
#endif
	return true;
}

KINE_API int Kine_Filament_GetRenderMode(KineFilamentContext *ctx) {
	return ctx ? ctx->renderMode : 0;
}

KINE_API bool Kine_Filament_HasRay(KineFilamentContext *ctx) {
	return ctx && ctx->rayState != nullptr;
}

KINE_API bool Kine_Ray_SetProperties(KineFilamentContext *ctx, const KineRayProperties *properties) {
	if (!ctx) {
		return false;
	}
#if KINE_WITH_RAY
	ctx->rayProperties = properties ? kine_ray_sanitize_properties(*properties)
									: kine_ray_default_properties();
	kine_ray_error_text.clear();
	if (ctx->rayState &&
		!kine_ray_set_properties((KineRayState *)ctx->rayState, ctx->rayProperties)) {
		kine_ray_error_text = kine_ray_last_error();
		return false;
	}
	return true;
#else
	(void)properties;
	return false;
#endif
}

KINE_API bool Kine_Ray_GetProperties(KineFilamentContext *ctx, KineRayProperties *outProperties) {
	if (!ctx || !outProperties) {
		return false;
	}
#if KINE_WITH_RAY
	*outProperties = ctx->rayProperties;
	return true;
#else
	*outProperties = KineRayProperties{};
	return false;
#endif
}

KINE_API const char *Kine_Filament_GetRayError(void) {
#if KINE_WITH_RAY
	return kine_ray_error_text.c_str();
#else
	return "this build does not include the Ray path tracer";
#endif
}
}

#include "kine_viewport.inc"
