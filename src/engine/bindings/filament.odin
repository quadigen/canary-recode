package kineffi

import sdl3 "../platform"

when ODIN_OS == .JS {
	foreign import kine_filament "kinemium_filament"
} else when ODIN_OS == .Windows {
	foreign import kine_filament {"../../../vendor/build/lib/kine_sdl3.lib", "../../../vendor/build/lib/kine_filament.lib", "../../../vendor/build/lib/kine_filament_filament-iblprefilter.lib", "../../../vendor/build/lib/kine_filament_matp.lib", "../../../vendor/build/lib/kine_filament_filamat.lib", "../../../vendor/build/lib/kine_filament_filament.lib", "../../../vendor/build/lib/kine_filament_backend.lib", "../../../vendor/build/lib/kine_filament_bluegl.lib", "../../../vendor/build/lib/kine_filament_bluevk.lib", "../../../vendor/build/lib/kine_filament_filabridge.lib", "../../../vendor/build/lib/kine_filament_filaflat.lib", "../../../vendor/build/lib/kine_filament_utils.lib", "../../../vendor/build/lib/kine_filament_geometry.lib", "../../../vendor/build/lib/kine_filament_smol-v.lib", "../../../vendor/build/lib/kine_filament_zstd.lib", "../../../vendor/build/lib/kine_filament_uberarchive.lib", "../../../vendor/build/lib/kine_filament_shaders.lib", "../../../vendor/build/lib/kine_assimp.lib", "../../../vendor/build/lib/kine_zlib.lib", "../../../vendor/build/lib/kine_ray.lib", "../../../vendor/build/lib/kine_vk.lib", "../../../vendor/build/lib/kine_skia.lib", "../../../vendor/build/lib/kine_skia_skiacore.lib", "../../../vendor/build/lib/kine_skia_svg.lib", "../../../vendor/build/lib/kine_skia_skshaper.lib", "../../../vendor/build/lib/kine_skia_skunicode_core.lib", "../../../vendor/build/lib/kine_skia_skunicode_icu.lib", "../../../vendor/build/lib/kine_vulkan_loader.lib", "system:advapi32.lib", "system:d2d1.lib", "system:delayimp.lib", "system:dwrite.lib", "system:dxgi.lib", "system:gdi32.lib", "system:imm32.lib", "system:ole32.lib", "system:oleaut32.lib", "system:opengl32.lib", "system:setupapi.lib", "system:shell32.lib", "system:shlwapi.lib", "system:user32.lib", "system:version.lib", "system:winmm.lib"}
} else when #config(KINE_ANDROID, false) {
	foreign import kine_filament "../../../build/android-native/lib/libkine_filament_shim.a"
} else when ODIN_OS == .Darwin {
	foreign import kine_filament {"../../../vendor/build/lib/KinemiumLibs.a", "system:vulkan", "system:c++", "system:z", "system:AppKit.framework", "system:Cocoa.framework", "system:CoreFoundation.framework", "system:CoreGraphics.framework", "system:CoreServices.framework", "system:CoreText.framework", "system:CoreVideo.framework", "system:IOKit.framework", "system:Metal.framework", "system:MetalKit.framework", "system:OpenGL.framework", "system:QuartzCore.framework", "system:UniformTypeIdentifiers.framework"}
} else {
	foreign import kine_filament {"../../../vendor/build/lib/KinemiumLibs.a", "system:vulkan", "system:c++", "system:GL", "system:X11", "system:dl", "system:pthread", "system:m"}
}

KINE_RENDER_MODE_FILAMENT :: 1
KINE_RENDER_MODE_RAY :: 2

KineFilamentContext :: struct {}
KineFilamentMesh :: struct {}
KineFilamentMeshData :: struct {}
KineFilamentMeshList :: struct {}
KineFilamentTex :: struct {}
KineFilamentInstanceBatch :: struct {}
KineFilamentShader :: struct {}
KineFilamentShaderCompile :: struct {}

@(default_calling_convention = "c")
foreign kine_filament {
	Kine_Filament_Shader_Destroy :: proc(shader: ^KineFilamentShader) ---
	Kine_Filament_Shader_SetUniform :: proc(shader: ^KineFilamentShader, name: cstring, values: ^f32, valueCount: i32) -> bool ---
	Kine_Filament_Shader_SetTextureFromPixels :: proc(shader: ^KineFilamentShader, name: cstring, width, height, rowBytes: i32, pixelsRGBA8: rawptr, srgb: bool) -> bool ---
	Kine_Filament_Shader_SetGeometryOptions :: proc(shader: ^KineFilamentShader, subdivisions: i32, boundsPadding: f32) -> bool ---
	Kine_Filament_Shader_TransferTextures :: proc(source, destination: ^KineFilamentShader) ---
	Kine_Filament_Shader_HasTexture :: proc(shader: ^KineFilamentShader, name: cstring) -> bool ---
	Kine_Filament_SetGlobalShader :: proc(ctx: ^KineFilamentContext, shader: ^KineFilamentShader) -> bool ---


	Kine_Filament_SetPostProcessShader :: proc(ctx: ^KineFilamentContext, shader: ^KineFilamentShader) -> bool ---
	Kine_Filament_Shader_GetLastError :: proc() -> cstring ---
}

KINE_FILAMENT_DRAW_CAST_SHADOWS :: (1 << 0)
KINE_FILAMENT_DRAW_RECEIVE_SHADOWS :: (1 << 1)
KINE_FILAMENT_DRAW_CULLING :: (1 << 2)


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


KineRayProperties :: struct {
	maxTotalDepth:      i32,
	maxDiffuseDepth:    i32,
	maxSpecularDepth:   i32,
	maxRefractionDepth: i32,
	samplesPerFrame:    i32,
	minSamples:         i32,
	varianceThreshold:  f32,
	exposure:           f32,
	clampDirect:        f32,
	clampIndirect:      f32,
}

KineFilamentWaterParams :: struct {
	speed:              f32,
	strength:           f32,
	octaves:            f32,
	height:             f32,
	waveScale:          f32,
	foamAmount:         f32,
	absorptionR:        f32,
	absorptionG:        f32,
	absorptionB:        f32,
	clearCoat:          f32,
	clearCoatRoughness: f32,
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
	instance:                 rawptr,
	physicalDevice:           rawptr,
	device:                   rawptr,
	queue:                    rawptr,
	graphicsQueueFamilyIndex: u32,
	maxApiVersion:            u32,
	getInstanceProcAddr:      rawptr,
	getDeviceProcAddr:        rawptr,
}

KINE_MAT_DEFAULT :: 0
KINE_MAT_GLASS :: 1
KINE_MAT_NEON :: 2
KINE_MAT_WATER :: 3
KINE_MAT_OUTLINE :: 4
KINE_MAT_GIZMO :: 5
KINE_MAT_PARTICLE :: 6
KINE_MAT_TERRAIN :: 7


KINE_MAT_HIGHLIGHT_OUTLINE :: 8
KINE_MAT_HIGHLIGHT_FILL :: 9
KINE_MAT_HIGHLIGHT_OUTLINE_TOP :: 10
KINE_MAT_HIGHLIGHT_FILL_TOP :: 11


KINE_MAT_OUTLINE_MASK :: 12
KINE_MAT_FORCEFIELD :: 13


KINE_GIZMO_AXIS_NONE :: 0
KINE_GIZMO_AXIS_X :: 1
KINE_GIZMO_AXIS_Y :: 2
KINE_GIZMO_AXIS_Z :: 3
KINE_GIZMO_AXIS_CENTER :: 4


KINE_GIZMO_AXIS_XY :: 5
KINE_GIZMO_AXIS_YZ :: 6
KINE_GIZMO_AXIS_XZ :: 7
KINE_GIZMO_AXIS_COUNT :: 8
KINE_MESH_CUBE :: 1
KINE_MESH_SPHERE :: 2
KINE_MESH_PYRAMID :: 3
KINE_MESH_PARTICLE_QUAD :: 4
KINE_MESH_DISPLACED_CUBE :: 5
KINE_MESH_CYLINDER :: 6

KINE_MESH_WATER_GRID :: 7


KINE_GIZMO_MOVE :: 10
KINE_GIZMO_ROTATE :: 11
KINE_GIZMO_SCALE :: 12

KineFilamentGizmo :: struct {}

@(default_calling_convention = "c")
foreign kine_filament {
	Kine_Filament_Create :: proc(width: i32, height: i32) -> ^KineFilamentContext ---
	Kine_Filament_CreateForSDLWindow :: proc(sdlWindow: rawptr, width: i32, height: i32) -> ^KineFilamentContext ---
	Kine_Filament_CreateForVulkanCompositor :: proc(compositor: rawptr, width: i32, height: i32) -> ^KineFilamentContext ---
	Kine_Filament_CreateForVulkanCompositorWindow :: proc(sdlWindow: ^sdl3.Window, width: i32, height: i32) -> ^KineFilamentContext ---
	Kine_Filament_GetVulkanCompositor :: proc(ctx: ^KineFilamentContext) -> rawptr ---
	Kine_Filament_GetColorTextureId :: proc(ctx: ^KineFilamentContext) -> i32 ---
	Kine_Filament_GetVulkanBackend :: proc(ctx: ^KineFilamentContext, outBackend: ^KineFilamentVulkanBackend) -> i32 ---
	Kine_Filament_Destroy :: proc(ctx: ^KineFilamentContext) ---


	Kine_Filament_NewRay :: proc(ctx: ^KineFilamentContext, width: i32, height: i32) -> bool ---
	Kine_Filament_DestroyRay :: proc(ctx: ^KineFilamentContext) ---
	Kine_Filament_SetRenderMode :: proc(ctx: ^KineFilamentContext, mode: i32) -> bool ---
	Kine_Filament_GetRenderMode :: proc(ctx: ^KineFilamentContext) -> i32 ---
	Kine_Filament_HasRay :: proc(ctx: ^KineFilamentContext) -> bool ---
	Kine_Filament_GetRayError :: proc() -> cstring ---


	Kine_Ray_SetProperties :: proc(ctx: ^KineFilamentContext, properties: ^KineRayProperties) -> bool ---
	Kine_Ray_GetProperties :: proc(ctx: ^KineFilamentContext, out: ^KineRayProperties) -> bool ---
	Kine_Filament_CreateMesh :: proc(ctx: ^KineFilamentContext, shape: i32) -> ^KineFilamentMesh ---
	Kine_Filament_SetWaterParams :: proc(ctx: ^KineFilamentContext, params: ^KineFilamentWaterParams) ---
	Kine_Filament_SetWaterTime :: proc(ctx: ^KineFilamentContext, time: f32) ---
	Kine_Filament_GetWaterParams :: proc(ctx: ^KineFilamentContext, out: ^KineFilamentWaterParams) -> bool ---
	Kine_Filament_RenderFrame :: proc(ctx: ^KineFilamentContext, deltaTime: f32) ---
	Kine_Filament_Resize :: proc(ctx: ^KineFilamentContext, width: i32, height: i32) ---
	Kine_Filament_SetViewport :: proc(ctx: ^KineFilamentContext, x: i32, y: i32, width: i32, height: i32) ---
	Kine_Filament_Shader_Create :: proc(ctx: ^KineFilamentContext, materialSource: cstring) -> ^KineFilamentShader ---
	Kine_Filament_Shader_CompileStart :: proc(source: cstring) -> ^KineFilamentShaderCompile ---
	Kine_Filament_Shader_CompilePoll :: proc(ctx: ^KineFilamentContext, job: ^KineFilamentShaderCompile, shader: ^^KineFilamentShader) -> bool ---
	Kine_Filament_Shader_CompileRelease :: proc(job: ^KineFilamentShaderCompile) ---
	Kine_Filament_SetDecalColor :: proc(ctx: ^KineFilamentContext, decal: i32, r: f32, g: f32, b: f32, a: f32) -> i32 ---
	Kine_Filament_CreateMeshFromMemory :: proc(ctx: ^KineFilamentContext, data: rawptr, data_size: uintptr, format_hint: cstring) -> ^KineFilamentMesh ---
	Kine_Filament_CreateMeshFromPath :: proc(ctx: ^KineFilamentContext, path: cstring) -> ^KineFilamentMesh ---
	Kine_Filament_GetMeshTexture :: proc(mesh: ^KineFilamentMesh) -> ^KineFilamentTex ---
	Kine_Filament_ListMeshes :: proc(path: cstring) -> ^KineFilamentMeshList ---
	Kine_Filament_GetMeshListCount :: proc(list: ^KineFilamentMeshList) -> i32 ---
	Kine_Filament_GetMeshListName :: proc(list: ^KineFilamentMeshList, mesh_index: u32) -> cstring ---
	Kine_Filament_DestroyMeshList :: proc(list: ^KineFilamentMeshList) ---
	Kine_Filament_CreateMeshFromPathIndexed :: proc(ctx: ^KineFilamentContext, path: cstring, mesh_index: u32) -> ^KineFilamentMesh ---
	Kine_Filament_CreateMeshFromMemoryIndexed :: proc(ctx: ^KineFilamentContext, data: rawptr, data_size: uintptr, format_hint: cstring, mesh_index: u32) -> ^KineFilamentMesh ---
	Kine_Filament_LoadMeshDataFromPathIndexed :: proc(path: cstring, mesh_index: u32) -> ^KineFilamentMeshData ---
	Kine_Filament_LoadMeshDataFromPath :: proc(path: cstring) -> ^KineFilamentMeshData ---
	Kine_Filament_CreateSky :: proc(ctx: ^KineFilamentContext, r: f32, g: f32, b: f32, a: f32) ---
	Kine_Filament_SetPostProcessing :: proc(ctx: ^KineFilamentContext, enabled: bool) -> i32 ---
	Kine_Filament_SetBloom :: proc(ctx: ^KineFilamentContext, enabled: bool, strength: f32, resolution: i32, levels: i32, threshold: bool, lensFlare: bool) -> i32 ---
	Kine_Filament_SetAmbientOcclusion :: proc(ctx: ^KineFilamentContext, enabled: bool, radius: f32, power: f32, intensity: f32, quality: i32, aoType: i32) -> i32 ---
	Kine_Filament_SetAntiAliasing :: proc(ctx: ^KineFilamentContext, fxaa: bool, taa: bool, msaa: bool, sampleCount: i32) -> i32 ---
	Kine_Filament_SetDynamicResolution :: proc(ctx: ^KineFilamentContext, enabled: bool, minScale: f32, maxScale: f32, quality: i32, sharpness: f32) -> i32 ---
	Kine_Filament_SetDepthOfField :: proc(ctx: ^KineFilamentContext, enabled: bool, cocScale: f32, cocAspectRatio: f32, maxApertureDiameter: f32, maxForegroundCOC: i32, maxBackgroundCOC: i32) -> i32 ---
	Kine_Filament_SetFocusDistance :: proc(ctx: ^KineFilamentContext, distance: f32) -> i32 ---
	Kine_Filament_SetVignette :: proc(ctx: ^KineFilamentContext, enabled: bool, midPoint: f32, roundness: f32, feather: f32, r: f32, g: f32, b: f32, a: f32) -> i32 ---
	Kine_Filament_SetScreenSpaceReflections :: proc(ctx: ^KineFilamentContext, enabled: bool, thickness: f32, bias: f32, maxDistance: f32, stride: f32) -> i32 ---
	Kine_Filament_SetColorGrading :: proc(ctx: ^KineFilamentContext, exposure: f32, contrast: f32, saturation: f32, vibrance: f32, temperature: f32, tint: f32) -> i32 ---
	Kine_Filament_ClearColorGrading :: proc(ctx: ^KineFilamentContext) -> i32 ---
	Kine_Filament_SetRenderQuality :: proc(ctx: ^KineFilamentContext, hdrQuality: i32) -> i32 ---
	Kine_Filament_SetDithering :: proc(ctx: ^KineFilamentContext, enabled: bool) -> i32 ---
	Kine_Filament_SetShadowOptions :: proc(ctx: ^KineFilamentContext, enabled: bool, shadowType: i32) -> i32 ---
	Kine_Filament_SetSunShadowOptions :: proc(ctx: ^KineFilamentContext, mapSize: i32, cascades: i32, shadowFar: f32, shadowNearHint: f32, shadowFarHint: f32, stable: bool, contactShadows: bool) -> i32 ---
	Kine_Filament_SetSunRays :: proc(ctx: ^KineFilamentContext, enabled: bool, distance: f32, cutOffDistance: f32, maximumOpacity: f32, height: f32, heightFalloff: f32, density: f32, inScatteringStart: f32, inScatteringSize: f32, r: f32, g: f32, b: f32, fogColorFromIbl: bool) -> i32 ---
	Kine_Filament_UpdateTexFromPixels :: proc(ctx: ^KineFilamentContext, tex: ^KineFilamentTex, width: i32, height: i32, rowBytes: i32, pixelsRGBA8: rawptr) -> i32 ---
	Kine_Filament_GetEngine :: proc(ctx: ^KineFilamentContext) -> ^i32 ---
	Kine_Filament_GetScene :: proc(ctx: ^KineFilamentContext) -> ^i32 ---
	Kine_Filament_GetView :: proc(ctx: ^KineFilamentContext) -> ^i32 ---
	Kine_Filament_GetCamera :: proc(ctx: ^KineFilamentContext) -> ^i32 ---
	Kine_Filament_SetCameraLookAt :: proc(ctx: ^KineFilamentContext, eyeX: f32, eyeY: f32, eyeZ: f32, targetX: f32, targetY: f32, targetZ: f32, upX: f32, upY: f32, upZ: f32) ---
	Kine_Filament_BlitToScreen :: proc(ctx: ^KineFilamentContext, dstX: i32, dstY: i32, dstWidth: i32, dstHeight: i32) -> i32 ---
	Kine_Filament_SetCameraPerspective :: proc(ctx: ^KineFilamentContext, fovYDegrees: f64, aspect: f64, nearPlane: f64, farPlane: f64) ---
	Kine_Filament_SetAdvancedEffect :: proc(ctx: ^KineFilamentContext, effect: i32, enabled: bool, values: ^f32, count: i32) ---
	Kine_Filament_GetAdvancedEffect :: proc(ctx: ^KineFilamentContext, effect: i32, enabled: ^bool, values: ^f32, capacity: i32) -> bool ---
	Kine_Filament_GetReflectionProbeRegion :: proc(ctx: ^KineFilamentContext, center, radius: ^f32) -> bool ---
	Kine_Filament_GetReflectionProbeCaptureCount :: proc(ctx: ^KineFilamentContext) -> u64 ---
	Kine_Filament_SetClouds :: proc(ctx: ^KineFilamentContext, enabled: bool, cover: f32, density: f32, height: f32, thickness: f32, r: f32, g: f32, b: f32) ---
	Kine_Filament_SetCameraPosition :: proc(ctx: ^KineFilamentContext, x: f32, y: f32, z: f32) ---
	Kine_Filament_SetCameraDirection :: proc(ctx: ^KineFilamentContext, dx: f32, dy: f32, dz: f32) ---
	Kine_Filament_DestroyMesh :: proc(ctx: ^KineFilamentContext, mesh: ^KineFilamentMesh) -> i32 ---
	Kine_Filament_CreateTex :: proc(ctx: ^KineFilamentContext, tex: ^KineGLTextureInfo) -> i32 ---
	Kine_Filament_CreateTexFromPixels :: proc(ctx: ^KineFilamentContext, width: i32, height: i32, rowBytes: i32, pixelsRGBA8: rawptr) -> ^KineFilamentTex ---
	Kine_Filament_CreatePbrTexFromPixels :: proc(ctx: ^KineFilamentContext, width: i32, height: i32, albedoRowBytes: i32, albedoRGBA8: rawptr, normalWidth: i32, normalHeight: i32, normalRowBytes: i32, normalRGBA8: rawptr, ormWidth: i32, ormHeight: i32, ormRowBytes: i32, ormRGBA8: rawptr, heightWidth: i32, heightHeight: i32, heightRowBytes: i32, heightRGBA8: rawptr, heightScale: f32) -> ^KineFilamentTex ---
	Kine_Filament_GetMeshBoneCount :: proc(mesh: ^KineFilamentMesh) -> i32 ---
	Kine_Filament_GetMeshBounds :: proc(mesh: ^KineFilamentMesh, center, halfExtent: ^f32) -> bool ---
	Kine_Filament_SetUseImportedMaterials :: proc(ctx: ^KineFilamentContext, mesh: ^KineFilamentMesh, enabled: bool) ---
	Kine_Filament_GetMeshMaterialCount :: proc(mesh: ^KineFilamentMesh) -> i32 ---
	Kine_Filament_GetMeshMaterialTexture :: proc(mesh: ^KineFilamentMesh, index: i32) -> ^KineFilamentTex ---
	Kine_Filament_GetMeshBoneName :: proc(mesh: ^KineFilamentMesh, boneIndex: i32) -> ^i32 ---
	Kine_Filament_GetMeshBoneParent :: proc(mesh: ^KineFilamentMesh, boneIndex: i32) -> i32 ---
	Kine_Filament_CopyMeshBoneBindTransform :: proc(mesh: ^KineFilamentMesh, boneIndex: i32, outTransform16: ^f32) -> i32 ---
	Kine_Filament_SetMeshBoneTransforms :: proc(ctx: ^KineFilamentContext, mesh: ^KineFilamentMesh, boneTransforms16: ^f32, boneCount: i32) -> i32 ---
	Kine_Filament_GetMeshAnimationCount :: proc(mesh: ^KineFilamentMesh) -> i32 ---
	Kine_Filament_GetMeshAnimationName :: proc(mesh: ^KineFilamentMesh, animationIndex: i32) -> ^i32 ---
	Kine_Filament_GetMeshAnimationDuration :: proc(mesh: ^KineFilamentMesh, animationIndex: i32) -> i32 ---
	Kine_Filament_ApplyMeshAnimation :: proc(ctx: ^KineFilamentContext, mesh: ^KineFilamentMesh, animationIndex: i32, timeSeconds: f32, loop: bool) -> i32 ---
	Kine_Filament_CreateGizmo :: proc(ctx: ^KineFilamentContext, gizmoType: i32) -> ^KineFilamentGizmo ---
	Kine_Filament_GetMeshDataVertexCount :: proc(meshData: ^KineFilamentMeshData) -> i32 ---
	Kine_Filament_GetMeshDataIndexCount :: proc(meshData: ^KineFilamentMeshData) -> i32 ---
	Kine_Filament_CopyMeshDataPositions :: proc(meshData: ^KineFilamentMeshData, outPositions: ^f32, positionFloatCapacity: i32) -> i32 ---
	Kine_Filament_CopyMeshDataIndices :: proc(meshData: ^KineFilamentMeshData, outIndices: ^u32, indexCapacity: i32) -> i32 ---
	Kine_Filament_DestroyMeshData :: proc(meshData: ^KineFilamentMeshData) -> i32 ---
	Kine_Filament_DebugPrintPixel :: proc(ctx: ^KineFilamentContext) -> i32 ---
	Kine_Filament_DestroyGizmo :: proc(ctx: ^KineFilamentContext, gizmo: ^KineFilamentGizmo) ---
	Kine_Filament_DestroyTex :: proc(ctx: ^KineFilamentContext, tex: ^KineFilamentTex) -> i32 ---
	Kine_Filament_UpdateCustomMesh :: proc(ctx: ^KineFilamentContext, mesh: ^KineFilamentMesh, vertexData: ^f32, vertexCount: i32) -> i32 ---
	Kine_Filament_DrawMeshEx :: proc(ctx: ^KineFilamentContext, mesh: ^KineFilamentMesh, materialKind: i32, r: f32, g: f32, b: f32, param1: f32, param2: f32, param3: f32, transmission: f32, mat4: ^f32, castShadows: bool, receiveShadows: bool, culling: bool, tex: ^KineFilamentTex) -> i32 ---
	Kine_Filament_DrawMeshList :: proc(ctx: ^KineFilamentContext, items: ^KineFilamentDrawItem, itemCount: u32) -> i32 ---
	Kine_Filament_DrawMeshListVersioned :: proc(ctx: ^KineFilamentContext, items: ^KineFilamentDrawItem, itemCount: u32, streamId: u64, version: u64) -> i32 ---
	Kine_Filament_DestroyInstanceBatch :: proc(batch: ^KineFilamentInstanceBatch) -> i32 ---
	Kine_Filament_UpdateInstanceTransforms :: proc(batch: ^KineFilamentInstanceBatch, indices: ^u32, transforms: ^f32, dirtyCount: u32) -> i32 ---
	Kine_Filament_DrawParticles :: proc(ctx: ^KineFilamentContext, texture: ^KineFilamentTex, items: ^KineFilamentParticleItem, itemCount: u32, uvScaleX: f32, uvScaleY: f32, uvOffsetX: f32, uvOffsetY: f32, castShadows: bool, culling: bool) -> i32 ---
	Kine_Filament_DrawMeshOutline :: proc(ctx: ^KineFilamentContext, mesh: ^KineFilamentMesh, r: f32, g: f32, b: f32, thickness: f32, mat4: ^f32) -> i32 ---
	Kine_Filament_DrawGizmo :: proc(ctx: ^KineFilamentContext, gizmo: ^KineFilamentGizmo, mat4: ^f32, hoveredAxis: i32, selectedAxis: i32) ---
	Kine_Filament_PickGizmo :: proc(ctx: ^KineFilamentContext, gizmo: ^KineFilamentGizmo, mat4: ^f32, screenX: f32, screenY: f32) -> i32 ---
	Kine_Filament_GetGizmoDragDelta :: proc(ctx: ^KineFilamentContext, gizmo: ^KineFilamentGizmo, mat4: ^f32, axis: i32, startX: f32, startY: f32, currentX: f32, currentY: f32) -> f32 ---
	Kine_Filament_DrawGizmoLine :: proc(ctx: ^KineFilamentContext, ax: f32, ay: f32, az: f32, bx: f32, by: f32, bz: f32, r: f32, g: f32, b: f32, thickness: f32) ---
	Kine_Filament_DrawGizmoLines :: proc(ctx: ^KineFilamentContext, points: ^f32, segmentCount: u32, r: f32, g: f32, b: f32, thickness: f32) ---
	Kine_Filament_DrawGizmoCube :: proc(ctx: ^KineFilamentContext, mat4: ^f32, r: f32, g: f32, b: f32, wire: bool, thickness: f32) ---
	Kine_Filament_DrawGizmoSphere :: proc(ctx: ^KineFilamentContext, cx: f32, cy: f32, cz: f32, radius: f32, r: f32, g: f32, b: f32, wire: bool, thickness: f32, segments: i32) ---
	Kine_Filament_DrawGizmoCylinder :: proc(ctx: ^KineFilamentContext, mat4: ^f32, r: f32, g: f32, b: f32, wire: bool, thickness: f32, segments: i32) ---
	Kine_Filament_DrawGizmoMesh :: proc(ctx: ^KineFilamentContext, mesh: ^KineFilamentMesh, mat4: ^f32, r: f32, g: f32, b: f32) ---
	Kine_Filament_DrawGizmoWireMesh :: proc(ctx: ^KineFilamentContext, mesh: ^KineFilamentMesh, mat4: ^f32, r: f32, g: f32, b: f32, thickness: f32, featureAngleDeg: f32) ---
	Kine_Filament_GetGizmoPlaneDragDelta :: proc(ctx: ^KineFilamentContext, gizmo: ^KineFilamentGizmo, mat4: ^f32, axis: i32, startX: f32, startY: f32, currentX: f32, currentY: f32, outFirst: ^f32, outSecond: ^f32) -> i32 ---
	Kine_Filament_CreateCustomMesh :: proc(ctx: ^KineFilamentContext, vertexData: ^f32, vertexCount: i32, indices: ^u16, indexCount: i32) -> ^KineFilamentMesh ---
	Kine_Filament_CreateCustomMesh32 :: proc(ctx: ^KineFilamentContext, vertexData: ^f32, vertexCount: i32, indices: ^u32, indexCount: i32) -> ^KineFilamentMesh ---
	Kine_Filament_CreateCustomMeshEx :: proc(ctx: ^KineFilamentContext, vertexData: ^f32, colorData: ^f32, vertexCount: i32, indices: ^u16, indexCount: i32) -> ^KineFilamentMesh ---
	Kine_Filament_CreateCustomMeshEx32 :: proc(ctx: ^KineFilamentContext, vertexData: ^f32, colorData: ^f32, vertexCount: i32, indices: ^u32, indexCount: i32) -> ^KineFilamentMesh ---
	Kine_Filament_CreateTerrainMesh :: proc(ctx: ^KineFilamentContext, vertexData: ^f32, materialWeights: ^f32, vertexCount: i32, indices: ^u16, indexCount: i32) -> ^KineFilamentMesh ---
	Kine_Filament_CreateTerrainTextureSet :: proc(ctx: ^KineFilamentContext, layer0: ^KineFilamentTex, layer1: ^KineFilamentTex, layer2: ^KineFilamentTex, layer3: ^KineFilamentTex, layer4: ^KineFilamentTex, layer5: ^KineFilamentTex) -> ^KineFilamentTex ---
	Kine_Filament_ReadPixels :: proc(ctx: ^KineFilamentContext, outPixels: rawptr) -> i32 ---
	Kine_Filament_GetWidth :: proc(ctx: ^KineFilamentContext) -> i32 ---
	Kine_Filament_GetHeight :: proc(ctx: ^KineFilamentContext) -> i32 ---


	Kine_Filament_SetSkyAtmosphere :: proc(ctx: ^KineFilamentContext, sunDirX: f32, sunDirY: f32, sunDirZ: f32, skyR: f32, skyG: f32, skyB: f32, horizonR: f32, horizonG: f32, horizonB: f32, groundR: f32, groundG: f32, groundB: f32, sunIntensity: f32) -> i32 ---


	Kine_Filament_CreateSkyboxCubemap :: proc(ctx: ^KineFilamentContext, texPosX: ^KineGLTextureInfo, texNegX: ^KineGLTextureInfo, texPosY: ^KineGLTextureInfo, texNegY: ^KineGLTextureInfo, texPosZ: ^KineGLTextureInfo, texNegZ: ^KineGLTextureInfo) -> i32 ---


	Kine_Filament_SetSun :: proc(ctx: ^KineFilamentContext, sunDirX: f32, sunDirY: f32, sunDirZ: f32, sunIntensity: f32) -> i32 ---


	Kine_Filament_CreateLight :: proc(ctx: ^KineFilamentContext, px: f32, py: f32, pz: f32, cr: f32, cg: f32, cb: f32, intensity: f32, falloff: f32) -> i32 ---
	Kine_Filament_CreateLightEx :: proc(ctx: ^KineFilamentContext, lightType: i32, px: f32, py: f32, pz: f32, dx: f32, dy: f32, dz: f32, cr: f32, cg: f32, cb: f32, intensity: f32, falloff: f32, innerConeRadians: f32, outerConeRadians: f32, castShadows: bool, enabled: bool) -> i32 ---
	Kine_Filament_SetColorLight :: proc(ctx: ^KineFilamentContext, light: i32, r: f32, g: f32, b: f32) -> i32 ---
	Kine_Filament_SetIntensityLight :: proc(ctx: ^KineFilamentContext, light: i32, intensity: f32) -> i32 ---
	Kine_Filament_SetFalloffLight :: proc(ctx: ^KineFilamentContext, light: i32, falloff: f32) -> i32 ---
	Kine_Filament_SetPositionLight :: proc(ctx: ^KineFilamentContext, light: i32, x: f32, y: f32, z: f32) -> i32 ---
	Kine_Filament_SetDirectionLight :: proc(ctx: ^KineFilamentContext, light: i32, x: f32, y: f32, z: f32) -> i32 ---
	Kine_Filament_SetConeLight :: proc(ctx: ^KineFilamentContext, light: i32, innerRadians: f32, outerRadians: f32) -> i32 ---
	Kine_Filament_SetShadowLight :: proc(ctx: ^KineFilamentContext, light: i32, castShadows: bool) -> i32 ---
	Kine_Filament_SetEnabledLight :: proc(ctx: ^KineFilamentContext, light: i32, enabled: bool) -> i32 ---
	Kine_Filament_RemoveLight :: proc(ctx: ^KineFilamentContext, light: i32) -> i32 ---


	Kine_Filament_CreateDecal :: proc(ctx: ^KineFilamentContext, width: f32, height: f32, texture: ^KineFilamentTex, offsetStudsU: f32, offsetStudsV: f32, studsPerTileU: f32, studsPerTileV: f32, culling: bool, castShadows: bool, receiveShadows: bool) -> i32 ---
	Kine_Filament_SetDecalTiling :: proc(ctx: ^KineFilamentContext, decal: i32, width: f32, height: f32, offsetStudsU: f32, offsetStudsV: f32, studsPerTileU: f32, studsPerTileV: f32) -> i32 ---
	Kine_Filament_RemoveDecal :: proc(ctx: ^KineFilamentContext, decal: i32) -> i32 ---
	Kine_Filament_SetDecalTransform :: proc(ctx: ^KineFilamentContext, decal: i32, mat4: ^f32) -> i32 ---
	Kine_Filament_EditDecal :: proc(ctx: ^KineFilamentContext, decal: i32, width: f32, height: f32, culling: bool, castShadows: bool, receiveShadows: bool) -> i32 ---
}


KineFilamentViewport :: struct {}
KineViewportSettings :: struct {
	camera:                              [16]f32,
	ambient, lightColor, lightDirection: [3]f32,
	fieldOfView:                         f32,
	width, height:                       i32,
	shadows, postProcessing:             i32,
	effectMask:                          u32,
	bloom:                               [5]f32,
	ao:                                  [7]f32,
	dof:                                 [6]f32,
	color:                               [7]f32,
	vignette:                            [8]f32,
	reflections:                         [5]f32,
	antialiasing:                        [4]f32,
	dithering, quality:                  i32,
}
@(default_calling_convention = "c")
foreign kine_filament {
	Kine_Filament_Viewport_Create :: proc(ctx: ^KineFilamentContext) -> ^KineFilamentViewport ---
	Kine_Filament_Viewport_Destroy :: proc(viewport: ^KineFilamentViewport) ---
	Kine_Filament_Viewport_Begin :: proc(ctx: ^KineFilamentContext) ---
	Kine_Filament_Viewport_IsValid :: proc(viewport: ^KineFilamentViewport, ctx: ^KineFilamentContext) -> bool ---
	Kine_Filament_Viewport_Touch :: proc(viewport: ^KineFilamentViewport) ---
	Kine_Filament_Viewport_Update :: proc(viewport: ^KineFilamentViewport, settings: ^KineViewportSettings, items: ^KineFilamentDrawItem, count: u32, version: u64) -> bool ---
	Kine_Filament_Viewport_Draw :: proc(viewport: ^KineFilamentViewport, surface: ^KineSkiaSurface, x, y, width, height, r, g, b, opacity: f32) ---
	Kine_Filament_Viewport_HasWork :: proc(ctx: ^KineFilamentContext) -> bool ---
	Kine_Filament_Viewport_RenderFrame :: proc(ctx: ^KineFilamentContext, dt: f32, renderWorld: bool) ---
	Kine_Filament_SetFrameProfileCallback :: proc(ctx: ^KineFilamentContext, callback: proc "c" (user: rawptr, phase: cstring, begin: bool), user: rawptr) ---
	Kine_Filament_Viewport_Primitive :: proc(ctx: ^KineFilamentContext, shape: i32) -> ^KineFilamentMesh ---
	Kine_Filament_Viewport_Mesh :: proc(ctx: ^KineFilamentContext, key: u64, data: rawptr, size: uintptr, hint: cstring) -> ^KineFilamentMesh ---
	Kine_Filament_Viewport_Stats :: proc(ctx: ^KineFilamentContext, handles, pages: ^u32, renders: ^u64) ---
}
