package kineffi

// Thin Odin mirror of vendor/kine_recast/include/recast_api.h.
//
// The RecastWrapper target is bundled into KinemiumLibs together with the Recast
// and Detour archives it calls into, so a single import covers the whole
// navigation stack.

when ODIN_OS == .Windows {
	foreign import lib {
		"../../../vendor/build/lib/kine_recast.lib",
		"../../../vendor/build/lib/kine_recast_core.lib",
		"../../../vendor/build/lib/kine_detour.lib",
	}
} else when ODIN_OS == .JS {
	// build_wasm.ps1 relocatably links RecastWrapper with the Recast and Detour
	// archives it calls into and emits this one object. wasm32 allows only a
	// single path per foreign import, which is why this is merged into one file
	// rather than the three archives the desktop branches name.
	foreign import lib "../../../build/web-native/lib/kine_recast_web.o"
} else when #config(KINE_ANDROID, false) {
	foreign import lib "../../../build/android-native/lib/libRecastWrapper.a"
} else {
	foreign import lib "../../../vendor/build/lib/KinemiumLibs.a"
}

RCN_NavMeshRef :: rawptr
RCN_NavQueryRef :: rawptr
RCN_FilterRef :: rawptr

RCN_PolyRef :: u32

RCN_POLYREF_INVALID :: RCN_PolyRef(0)

RECAST_AreaId :: u8

RECAST_NULL_AREA     :: RECAST_AreaId(0)
RECAST_WALKABLE_AREA :: RECAST_AreaId(63)

RCN_Error_None            :: 0
RCN_Error_InvalidArgument :: 1
RCN_Error_AllocationFailed :: 2
RCN_Error_BuildFailed     :: 3
RCN_Error_QueryFailed     :: 4
RCN_Error_NoPath          :: 5

RECAST_BuildConfig :: struct {
	cellSize:            f32,
	cellHeight:          f32,
	agentHeight:         f32,
	agentRadius:         f32,
	agentMaxClimb:       f32,
	agentMaxSlope:       f32,
	regionMinSize:       f32,
	regionMergeSize:     f32,
	edgeMaxLen:          f32,
	edgeMaxError:        f32,
	vertsPerPoly:        f32,
	detailSampleDist:    f32,
	detailSampleMaxError: f32,
}

RECAST_QueryFilter :: struct {
	includeFlags: u16,
	excludeFlags: u16,
	areaCost:     [64]f32,
}

RECAST_PathPoint :: struct {
	x:     f32,
	y:     f32,
	z:     f32,
	flags: u8,
	ref:   RCN_PolyRef,
}

RECAST_RaycastHit :: struct {
	t:         f32,
	hitNormal: [3]f32,
	pathCount: i32,
}

@(default_calling_convention="c")
foreign lib {
	RCN_GetVersion          :: proc() -> cstring ---
	RCN_DefaultBuildConfig  :: proc(config: ^RECAST_BuildConfig) ---
	RCN_DefaultQueryFilter  :: proc(filter: ^RECAST_QueryFilter) ---

	RCN_BuildNavMesh :: proc(
		verts: [^]f32,
		numVerts: i32,
		tris: [^]i32,
		numTris: i32,
		config: ^RECAST_BuildConfig,
		outNavMesh: ^RCN_NavMeshRef,
	) -> i32 ---

	RCN_FreeNavMesh :: proc(navMesh: RCN_NavMeshRef) ---

	RCN_CreateNavQuery :: proc(navMesh: RCN_NavMeshRef, maxNodes: i32) -> RCN_NavQueryRef ---
	RCN_FreeNavQuery   :: proc(query: RCN_NavQueryRef) ---

	RCN_CreateQueryFilter :: proc(description: ^RECAST_QueryFilter) -> RCN_FilterRef ---
	RCN_FreeQueryFilter   :: proc(filter: RCN_FilterRef) ---

	RCN_FindNearestPoly :: proc(
		query: RCN_NavQueryRef,
		center: [^]f32,
		halfExtents: [^]f32,
		filter: RCN_FilterRef,
		outRef: ^RCN_PolyRef,
		outNearestPoint: [^]f32,
	) -> i32 ---

	RCN_FindPath :: proc(
		query: RCN_NavQueryRef,
		startPos: [^]f32,
		endPos: [^]f32,
		filter: RCN_FilterRef,
		outPath: [^]RCN_PolyRef,
		maxPath: i32,
		outPathCount: ^i32,
	) -> i32 ---

	RCN_FindStraightPath :: proc(
		query: RCN_NavQueryRef,
		startPos: [^]f32,
		endPos: [^]f32,
		path: [^]RCN_PolyRef,
		pathCount: i32,
		outPoints: [^]RECAST_PathPoint,
		maxPoints: i32,
		outPointCount: ^i32,
	) -> i32 ---

	RCN_Raycast :: proc(
		query: RCN_NavQueryRef,
		startPos: [^]f32,
		endPos: [^]f32,
		filter: RCN_FilterRef,
		outHit: ^RECAST_RaycastHit,
		path: [^]RCN_PolyRef,
		maxPath: i32,
	) -> i32 ---

	RCN_MoveAlongSurface :: proc(
		query: RCN_NavQueryRef,
		startPos: [^]f32,
		endPos: [^]f32,
		filter: RCN_FilterRef,
		outResultPos: [^]f32,
		visited: [^]RCN_PolyRef,
		maxVisited: i32,
		outVisitedCount: ^i32,
	) -> i32 ---

	RCN_GetPolyHeight :: proc(
		query: RCN_NavQueryRef,
		ref: RCN_PolyRef,
		pos: [^]f32,
		outHeight: ^f32,
	) -> i32 ---

	RCN_FindPolysAroundCircle :: proc(
		query: RCN_NavQueryRef,
		center: [^]f32,
		radius: f32,
		filter: RCN_FilterRef,
		outRefs: [^]RCN_PolyRef,
		outCosts: [^]f32,
		maxResults: i32,
		outResultCount: ^i32,
	) -> i32 ---
}
