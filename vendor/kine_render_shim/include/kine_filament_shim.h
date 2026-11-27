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


KINE_API KineFilamentShader *Kine_Filament_Shader_Create(KineFilamentContext *ctx, const char *materialSource);
KINE_API KineFilamentShaderCompile *Kine_Filament_Shader_CompileStart(const char *source);
KINE_API bool Kine_Filament_Shader_CompilePoll(KineFilamentContext *ctx, KineFilamentShaderCompile *job, KineFilamentShader **shader);
KINE_API void Kine_Filament_Shader_CompileRelease(KineFilamentShaderCompile *job);
KINE_API KineFilamentShader *Kine_Filament_Shader_ResolveFade(KineFilamentShader *shader);
KINE_API void Kine_Filament_Shader_Destroy(KineFilamentShader *shader);
KINE_API bool Kine_Filament_Shader_SetUniform(
	KineFilamentShader *shader, const char *name, const float *values, int valueCount);

KINE_API bool Kine_Filament_Shader_SetTextureFromPixels(
	KineFilamentShader *shader, const char *name, int width, int height,
	int rowBytes, const void *pixelsRGBA8, bool srgb);
KINE_API bool Kine_Filament_Shader_SetGeometryOptions(KineFilamentShader *shader, int subdivisions, float boundsPadding);
KINE_API void Kine_Filament_Shader_TransferTextures(KineFilamentShader *source, KineFilamentShader *destination);
KINE_API bool Kine_Filament_Shader_HasTexture(KineFilamentShader *shader, const char *name);
KINE_API bool Kine_Filament_SetGlobalShader(KineFilamentContext *ctx, KineFilamentShader *shader);


KINE_API bool Kine_Filament_SetPostProcessShader(KineFilamentContext *ctx, KineFilamentShader *shader);
KINE_API bool Kine_Filament_SetPostProcessChain(KineFilamentContext *ctx, KineFilamentShader *const *shaders, int count);
KINE_API const char *Kine_Filament_Shader_GetLastError(void);


KINE_API bool Kine_Filament_Shader_DispatchTexture(KineFilamentShader *shader, const char *name,
    const uint32_t *words, size_t bytes, uint32_t width, uint32_t height);

KINE_API void Kine_Filament_ComputeTextureStats(uint64_t *out);

#define KINE_FILAMENT_DRAW_CAST_SHADOWS (1u << 0)
#define KINE_FILAMENT_DRAW_RECEIVE_SHADOWS (1u << 1)
#define KINE_FILAMENT_DRAW_CULLING (1u << 2)
#define KINE_FILAMENT_DRAW_WORLD_POSITION (1u << 3)


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
	uint32_t reserved;
	KineFilamentShader *shader;
	double worldPosition[3];
} KineFilamentDrawItem;

typedef struct KineFilamentParticleItem {
	float transform[16];
	uint8_t r;
	uint8_t g;
	uint8_t b;
	uint8_t a;
	double worldPosition[3];
} KineFilamentParticleItem;

typedef struct KineGLTextureInfo {
	unsigned int id;
	int width;
	int height;
	int mipmaps;
	int format;
} KineGLTextureInfo;

typedef struct KineFilamentVulkanBackend {
	void *instance;
	void *physicalDevice;
	void *device;
	void *queue;
	uint32_t graphicsQueueFamilyIndex;
	uint32_t maxApiVersion;
	void *getInstanceProcAddr;
	void *getDeviceProcAddr;
} KineFilamentVulkanBackend;


#define KINE_MAT_DEFAULT 0
#define KINE_MAT_GLASS 1
#define KINE_MAT_NEON 2
#define KINE_MAT_WATER 3
#define KINE_MAT_OUTLINE 4
#define KINE_MAT_GIZMO 5
#define KINE_MAT_PARTICLE 6
#define KINE_MAT_TERRAIN 7


#define KINE_MAT_HIGHLIGHT_OUTLINE 8
#define KINE_MAT_HIGHLIGHT_FILL 9
#define KINE_MAT_HIGHLIGHT_OUTLINE_TOP 10
#define KINE_MAT_HIGHLIGHT_FILL_TOP 11


#define KINE_MAT_OUTLINE_MASK 12
#define KINE_MAT_FORCEFIELD 13
#define KINE_MAT_FADE 14
#define KINE_MAT_NEON_FADE 15


#define KINE_GIZMO_AXIS_NONE 0
#define KINE_GIZMO_AXIS_X 1
#define KINE_GIZMO_AXIS_Y 2
#define KINE_GIZMO_AXIS_Z 3
#define KINE_GIZMO_AXIS_CENTER 4


#define KINE_GIZMO_AXIS_XY 5
#define KINE_GIZMO_AXIS_YZ 6
#define KINE_GIZMO_AXIS_XZ 7
#define KINE_GIZMO_AXIS_COUNT 8


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

KINE_API float Kine_Filament_GetDisplayRefreshRate(KineFilamentContext *ctx);
KINE_API float Kine_Filament_GetResolutionScale(KineFilamentContext *ctx);
KINE_API void Kine_Filament_SetAdaptiveShadowResolution(KineFilamentContext *ctx, bool enabled);
KINE_API uint32_t Kine_Filament_GetEffectiveShadowMapSize(KineFilamentContext *ctx);
KINE_API void Kine_Filament_ReportFrameTiming(KineFilamentContext *ctx, float seconds, float presentSeconds);
KINE_API unsigned int Kine_Filament_GetColorTextureId(KineFilamentContext *ctx);
KINE_API bool Kine_Filament_GetVulkanBackend(KineFilamentContext *ctx, KineFilamentVulkanBackend *outBackend);
KINE_API void Kine_Filament_Destroy(KineFilamentContext *ctx);


#define KINE_RENDER_MODE_FILAMENT 1
#define KINE_RENDER_MODE_RAY 2

KINE_API bool Kine_Filament_NewRay(KineFilamentContext *ctx, int width, int height);
KINE_API void Kine_Filament_DestroyRay(KineFilamentContext *ctx);
KINE_API bool Kine_Filament_SetRenderMode(KineFilamentContext *ctx, int mode);
KINE_API int Kine_Filament_GetRenderMode(KineFilamentContext *ctx);
KINE_API bool Kine_Filament_HasRay(KineFilamentContext *ctx);
KINE_API const char *Kine_Filament_GetRayError(void);


typedef struct KineRayProperties {
	int maxTotalDepth;
	int maxDiffuseDepth;
	int maxSpecularDepth;
	int maxRefractionDepth;
	int samplesPerFrame;
	int minSamples;
	float varianceThreshold;
	float exposure;
	float clampDirect;
	float clampIndirect;
} KineRayProperties;


KINE_API bool Kine_Ray_SetProperties(KineFilamentContext *ctx, const KineRayProperties *properties);
KINE_API bool Kine_Ray_GetProperties(KineFilamentContext *ctx, KineRayProperties *outProperties);


KINE_API void Kine_Filament_RenderFrame(KineFilamentContext *ctx, float deltaTime);

KINE_API void Kine_Filament_XR_Poll(KineFilamentContext *ctx);
KINE_API void Kine_Filament_XR_IdleFrame(KineFilamentContext *ctx);
KINE_API void Kine_Filament_XR_FinishFrame(KineFilamentContext *ctx);
KINE_API bool Kine_Filament_XR_GetUIPointer(KineFilamentContext *ctx, int hand, float *u, float *v, float *trigger);
typedef struct KineSkiaSurface KineSkiaSurface;

KINE_API KineSkiaSurface *Kine_Filament_XR_BeginUI(KineFilamentContext *ctx, int width, int height, int *outWidth, int *outHeight);
KINE_API bool Kine_Filament_XR_Active(KineFilamentContext *ctx);
KINE_API bool Kine_Filament_XR_Available(KineFilamentContext *ctx);
KINE_API bool Kine_Filament_XR_GetPose(KineFilamentContext *ctx, int index, float *out);

typedef struct KineXRControllerState {
    float trigger, grip, stick_x, stick_y;
    uint32_t active_mask;
} KineXRControllerState;
KINE_API bool Kine_Filament_XR_GetControllerState(KineFilamentContext *ctx, int hand, KineXRControllerState *out);
KINE_API bool Kine_Filament_XR_SetHaptic(KineFilamentContext *ctx, int hand, float amplitude, float seconds, float frequency);


typedef struct KineFilamentViewport KineFilamentViewport;
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
typedef void (*KineFrameCpuWork)(void *user);
KINE_API void Kine_Filament_Viewport_RenderFrameWithCpuWork(KineFilamentContext *ctx,
    float dt, bool renderWorld, KineFrameCpuWork work, void *user);
typedef void (*KineFrameProfileCallback)(void *user, const char *phase, bool begin);
KINE_API void Kine_Filament_SetFrameProfileCallback(KineFilamentContext *ctx, KineFrameProfileCallback callback, void *user);
KINE_API bool Kine_Filament_GetLatestGpuFrameTime(KineFilamentContext *ctx, uint32_t *frameId, uint64_t *durationNs);
typedef struct KineFilamentPassStats {
    uint32_t world, clouds, waterDepth, sharedDepth, customDepth, screenEffects;
    uint32_t customPost, outlineMask, outlineComposite, reflectionFaces;
    uint32_t viewportScene, viewportClear, viewportCopy, viewportShadow, viewportPresent;
} KineFilamentPassStats;
KINE_API void Kine_Filament_GetPassStats(KineFilamentContext *ctx, KineFilamentPassStats *out);
typedef struct KineFilamentBatchStats {
    uint32_t activeBatches, activeChunks, retainedChunks, createdChunks, destroyedChunks;
    uint32_t unchangedBatches, transformUploads, colorUploads, uvUploads, boundsUpdates;
} KineFilamentBatchStats;
KINE_API void Kine_Filament_GetBatchStats(KineFilamentContext *ctx, KineFilamentBatchStats *out);

KINE_API uint64_t Kine_Filament_Viewport_PersistentReuses(KineFilamentContext *ctx);
KINE_API uint64_t Kine_Filament_Viewport_ReusedRenders(KineFilamentContext *ctx);
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

KINE_API void Kine_Filament_SetShadowViewQuality(
    KineFilamentContext *ctx,
    float penumbraScale,
    float penumbraRatioScale,
    bool vsmHighPrecision,
    float vsmBleedReduction);

KINE_API void Kine_Filament_SetShadowExtraOptions(
    KineFilamentContext *ctx,
    float maxPenumbraRatio, float maxSearchRadius,
    int vsmAnisotropy, bool vsmMipmapping, int vsmMSAASamples,
    float sunAngularRadius, float sunHaloSize, float sunHaloFalloff);

KINE_API void Kine_Filament_SetSunShadowOptionsAdvanced(
    KineFilamentContext *ctx,
    int mapSize, int cascades,
    float shadowFar, float shadowNearHint, float shadowFarHint,
    bool stable, bool lispsm, float cascadeLambda,
    bool contactShadows, int contactSteps, float contactDistance,
    float constantBias, float normalBias,
    float polygonOffsetConstant, float polygonOffsetSlope,
    float bulbRadius, float vsmBlur, bool vsmELVSM);


typedef enum KineAdvancedEffect {
    KINE_EFFECT_REFLECTION_PROBE = 0,
    KINE_EFFECT_SSGI = 1,
    KINE_EFFECT_FOG = 2,
    KINE_EFFECT_SSCT = 3,
    KINE_EFFECT_TAA = 4,
    KINE_EFFECT_DYNAMIC_RESOLUTION = 5,
    KINE_EFFECT_TONE_MAPPING = 6,
    KINE_EFFECT_VOLUMETRIC_FOG = 7,
    KINE_EFFECT_CHROMATIC_ABERRATION = 8,
    KINE_EFFECT_FILM_GRAIN = 9,
    KINE_EFFECT_COUNT = 10
} KineAdvancedEffect;
KINE_API void Kine_Filament_SetAdvancedEffect(KineFilamentContext *ctx, int effect, bool enabled, const float *values, int count);
KINE_API bool Kine_Filament_GetAdvancedEffect(KineFilamentContext *ctx, int effect, bool *enabled, float *values, int capacity);
KINE_API bool Kine_Filament_GetDDGIStats(KineFilamentContext *ctx,
        uint32_t *total, uint32_t *initialized, uint64_t *updated);
KINE_API bool Kine_Filament_GetReflectionProbeRegion(KineFilamentContext *ctx, float *center, float *radius);
KINE_API uint64_t Kine_Filament_GetReflectionProbeCaptureCount(KineFilamentContext *ctx);
KINE_API void Kine_Filament_SetCloudResolutionScale(KineFilamentContext *ctx, float scale);
KINE_API void Kine_Filament_SetCloudShadowOptions(
        KineFilamentContext* ctx, bool castShadows, float intensity,
        float scale, float speed, float softness, float maxDistance);
KINE_API int Kine_Filament_GetCloudNoiseSource(KineFilamentContext *ctx);
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


KINE_API void Kine_Filament_SetCameraPose(
 KineFilamentContext *ctx, double x, double y, double z,
 double dx, double dy, double dz, double ux, double uy, double uz);

KINE_API bool Kine_Filament_BlitToScreen(KineFilamentContext *ctx, int dstX, int dstY, int dstWidth, int dstHeight);
KINE_API void Kine_Filament_SetCameraPerspective(
	KineFilamentContext *ctx,
	double fovYDegrees, double aspect, double nearPlane, double farPlane);

KINE_API void Kine_Filament_SetCameraPosition(KineFilamentContext *ctx, float x, float y, float z);
KINE_API void Kine_Filament_SetCameraDirection(KineFilamentContext *ctx, float dx, float dy, float dz);


KINE_API KineFilamentMesh *Kine_Filament_CreateMesh(KineFilamentContext *ctx, int shape);

KINE_API KineFilamentMesh *Kine_Filament_GetWaterGrid(
	KineFilamentContext *ctx, float width, float depth);

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


KINE_API int Kine_Filament_GetMeshBoneCount(const KineFilamentMesh *mesh);

KINE_API bool Kine_Filament_GetMeshBounds(const KineFilamentMesh *mesh, float *center, float *halfExtent);

KINE_API void Kine_Filament_SetUseImportedMaterials(KineFilamentContext *ctx, KineFilamentMesh *mesh, bool enabled);
KINE_API int Kine_Filament_GetMeshMaterialCount(const KineFilamentMesh *mesh);
KINE_API KineFilamentTex *Kine_Filament_GetMeshMaterialTexture(const KineFilamentMesh *mesh, int index);
KINE_API const char *Kine_Filament_GetMeshBoneName(const KineFilamentMesh *mesh, int boneIndex);
KINE_API int Kine_Filament_GetMeshBoneParent(const KineFilamentMesh *mesh, int boneIndex);
KINE_API bool Kine_Filament_CopyMeshBoneBindTransform(
	const KineFilamentMesh *mesh, int boneIndex, float *outTransform16);
KINE_API bool Kine_Filament_CopyMeshBoneGlobalTransform(
	const KineFilamentMesh *mesh, int boneIndex, float *outTransform16);
KINE_API bool Kine_Filament_SetMeshBoneTransforms(
	KineFilamentContext *ctx, KineFilamentMesh *mesh,
	const float *boneTransforms16, int boneCount);
KINE_API bool Kine_Filament_SetMeshProceduralLocalPose(
    KineFilamentContext *ctx, KineFilamentMesh *mesh,
    const float *localTransforms16, const uint8_t *mask, int boneCount);
KINE_API bool Kine_Filament_ClearMeshProceduralPose(
    KineFilamentContext *ctx, KineFilamentMesh *mesh);
KINE_API int Kine_Filament_GetMeshAnimationCount(const KineFilamentMesh *mesh);
KINE_API const char *Kine_Filament_GetMeshAnimationName(
	const KineFilamentMesh *mesh, int animationIndex);
KINE_API float Kine_Filament_GetMeshAnimationDuration(
	const KineFilamentMesh *mesh, int animationIndex);
KINE_API bool Kine_Filament_ApplyMeshAnimation(
	KineFilamentContext *ctx, KineFilamentMesh *mesh,
	int animationIndex, float timeSeconds, bool loop);


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


KINE_API KineFilamentMesh *Kine_Filament_CreateCustomMesh(
	KineFilamentContext *ctx,
	const float *vertexData,
	int vertexCount,
	const uint16_t *indices,
	int indexCount);

KINE_API KineFilamentMesh *Kine_Filament_CreateCustomMesh32(
	KineFilamentContext *ctx,
	const float *vertexData,
	int vertexCount,
	const uint32_t *indices,
	int indexCount);


KINE_API KineFilamentMesh *Kine_Filament_CreateCustomMeshEx(
	KineFilamentContext *ctx,
	const float *vertexData,
	const float *colorData,
	int vertexCount,
	const uint16_t *indices,
	int indexCount);
KINE_API KineFilamentMesh *Kine_Filament_CreateCustomMeshEx32(
	KineFilamentContext *ctx,
	const float *vertexData,
	const float *colorData,
	int vertexCount,
	const uint32_t *indices,
	int indexCount);
KINE_API KineFilamentMesh *Kine_Filament_CreateTerrainMesh(
	KineFilamentContext *ctx,
	const float *vertexData,
	const float *materialWeights,
	int vertexCount,
	const uint16_t *indices,
	int indexCount);


KINE_API bool Kine_Filament_UploadTerrainField(
	KineFilamentContext *ctx,
	KineFilamentMesh *mesh,
	const float *samples,
	const int32_t sampleSize[3],
	const int32_t sampleOrigin[3],
	const int32_t boundsMin[3],
	const int32_t boundsMax[3],
	float voxelSize,
	float isoLevel);
KINE_API bool Kine_Filament_UpdateCustomMesh(
	KineFilamentContext *ctx,
	KineFilamentMesh *mesh,
	const float *vertexData,
	int vertexCount);


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
	double *mat4,
	int hoveredAxis,
	int selectedAxis);
KINE_API int Kine_Filament_PickGizmo(
	KineFilamentContext *ctx,
	KineFilamentGizmo *gizmo,
	double *mat4,
	float screenX,
	float screenY);
KINE_API float Kine_Filament_GetGizmoDragDelta(
	KineFilamentContext *ctx,
	KineFilamentGizmo *gizmo,
	double *mat4,
	int axis,
	float startX,
	float startY,
	float currentX,
	float currentY);


KINE_API int Kine_Filament_GetGizmoPlaneDragDelta(
	KineFilamentContext *ctx,
	KineFilamentGizmo *gizmo,
	double *mat4,
	int axis,
	float startX,
	float startY,
	float currentX,
	float currentY,
	float *outFirst,
	float *outSecond);


KINE_API void Kine_Filament_ReadPixels(KineFilamentContext *ctx, void *outPixels);
KINE_API int Kine_Filament_GetWidth(KineFilamentContext *ctx);
KINE_API int Kine_Filament_GetHeight(KineFilamentContext *ctx);


KINE_API void Kine_Filament_SetSkyAtmosphere(
	KineFilamentContext *ctx,
	float sunDirX, float sunDirY, float sunDirZ,
	float skyR, float skyG, float skyB,
	float horizonR, float horizonG, float horizonB,
	float groundR, float groundG, float groundB,
	float sunIntensity);


KINE_API int32_t Kine_Filament_CreateSkyboxPixels(KineFilamentContext *ctx, int32_t size, const uint8_t *rgba, bool showSun);
KINE_API void Kine_Filament_CreateSkyboxCubemap(
	KineFilamentContext *ctx,
	const KineGLTextureInfo *texPosX, const KineGLTextureInfo *texNegX,
	const KineGLTextureInfo *texPosY, const KineGLTextureInfo *texNegY,
	const KineGLTextureInfo *texPosZ, const KineGLTextureInfo *texNegZ);


KINE_API void Kine_Filament_SetSun(
	KineFilamentContext *ctx,
	float sunDirX, float sunDirY, float sunDirZ,
	float sunIntensity);


KINE_API int Kine_Filament_CreateLight(
	KineFilamentContext *ctx,
	double px, double py, double pz,
	float cr, float cg, float cb,
	float intensity, float falloff);

KINE_API int Kine_Filament_CreateLightEx(
	KineFilamentContext *ctx, int lightType,
	double px, double py, double pz,
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
	KineFilamentContext *ctx, int light, double x, double y, double z);
KINE_API void Kine_Filament_SetDirectionLight(
	KineFilamentContext *ctx, int light, float x, float y, float z);
KINE_API void Kine_Filament_SetConeLight(
	KineFilamentContext *ctx, int light, float innerRadians, float outerRadians);
KINE_API void Kine_Filament_SetShadowLight(
	KineFilamentContext *ctx, int light, bool castShadows);
KINE_API void Kine_Filament_SetEnabledLight(
	KineFilamentContext *ctx, int light, bool enabled);
KINE_API void Kine_Filament_RemoveLight(KineFilamentContext *ctx, int light);


KINE_API void Kine_Filament_DrawGizmoLine(
	KineFilamentContext *ctx,
	double ax, double ay, double az,
	double bx, double by, double bz,
	float r, float g, float b,
	float thickness);


KINE_API void Kine_Filament_DrawGizmoLines(
	KineFilamentContext *ctx,
	const double *points,
	uint32_t segmentCount,
	float r, float g, float b,
	float thickness);


KINE_API void Kine_Filament_DrawGizmoCube(
	KineFilamentContext *ctx,
	const double *mat4,
	float r, float g, float b,
	bool wire,
	float thickness);

KINE_API void Kine_Filament_DrawGizmoSphere(
	KineFilamentContext *ctx,
	double cx, double cy, double cz,
	float radius,
	float r, float g, float b,
	bool wire,
	float thickness,
	int segments);


KINE_API void Kine_Filament_DrawGizmoCylinder(
	KineFilamentContext *ctx,
	const double *mat4,
	float r, float g, float b,
	bool wire,
	float thickness,
	int segments);


KINE_API void Kine_Filament_DrawGizmoMesh(
	KineFilamentContext *ctx,
	KineFilamentMesh *mesh,
	const double *mat4,
	float r, float g, float b);


KINE_API void Kine_Filament_DrawGizmoWireMesh(
    KineFilamentContext* ctx,
    KineFilamentMesh* mesh,
    const double* mat4,
    float r, float g, float b,
    float thickness,
    float featureAngleDeg);


KINE_API int Kine_Filament_CreateDecal(
	KineFilamentContext *ctx,
	float width, float height,
	KineFilamentTex *texture,
	float offsetStudsU, float offsetStudsV,
	float studsPerTileU, float studsPerTileV,
	bool culling, bool castShadows, bool receiveShadows);


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
KINE_API bool Kine_Filament_SetDecalTransform(KineFilamentContext *ctx, int decal, double *mat4);

KINE_API bool Kine_Filament_EditDecal(
	KineFilamentContext *ctx, int decal,
	float width, float height,
	bool culling, bool castShadows, bool receiveShadows);

#ifdef __cplusplus
}
#endif

#endif
