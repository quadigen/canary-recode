#include "jph_api.h"

#define ENABLE_VHACD_IMPLEMENTATION 1
#include "VHACD.h"

#include <Jolt/Jolt.h>
#include <Jolt/Physics/Collision/Shape/CompoundShape.h>
#include <Jolt/Physics/Collision/Shape/StaticCompoundShape.h>
#include <Jolt/Physics/Collision/Shape/ConvexHullShape.h>

#include <memory>
#include <cstdint>

namespace
{

JPH::Vec3 ToJPHVec3(const JPH_Vec3& v)
{
    return JPH::Vec3(v.x, v.y, v.z);
}

struct VHACDInterfaceDeleter
{
    void operator()(VHACD::IVHACD* interface) const
    {
        if (interface != nullptr)
            interface->Release();
    }
};

using VHACDInterface = std::unique_ptr<VHACD::IVHACD, VHACDInterfaceDeleter>;

} // namespace

JPH_ShapeRef JPH_VHACD_Compound_Create(
    const JPH_Vec3* points,
    uint32_t pointCount,
    const uint32_t* triangles,
    uint32_t triangleCount,
    const JPH_Vec3* scale)
{
    if (points == nullptr || triangles == nullptr || pointCount == 0 || triangleCount == 0 || triangleCount % 3 != 0 || scale == nullptr)
        return nullptr;

    VHACDInterface vhacd(VHACD::CreateVHACD());
    if (vhacd == nullptr)
        return nullptr;

    VHACD::IVHACD::Parameters parameters;
    parameters.m_callback = nullptr;
    parameters.m_logger = nullptr;
    parameters.m_taskRunner = nullptr;
    parameters.m_maxConvexHulls = 16;
    parameters.m_resolution = 200000;
    parameters.m_minimumVolumePercentErrorAllowed = 1.0;
    parameters.m_maxRecursionDepth = 10;
    parameters.m_shrinkWrap = true;
    parameters.m_fillMode = VHACD::FillMode::FLOOD_FILL;
    parameters.m_maxNumVerticesPerCH = 64;
    parameters.m_asyncACD = false;
    parameters.m_minEdgeLength = 2;
    parameters.m_findBestPlane = false;

    if (!vhacd->Compute((const float*)points, pointCount, triangles, triangleCount / 3, parameters))
        return nullptr;

    JPH::Vec3 shapeScale = ToJPHVec3(*scale);

    JPH::StaticCompoundShapeSettings compoundSettings;
    const uint32_t numHulls = vhacd->GetNConvexHulls();
    for (uint32_t i = 0; i < numHulls; ++i)
    {
        VHACD::IVHACD::ConvexHull hull;
        if (!vhacd->GetConvexHull(i, hull))
            return nullptr;

        JPH::Array<JPH::Vec3> hullPoints;
        hullPoints.reserve(hull.m_points.size());
        for (const VHACD::Vertex& vertex : hull.m_points)
            hullPoints.emplace_back(
                (float)vertex.mX * shapeScale.GetX(),
                (float)vertex.mY * shapeScale.GetY(),
                (float)vertex.mZ * shapeScale.GetZ());

        if (hullPoints.size() < 4)
            continue;

        JPH::Ref<JPH::ConvexHullShapeSettings> hullSettings = new JPH::ConvexHullShapeSettings(hullPoints);
        compoundSettings.AddShape(JPH::Vec3::sZero(), JPH::Quat::sIdentity(), hullSettings.GetPtr());
    }

    JPH::ShapeSettings::ShapeResult compoundResult = compoundSettings.Create();
    if (compoundResult.HasError())
        return nullptr;

    JPH::Shape* shape = compoundResult.Get().GetPtr();
    shape->AddRef();
    return shape;
}