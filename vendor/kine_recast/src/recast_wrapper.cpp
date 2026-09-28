
#include "recast_api.h"

#include <Recast.h>
#include <RecastAlloc.h>
#include <DetourNavMesh.h>
#include <DetourNavMeshBuilder.h>
#include <DetourNavMeshQuery.h>
#include <DetourCommon.h>
#include <DetourAlloc.h>

#include <cmath>
#include <cstring>
#include <new>
#include <vector>
namespace
{

// Recast logs through rcContext. The wrapper is silent by default: a navmesh
// build is a normal engine operation, and spewing warnings into the editor log
// for every rebuild would be noise. Callers get success/failure through the
// return code instead.
class SilentContext final : public rcContext
{
public:
    SilentContext()
        : rcContext(false) {}
};

// Recast's build entry points all take an rcContext pointer, so the shared
// context is handed out as a pointer rather than a reference.
SilentContext* BuildContext()
{
    static SilentContext context;
    return &context;
}

int ClampInt(int value, int low, int high)
{
    if (value < low) { return low; }
    if (value > high) { return high; }
    return value;
}

// Clamp the agent's voxel dimensions the way Recast's own samples do. Passing an
// unclamped 0 for agentRadius silently produces an unusable navmesh, so the
// wrapper enforces Recast's documented limits up front.
void ClampAgentConfig(RECAST_BuildConfig* config)
{
    config->cellSize = config->cellSize > 0.0f ? config->cellSize : 0.3f;
    config->cellHeight = config->cellHeight > 0.0f ? config->cellHeight : 0.2f;
    config->agentHeight = config->agentHeight > 0.0f ? config->agentHeight : 2.0f;
    config->agentRadius = config->agentRadius > 0.0f ? config->agentRadius : 0.6f;
    config->agentMaxClimb = config->agentMaxClimb >= 0.0f ? config->agentMaxClimb : 0.9f;
    config->agentMaxSlope = config->agentMaxSlope >= 0.0f ? config->agentMaxSlope : 45.0f;
    config->vertsPerPoly = config->vertsPerPoly >= 3.0f ? config->vertsPerPoly : 6.0f;

    if (config->vertsPerPoly > 6.0f) { config->vertsPerPoly = 6.0f; }
    if (config->regionMinSize < 0.0f) { config->regionMinSize = 0.0f; }
    if (config->regionMergeSize < 0.0f) { config->regionMergeSize = 0.0f; }
    if (config->edgeMaxError < 0.0f) { config->edgeMaxError = 0.0f; }
    if (config->detailSampleDist < 0.0f) { config->detailSampleDist = 0.0f; }
    if (config->detailSampleMaxError < 0.0f) { config->detailSampleMaxError = 0.0f; }
}

// Detour has no DT_MAX_PATH in current recastnavigation, so the wrapper defines
// its own ceiling for the polygon corridors callers may request. It matches the
// node budget RCN_CreateNavQuery defaults to.
const int RCN_MAX_PATH = 256;

} // namespace

extern "C" {

const char* RCN_GetVersion(void)
{
    return "kine_recast 0.1.0 (recastnavigation main)";
}

void RCN_DefaultBuildConfig(RECAST_BuildConfig* config)
{
    if (config == nullptr) { return; }

    std::memset(config, 0, sizeof(*config));

    // These match the agent a typical humanoid controller assumes: roughly
    // 2 studs tall with a 0.6 stud clearance radius.
    config->cellSize = 0.3f;
    config->cellHeight = 0.2f;
    config->agentHeight = 2.0f;
    config->agentRadius = 0.6f;
    config->agentMaxClimb = 0.9f;
    config->agentMaxSlope = 45.0f;

    config->regionMinSize = 8.0f;
    config->regionMergeSize = 20.0f;

    config->edgeMaxLen = 12.0f;
    config->edgeMaxError = 1.3f;
    config->vertsPerPoly = 6.0f;

    config->detailSampleDist = 6.0f;
    config->detailSampleMaxError = 1.0f;
}

void RCN_DefaultQueryFilter(RECAST_QueryFilter* filter)
{
    if (filter == nullptr) { return; }

    std::memset(filter, 0, sizeof(*filter));

    // Match dtQueryFilter's own default: include every polygon and exclude
    // none. Leaving includeFlags at zero would filter out the entire navmesh.
    filter->includeFlags = 0xffff;
    filter->excludeFlags = 0x0;

    // dtQueryFilter treats a cost of 0 as impassable, so every area starts at a
    // cost of 1 and the caller raises specific areas from there.
    for (int i = 0; i < 64; ++i) {
        filter->areaCost[i] = 1.0f;
    }
}

// Scoped owners for the intermediate Recast structures. The build allocates
// heightfields, contour sets, and polygon meshes that must all be released even
// when a later step fails, so they are held here and freed on the way out.
class BuildScratch
{
public:
    ~BuildScratch()
    {
        rcFreeHeightField(solid);
        rcFreeCompactHeightfield(compact);
        rcFreeContourSet(contours);
        rcFreePolyMesh(polys);
        rcFreePolyMeshDetail(detail);
        // Navmesh data is a plain Recast allocation; Detour only takes ownership
        // of it once the tile has been handed over successfully.
        rcFree(navData);
    }

    rcHeightfield* solid = nullptr;
    rcCompactHeightfield* compact = nullptr;
    rcContourSet* contours = nullptr;
    rcPolyMesh* polys = nullptr;
    rcPolyMeshDetail* detail = nullptr;
    unsigned char* navData = nullptr;
};

} // namespace

extern "C" {

int RCN_BuildNavMesh(
    const float* verts,
    int numVerts,
    const int* tris,
    int numTris,
    const RECAST_BuildConfig* config,
    RECAST_NavMeshRef* outNavMesh)
{
    if (verts == nullptr || tris == nullptr ||
        config == nullptr || outNavMesh == nullptr) {
        return RCN_Error_InvalidArgument;
    }

    // A navmesh needs real geometry. Guarding here turns a caller mistake into a
    // clean error instead of a divide-by-zero deep inside the rasterizer.
    if (numVerts < 3 || numTris < 1) {
        return RCN_Error_InvalidArgument;
    }

    *outNavMesh = nullptr;

    RECAST_BuildConfig tuned = *config;
    ClampAgentConfig(&tuned);

    rcContext* context = BuildContext();

    float bmin[3];
    float bmax[3];
    rcCalcBounds(verts, numVerts, bmin, bmax);

    // A level that is perfectly flat (a single ground plane, say) produces an
    // AABB with zero height. Recast cannot voxelize that, and the resulting
    // navmesh ends up with no usable height, so grow the vertical extent by a
    // single cell to give the field a real thickness.
    if (bmax[1] - bmin[1] < tuned.cellHeight) {
        bmax[1] = bmin[1] + tuned.cellHeight;
    }

    rcConfig rc;
    std::memset(&rc, 0, sizeof(rc));

    rc.cs = tuned.cellSize;
    rc.ch = tuned.cellHeight;
    rc.walkableSlopeAngle = tuned.agentMaxSlope;
    rc.walkableHeight = static_cast<int>(std::ceil(tuned.agentHeight / rc.ch));
    rc.walkableClimb = static_cast<int>(std::floor(tuned.agentMaxClimb / rc.ch));
    rc.walkableRadius = static_cast<int>(std::ceil(tuned.agentRadius / rc.cs));
    rc.maxEdgeLen = static_cast<int>(tuned.edgeMaxLen / rc.cs);
    rc.maxSimplificationError = tuned.edgeMaxError;
    rc.minRegionArea = static_cast<int>(std::sqrt(tuned.regionMinSize * tuned.regionMinSize / (rc.cs * rc.cs)));
    rc.mergeRegionArea = static_cast<int>(std::sqrt(tuned.regionMergeSize * tuned.regionMergeSize / (rc.cs * rc.cs)));
    rc.maxVertsPerPoly = static_cast<int>(tuned.vertsPerPoly);
    // Recast treats a distance below 0.9 as "no detail mesh", so snap small
    // values to zero instead of building a mesh nobody asked for.
    rc.detailSampleDist = tuned.detailSampleDist < 0.9f ? 0.0f : tuned.detailSampleDist;
    rc.detailSampleMaxError = tuned.detailSampleMaxError;

    rcVcopy(rc.bmin, bmin);
    rcVcopy(rc.bmax, bmax);

    rcCalcGridSize(rc.bmin, rc.bmax, rc.cs, &rc.width, &rc.height);

    // The border keeps walkable area from touching the edge of the field, which
    // is what stops agents from clipping through the boundary of the level.
    rc.borderSize = rc.walkableRadius + 3;

    if (rc.width <= 0 || rc.height <= 0) {
        return RCN_Error_InvalidArgument;
    }

    BuildScratch scratch;

    scratch.solid = rcAllocHeightfield();
    if (scratch.solid == nullptr) {
        return RCN_Error_AllocationFailed;
    }

    if (!rcCreateHeightfield(context, *scratch.solid, rc.width, rc.height, rc.bmin, rc.bmax, rc.cs, rc.ch)) {
        return RCN_Error_BuildFailed;
    }

    // Triangles are rasterized, then three filters remove geometry an agent
    // cannot actually use: small steppable obstacles, ledges, and spans without
    // enough headroom.
    // Record which triangles are walkable. Recast reads this array
    // unconditionally, so it cannot be null.
    const int numAreas = numTris;
    std::vector<unsigned char> areas(static_cast<size_t>(numAreas), RECAST_WALKABLE_AREA);
    rcMarkWalkableTriangles(context, tuned.agentMaxSlope, verts, numVerts, tris, numAreas, areas.data());

    if (!rcRasterizeTriangles(context, verts, numVerts, tris, areas.data(), numAreas, *scratch.solid, rc.walkableClimb)) {
        return RCN_Error_BuildFailed;
    }

    rcFilterLowHangingWalkableObstacles(context, rc.walkableClimb, *scratch.solid);
    rcFilterLedgeSpans(context, rc.walkableHeight, rc.walkableClimb, *scratch.solid);
    rcFilterWalkableLowHeightSpans(context, rc.walkableHeight, *scratch.solid);

    scratch.compact = rcAllocCompactHeightfield();
    if (scratch.compact == nullptr) {
        return RCN_Error_AllocationFailed;
    }

    if (!rcBuildCompactHeightfield(context, rc.walkableHeight, rc.walkableClimb, *scratch.solid, *scratch.compact)) {
        return RCN_Error_BuildFailed;
    }

    // Eroding by the agent radius keeps agents off walls, so they do not clip
    // into geometry while following a path.
    if (!rcErodeWalkableArea(context, rc.walkableRadius, *scratch.compact)) {
        return RCN_Error_BuildFailed;
    }

    if (!rcMedianFilterWalkableArea(context, *scratch.compact)) {
        return RCN_Error_BuildFailed;
    }

    if (!rcBuildDistanceField(context, *scratch.compact)) {
        return RCN_Error_BuildFailed;
    }

    if (!rcBuildRegions(context, *scratch.compact, rc.borderSize, rc.minRegionArea, rc.mergeRegionArea)) {
        return RCN_Error_BuildFailed;
    }

    scratch.contours = rcAllocContourSet();
    if (scratch.contours == nullptr) {
        return RCN_Error_AllocationFailed;
    }

    if (!rcBuildContours(context, *scratch.compact, rc.maxSimplificationError, rc.maxEdgeLen, *scratch.contours)) {
        return RCN_Error_BuildFailed;
    }

    scratch.polys = rcAllocPolyMesh();
    if (scratch.polys == nullptr) {
        return RCN_Error_AllocationFailed;
    }

    if (!rcBuildPolyMesh(context, *scratch.contours, rc.maxVertsPerPoly, *scratch.polys)) {
        return RCN_Error_BuildFailed;
    }

    // The detail mesh is optional: it improves height accuracy on slopes, and
    // skipping it still leaves a fully usable navmesh.
    if (rc.detailSampleDist > 0.0f) {
        scratch.detail = rcAllocPolyMeshDetail();
        if (scratch.detail != nullptr) {
            rcBuildPolyMeshDetail(context, *scratch.polys, *scratch.compact,
                                  rc.detailSampleDist, rc.detailSampleMaxError, *scratch.detail);
        }
    }

    // A mesh with no contours means nothing in the input was walkable at the
    // requested agent height. That is a legitimate outcome (an empty level, or a
    // slope filter set too low), not a failure to report as corruption.
    if (scratch.polys->npolys == 0) {
        return RCN_Error_NoPath;
    }

    // rcBuildPolyMesh copies poly areas across but leaves the sample flags at
    // zero, and Detour treats a flag of 0 as "not walkable" so every query
    // filters the whole mesh out. Mark the polygons the build produced as
    // walkable; Detour's SAMPLE_POLYFLAGS_WALK is 0x01.
    //
    // The same applies to area: a poly whose area is RC_NULL_AREA costs nothing
    // to traverse and is filtered out, even when its geometry is fine. Promote
    // any polygon the build kept to the standard ground area.
    for (int i = 0; i < scratch.polys->npolys; ++i) {
        scratch.polys->flags[i] = 0x01;
        scratch.polys->areas[i] = RECAST_WALKABLE_AREA;
    }

    // Marshal the generated meshes into the flat tile layout Detour loads.
    //
    // rcPolyMesh stores its vertices as unsigned shorts in *voxel* space, and
    // dtCreateNavMeshData converts them to world units itself using bmin/cs/ch.
    // Passing the buffer through as-is is what the field types expect.
    dtNavMeshCreateParams createParams;
    std::memset(&createParams, 0, sizeof(createParams));

    createParams.verts = scratch.polys->verts;
    createParams.vertCount = scratch.polys->nverts;
    createParams.polys = scratch.polys->polys;
    createParams.polyAreas = scratch.polys->areas;
    createParams.polyFlags = scratch.polys->flags;
    createParams.polyCount = scratch.polys->npolys;
    createParams.nvp = scratch.polys->nvp;

    if (scratch.detail != nullptr) {
        createParams.detailMeshes = scratch.detail->meshes;
        createParams.detailVerts = scratch.detail->verts;
        createParams.detailVertsCount = scratch.detail->nverts;
        createParams.detailTris = scratch.detail->tris;
        createParams.detailTriCount = scratch.detail->ntris;
    }

    createParams.walkableHeight = static_cast<float>(rc.walkableHeight) * rc.ch;
    createParams.walkableRadius = static_cast<float>(rc.walkableRadius) * rc.cs;
    createParams.walkableClimb = static_cast<float>(rc.walkableClimb) * rc.ch;
    // The vertex conversion above is driven by bmin/cs/ch, so these must be set
    // for the mesh to land at the right world position.
    createParams.cs = rc.cs;
    createParams.ch = rc.ch;
    dtVcopy(createParams.bmin, rc.bmin);
    dtVcopy(createParams.bmax, rc.bmax);

    int navDataSize = 0;
    if (!dtCreateNavMeshData(&createParams, &scratch.navData, &navDataSize)) {
        return RCN_Error_BuildFailed;
    }

    dtNavMesh* navMesh = dtAllocNavMesh();
    if (navMesh == nullptr) {
        return RCN_Error_AllocationFailed;
    }

    dtNavMeshParams params;
    std::memset(&params, 0, sizeof(params));
    dtVcopy(params.orig, rc.bmin);
    params.tileWidth = static_cast<float>(rc.width) * rc.cs;
    params.tileHeight = static_cast<float>(rc.height) * rc.cs;
    // This wrapper builds one tile covering the whole mesh. A tiled setup would
    // be needed for streaming open worlds, which is a larger change.
    params.maxTiles = 1;
    // Bit budget for encoding a polygon id. Must cover the poly count Recast
    // just produced.
    params.maxPolys = 0x8000;

    if (dtStatusFailed(navMesh->init(&params))) {
        dtFreeNavMesh(navMesh);
        return RCN_Error_BuildFailed;
    }

    // DT_TILE_FREE_DATA transfers ownership of the buffer to Detour, so the
    // scratch guard must stop tracking it once this succeeds.
    if (dtStatusFailed(navMesh->init(scratch.navData, navDataSize, DT_TILE_FREE_DATA))) {
        dtFreeNavMesh(navMesh);
        return RCN_Error_BuildFailed;
    }
    scratch.navData = nullptr;

    *outNavMesh = navMesh;
    return RCN_Error_None;
}

void RCN_FreeNavMesh(RECAST_NavMeshRef navMesh)
{
    if (navMesh == nullptr) { return; }
    dtFreeNavMesh(static_cast<dtNavMesh*>(navMesh));
}

RECAST_NavQueryRef RCN_CreateNavQuery(RECAST_NavMeshRef navMesh, int maxNodes)
{
    if (navMesh == nullptr) { return nullptr; }

    // Detour needs a node budget up front; default to a value large enough for
    // typical level-sized meshes when the caller does not care.
    if (maxNodes <= 0) { maxNodes = 2048; }

    dtNavMeshQuery* query = dtAllocNavMeshQuery();
    if (query == nullptr) { return nullptr; }

    if (dtStatusFailed(query->init(static_cast<dtNavMesh*>(navMesh), maxNodes))) {
        dtFreeNavMeshQuery(query);
        return nullptr;
    }

    return query;
}

void RCN_FreeNavQuery(RECAST_NavQueryRef query)
{
    if (query == nullptr) { return; }
    dtFreeNavMeshQuery(static_cast<dtNavMeshQuery*>(query));
}

RECAST_FilterRef RCN_CreateQueryFilter(const RECAST_QueryFilter* description)
{
    dtQueryFilter* filter = new (std::nothrow) dtQueryFilter();
    if (filter == nullptr) { return nullptr; }

    if (description != nullptr) {
        filter->setIncludeFlags(description->includeFlags);
        filter->setExcludeFlags(description->excludeFlags);

        for (int i = 0; i < DT_MAX_AREAS; ++i) {
            // dtQueryFilter indexes its cost table by area id, and a negative or
            // zero cost means impassable, so only forward sane values.
            const float cost = description->areaCost[i];
            filter->setAreaCost(i, cost > 0.0f ? cost : 1.0f);
        }
    }

    return filter;
}

void RCN_FreeQueryFilter(RECAST_FilterRef filter)
{
    delete static_cast<dtQueryFilter*>(filter);
}

int RCN_FindNearestPoly(
    RECAST_NavQueryRef query,
    const float center[3],
    const float halfExtents[3],
    RECAST_FilterRef filter,
    RECAST_PolyRef* outRef,
    float outNearestPoint[3])
{
    if (query == nullptr || center == nullptr || halfExtents == nullptr || outRef == nullptr) {
        return RCN_Error_InvalidArgument;
    }

    *outRef = RECAST_POLYREF_INVALID;

    const dtNavMeshQuery* navQuery = static_cast<const dtNavMeshQuery*>(query);
    const dtQueryFilter* dtFilter = static_cast<const dtQueryFilter*>(filter);

    dtPolyRef nearest = 0;
    float nearestPoint[3] = { 0.0f, 0.0f, 0.0f };

    const dtStatus status = navQuery->findNearestPoly(center, halfExtents, dtFilter, &nearest, nearestPoint);
    if (dtStatusFailed(status)) {
        return RCN_Error_QueryFailed;
    }

    *outRef = static_cast<RECAST_PolyRef>(nearest);

    if (outNearestPoint != nullptr) {
        dtVcopy(outNearestPoint, nearestPoint);
    }

    // Finding no polygon is a normal answer, not an error, so report success and
    // let the invalid reference tell the caller there was nothing there.
    return RCN_Error_None;
}

int RCN_FindPath(
    RECAST_NavQueryRef query,
    const float startPos[3],
    const float endPos[3],
    RECAST_FilterRef filter,
    RECAST_PolyRef* outPath,
    int maxPath,
    int* outPathCount)
{
    if (query == nullptr || startPos == nullptr || endPos == nullptr ||
        outPath == nullptr || outPathCount == nullptr) {
        return RCN_Error_InvalidArgument;
    }

    if (maxPath <= 0) {
        return RCN_Error_InvalidArgument;
    }

    *outPathCount = 0;

    const dtNavMeshQuery* navQuery = static_cast<const dtNavMeshQuery*>(query);
    const dtQueryFilter* dtFilter = static_cast<const dtQueryFilter*>(filter);

    // Project both endpoints onto the mesh. A path request usually starts from a
    // position that is slightly off the surface (an agent's feet, say), and
    // Detour needs polygon references rather than raw points.
    const float halfExtents[3] = { 2.0f, 4.0f, 2.0f };

    dtPolyRef startRef = 0;
    dtPolyRef endRef = 0;
    float startNearest[3];
    float endNearest[3];

    const dtStatus s1 = navQuery->findNearestPoly(startPos, halfExtents, dtFilter, &startRef, startNearest);
    const dtStatus s2 = navQuery->findNearestPoly(endPos, halfExtents, dtFilter, &endRef, endNearest);

    if (dtStatusFailed(s1)) {
        return RCN_Error_QueryFailed;
    }

    if (dtStatusFailed(s2)) {
        return RCN_Error_QueryFailed;
    }

    // Either endpoint off the mesh means there is no corridor to search at all.
    if (startRef == 0 || endRef == 0) {
        return RCN_Error_NoPath;
    }

    int pathCount = 0;
    const dtStatus status = navQuery->findPath(
        startRef, endRef, startNearest, endNearest, dtFilter, outPath, &pathCount, maxPath);

    if (dtStatusFailed(status)) {
        return RCN_Error_QueryFailed;
    }

    *outPathCount = pathCount;

    // Detour reports DT_FAILURE with a partial path when the goal is only
    // partially reachable. That partial corridor is still the best answer a
    // follower can use, so surface it instead of discarding it.
    if (pathCount == 0) {
        return RCN_Error_NoPath;
    }

    return RCN_Error_None;
}

int RCN_FindStraightPath(
    RECAST_NavQueryRef query,
    const float startPos[3],
    const float endPos[3],
    const RECAST_PolyRef* path,
    int pathCount,
    RECAST_PathPoint* outPoints,
    int maxPoints,
    int* outPointCount)
{
    if (query == nullptr || startPos == nullptr || endPos == nullptr ||
        path == nullptr || outPoints == nullptr || outPointCount == nullptr) {
        return RCN_Error_InvalidArgument;
    }

    if (pathCount <= 0 || maxPoints <= 0) {
        return RCN_Error_InvalidArgument;
    }

    *outPointCount = 0;

    const dtNavMeshQuery* navQuery = static_cast<const dtNavMeshQuery*>(query);

    // Detour writes a flat array of xyz triples, but RECAST_PathPoint is padded
    // out to hold its flags and poly ref, so its stride is larger than 12 bytes.
    // Buffer Detour's output separately and copy it across, otherwise the writes
    // would land at the wrong offsets and overrun the caller's array.
    const int floatCount = maxPoints * 3;
    std::vector<float> scratch(static_cast<size_t>(floatCount), 0.0f);

    int pointCount = 0;
    const dtStatus status = navQuery->findStraightPath(
        startPos, endPos, path, pathCount,
        scratch.data(), nullptr, nullptr, &pointCount, maxPoints, 0);

    if (dtStatusFailed(status)) {
        return RCN_Error_QueryFailed;
    }

    if (pointCount > maxPoints) {
        // Defensive: never write past what the caller sized, even if Detour
        // reports more corners than were requested.
        pointCount = maxPoints;
    }

    // Every point is on-mesh here because this wrapper never builds off-mesh
    // links, so no DT_STRAIGHTPATH_OFFMESH_CONNECTION flag is produced.
    for (int i = 0; i < pointCount; ++i) {
        outPoints[i].x = scratch[static_cast<size_t>(i) * 3 + 0];
        outPoints[i].y = scratch[static_cast<size_t>(i) * 3 + 1];
        outPoints[i].z = scratch[static_cast<size_t>(i) * 3 + 2];
        outPoints[i].flags = 0;
        outPoints[i].ref = RECAST_POLYREF_INVALID;
    }

    *outPointCount = pointCount;
    return RCN_Error_None;
}

int RCN_Raycast(
    RECAST_NavQueryRef query,
    const float startPos[3],
    const float endPos[3],
    RECAST_FilterRef filter,
    RECAST_RaycastHit* outHit,
    RECAST_PolyRef* path,
    int maxPath)
{
    if (query == nullptr || startPos == nullptr || endPos == nullptr || outHit == nullptr) {
        return RCN_Error_InvalidArgument;
    }

    const dtNavMeshQuery* navQuery = static_cast<const dtNavMeshQuery*>(query);
    const dtQueryFilter* dtFilter = static_cast<const dtQueryFilter*>(filter);

    // Project the origin onto the mesh; a raycast has to start on a polygon.
    const float halfExtents[3] = { 2.0f, 4.0f, 2.0f };

    dtPolyRef startRef = 0;
    float startNearest[3];
    if (dtStatusFailed(navQuery->findNearestPoly(startPos, halfExtents, dtFilter, &startRef, startNearest))) {
        return RCN_Error_QueryFailed;
    }

    if (startRef == 0) {
        return RCN_Error_NoPath;
    }

    // The corridor is optional. Cap what Detour is asked to record so a caller
    // cannot be told it got more entries than it sized for.
    dtPolyRef* corridor = nullptr;
    int corridorCapacity = 0;

    if (path != nullptr && maxPath > 0) {
        corridorCapacity = maxPath < RCN_MAX_PATH ? maxPath : RCN_MAX_PATH;
        corridor = path;
    }

    // Detour's dtRaycastHit overload takes a single "previous ref" rather than a
    // corridor array, so use the older signature that accepts a path buffer.
    // Either overload reports a blocked ray as a failure, so the returned t and
    // normal are the answer rather than an error.
    float t = 0.0f;
    float hitNormal[3] = { 0.0f, 0.0f, 0.0f };
    int pathCount = 0;

    const dtStatus status = navQuery->raycast(
        startRef, startNearest, endPos, dtFilter,
        &t, hitNormal, corridor, &pathCount, corridorCapacity);

    // A blocked ray still comes back as a failure, so only give up when the ray
    // actually reached its endpoint without hitting anything.
    if (dtStatusFailed(status) && t >= 1.0f) {
        return RCN_Error_NoPath;
    }

    outHit->t = t;
    outHit->pathCount = pathCount > corridorCapacity ? corridorCapacity : pathCount;
    dtVcopy(outHit->hitNormal, hitNormal);

    return RCN_Error_None;
}

int RCN_MoveAlongSurface(
    RECAST_NavQueryRef query,
    const float startPos[3],
    const float endPos[3],
    RECAST_FilterRef filter,
    float outResultPos[3],
    RECAST_PolyRef* visited,
    int maxVisited,
    int* outVisitedCount)
{
    if (query == nullptr || startPos == nullptr || endPos == nullptr ||
        outResultPos == nullptr || visited == nullptr || outVisitedCount == nullptr) {
        return RCN_Error_InvalidArgument;
    }

    if (maxVisited <= 0) {
        return RCN_Error_InvalidArgument;
    }

    const dtNavMeshQuery* navQuery = static_cast<const dtNavMeshQuery*>(query);
    const dtQueryFilter* dtFilter = static_cast<const dtQueryFilter*>(filter);

    const float halfExtents[3] = { 2.0f, 4.0f, 2.0f };

    dtPolyRef startRef = 0;
    float startNearest[3];
    if (dtStatusFailed(navQuery->findNearestPoly(startPos, halfExtents, dtFilter, &startRef, startNearest))) {
        return RCN_Error_QueryFailed;
    }

    if (startRef == 0) {
        return RCN_Error_NoPath;
    }

    float resultPos[3] = { 0.0f, 0.0f, 0.0f };
    int visitedCount = 0;

    const dtStatus status = navQuery->moveAlongSurface(
        startRef, startNearest, endPos, dtFilter,
        resultPos, visited, &visitedCount, maxVisited);

    // A blocked move still returns the furthest reachable position, which is
    // exactly what a character controller needs, so only treat a missing result
    // as a failure.
    if (dtStatusFailed(status) && visitedCount == 0) {
        return RCN_Error_QueryFailed;
    }

    dtVcopy(outResultPos, resultPos);
    *outVisitedCount = visitedCount > maxVisited ? maxVisited : visitedCount;

    return RCN_Error_None;
}

int RCN_GetPolyHeight(
    RECAST_NavQueryRef query,
    RECAST_PolyRef ref,
    const float pos[3],
    float* outHeight)
{
    if (query == nullptr || pos == nullptr || outHeight == nullptr) {
        return RCN_Error_InvalidArgument;
    }

    if (ref == RECAST_POLYREF_INVALID) {
        return RCN_Error_InvalidArgument;
    }

    const dtNavMeshQuery* navQuery = static_cast<const dtNavMeshQuery*>(query);

    float height = 0.0f;
    const dtStatus status = navQuery->getPolyHeight(static_cast<dtPolyRef>(ref), pos, &height);
    if (dtStatusFailed(status)) {
        return RCN_Error_QueryFailed;
    }

    *outHeight = height;
    return RCN_Error_None;
}

int RCN_FindPolysAroundCircle(
    RECAST_NavQueryRef query,
    const float center[3],
    float radius,
    RECAST_FilterRef filter,
    RECAST_PolyRef* outRefs,
    float* outCosts,
    int maxResults,
    int* outResultCount)
{
    if (query == nullptr || center == nullptr || outRefs == nullptr || outResultCount == nullptr) {
        return RCN_Error_InvalidArgument;
    }

    if (maxResults <= 0) {
        return RCN_Error_InvalidArgument;
    }

    const dtNavMeshQuery* navQuery = static_cast<const dtNavMeshQuery*>(query);
    const dtQueryFilter* dtFilter = static_cast<const dtQueryFilter*>(filter);

    // An area query still needs a polygon to expand outwards from.
    const float halfExtents[3] = { 2.0f, 4.0f, 2.0f };

    dtPolyRef startRef = 0;
    float startNearest[3];
    if (dtStatusFailed(navQuery->findNearestPoly(center, halfExtents, dtFilter, &startRef, startNearest))) {
        return RCN_Error_QueryFailed;
    }

    if (startRef == 0) {
        return RCN_Error_NoPath;
    }

    // Costs are optional for the caller, but Detour always wants somewhere to
    // write them, so fall back to a scratch array when none was supplied.
    std::vector<float> costScratch;

    dtPolyRef parentRefs[RCN_MAX_PATH];
    float* costs = outCosts;
    int capacity = maxResults;

    if (capacity > RCN_MAX_PATH) {
        // Report no more than the ceiling rather than implying the caller should
        // have sized a larger array.
        capacity = RCN_MAX_PATH;
    }

    if (costs == nullptr) {
        costScratch.assign(static_cast<size_t>(capacity), 0.0f);
        costs = costScratch.data();
    }

    // findPolysAroundCircle needs a parent array matching the result array. The
    // caller does not want parents, so always use the local buffer.
    int resultCount = 0;
    const dtStatus status = navQuery->findPolysAroundCircle(
        startRef, center, radius, dtFilter,
        outRefs, parentRefs, costs, &resultCount, capacity);

    if (dtStatusFailed(status)) {
        return RCN_Error_QueryFailed;
    }

    *outResultCount = resultCount > capacity ? capacity : resultCount;
    return RCN_Error_None;
}

} // extern "C"
