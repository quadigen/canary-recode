package kineffi

import sdl3 "vendor:sdl3"

when ODIN_OS == .Windows {
	foreign import lib {
		"../../../vendor/build/lib/kine_sdl3.lib",
		"../../../vendor/build/lib/kine_filament.lib",
		"../../../vendor/build/lib/kine_filament_matp.lib",
		"../../../vendor/build/lib/kine_filament_filamat.lib",
		"../../../vendor/build/lib/kine_filament_filament.lib",
		"../../../vendor/build/lib/kine_filament_backend.lib",
		"../../../vendor/build/lib/kine_filament_bluegl.lib",
		"../../../vendor/build/lib/kine_filament_bluevk.lib",
		"../../../vendor/build/lib/kine_filament_filabridge.lib",
		"../../../vendor/build/lib/kine_filament_filaflat.lib",
		"../../../vendor/build/lib/kine_filament_utils.lib",
		"../../../vendor/build/lib/kine_filament_geometry.lib",
		"../../../vendor/build/lib/kine_filament_smol-v.lib",
		"../../../vendor/build/lib/kine_filament_zstd.lib",
		"../../../vendor/build/lib/kine_filament_uberarchive.lib",
		"../../../vendor/build/lib/kine_filament_shaders.lib",
		"../../../vendor/build/lib/kine_assimp.lib",
		"../../../vendor/build/lib/kine_zlib.lib",
		"../../../vendor/build/lib/kine_vk.lib",
		"../../../vendor/build/lib/kine_skia.lib",
		"../../../vendor/build/lib/kine_skia_skiacore.lib",
		"../../../vendor/build/lib/kine_skia_svg.lib",
		"../../../vendor/build/lib/kine_skia_skshaper.lib",
		"../../../vendor/build/lib/kine_skia_skunicode_core.lib",
		"../../../vendor/build/lib/kine_skia_skunicode_icu.lib",
		"../../../vendor/build/lib/kine_vulkan_loader.lib",
		"system:advapi32.lib",
		"system:d2d1.lib",
		"system:delayimp.lib",
		"system:dwrite.lib",
		"system:dxgi.lib",
		"system:gdi32.lib",
		"system:imm32.lib",
		"system:ole32.lib",
		"system:oleaut32.lib",
		"system:opengl32.lib",
		"system:setupapi.lib",
		"system:shell32.lib",
		"system:shlwapi.lib",
		"system:user32.lib",
		"system:version.lib",
		"system:winmm.lib",
	}
} else {
	foreign import lib "../../../vendor/build/lib/kine_filament.a"
}

KineFilamentContext       :: struct {}
KineFilamentMesh          :: struct {}
KineFilamentMeshData      :: struct {}
KineFilamentTex           :: struct {}
KineFilamentInstanceBatch :: struct {}
KineFilamentShader        :: struct {}

@(default_calling_convention="c")
foreign lib {
	Kine_Filament_Shader_Destroy    :: proc(shader: ^KineFilamentShader) -> i32 ---
	Kine_Filament_Shader_SetUniform :: proc(shader: ^KineFilamentShader, name: cstring, values: ^f32, valueCount: i32) -> i32 ---
	Kine_Filament_SetGlobalShader   :: proc(ctx: ^KineFilamentContext, shader: ^KineFilamentShader) -> i32 ---

	/* Applies a surface-domain Filamat material as a fullscreen pass. The material
	must declare a sampler2d parameter named inputTexture. */
	Kine_Filament_SetPostProcessShader :: proc(ctx: ^KineFilamentContext, shader: ^KineFilamentShader) -> i32 ---
	Kine_Filament_Shader_GetLastError  :: proc() -> ^i32 ---
}

KINE_FILAMENT_DRAW_CAST_SHADOWS    :: (1<<0)
KINE_FILAMENT_DRAW_RECEIVE_SHADOWS :: (1<<1)
KINE_FILAMENT_DRAW_CULLING         :: (1<<2)

/* Packed frame-submission item used by Kine_Filament_DrawMeshList.
Keep this layout in sync with filament/structs.luau. */
KineFilamentDrawItem :: struct {
	mesh:         ^KineFilamentMesh,
	tex:          ^KineFilamentTex,
	transform:    [16]f32,
	r:            f32,
	g:            f32,
	b:            f32,
	param1:       f32,
	param2:       f32,
	param3:       f32,
	transmission: f32,
	materialKind: i32,
	flags:        u32,
	reserved:     u32,
	shader:       ^KineFilamentShader,
}

KineFilamentParticleItem :: struct {
	transform: [16]f32,
	r:         u8,
	g:         u8,
	b:         u8,
	a:         u8,
}

KineGLTextureInfo :: struct {
	id:      u32,
	width:   i32,
	height:  i32,
	mipmaps: i32,
	format:  i32,
}

KineFilamentVulkanBackend :: struct {
	instance:                 rawptr, /* VkInstance */
	physicalDevice:           rawptr, /* VkPhysicalDevice */
	device:                   rawptr, /* VkDevice */
	queue:                    rawptr, /* VkQueue */
	graphicsQueueFamilyIndex: u32,
	maxApiVersion:            u32,    /* 0 = let Skia infer/default */
	getInstanceProcAddr:      rawptr, /* PFN_vkGetInstanceProcAddr */
	getDeviceProcAddr:        rawptr, /* PFN_vkGetDeviceProcAddr */
}

// ---------------------------------------------------------------------------
// Material kinds for Kine_Filament_DrawMeshEx's materialKind parameter.
// Keep in sync with the KineMaterialKind enum in kine_filament_shim.cpp.
// ---------------------------------------------------------------------------
KINE_MAT_DEFAULT  :: 0
KINE_MAT_GLASS    :: 1
KINE_MAT_NEON     :: 2
KINE_MAT_WATER    :: 3
KINE_MAT_OUTLINE  :: 4
KINE_MAT_GIZMO    :: 5
KINE_MAT_PARTICLE :: 6
KINE_MAT_TERRAIN  :: 7

// Which arm/handle of a gizmo is being interacted with.
KINE_GIZMO_AXIS_NONE   :: 0
KINE_GIZMO_AXIS_X      :: 1
KINE_GIZMO_AXIS_Y      :: 2
KINE_GIZMO_AXIS_Z      :: 3
KINE_GIZMO_AXIS_CENTER :: 4
KINE_MESH_CUBE           :: 1
KINE_MESH_SPHERE         :: 2
KINE_MESH_PYRAMID        :: 3
KINE_MESH_PARTICLE_QUAD  :: 4
KINE_MESH_DISPLACED_CUBE :: 5
KINE_MESH_CYLINDER       :: 6

// Gizmo type, matches the existing shape codes used by Kine_Filament_CreateMesh.
KINE_GIZMO_MOVE   :: 10
KINE_GIZMO_ROTATE :: 11
KINE_GIZMO_SCALE  :: 12

KineFilamentGizmo :: struct {}

@(default_calling_convention="c")
foreign lib {
	Kine_Filament_Create                          :: proc(width: i32, height: i32) -> ^KineFilamentContext ---
	Kine_Filament_CreateForSDLWindow              :: proc(sdlWindow: rawptr, width: i32, height: i32) -> ^KineFilamentContext ---
	Kine_Filament_CreateForVulkanCompositor       :: proc(compositor: rawptr, width: i32, height: i32) -> ^KineFilamentContext ---
	Kine_Filament_CreateForVulkanCompositorWindow :: proc(sdlWindow: ^sdl3.Window, width: i32, height: i32) -> ^KineFilamentContext ---
	Kine_Filament_GetVulkanCompositor             :: proc(ctx: ^KineFilamentContext) -> rawptr ---
	Kine_Filament_GetColorTextureId   :: proc(ctx: ^KineFilamentContext) -> i32 ---
	Kine_Filament_GetVulkanBackend    :: proc(ctx: ^KineFilamentContext, outBackend: ^KineFilamentVulkanBackend) -> i32 ---
	Kine_Filament_Destroy             :: proc(ctx: ^KineFilamentContext) ---
	Kine_Filament_CreateMesh :: proc(
		ctx: ^KineFilamentContext,
		shape: i32,
	) -> ^KineFilamentMesh ---

	// deltaTime (seconds) drives ctx->time, used to animate the water material.
	Kine_Filament_RenderFrame               :: proc(ctx: ^KineFilamentContext, deltaTime: f32) ---
	Kine_Filament_Resize                    :: proc(ctx: ^KineFilamentContext, width: i32, height: i32) ---
	Kine_Filament_SetViewport               :: proc(ctx: ^KineFilamentContext, x: i32, y: i32, width: i32, height: i32) -> i32 ---
	Kine_Filament_CreateSky                 :: proc(ctx: ^KineFilamentContext, r: f32, g: f32, b: f32, a: f32) ---
	Kine_Filament_SetPostProcessing         :: proc(ctx: ^KineFilamentContext, enabled: bool) -> i32 ---
	Kine_Filament_SetBloom                  :: proc(ctx: ^KineFilamentContext, enabled: bool, strength: f32, resolution: i32, levels: i32, threshold: bool, lensFlare: bool) -> i32 ---
	Kine_Filament_SetAmbientOcclusion       :: proc(ctx: ^KineFilamentContext, enabled: bool, radius: f32, power: f32, intensity: f32, quality: i32, aoType: i32) -> i32 ---
	Kine_Filament_SetAntiAliasing           :: proc(ctx: ^KineFilamentContext, fxaa: bool, taa: bool, msaa: bool, sampleCount: i32) -> i32 ---
	Kine_Filament_SetDynamicResolution      :: proc(ctx: ^KineFilamentContext, enabled: bool, minScale: f32, maxScale: f32, quality: i32, sharpness: f32) -> i32 ---
	Kine_Filament_SetDepthOfField           :: proc(ctx: ^KineFilamentContext, enabled: bool, cocScale: f32, cocAspectRatio: f32, maxApertureDiameter: f32, maxForegroundCOC: i32, maxBackgroundCOC: i32) -> i32 ---
	Kine_Filament_SetFocusDistance          :: proc(ctx: ^KineFilamentContext, distance: f32) -> i32 ---
	Kine_Filament_SetVignette               :: proc(ctx: ^KineFilamentContext, enabled: bool, midPoint: f32, roundness: f32, feather: f32, r: f32, g: f32, b: f32, a: f32) -> i32 ---
	Kine_Filament_SetScreenSpaceReflections :: proc(ctx: ^KineFilamentContext, enabled: bool, thickness: f32, bias: f32, maxDistance: f32, stride: f32) -> i32 ---
	Kine_Filament_SetColorGrading           :: proc(ctx: ^KineFilamentContext, exposure: f32, contrast: f32, saturation: f32, vibrance: f32, temperature: f32, tint: f32) -> i32 ---
	Kine_Filament_ClearColorGrading         :: proc(ctx: ^KineFilamentContext) -> i32 ---
	Kine_Filament_SetRenderQuality          :: proc(ctx: ^KineFilamentContext, hdrQuality: i32) -> i32 ---
	Kine_Filament_SetDithering              :: proc(ctx: ^KineFilamentContext, enabled: bool) -> i32 ---
	Kine_Filament_SetShadowOptions          :: proc(ctx: ^KineFilamentContext, enabled: bool, shadowType: i32) -> i32 ---
	Kine_Filament_SetSunShadowOptions       :: proc(ctx: ^KineFilamentContext, mapSize: i32, cascades: i32, shadowFar: f32, shadowNearHint: f32, shadowFarHint: f32, stable: bool, contactShadows: bool) -> i32 ---
	Kine_Filament_SetSunRays                :: proc(ctx: ^KineFilamentContext, enabled: bool, distance: f32, cutOffDistance: f32, maximumOpacity: f32, height: f32, heightFalloff: f32, density: f32, inScatteringStart: f32, inScatteringSize: f32, r: f32, g: f32, b: f32, fogColorFromIbl: bool) -> i32 ---
	Kine_Filament_UpdateTexFromPixels       :: proc(ctx: ^KineFilamentContext, tex: ^KineFilamentTex, width: i32, height: i32, rowBytes: i32, pixelsRGBA8: rawptr) -> i32 ---
	Kine_Filament_GetEngine                 :: proc(ctx: ^KineFilamentContext) -> ^i32 ---
	Kine_Filament_GetScene                  :: proc(ctx: ^KineFilamentContext) -> ^i32 ---
	Kine_Filament_GetView                   :: proc(ctx: ^KineFilamentContext) -> ^i32 ---
	Kine_Filament_GetCamera                 :: proc(ctx: ^KineFilamentContext) -> ^i32 ---
	Kine_Filament_SetCameraLookAt           :: proc(ctx: ^KineFilamentContext, eyeX: f32, eyeY: f32, eyeZ: f32, targetX: f32, targetY: f32, targetZ: f32, upX: f32, upY: f32, upZ: f32) ---
	Kine_Filament_BlitToScreen              :: proc(ctx: ^KineFilamentContext, dstX: i32, dstY: i32, dstWidth: i32, dstHeight: i32) -> i32 ---
	Kine_Filament_SetCameraPerspective      :: proc(ctx: ^KineFilamentContext, fovYDegrees: f64, aspect: f64, nearPlane: f64, farPlane: f64) ---
	Kine_Filament_SetCameraPosition         :: proc(ctx: ^KineFilamentContext, x: f32, y: f32, z: f32) ---
	Kine_Filament_SetCameraDirection        :: proc(ctx: ^KineFilamentContext, dx: f32, dy: f32, dz: f32) ---
	Kine_Filament_DestroyMesh               :: proc(ctx: ^KineFilamentContext, mesh: ^KineFilamentMesh) -> i32 ---
	Kine_Filament_CreateTex                 :: proc(ctx: ^KineFilamentContext, tex: ^KineGLTextureInfo) -> i32 ---
	Kine_Filament_CreateTexFromPixels :: proc(
		ctx: ^KineFilamentContext,
		width: i32,
		height: i32,
		rowBytes: i32,
		pixelsRGBA8: rawptr,
	) -> ^KineFilamentTex ---

	/* Imported skeletal data. Bind transforms and caller-provided bone transforms
	are row-major affine float[16] matrices in mesh-local space. Bone transforms
	are converted to final skin matrices with the imported inverse bind pose. */
	Kine_Filament_GetMeshBoneCount          :: proc(mesh: ^KineFilamentMesh) -> i32 ---
	Kine_Filament_GetMeshBoneName           :: proc(mesh: ^KineFilamentMesh, boneIndex: i32) -> ^i32 ---
	Kine_Filament_GetMeshBoneParent         :: proc(mesh: ^KineFilamentMesh, boneIndex: i32) -> i32 ---
	Kine_Filament_CopyMeshBoneBindTransform :: proc(mesh: ^KineFilamentMesh, boneIndex: i32, outTransform16: ^f32) -> i32 ---
	Kine_Filament_SetMeshBoneTransforms     :: proc(ctx: ^KineFilamentContext, mesh: ^KineFilamentMesh, boneTransforms16: ^f32, boneCount: i32) -> i32 ---
	Kine_Filament_GetMeshAnimationCount     :: proc(mesh: ^KineFilamentMesh) -> i32 ---
	Kine_Filament_GetMeshAnimationName      :: proc(mesh: ^KineFilamentMesh, animationIndex: i32) -> ^i32 ---
	Kine_Filament_GetMeshAnimationDuration  :: proc(mesh: ^KineFilamentMesh, animationIndex: i32) -> i32 ---
	Kine_Filament_ApplyMeshAnimation        :: proc(ctx: ^KineFilamentContext, mesh: ^KineFilamentMesh, animationIndex: i32, timeSeconds: f32, loop: bool) -> i32 ---
	Kine_Filament_GetMeshDataVertexCount    :: proc(meshData: ^KineFilamentMeshData) -> i32 ---
	Kine_Filament_GetMeshDataIndexCount     :: proc(meshData: ^KineFilamentMeshData) -> i32 ---
	Kine_Filament_CopyMeshDataPositions     :: proc(meshData: ^KineFilamentMeshData, outPositions: ^f32, positionFloatCapacity: i32) -> i32 ---
	Kine_Filament_CopyMeshDataIndices       :: proc(meshData: ^KineFilamentMeshData, outIndices: ^u32, indexCapacity: i32) -> i32 ---
	Kine_Filament_DestroyMeshData           :: proc(meshData: ^KineFilamentMeshData) -> i32 ---
	Kine_Filament_DebugPrintPixel           :: proc(ctx: ^KineFilamentContext) -> i32 ---
	Kine_Filament_DestroyGizmo              :: proc(ctx: ^KineFilamentContext, gizmo: ^KineFilamentGizmo) -> i32 ---
	Kine_Filament_DestroyTex                :: proc(ctx: ^KineFilamentContext, tex: ^KineFilamentTex) -> i32 ---
	Kine_Filament_UpdateCustomMesh          :: proc(ctx: ^KineFilamentContext, mesh: ^KineFilamentMesh, vertexData: ^f32, vertexCount: i32) -> i32 ---
	Kine_Filament_DrawMeshEx                :: proc(ctx: ^KineFilamentContext, mesh: ^KineFilamentMesh, materialKind: i32, r: f32, g: f32, b: f32, param1: f32, param2: f32, param3: f32, transmission: f32, mat4: ^f32, castShadows: bool, receiveShadows: bool, culling: bool, tex: ^KineFilamentTex) -> i32 ---
	Kine_Filament_DrawMeshList              :: proc(ctx: ^KineFilamentContext, items: ^KineFilamentDrawItem, itemCount: u32) -> i32 ---

	/* Retained draw stream. Reusing the same streamId/version keeps the existing
	GPU instance buffers without resubmitting the item array. */
	Kine_Filament_DrawMeshListVersioned    :: proc(ctx: ^KineFilamentContext, items: ^KineFilamentDrawItem, itemCount: u32, streamId: u64, version: u64) -> i32 ---
	Kine_Filament_DestroyInstanceBatch     :: proc(batch: ^KineFilamentInstanceBatch) -> i32 ---
	Kine_Filament_UpdateInstanceTransforms :: proc(batch: ^KineFilamentInstanceBatch, indices: ^u32, transforms: ^f32, dirtyCount: u32) -> i32 ---
	Kine_Filament_DrawParticles            :: proc(ctx: ^KineFilamentContext, texture: ^KineFilamentTex, items: ^KineFilamentParticleItem, itemCount: u32, uvScaleX: f32, uvScaleY: f32, uvOffsetX: f32, uvOffsetY: f32, castShadows: bool, culling: bool) -> i32 ---
	Kine_Filament_DrawMeshOutline          :: proc(ctx: ^KineFilamentContext, mesh: ^KineFilamentMesh, r: f32, g: f32, b: f32, thickness: f32, mat4: ^f32) -> i32 ---
	Kine_Filament_DrawGizmo                :: proc(ctx: ^KineFilamentContext, gizmo: ^KineFilamentGizmo, mat4: ^f32, hoveredAxis: i32, selectedAxis: i32) -> i32 ---
	Kine_Filament_PickGizmo                :: proc(ctx: ^KineFilamentContext, gizmo: ^KineFilamentGizmo, mat4: ^f32, screenX: f32, screenY: f32) -> i32 ---
	Kine_Filament_GetGizmoDragDelta        :: proc(ctx: ^KineFilamentContext, gizmo: ^KineFilamentGizmo, mat4: ^f32, axis: i32, startX: f32, startY: f32, currentX: f32, currentY: f32) -> i32 ---

	// OpenGL path reads the offscreen GL color target. Vulkan builds intentionally
	// keep this disabled unless KINE_FILAMENT_VULKAN_READBACK=ON is set, because a
	// per-frame GPU readback is a debugging path, not the high-performance compositor path.
	Kine_Filament_ReadPixels :: proc(ctx: ^KineFilamentContext, outPixels: rawptr) -> i32 ---
	Kine_Filament_GetWidth   :: proc(ctx: ^KineFilamentContext) -> i32 ---
	Kine_Filament_GetHeight  :: proc(ctx: ^KineFilamentContext) -> i32 ---

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
	Kine_Filament_SetSkyAtmosphere :: proc(ctx: ^KineFilamentContext, sunDirX: f32, sunDirY: f32, sunDirZ: f32, skyR: f32, skyG: f32, skyB: f32, horizonR: f32, horizonG: f32, horizonB: f32, groundR: f32, groundG: f32, groundB: f32, sunIntensity: f32) -> i32 ---

	// ---------------------------------------------------------------------------
	// Custom Texture Cubemap Skybox
	// Takes 6 OpenGL texture descriptors and builds a cubemap skybox from them.
	// Faces must all be square and have identical dimensions.
	// ---------------------------------------------------------------------------
	Kine_Filament_CreateSkyboxCubemap :: proc(ctx: ^KineFilamentContext, texPosX: ^KineGLTextureInfo, texNegX: ^KineGLTextureInfo, texPosY: ^KineGLTextureInfo, texNegY: ^KineGLTextureInfo, texPosZ: ^KineGLTextureInfo, texNegZ: ^KineGLTextureInfo) -> i32 ---

	// ---------------------------------------------------------------------------
	// Set the built-in sun light direction and intensity independently of the sky.
	// ---------------------------------------------------------------------------
	Kine_Filament_SetSun :: proc(ctx: ^KineFilamentContext, sunDirX: f32, sunDirY: f32, sunDirZ: f32, sunIntensity: f32) -> i32 ---

	// ---------------------------------------------------------------------------
	// Point / spot light management.
	// Returns an opaque integer light ID, or -1 on failure.
	// ---------------------------------------------------------------------------
	Kine_Filament_CreateLight       :: proc(ctx: ^KineFilamentContext, px: f32, py: f32, pz: f32, cr: f32, cg: f32, cb: f32, intensity: f32, falloff: f32) -> i32 ---
	Kine_Filament_CreateLightEx     :: proc(ctx: ^KineFilamentContext, lightType: i32, px: f32, py: f32, pz: f32, dx: f32, dy: f32, dz: f32, cr: f32, cg: f32, cb: f32, intensity: f32, falloff: f32, innerConeRadians: f32, outerConeRadians: f32, castShadows: bool, enabled: bool) -> i32 ---
	Kine_Filament_SetColorLight     :: proc(ctx: ^KineFilamentContext, light: i32, r: f32, g: f32, b: f32) -> i32 ---
	Kine_Filament_SetIntensityLight :: proc(ctx: ^KineFilamentContext, light: i32, intensity: f32) -> i32 ---
	Kine_Filament_SetFalloffLight   :: proc(ctx: ^KineFilamentContext, light: i32, falloff: f32) -> i32 ---
	Kine_Filament_SetPositionLight  :: proc(ctx: ^KineFilamentContext, light: i32, x: f32, y: f32, z: f32) -> i32 ---
	Kine_Filament_SetDirectionLight :: proc(ctx: ^KineFilamentContext, light: i32, x: f32, y: f32, z: f32) -> i32 ---
	Kine_Filament_SetConeLight      :: proc(ctx: ^KineFilamentContext, light: i32, innerRadians: f32, outerRadians: f32) -> i32 ---
	Kine_Filament_SetShadowLight    :: proc(ctx: ^KineFilamentContext, light: i32, castShadows: bool) -> i32 ---
	Kine_Filament_SetEnabledLight   :: proc(ctx: ^KineFilamentContext, light: i32, enabled: bool) -> i32 ---
	Kine_Filament_RemoveLight       :: proc(ctx: ^KineFilamentContext, light: i32) -> i32 ---

	// ---------------------------------------------------------------------------
	// Screen-space decal management.
	// Returns an opaque integer decal ID, or -1 on failure.
	// ---------------------------------------------------------------------------
	Kine_Filament_CreateDecal       :: proc(ctx: ^KineFilamentContext, width: f32, height: f32, texture: ^KineFilamentTex, offsetStudsU: f32, offsetStudsV: f32, studsPerTileU: f32, studsPerTileV: f32, culling: bool, castShadows: bool, receiveShadows: bool) -> i32 ---
	Kine_Filament_SetDecalTiling    :: proc(ctx: ^KineFilamentContext, decal: i32, width: f32, height: f32, offsetStudsU: f32, offsetStudsV: f32, studsPerTileU: f32, studsPerTileV: f32) -> i32 ---
	Kine_Filament_RemoveDecal       :: proc(ctx: ^KineFilamentContext, decal: i32) -> i32 ---
	Kine_Filament_SetDecalTransform :: proc(ctx: ^KineFilamentContext, decal: i32, mat4: ^f32) -> i32 ---
	Kine_Filament_EditDecal         :: proc(ctx: ^KineFilamentContext, decal: i32, width: f32, height: f32, culling: bool, castShadows: bool, receiveShadows: bool) -> i32 ---
}
