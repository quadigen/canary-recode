#ifndef KINE_FILAMENT_SHIM_H
#define KINE_FILAMENT_SHIM_H

#include "kine_render_shim_export.h"
#include <stddef.h>

#ifndef __cplusplus
#include <stdbool.h>
#endif
#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>

typedef struct KineFilamentContext KineFilamentContext;
typedef struct KineFilamentMesh KineFilamentMesh;
typedef struct KineFilamentMeshData KineFilamentMeshData;
typedef struct KineFilamentTex KineFilamentTex;
typedef struct KineFilamentInstanceBatch KineFilamentInstanceBatch;
typedef struct KineFilamentShader KineFilamentShader;
typedef struct KineFilamentShaderCompile KineFilamentShaderCompile;

typedef struct KineFilamentWaterParams {
    float speed;
    float strength;
    float octaves;
    float height;
    float waveScale;
    float foamAmount;
    float absorptionR, absorptionG, absorptionB;
    float clearCoat;
    float clearCoatRoughness;
} KineFilamentWaterParams;

KINE_API void Kine_Filament_SetWaterParams(KineFilamentContext *ctx, const KineFilamentWaterParams *params);
KINE_API void Kine_Filament_SetWaterTime(KineFilamentContext *ctx, float time);
KINE_API bool Kine_Filament_GetWaterParams(KineFilamentContext *ctx, KineFilamentWaterParams *out);

/* Runtime Filamat surface materials. Source is a complete .mat material definition. */
KINE_API KineFilamentShader *Kine_Filament_Shader_Create(KineFilamentContext *ctx, const char *materialSource);
KINE_API KineFilamentShaderCompile *Kine_Filament_Shader_CompileStart(const char *source);
KINE_API bool Kine_Filament_Shader_CompilePoll(KineFilamentContext *ctx, KineFilamentShaderCompile *job, KineFilamentShader **shader);
KINE_API void Kine_Filament_Shader_CompileRelease(KineFilamentShaderCompile *job);
KINE_API KineFilamentShader *Kine_Filament_Shader_ResolveFade(KineFilamentShader *shader);
KINE_API void Kine_Filament_Shader_Destroy(KineFilamentShader *shader);
KINE_API bool Kine_Filament_Shader_SetUniform(
	KineFilamentShader *shader, const char *name, const float *values, int valueCount);
/* Uploads an owned, repeating sampler2d. Color maps use sRGB; data maps use linear RGBA8. */
KINE_API bool Kine_Filament_Shader_SetTextureFromPixels(
	KineFilamentShader *shader, const char *name, int width, int height,
	int rowBytes, const void *pixelsRGBA8, bool srgb);
KINE_API bool Kine_Filament_Shader_SetGeometryOptions(KineFilamentShader *shader, int subdivisions, float boundsPadding);
KINE_API void Kine_Filament_Shader_TransferTextures(KineFilamentShader *source, KineFilamentShader *destination);
KINE_API bool Kine_Filament_Shader_HasTexture(KineFilamentShader *shader, const char *name);
KINE_API bool Kine_Filament_SetGlobalShader(KineFilamentContext *ctx, KineFilamentShader *shader);
/* Applies a surface-domain Filamat material as a fullscreen pass. The material
   must declare a sampler2d parameter named inputTexture. */
KINE_API bool Kine_Filament_SetPostProcessShader(KineFilamentContext *ctx, KineFilamentShader *shader);
KINE_API const char *Kine_Filament_Shader_GetLastError(void);

#define KINE_FILAMENT_DRAW_CAST_SHADOWS (1u << 0)
#define KINE_FILAMENT_DRAW_RECEIVE_SHADOWS (1u << 1)
#define KINE_FILAMENT_DRAW_CULLING (1u << 2)

/* Packed frame-submission item used by Kine_Filament_DrawMeshList.
   Keep this layout in sync with filament/structs.luau. */
typedef struct KineFilamentDrawItem {
	KineFilamentMesh *mesh;
	KineFilamentTex *tex;
	float transform[16];
	float r;
	float g;
	float b;
	float param1;
	float param2;
	float param3;
	float transmission;
	int32_t materialKind;
	uint32_t flags;
	uint32_t reserved; // Optional opacity encoded as float bits for Water and ForceField. Zero uses the default.
	KineFilamentShader *shader;
} KineFilamentDrawItem;

typedef struct KineFilamentParticleItem {
	float transform[16];
	uint8_t r;
	uint8_t g;
	uint8_t b;
	uint8_t a;
} KineFilamentParticleItem;

typedef struct KineGLTextureInfo {
	unsigned int id;
	int width;
	int height;
	int mipmaps;
	int format;
} KineGLTextureInfo;

typedef struct KineFilamentVulkanBackend {
	void *instance;		  /* VkInstance */
	void *physicalDevice; /* VkPhysicalDevice */
	void *device;		  /* VkDevice */
	void *queue;		  /* VkQueue */
	uint32_t graphicsQueueFamilyIndex;
	uint32_t maxApiVersion;	   /* 0 = let Skia infer/default */
	void *getInstanceProcAddr; /* PFN_vkGetInstanceProcAddr */
	void *getDeviceProcAddr;   /* PFN_vkGetDeviceProcAddr */
} KineFilamentVulkanBackend;

// ---------------------------------------------------------------------------
// Material kinds for Kine_Filament_DrawMeshEx's materialKind parameter.
// Keep in sync with the KineMaterialKind enum in kine_filament_shim.cpp.
// ---------------------------------------------------------------------------
#define KINE_MAT_DEFAULT 0
#define KINE_MAT_GLASS 1
#define KINE_MAT_NEON 2
#define KINE_MAT_WATER 3
#define KINE_MAT_OUTLINE 4
#define KINE_MAT_GIZMO 5
#define KINE_MAT_PARTICLE 6
#define KINE_MAT_TERRAIN 7

// Highlight fill and outline. Each comes in a depth-tested and an
// AlwaysOnTop variant because Filament bakes depthCulling into the material,
// so DepthMode.AlwaysOnTop needs a separate material rather than a flag.
// Order matters: kine_update_batches sorts by materialKind, and the outline
// shell must be queued before the fill that covers its interior.
#define KINE_MAT_HIGHLIGHT_OUTLINE 8
#define KINE_MAT_HIGHLIGHT_FILL 9
#define KINE_MAT_HIGHLIGHT_OUTLINE_TOP 10
#define KINE_MAT_HIGHLIGHT_FILL_TOP 11

// Selected geometry for the screen-space Highlight outline. Mask draws render
// into a private offscreen target (flat per-instance color+alpha) instead of
// the main scene; a fullscreen composite pass dilates that mask into the
// visible outline ring, giving a constant pixel width on any topology.
// param1 = maskValue (1.0 = selected), param2 = outline width in pixels,
// color/alpha (w) ride along as per-instance data like other instanced kinds.
#define KINE_MAT_OUTLINE_MASK 12
#define KINE_MAT_FORCEFIELD 13
#define KINE_MAT_FADE 14
#define KINE_MAT_NEON_FADE 15

// Which arm/handle of a gizmo is being interacted with.
#define KINE_GIZMO_AXIS_NONE 0
#define KINE_GIZMO_AXIS_X 1
#define KINE_GIZMO_AXIS_Y 2
#define KINE_GIZMO_AXIS_Z 3
#define KINE_GIZMO_AXIS_CENTER 4

// Plane handles. An axis arrow foreshortens into an unusable dot once the camera
// looks down it, so the plane perpendicular to that axis takes over. Each one is
// named for the two axes it drags, and is colored with the color of the axis it
// replaces.
#define KINE_GIZMO_AXIS_XY 5
#define KINE_GIZMO_AXIS_YZ 6
#define KINE_GIZMO_AXIS_XZ 7
#define KINE_GIZMO_AXIS_COUNT 8

// Gizmo type, matches the existing shape codes used by Kine_Filament_CreateMesh.
#define KINE_GIZMO_MOVE 10
#define KINE_GIZMO_ROTATE 11
#define KINE_GIZMO_SCALE 12

typedef struct KineFilamentGizmo KineFilamentGizmo;

KINE_API KineFilamentContext *Kine_Filament_Create(int width, int height);
KINE_API KineFilamentContext *Kine_Filament_CreateForSDLWindow(void *sdlWindow, int width, int height);
KINE_API KineFilamentContext *Kine_Filament_CreateForVulkanCompositor(
	void *vulkanCompositor,
	int width,
	int height);
KINE_API KineFilamentContext *Kine_Filament_CreateForVulkanCompositorWindow(
	void *sdlWindow,
	int width,
	int height);
KINE_API void *Kine_Filament_GetVulkanCompositor(KineFilamentContext *ctx);
KINE_API unsigned int Kine_Filament_GetColorTextureId(KineFilamentContext *ctx);
KINE_API bool Kine_Filament_GetVulkanBackend(KineFilamentContext *ctx, KineFilamentVulkanBackend *outBackend);
KINE_API void Kine_Filament_Destroy(KineFilamentContext *ctx);

// ---------------------------------------------------------------------------
// Render mode: 1 = Filament (default), 2 = Ray path tracer.
//
// Ray is an optional feature that traces on the Vulkan device Filament already
// owns (the same one Skia renders on), so it only exists in Vulkan builds.
// Kine_Filament_NewRay creates it at the requested trace resolution; it does
// not switch modes. Both calls are safe to repeat, and the path tracer can be
// created lazily the first time the user actually asks for mode 2.
// ---------------------------------------------------------------------------
#define KINE_RENDER_MODE_FILAMENT 1
#define KINE_RENDER_MODE_RAY 2

KINE_API bool Kine_Filament_NewRay(KineFilamentContext *ctx, int width, int height);
KINE_API void Kine_Filament_DestroyRay(KineFilamentContext *ctx);
KINE_API bool Kine_Filament_SetRenderMode(KineFilamentContext *ctx, int mode);
KINE_API int Kine_Filament_GetRenderMode(KineFilamentContext *ctx);
KINE_API bool Kine_Filament_HasRay(KineFilamentContext *ctx);
KINE_API const char *Kine_Filament_GetRayError(void);

/* Path tracer settings. Every field is clamped when applied: out-of-range values
   are pinned to the documented range instead of being rejected, and a change
   restarts sample accumulation. Get fills in the defaults when called before
   Set. */
typedef struct KineRayProperties {
	int maxTotalDepth;		/* total bounces ("steps"), 1..32, default 8 */
	int maxDiffuseDepth;	 /* diffuse bounces, 0..32, default 4 */
	int maxSpecularDepth;	 /* glossy bounces, 0..32, default 8 */
	int maxRefractionDepth; /* transmission bounces, 0..32, default 8 */
	int samplesPerFrame;	 /* traces per rendered frame, 1..64, default 1 */
	int minSamples;		 /* adaptive-sampling floor, 0..4096, default 128 */
	float varianceThreshold; /* early-out below this variance, 0 = never, default 0 */
	float exposure;		 /* stops applied by Ray's tonemapper, default 0 */
	float clampDirect;	 /* firefly clamp on direct light, 0 = off, default 0 */
	float clampIndirect;	 /* firefly clamp on indirect light, 0 = off, default 0 */
} KineRayProperties;

/* properties == NULL restores the defaults. Also accepted before NewRay, in
   which case the values are kept for the renderer created afterwards. */
KINE_API bool Kine_Ray_SetProperties(KineFilamentContext *ctx, const KineRayProperties *properties);
KINE_API bool Kine_Ray_GetProperties(KineFilamentContext *ctx, KineRayProperties *outProperties);

// deltaTime (seconds) drives ctx->time, used to animate the water material.
KINE_API void Kine_Filament_RenderFrame(KineFilamentContext *ctx, float deltaTime);

// Lightweight isolated previews. All handles share ctx's Engine and atlas pool.
typedef struct KineFilamentViewport KineFilamentViewport;
typedef struct KineSkiaSurface KineSkiaSurface;
typedef struct KineViewportSettings {
    float camera[16];
    float ambient[3], lightColor[3], lightDirection[3];
    float fieldOfView;
    int32_t width, height;
    int32_t shadows, postProcessing;
    uint32_t effectMask;
    float bloom[5], ao[7], dof[6], color[7], vignette[8], reflections[5], antialiasing[4];
    int32_t dithering, quality;
} KineViewportSettings;
KINE_API KineFilamentViewport *Kine_Filament_Viewport_Create(KineFilamentContext *ctx);
KINE_API void Kine_Filament_Viewport_Destroy(KineFilamentViewport *viewport);
KINE_API void Kine_Filament_Viewport_Begin(KineFilamentContext *ctx);
KINE_API bool Kine_Filament_Viewport_IsValid(KineFilamentViewport *viewport, KineFilamentContext *ctx);
KINE_API void Kine_Filament_Viewport_Touch(KineFilamentViewport *viewport);
KINE_API KineFilamentMesh *Kine_Filament_Viewport_Primitive(KineFilamentContext *ctx, int shape);
KINE_API KineFilamentMesh *Kine_Filament_Viewport_Mesh(KineFilamentContext *ctx, uint64_t key,
    const void *data, size_t size, const char *hint);
KINE_API bool Kine_Filament_Viewport_Update(KineFilamentViewport *viewport,
    const KineViewportSettings *settings, const KineFilamentDrawItem *items, uint32_t count, uint64_t version);
KINE_API void Kine_Filament_Viewport_Draw(KineFilamentViewport *viewport, KineSkiaSurface *surface,
    float x, float y, float width, float height, float r, float g, float b, float opacity);
KINE_API bool Kine_Filament_Viewport_HasWork(KineFilamentContext *ctx);
KINE_API void Kine_Filament_Viewport_RenderFrame(KineFilamentContext *ctx, float dt, bool renderWorld);
typedef void (*KineFrameProfileCallback)(void *user, const char *phase, bool begin);
KINE_API void Kine_Filament_SetFrameProfileCallback(KineFilamentContext *ctx, KineFrameProfileCallback callback, void *user);
// Diagnostics for stress / resource-lifetime tests, not a script property.
KINE_API void Kine_Filament_Viewport_Stats(KineFilamentContext *ctx,
    uint32_t *handles, uint32_t *pages, uint64_t *renders);


KINE_API void Kine_Filament_Resize(KineFilamentContext *ctx, int width, int height);
KINE_API void Kine_Filament_SetViewport(KineFilamentContext *ctx, int x, int y, int width, int height);

KINE_API void Kine_Filament_CreateSky(KineFilamentContext *ctx, float r, float g, float b, float a);
KINE_API void Kine_Filament_SetPostProcessing(KineFilamentContext *ctx, bool enabled);
KINE_API void Kine_Filament_SetBloom(
	KineFilamentContext *ctx,
	bool enabled,
	float strength,
	int resolution,
	int levels,
	bool threshold,
	bool lensFlare);
KINE_API void Kine_Filament_SetAmbientOcclusion(
	KineFilamentContext *ctx,
	bool enabled,
	float radius,
	float power,
	float intensity,
	int quality,
	int aoType);
KINE_API void Kine_Filament_SetAntiAliasing(
	KineFilamentContext *ctx,
	bool fxaa,
	bool taa,
	bool msaa,
	int sampleCount);
KINE_API void Kine_Filament_SetDynamicResolution(
	KineFilamentContext *ctx,
	bool enabled,
	float minScale,
	float maxScale,
	int quality,
	float sharpness);
KINE_API void Kine_Filament_SetDepthOfField(
	KineFilamentContext *ctx,
	bool enabled,
	float cocScale,
	float cocAspectRatio,
	float maxApertureDiameter,
	int maxForegroundCOC,
	int maxBackgroundCOC);
KINE_API void Kine_Filament_SetFocusDistance(KineFilamentContext *ctx, float distance);
KINE_API void Kine_Filament_SetVignette(
	KineFilamentContext *ctx,
	bool enabled,
	float midPoint,
	float roundness,
	float feather,
	float r,
	float g,
	float b,
	float a);
KINE_API void Kine_Filament_SetScreenSpaceReflections(
	KineFilamentContext *ctx,
	bool enabled,
	float thickness,
	float bias,
	float maxDistance,
	float stride);
KINE_API void Kine_Filament_SetColorGrading(
	KineFilamentContext *ctx,
	float exposure,
	float contrast,
	float saturation,
	float vibrance,
	float temperature,
	float tint);
KINE_API void Kine_Filament_ClearColorGrading(KineFilamentContext *ctx);
KINE_API void Kine_Filament_SetRenderQuality(KineFilamentContext *ctx, int hdrQuality);
KINE_API void Kine_Filament_SetDithering(KineFilamentContext *ctx, bool enabled);
KINE_API void Kine_Filament_SetShadowOptions(KineFilamentContext *ctx, bool enabled, int shadowType);
KINE_API void Kine_Filament_SetSunShadowOptions(
	KineFilamentContext *ctx,
	int mapSize,
	int cascades,
	float shadowFar,
	float shadowNearHint,
	float shadowFarHint,
	bool stable,
	bool contactShadows);
// Sky cloud layer, driven by the Lighting.Clouds instance.
//
//   cover     : 0..1 sky coverage; higher leaves fewer gaps
//   density   : 0..1 thickness; higher absorbs more light through the layer
//   height    : world Y of the layer centre
//   thickness : world Y extent of the layer
// The layer follows the camera horizontally and is sized inside the far plane,
// so setting these every frame is cheap and idempotent.
typedef enum KineAdvancedEffect {
    KINE_EFFECT_REFLECTION_PROBE = 0,
    KINE_EFFECT_SSGI = 1,
    KINE_EFFECT_FOG = 2,
    KINE_EFFECT_SSCT = 3,
    KINE_EFFECT_TAA = 4,
    KINE_EFFECT_DYNAMIC_RESOLUTION = 5,
    KINE_EFFECT_TONE_MAPPING = 6,
    KINE_EFFECT_COUNT = 7
} KineAdvancedEffect;
KINE_API void Kine_Filament_SetAdvancedEffect(KineFilamentContext *ctx, int effect, bool enabled, const float *values, int count);
KINE_API bool Kine_Filament_GetAdvancedEffect(KineFilamentContext *ctx, int effect, bool *enabled, float *values, int capacity);
KINE_API bool Kine_Filament_GetReflectionProbeRegion(KineFilamentContext *ctx, float *center, float *radius);
KINE_API uint64_t Kine_Filament_GetReflectionProbeCaptureCount(KineFilamentContext *ctx);
KINE_API void Kine_Filament_SetClouds(
	KineFilamentContext *ctx,
	bool enabled,
	float cover,
	float density,
	float height,
	float thickness,
	float r, float g, float b);

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
	bool fogColorFromIbl);
KINE_API KineFilamentTex *Kine_Filament_CreateTexFromPixels(
	KineFilamentContext *ctx,
	int width, int height,
	int rowBytes,
	const void *pixelsRGBA8);
KINE_API bool Kine_Filament_UpdateTexFromPixels(
	KineFilamentContext *ctx,
	KineFilamentTex *tex,
	int width, int height,
	int rowBytes,
	const void *pixelsRGBA8);
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
	float heightScale);
KINE_API KineFilamentTex *Kine_Filament_CreateTerrainTextureSet(
	KineFilamentContext *ctx,
	KineFilamentTex *layer0,
	KineFilamentTex *layer1,
	KineFilamentTex *layer2,
	KineFilamentTex *layer3,
	KineFilamentTex *layer4,
	KineFilamentTex *layer5);
KINE_API void *Kine_Filament_GetEngine(KineFilamentContext *ctx);
KINE_API void *Kine_Filament_GetScene(KineFilamentContext *ctx);
KINE_API void *Kine_Filament_GetView(KineFilamentContext *ctx);
KINE_API void *Kine_Filament_GetCamera(KineFilamentContext *ctx);

KINE_API void Kine_Filament_SetCameraLookAt(
	KineFilamentContext *ctx,
	float eyeX, float eyeY, float eyeZ,
	float targetX, float targetY, float targetZ,
	float upX, float upY, float upZ);

KINE_API bool Kine_Filament_BlitToScreen(KineFilamentContext *ctx, int dstX, int dstY, int dstWidth, int dstHeight);
KINE_API void Kine_Filament_SetCameraPerspective(
	KineFilamentContext *ctx,
	double fovYDegrees, double aspect, double nearPlane, double farPlane);

KINE_API void Kine_Filament_SetCameraPosition(KineFilamentContext *ctx, float x, float y, float z);
KINE_API void Kine_Filament_SetCameraDirection(KineFilamentContext *ctx, float dx, float dy, float dz);

// shape: 1 = cube, 2 = sphere, 3 = pyramid, 4 = quad, 6 = cylinder,
//        10 = move gizmo, 11 = rotate gizmo, 12 = scale gizmo
KINE_API KineFilamentMesh *Kine_Filament_CreateMesh(KineFilamentContext *ctx, int shape);
// Mesh indices follow scene traversal order. Zero loads the complete model.
typedef struct KineFilamentMeshList KineFilamentMeshList;
KINE_API KineFilamentMeshList *Kine_Filament_ListMeshes(const char *path);
KINE_API int Kine_Filament_GetMeshListCount(const KineFilamentMeshList *list);
KINE_API const char *Kine_Filament_GetMeshListName(const KineFilamentMeshList *list, uint32_t meshIndex);
KINE_API void Kine_Filament_DestroyMeshList(KineFilamentMeshList *list);
KINE_API KineFilamentMesh *Kine_Filament_CreateMeshFromPathIndexed(
	KineFilamentContext *ctx, const char *path, uint32_t meshIndex);
KINE_API KineFilamentMesh *Kine_Filament_CreateMeshFromMemoryIndexed(
	KineFilamentContext *ctx, const void *data, size_t dataSize, const char *formatHint, uint32_t meshIndex);
KINE_API KineFilamentMeshData *Kine_Filament_LoadMeshDataFromMemoryIndexed(
	const void *bytes, size_t length, const char *formatHint, uint32_t meshIndex);
KINE_API KineFilamentMeshData *Kine_Filament_LoadMeshDataFromPathIndexed(const char *path, uint32_t meshIndex);

KINE_API KineFilamentMesh *Kine_Filament_CreateMeshFromPath(KineFilamentContext *ctx, const char *path);
KINE_API KineFilamentMesh *Kine_Filament_CreateMeshFromMemory(
	KineFilamentContext *ctx,
	const void *data,
	size_t dataSize,
	const char *formatHint);
KINE_API bool Kine_Filament_SetDecalColor(
	KineFilamentContext *ctx,
	int decal,
	float r,
	float g,
	float b,
	float a);
KINE_API void Kine_Filament_DestroyMesh(KineFilamentContext *ctx, KineFilamentMesh *mesh);
/* Imported skeletal data. Bind transforms and caller-provided bone transforms
   are row-major affine float[16] matrices in mesh-local space. Bone transforms
   are converted to final skin matrices with the imported inverse bind pose. */
KINE_API int Kine_Filament_GetMeshBoneCount(const KineFilamentMesh *mesh);
// Local-space bounds of the actual uploaded geometry, before Part transforms.
KINE_API bool Kine_Filament_GetMeshBounds(const KineFilamentMesh *mesh, float *center, float *halfExtent);
// Built-in Part shapes import geometry only; their appearance comes from Part.Material.
KINE_API void Kine_Filament_SetUseImportedMaterials(KineFilamentContext *ctx, KineFilamentMesh *mesh, bool enabled);
KINE_API int Kine_Filament_GetMeshMaterialCount(const KineFilamentMesh *mesh);
KINE_API KineFilamentTex *Kine_Filament_GetMeshMaterialTexture(const KineFilamentMesh *mesh, int index);
KINE_API const char *Kine_Filament_GetMeshBoneName(const KineFilamentMesh *mesh, int boneIndex);
KINE_API int Kine_Filament_GetMeshBoneParent(const KineFilamentMesh *mesh, int boneIndex);
KINE_API bool Kine_Filament_CopyMeshBoneBindTransform(
	const KineFilamentMesh *mesh, int boneIndex, float *outTransform16);
KINE_API bool Kine_Filament_SetMeshBoneTransforms(
	KineFilamentContext *ctx, KineFilamentMesh *mesh,
	const float *boneTransforms16, int boneCount);
KINE_API int Kine_Filament_GetMeshAnimationCount(const KineFilamentMesh *mesh);
KINE_API const char *Kine_Filament_GetMeshAnimationName(
	const KineFilamentMesh *mesh, int animationIndex);
KINE_API float Kine_Filament_GetMeshAnimationDuration(
	const KineFilamentMesh *mesh, int animationIndex);
KINE_API bool Kine_Filament_ApplyMeshAnimation(
	KineFilamentContext *ctx, KineFilamentMesh *mesh,
	int animationIndex, float timeSeconds, bool loop);
/* CPU-only import used by headless/server collision generation. Positions are
   returned as tightly packed xyz floats and indices are zero-based uint32s. */
KINE_API KineFilamentMeshData *Kine_Filament_LoadMeshDataFromPath(const char *path);
KINE_API int Kine_Filament_GetMeshDataVertexCount(const KineFilamentMeshData *meshData);
KINE_API int Kine_Filament_GetMeshDataIndexCount(const KineFilamentMeshData *meshData);
KINE_API bool Kine_Filament_CopyMeshDataVertices(
	const KineFilamentMeshData *meshData, float *outVertices, int floatCapacity);
KINE_API bool Kine_Filament_CopyMeshDataPositions(
	const KineFilamentMeshData *meshData, float *outPositions, int positionFloatCapacity);
KINE_API bool Kine_Filament_CopyMeshDataIndices(
	const KineFilamentMeshData *meshData, uint32_t *outIndices, int indexCapacity);
KINE_API void Kine_Filament_DestroyMeshData(KineFilamentMeshData *meshData);
KINE_API void Kine_Filament_DebugPrintPixel(KineFilamentContext *ctx);
KINE_API KineFilamentGizmo *Kine_Filament_CreateGizmo(KineFilamentContext *ctx, int gizmoType);
KINE_API void Kine_Filament_DestroyGizmo(KineFilamentContext *ctx, KineFilamentGizmo *gizmo);

KINE_API KineFilamentTex *Kine_Filament_CreateTex(KineFilamentContext *ctx, const KineGLTextureInfo *texture);
KINE_API void Kine_Filament_DestroyTex(KineFilamentContext *ctx, KineFilamentTex *tex);

// ---------------------------------------------------------------------------
// DrawMeshEx -- queues a mesh to be drawn this frame with a chosen material.
//
//   materialKind : one of the KINE_MAT_* constants above
//   r,g,b        : base/emissive color [0..1]
//   param1       : roughness (default/glass/water) or intensity (neon)
//   param2       : metallic (default) or ior (glass/water) -- unused for neon
//   param3       : uv tile scale (default/terrain), unused (neon), or thickness (glass/water)
//   transmission : unused (default/neon) or transmission (glass/water)
//   mat4         : row-major float[16] world transform; converted to Filament columns by the shim
//   tex          : optional KineFilamentTex* (from Kine_Filament_CreateTex), nil for no texture
// ---------------------------------------------------------------------------

KINE_API KineFilamentMesh *Kine_Filament_CreateCustomMesh(
	KineFilamentContext *ctx,
	const float *vertexData, // interleaved px,py,pz,nx,ny,nz,u,v — 8 floats/vertex
	int vertexCount,
	const uint16_t *indices,
	int indexCount);
// 32-bit indices for large meshes. Counts are vertices and indices, not bytes.
KINE_API KineFilamentMesh *Kine_Filament_CreateCustomMesh32(
	KineFilamentContext *ctx,
	const float *vertexData, // interleaved px,py,pz,nx,ny,nz,u,v — 8 floats/vertex
	int vertexCount,
	const uint32_t *indices,
	int indexCount);
// Variant that also uploads per-vertex colors (one float4 r,g,b,a per vertex).
// colorData may be null for no colors. Bound as VertexAttribute::COLOR so
// materials declaring `requires: [ color ]` read them via getColor().
KINE_API KineFilamentMesh *Kine_Filament_CreateCustomMeshEx(
	KineFilamentContext *ctx,
	const float *vertexData, // interleaved px,py,pz,nx,ny,nz,u,v — 8 floats/vertex
	const float *colorData,	 // interleaved r,g,b,a — 4 floats/vertex, or null
	int vertexCount,
	const uint16_t *indices,
	int indexCount);
// 32-bit indices for large meshes. Counts are vertices and indices, not bytes.
KINE_API KineFilamentMesh *Kine_Filament_CreateCustomMeshEx32(
	KineFilamentContext *ctx,
	const float *vertexData, // interleaved px,py,pz,nx,ny,nz,u,v — 8 floats/vertex
	const float *colorData,	 // interleaved r,g,b,a — 4 floats/vertex, or null
	int vertexCount,
	const uint32_t *indices,
	int indexCount);
KINE_API KineFilamentMesh *Kine_Filament_CreateTerrainMesh(
	KineFilamentContext *ctx,
	const float *vertexData,
	const float *materialWeights, // 8 floats/vertex; first 6 are material weights
	int vertexCount,
	const uint16_t *indices,
	int indexCount);
KINE_API bool Kine_Filament_UpdateCustomMesh(
	KineFilamentContext *ctx,
	KineFilamentMesh *mesh,
	const float *vertexData,
	int vertexCount);
// Returns the base colour texture the model file carried (GLB/gltf embedded
// image, or an external file next to the model), or NULL when the mesh was
// built without one. Owned by the mesh; do not destroy it.
KINE_API KineFilamentTex *Kine_Filament_GetMeshTexture(const KineFilamentMesh *mesh);

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
	bool castShadows,
	bool receiveShadows,
	bool culling,
	KineFilamentTex *tex);

KINE_API void Kine_Filament_DrawMeshList(
	KineFilamentContext *ctx,
	const KineFilamentDrawItem *items,
	uint32_t itemCount);

/* Retained draw stream. Reusing the same streamId/version keeps the existing
   GPU instance buffers without resubmitting the item array. */
KINE_API void Kine_Filament_DrawMeshListVersioned(
	KineFilamentContext *ctx,
	const KineFilamentDrawItem *items,
	uint32_t itemCount,
	uint64_t streamId,
	uint64_t version);

KINE_API KineFilamentInstanceBatch *Kine_Filament_CreateInstanceBatch(
	KineFilamentContext *ctx,
	const KineFilamentDrawItem *items,
	uint32_t itemCount);

KINE_API void Kine_Filament_DestroyInstanceBatch(
	KineFilamentInstanceBatch *batch);

KINE_API void Kine_Filament_UpdateInstanceTransforms(
	KineFilamentInstanceBatch *batch,
	const uint32_t *indices,
	const float *transforms,
	uint32_t dirtyCount);

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
	bool culling);

KINE_API void Kine_Filament_DrawMeshOutline(
	KineFilamentContext *ctx,
	KineFilamentMesh *mesh,
	float r, float g, float b,
	float thickness,
	float *mat4);

KINE_API void Kine_Filament_DrawGizmo(
	KineFilamentContext *ctx,
	KineFilamentGizmo *gizmo,
	float *mat4,
	int hoveredAxis,
	int selectedAxis);
KINE_API int Kine_Filament_PickGizmo(
	KineFilamentContext *ctx,
	KineFilamentGizmo *gizmo,
	float *mat4,
	float screenX,
	float screenY);
KINE_API float Kine_Filament_GetGizmoDragDelta(
	KineFilamentContext *ctx,
	KineFilamentGizmo *gizmo,
	float *mat4,
	int axis,
	float startX,
	float startY,
	float currentX,
	float currentY);

// Solves a plane-handle drag. Returns 1 and writes one delta per axis the plane
// spans (XY writes X then Y, YZ writes Y then Z, XZ writes X then Z), in the same
// local units a single-axis drag reports. Returns 0 for any other axis.
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
	float *outSecond);

// OpenGL path reads the offscreen GL color target. Vulkan builds intentionally
// keep this disabled unless KINE_FILAMENT_VULKAN_READBACK=ON is set, because a
// per-frame GPU readback is a debugging path, not the high-performance compositor path.
KINE_API void Kine_Filament_ReadPixels(KineFilamentContext *ctx, void *outPixels);
KINE_API int Kine_Filament_GetWidth(KineFilamentContext *ctx);
KINE_API int Kine_Filament_GetHeight(KineFilamentContext *ctx);

// ---------------------------------------------------------------------------
// Atmospheric sky.
//
// Drives the procedural sky appearance each frame.  All colour components are
// linear [0..1].
//
//   sunDirX/Y/Z   : normalised world-space direction *toward* the sun.
//                   Y > 0 = above horizon, Y < 0 = below horizon.
//   skyR/G/B      : zenith (overhead) sky colour.
//   horizonR/G/B  : horizon band colour (blended in at low sun elevation).
//   groundR/G/B   : ground-fill colour visible when sun is below horizon.
//   sunIntensity  : sun light intensity in lux (e.g. 100 000 for full day,
//                   0 for night).  Controls both the sun-light entity and
//                   the brightness of the blended clear colour.
// ---------------------------------------------------------------------------
KINE_API void Kine_Filament_SetSkyAtmosphere(
	KineFilamentContext *ctx,
	float sunDirX, float sunDirY, float sunDirZ,
	float skyR, float skyG, float skyB,
	float horizonR, float horizonG, float horizonB,
	float groundR, float groundG, float groundB,
	float sunIntensity);

// ---------------------------------------------------------------------------
// Custom Texture Cubemap Skybox
// Takes 6 OpenGL texture descriptors and builds a cubemap skybox from them.
// Faces must all be square and have identical dimensions.
// ---------------------------------------------------------------------------
KINE_API void Kine_Filament_CreateSkyboxCubemap(
	KineFilamentContext *ctx,
	const KineGLTextureInfo *texPosX, const KineGLTextureInfo *texNegX,
	const KineGLTextureInfo *texPosY, const KineGLTextureInfo *texNegY,
	const KineGLTextureInfo *texPosZ, const KineGLTextureInfo *texNegZ);

// ---------------------------------------------------------------------------
// Set the built-in sun light direction and intensity independently of the sky.
// ---------------------------------------------------------------------------
KINE_API void Kine_Filament_SetSun(
	KineFilamentContext *ctx,
	float sunDirX, float sunDirY, float sunDirZ,
	float sunIntensity);

// ---------------------------------------------------------------------------
// Point / spot light management.
// Returns an opaque integer light ID, or -1 on failure.
// ---------------------------------------------------------------------------
KINE_API int Kine_Filament_CreateLight(
	KineFilamentContext *ctx,
	float px, float py, float pz,
	float cr, float cg, float cb,
	float intensity, float falloff);

KINE_API int Kine_Filament_CreateLightEx(
	KineFilamentContext *ctx, int lightType,
	float px, float py, float pz,
	float dx, float dy, float dz,
	float cr, float cg, float cb,
	float intensity, float falloff,
	float innerConeRadians, float outerConeRadians,
	bool castShadows, bool enabled);

KINE_API void Kine_Filament_SetColorLight(
	KineFilamentContext *ctx, int light, float r, float g, float b);
KINE_API void Kine_Filament_SetIntensityLight(
	KineFilamentContext *ctx, int light, float intensity);
KINE_API void Kine_Filament_SetFalloffLight(
	KineFilamentContext *ctx, int light, float falloff);
KINE_API void Kine_Filament_SetPositionLight(
	KineFilamentContext *ctx, int light, float x, float y, float z);
KINE_API void Kine_Filament_SetDirectionLight(
	KineFilamentContext *ctx, int light, float x, float y, float z);
KINE_API void Kine_Filament_SetConeLight(
	KineFilamentContext *ctx, int light, float innerRadians, float outerRadians);
KINE_API void Kine_Filament_SetShadowLight(
	KineFilamentContext *ctx, int light, bool castShadows);
KINE_API void Kine_Filament_SetEnabledLight(
	KineFilamentContext *ctx, int light, bool enabled);
KINE_API void Kine_Filament_RemoveLight(KineFilamentContext *ctx, int light);

// ---------------------------------------------------------------------------
// Immediate-mode debug shapes (not the interactive transform gizmo).
// Submit every frame before Kine_Filament_RenderFrame. mat4 is a row-major
// float[16] and may be NULL for identity. thickness <= 0 uses the default
// (0.02 world units). segments <= 0 uses 32. Colors are [0..1].
// ---------------------------------------------------------------------------
KINE_API void Kine_Filament_DrawGizmoLine(
	KineFilamentContext *ctx,
	float ax, float ay, float az,
	float bx, float by, float bz,
	float r, float g, float b,
	float thickness);

/* points: 6 floats per segment (ax ay az bx by bz). */
KINE_API void Kine_Filament_DrawGizmoLines(
	KineFilamentContext *ctx,
	const float *points,
	uint32_t segmentCount,
	float r, float g, float b,
	float thickness);

/* Unit cube (edge 1, centered) transformed by mat4; put the size in the scale. */
KINE_API void Kine_Filament_DrawGizmoCube(
	KineFilamentContext *ctx,
	const float *mat4,
	float r, float g, float b,
	bool wire,
	float thickness);

KINE_API void Kine_Filament_DrawGizmoSphere(
	KineFilamentContext *ctx,
	float cx, float cy, float cz,
	float radius,
	float r, float g, float b,
	bool wire,
	float thickness,
	int segments);

/* Unit cylinder (diameter 1, height 1 along local Y, centered) transformed by mat4. */
KINE_API void Kine_Filament_DrawGizmoCylinder(
	KineFilamentContext *ctx,
	const float *mat4,
	float r, float g, float b,
	bool wire,
	float thickness,
	int segments);

/* Any mesh, solid and unlit in one flat color. */
KINE_API void Kine_Filament_DrawGizmoMesh(
	KineFilamentContext *ctx,
	KineFilamentMesh *mesh,
	const float *mat4,
	float r, float g, float b);

/* Any mesh as a wireframe of unique triangle edges (capped at 16384 per call). */
KINE_API void Kine_Filament_DrawGizmoWireMesh(
    KineFilamentContext* ctx,
    KineFilamentMesh* mesh,
    const float* mat4,
    float r, float g, float b,
    float thickness,
    float featureAngleDeg);   /* 0 = every edge; ~30 = outline-style */

// ---------------------------------------------------------------------------
// Screen-space decal management.
// Returns an opaque integer decal ID, or -1 on failure.
// ---------------------------------------------------------------------------
KINE_API int Kine_Filament_CreateDecal(
	KineFilamentContext *ctx,
	float width, float height,
	KineFilamentTex *texture,
	float offsetStudsU, float offsetStudsV,
	float studsPerTileU, float studsPerTileV,
	bool culling, bool castShadows, bool receiveShadows);

// The decal owns the mesh after a successful creation.
KINE_API int Kine_Filament_CreateMeshDecal(
	KineFilamentContext *ctx, KineFilamentMesh *mesh, KineFilamentTex *texture);
KINE_API bool Kine_Filament_EditMeshDecal(
	KineFilamentContext *ctx, int decal, KineFilamentMesh *mesh,
	bool culling, bool castShadows, bool receiveShadows);
KINE_API void Kine_Filament_SetMeshDoubleSided(KineFilamentMesh *mesh);

KINE_API bool Kine_Filament_SetDecalTiling(
	KineFilamentContext *ctx, int decal,
	float width, float height,
	float offsetStudsU, float offsetStudsV,
	float studsPerTileU, float studsPerTileV);

KINE_API void Kine_Filament_RemoveDecal(KineFilamentContext *ctx, int decal);
KINE_API bool Kine_Filament_SetDecalTransform(KineFilamentContext *ctx, int decal, float *mat4);

KINE_API bool Kine_Filament_EditDecal(
	KineFilamentContext *ctx, int decal,
	float width, float height,
	bool culling, bool castShadows, bool receiveShadows);

#ifdef __cplusplus
}
#endif

#endif
