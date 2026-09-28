
#pragma once

#include <stdint.h>

// Thin C surface over Recast & Detour from recastnavigation.
//
// The wrapper deliberately exposes the two things an engine needs from
// navigation data: building a navmesh out of level triangle soup, and asking
// questions about the result. It hides rcConfig/dtNavMeshParams construction and
// the multi-step build pipeline, but does not wrap the algorithms themselves, so
// the caller still controls walkability and area costs.

// Export/import decoration
#if (defined(_WIN32) || defined(__CYGWIN__)) && (defined(KINE_BUILD_SHARED) || defined(RECAST_WRAPPER_BUILD_SHARED))
  #ifdef RECAST_WRAPPER_EXPORTS
    #define RECAST_API __declspec(dllexport)
  #else
    #define RECAST_API __declspec(dllimport)
  #endif
#elif defined(__GNUC__) && (defined(KINE_BUILD_SHARED) || defined(RECAST_WRAPPER_BUILD_SHARED))
  #define RECAST_API __attribute__((visibility("default")))
#else
  #define RECAST_API
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Opaque handles. The engine owns the pointed-to C++ objects; the caller only
// ever sees these tokens.
typedef void* RECAST_NavMeshRef;   // dtNavMesh*
typedef void* RECAST_NavQueryRef;  // dtNavMeshQuery*
typedef void* RECAST_FilterRef;    // dtQueryFilter*

// Detour packs a polygon reference into a salt/tile/poly triple. Callers treat it
// as opaque and only ever pass it back to this API.
typedef uint32_t RECAST_PolyRef;

#define RECAST_POLYREF_INVALID ((RECAST_PolyRef)0)
#define RECAST_TILEREF_INVALID ((uint32_t)0)

// Area ids. RECAST_WALKABLE_AREA matches Recast's own default ground area.
typedef uint8_t RECAST_AreaId;

enum
{
    RECAST_NULL_AREA = 0,
    RECAST_WALKABLE_AREA = 63,
};

// RCN_BuildConfig is the caller-facing build configuration. These map onto
// rcConfig and the usual agent dimensions, expressed in world units so callers
// do not have to think in voxels.
typedef struct RECAST_BuildConfig
{
    // The xz-plane cell size in world units. This is the single most important
    // tuning knob: smaller means more detail and a larger build.
    float cellSize;
    // The y-axis cell size in world units. Often matched to cellSize.
    float cellHeight;

    // Agent dimensions in world units. The wrapper converts these to the voxel
    // counts rcConfig expects.
    float agentHeight;
    float agentRadius;
    float agentMaxClimb;
    // Maximum walkable slope in degrees.
    float agentMaxSlope;

    // Region filtering, in world units. Small islands below regionMinSize are
    // discarded, and regions within regionMergeSize of each other are merged.
    float regionMinSize;
    float regionMergeSize;

    // Contour simplification, in world units and vertex counts.
    float edgeMaxLen;
    float edgeMaxError;
    // Maximum vertices per navigation polygon. Must be 3..6.
    float vertsPerPoly;

    // Detail mesh sampling, in world units. detailSampleMaxError may be 0 to
    // use only the sampling distance.
    float detailSampleDist;
    float detailSampleMaxError;
} RECAST_BuildConfig;

// RCN_QueryFilter mirrors the subset of dtQueryFilter an engine normally
// changes. Costs are per area id and default to 1.
typedef struct RECAST_QueryFilter
{
    // includeFlags/excludeFlags are Detour sample flags, applied to every polygon
    // the query walks over. Zeroing includeFlags would exclude the whole navmesh,
    // so RCN_DefaultQueryFilter sets the same 0xffff/0x0 pair dtQueryFilter uses.
    uint16_t includeFlags;
    uint16_t excludeFlags;

    // Cost assigned to each area id, indexed directly by area id. Values above 1
    // make an area more expensive, and are how a "slow" surface is discouraged
    // without removing it from the navmesh.
    float areaCost[64];
} RECAST_QueryFilter;

// RCN_PathPoint is one corner of a straightened path.
typedef struct RECAST_PathPoint
{
    float x;
    float y;
    float z;
    // DT_STRAIGHTPATH_OFFMESH_CONNECTION when this point is an off-mesh link.
    uint8_t flags;
    RECAST_PolyRef ref;
} RECAST_PathPoint;

// RCN_RaycastHit describes where a walkability ray stopped.
typedef struct RECAST_RaycastHit
{
    // Fraction of the requested distance that was travelled before the hit.
    float t;
    float hitNormal[3];
    // Number of polygons entered along the ray, written to `pathCount`.
    int pathCount;
} RECAST_RaycastHit;

// Error codes. Every fallible entry point returns 0 on success and one of these
// otherwise, so a caller never has to interpret a Recast/Detour status directly.
enum
{
    RCN_Error_None = 0,
    RCN_Error_InvalidArgument = 1,
    RCN_Error_AllocationFailed = 2,
    RCN_Error_BuildFailed = 3,
    RCN_Error_QueryFailed = 4,
    RCN_Error_NoPath = 5,
};

// Returns a static string naming the wrapper and the Recast/Detour version it
// was built against.
RECAST_API const char* RCN_GetVersion(void);

// Fills `config` with the same defaults a typical game character uses. Calling
// this first and then adjusting fields is the intended entry point.
RECAST_API void RCN_DefaultBuildConfig(RECAST_BuildConfig* config);

// Fills `filter` with the defaults: no flag restrictions and a cost of 1 for
// every area id.
RECAST_API void RCN_DefaultQueryFilter(RECAST_QueryFilter* filter);

// Builds a single-tile navmesh from an indexed triangle soup.
//
// `verts` is numVerts * 3 floats (xyz) and `tris` is numTris * 3 ints. The mesh
// must be counter-clockwise winding when viewed from above. Triangles steeper
// than agentMaxSlope are treated as unwalkable, so a sloped roof is excluded
// while a floor is kept. On success a navmesh handle is written to `outNavMesh`;
// the caller owns that handle and must release it with RCN_FreeNavMesh.
RECAST_API int RCN_BuildNavMesh(
    const float* verts,
    int numVerts,
    const int* tris,
    int numTris,
    const RECAST_BuildConfig* config,
    RECAST_NavMeshRef* outNavMesh);

// Releases a navmesh returned by RCN_BuildNavMesh. Passing NULL is a no-op.
RECAST_API void RCN_FreeNavMesh(RECAST_NavMeshRef navMesh);

// Creates a query object for `navMesh`, used for all subsequent pathfinding and
// lookup calls. The query holds a reference to the navmesh, so the navmesh must
// outlive it. Release with RCN_FreeNavQuery.
RECAST_API RECAST_NavQueryRef RCN_CreateNavQuery(RECAST_NavMeshRef navMesh, int maxNodes);
RECAST_API void RCN_FreeNavQuery(RECAST_NavQueryRef query);

// Allocates a filter from a RECAST_QueryFilter description. Release with
// RCN_FreeQueryFilter.
RECAST_API RECAST_FilterRef RCN_CreateQueryFilter(const RECAST_QueryFilter* description);
RECAST_API void RCN_FreeQueryFilter(RECAST_FilterRef filter);

// Finds the polygon nearest to `center` within `halfExtents` (world units),
// writing its reference and closest point. A reference of RECAST_POLYREF_INVALID
// means nothing was within range.
RECAST_API int RCN_FindNearestPoly(
    RECAST_NavQueryRef query,
    const float center[3],
    const float halfExtents[3],
    RECAST_FilterRef filter,
    RECAST_PolyRef* outRef,
    float outNearestPoint[3]);

// Finds a corridor of polygons from `startPos` to `endPos`. `outPath` must hold
// at least `maxPath` entries and the number found is written to `outPathCount`.
// A partial path toward the closest reachable polygon is returned on failure,
// which is what a follower walking at an unreachable goal needs.
RECAST_API int RCN_FindPath(
    RECAST_NavQueryRef query,
    const float startPos[3],
    const float endPos[3],
    RECAST_FilterRef filter,
    RECAST_PolyRef* outPath,
    int maxPath,
    int* outPathCount);

// Turns a polygon corridor into a straightened path of corners. `outPoints`
// must hold at least `maxPoints` RCN_PathPoint entries. The corner flags tell a
// caller where to turn, so a follower can walk a straight line between them.
RECAST_API int RCN_FindStraightPath(
    RECAST_NavQueryRef query,
    const float startPos[3],
    const float endPos[3],
    const RECAST_PolyRef* path,
    int pathCount,
    RECAST_PathPoint* outPoints,
    int maxPoints,
    int* outPointCount);

// Casts a walkability ray along the navmesh surface from `startPos` toward
// `endPos`. `outHit` reports how far the ray got and the surface normal at the
// impact. `path`/`maxPath` may be NULL when the traversed corridor is not needed.
RECAST_API int RCN_Raycast(
    RECAST_NavQueryRef query,
    const float startPos[3],
    const float endPos[3],
    RECAST_FilterRef filter,
    RECAST_RaycastHit* outHit,
    RECAST_PolyRef* path,
    int maxPath);

// Moves `startPos` toward `endPos` while staying on the navmesh, stopping at the
// first obstruction. `visited` must hold at least `maxVisited` entries. This is
// the primitive a character controller uses to avoid walking into geometry.
RECAST_API int RCN_MoveAlongSurface(
    RECAST_NavQueryRef query,
    const float startPos[3],
    const float endPos[3],
    RECAST_FilterRef filter,
    float outResultPos[3],
    RECAST_PolyRef* visited,
    int maxVisited,
    int* outVisitedCount);

// Returns the height of the navmesh surface at `pos` using height detail.
RECAST_API int RCN_GetPolyHeight(
    RECAST_NavQueryRef query,
    RECAST_PolyRef ref,
    const float pos[3],
    float* outHeight);

// Finds every polygon overlapping a circle of `radius` (world units) around
// `center`, which is how an area-of-effect or explosion query is done.
RECAST_API int RCN_FindPolysAroundCircle(
    RECAST_NavQueryRef query,
    const float center[3],
    float radius,
    RECAST_FilterRef filter,
    RECAST_PolyRef* outRefs,
    float* outCosts,
    int maxResults,
    int* outResultCount);

#ifdef __cplusplus
}
#endif
