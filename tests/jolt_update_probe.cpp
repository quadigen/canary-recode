#include "jph_api.h"

#include <cstdio>

int main()
{
    if (!JPH_Init()) return 1;
    JPH_ObjectLayerPairFilterRef pairs = JPH_ObjectLayerPairFilterTable_Create(2);
    JPH_ObjectLayerPairFilterTable_EnableCollision(pairs, 0, 1);
    JPH_BroadPhaseLayerInterfaceRef broad = JPH_BroadPhaseLayerInterfaceTable_Create(2, 2);
    JPH_BroadPhaseLayerInterfaceTable_MapObjectToBroadPhaseLayer(broad, 0, 0);
    JPH_BroadPhaseLayerInterfaceTable_MapObjectToBroadPhaseLayer(broad, 1, 1);
    JPH_ObjectVsBroadPhaseLayerFilterRef object_vs_broad =
        JPH_ObjectVsBroadPhaseLayerFilterTable_Create(broad, 2, pairs, 2);

    JPH_PhysicsSystemSettings settings{};
    settings.maxBodies = 1024;
    settings.maxBodyPairs = 1024;
    settings.maxContactConstraints = 1024;
    settings.broadPhaseLayerInterface = broad;
    settings.objectLayerPairFilter = pairs;
    settings.objectVsBroadPhaseLayerFilter = object_vs_broad;
    JPH_PhysicsSystemRef system = JPH_PhysicsSystem_Create(&settings);
    JPH_BodyInterfaceRef bodies = JPH_PhysicsSystem_GetBodyInterface(system);

    JPH_JobSystemConfig jobs{};
    jobs.maxConcurrency = 1;
    JPH_JobSystemRef job_system = JPH_JobSystemThreadPool_Create(&jobs);
    JPH_Vec3 half_extent{1, 1, 1};
    JPH_ShapeRef shape = JPH_BoxShape_Create(&half_extent, 0);
    JPH_RVec3 position{0, 10, 0};
    JPH_Quat rotation{0, 0, 0, 1};
    JPH_BodyCreationSettingsRef body_settings =
        JPH_BodyCreationSettings_Create3(shape, &position, &rotation, JPH_MotionType_Dynamic, 1);
    JPH_BodyRef body = JPH_BodyInterface_CreateBody(bodies, body_settings);
    JPH_BodyID body_id = JPH_Body_GetID(body);
    JPH_BodyInterface_AddBody(bodies, body_id, JPH_ActivationMode_Activate);

    std::puts("C probe before update");
    JPH_PhysicsSystem_Update(system, 1.0f / 60.0f, 1, job_system);
    JPH_BodyInterface_GetPosition(bodies, body_id, &position);
    std::printf("C probe after update y=%f\n", position.y);

    JPH_BodyInterface_RemoveAndDestroyBody(bodies, body_id);
    JPH_BodyCreationSettings_Destroy(body_settings);
    JPH_Shape_Destroy(shape);
    JPH_JobSystem_Destroy(job_system);
    JPH_PhysicsSystem_Destroy(system);
    JPH_ObjectVsBroadPhaseLayerFilterTable_Destroy(object_vs_broad);
    JPH_ObjectLayerPairFilterTable_Destroy(pairs);
    JPH_BroadPhaseLayerInterfaceTable_Destroy(broad);
    JPH_Shutdown();
    return 0;
}
