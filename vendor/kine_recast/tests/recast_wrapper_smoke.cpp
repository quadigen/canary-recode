#include "recast_api.h"

#include <cstdio>
#include <cmath>
#include <vector>

// Smoke test: build a navmesh from a flat 20x20 ground plane, then walk a
// query across it. This exercises the whole wrapper, including the Recast build
// pipeline and every Detour query entry point.
int main()
{
    std::printf("version: %s\n", RCN_GetVersion());

    // A flat square at y=0, wound counter-clockwise when viewed from above.
    std::vector<float> verts = {
        -10.0f, 0.0f, -10.0f,
         10.0f, 0.0f, -10.0f,
         10.0f, 0.0f,  10.0f,
        -10.0f, 0.0f,  10.0f,
    };
    std::vector<int> tris = { 0, 2, 1, 0, 3, 2 };

    RECAST_BuildConfig config;
    RCN_DefaultBuildConfig(&config);
    config.cellSize = 0.5f;
    config.cellHeight = 0.2f;

    RECAST_NavMeshRef navMesh = nullptr;
    const int built = RCN_BuildNavMesh(verts.data(), (int)verts.size() / 3,
                                       tris.data(), (int)tris.size() / 3,
                                       &config, &navMesh);
    if (built != RCN_Error_None) {
        std::printf("FAIL: RCN_BuildNavMesh returned %d\n", built);
        return 1;
    }
    std::printf("build: ok\n");

    RECAST_NavQueryRef query = RCN_CreateNavQuery(navMesh, 0);
    if (query == nullptr) {
        std::printf("FAIL: RCN_CreateNavQuery returned null\n");
        RCN_FreeNavMesh(navMesh);
        return 1;
    }

    RECAST_QueryFilter filterDesc;
    RCN_DefaultQueryFilter(&filterDesc);
    RECAST_FilterRef filter = RCN_CreateQueryFilter(&filterDesc);

    // Nearest polygon at the centre of the plane.
    const float center[3] = { 0.0f, 0.0f, 0.0f };
    const float extents[3] = { 4.0f, 4.0f, 4.0f };
    RECAST_PolyRef ref = RECAST_POLYREF_INVALID;
    float nearest[3] = { 0.0f, 0.0f, 0.0f };
    int npc = RCN_FindNearestPoly(query, center, extents, filter, &ref, nearest);
    if (npc != RCN_Error_None || ref == RECAST_POLYREF_INVALID) {
        std::printf("FAIL: FindNearestPoly found nothing on a flat plane\n");
        return 1;
    }
    std::printf("nearest poly: ok (y=%.3f)\n", nearest[1]);

    float height = 0.0f;
    if (RCN_GetPolyHeight(query, ref, center, &height) != RCN_Error_None) {
        std::printf("FAIL: GetPolyHeight\n");
        return 1;
    }
    if (std::fabs(height) > 0.5f) {
        std::printf("FAIL: expected ~0 height on flat ground, got %.3f\n", height);
        return 1;
    }
    std::printf("poly height: ok (%.3f)\n", height);

    // Walk a corridor across the buildable surface. The navmesh is inset from
    // the input geometry by the agent radius and border, so the endpoints stay
    // well inside the mesh rather than at the outer corners.
    const float startPos[3] = { -8.0f, 0.2f, -8.0f };
    const float endPos[3] = { 0.0f, 0.2f, 0.0f };
    RECAST_PolyRef path[128];
    int pathCount = 0;
    const int found = RCN_FindPath(query, startPos, endPos, filter, path, 128, &pathCount);
    if (found != RCN_Error_None || pathCount == 0) {
        std::printf("FAIL: FindPath returned %d with %d polys\n", found, pathCount);
        return 1;
    }
    std::printf("path: ok (%d polys)\n", pathCount);

    RECAST_PathPoint points[128];
    int pointCount = 0;
    if (RCN_FindStraightPath(query, startPos, endPos, path, pathCount, points, 128, &pointCount) != RCN_Error_None) {
        std::printf("FAIL: FindStraightPath\n");
        return 1;
    }
    if (pointCount < 2) {
        std::printf("FAIL: expected at least 2 corners, got %d\n", pointCount);
        return 1;
    }
    const float lastX = points[pointCount - 1].x;
    const float lastZ = points[pointCount - 1].z;
    if (std::fabs(lastX - endPos[0]) > 1.0f || std::fabs(lastZ - endPos[2]) > 1.0f) {
        std::printf("FAIL: path ends at (%.2f, %.2f), expected near (0, 0)\n", lastX, lastZ);
        return 1;
    }
    std::printf("straight path: ok (%d corners, ends near goal)\n", pointCount);

    // Area query over a 5 unit circle should pick up polygons under it.
    RECAST_PolyRef circleRefs[64];
    float circleCosts[64];
    int circleCount = 0;
    if (RCN_FindPolysAroundCircle(query, center, 5.0f, filter, circleRefs, circleCosts, 64, &circleCount) != RCN_Error_None || circleCount == 0) {
        std::printf("FAIL: FindPolysAroundCircle found nothing\n");
        return 1;
    }
    std::printf("area query: ok (%d polys)\n", circleCount);

    // Move along the surface: a short unobstructed step should arrive.
    const float moveTo[3] = { 0.0f, 0.0f, 5.0f };
    float moved[3] = { 0.0f, 0.0f, 0.0f };
    RECAST_PolyRef visited[64];
    int visitedCount = 0;
    if (RCN_MoveAlongSurface(query, center, moveTo, filter, moved, visited, 64, &visitedCount) != RCN_Error_None) {
        std::printf("FAIL: MoveAlongSurface\n");
        return 1;
    }
    if (std::fabs(moved[2] - moveTo[2]) > 1.0f) {
        std::printf("FAIL: move ended at z=%.2f, expected ~5\n", moved[2]);
        return 1;
    }
    std::printf("move along surface: ok (z=%.2f)\n", moved[2]);

    // Raycast across the buildable surface. The navmesh only covers part of the
    // input plane, so the ray is expected to stop at the mesh edge rather than
    // reach the far end.
    const float rayEnd[3] = { 0.0f, 0.2f, 9.0f };
    RECAST_RaycastHit hit;
    if (RCN_Raycast(query, center, rayEnd, filter, &hit, nullptr, 0) != RCN_Error_None) {
        std::printf("FAIL: Raycast\n");
        return 1;
    }
    if (hit.t <= 0.0f || hit.t > 1.0f) {
        std::printf("FAIL: raycast reported an out-of-range t=%.3f\n", hit.t);
        return 1;
    }
    std::printf("raycast: ok (t=%.3f, stopped at mesh edge)\n", hit.t);

    // Bad arguments must be reported, not crash.
    if (RCN_BuildNavMesh(nullptr, 0, nullptr, 0, &config, &navMesh) != RCN_Error_InvalidArgument) {
        std::printf("FAIL: expected invalid-argument rejection\n");
        return 1;
    }

    // Free handles are all NULL-tolerant.
    RCN_FreeNavMesh(navMesh);
    RCN_FreeNavQuery(query);
    RCN_FreeQueryFilter(filter);
    RCN_FreeNavMesh(nullptr);
    RCN_FreeNavQuery(nullptr);
    RCN_FreeQueryFilter(nullptr);

    std::printf("RECAST_WRAPPER_SMOKE_PASSED\n");
    return 0;
}
