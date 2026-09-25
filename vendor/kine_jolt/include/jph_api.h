
#pragma once

#include <cstdint>

// Export/import decoration
#if (defined(_WIN32) || defined(__CYGWIN__)) && (defined(KINE_BUILD_SHARED) || defined(JOLT_WRAPPER_BUILD_SHARED))
  #ifdef JOLT_WRAPPER_EXPORTS
    #define JPH_API __declspec(dllexport)
  #else
    #define JPH_API __declspec(dllimport)
  #endif
#elif defined(__GNUC__) && (defined(KINE_BUILD_SHARED) || defined(JOLT_WRAPPER_BUILD_SHARED))
  #define JPH_API __attribute__((visibility("default")))
#else
  #define JPH_API
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct JPH_Vec3
{
    float x;
    float y;
    float z;
} JPH_Vec3;

typedef struct JPH_RVec3
{
    double x;
    double y;
    double z;
} JPH_RVec3;

typedef struct JPH_Quat
{
    float x;
    float y;
    float z;
    float w;
} JPH_Quat;

typedef struct JPH_Triangle
{
    JPH_Vec3 v1;
    JPH_Vec3 v2;
    JPH_Vec3 v3;
    uint32_t materialIndex;
} JPH_Triangle;

typedef void* JPH_ShapeRef;
typedef void* JPH_BodyCreationSettingsRef;
typedef void* JPH_BodyRef;                 // JPH::Body*
typedef uint32_t JPH_BodyID;               // packed JPH::BodyID
typedef uint32_t JPH_ObjectLayer;
typedef uint32_t JPH_BroadPhaseLayer;
typedef void* JPH_PhysicsSystemRef;
typedef void* JPH_BodyInterfaceRef;
typedef void* JPH_JobSystemRef;
typedef void* JPH_BroadPhaseLayerInterfaceRef;
typedef void* JPH_ObjectLayerPairFilterRef;
typedef void* JPH_ObjectVsBroadPhaseLayerFilterRef;
typedef void* JPH_MotionPropertiesRef;
typedef void* JPH_ContactListenerRef;
typedef void* JPH_ConstraintRef;

#define JPH_BODY_ID_INVALID UINT32_C(0xffffffff)

typedef int32_t JPH_MotionType;
enum
{
    JPH_MotionType_Static = 0,
    JPH_MotionType_Kinematic = 1,
    JPH_MotionType_Dynamic = 2
};

typedef int32_t JPH_ActivationMode;
enum
{
    JPH_ActivationMode_Activate = 0,
    JPH_ActivationMode_DontActivate = 1
};

typedef int32_t JPH_ConstraintSpace;
enum
{
    JPH_ConstraintSpace_LocalToBodyCOM = 0,
    JPH_ConstraintSpace_WorldSpace = 1
};

typedef uint32_t JPH_SpringMode;
enum
{
    JPH_SpringMode_FrequencyAndDamping = 0,
    JPH_SpringMode_StiffnessAndDamping = 1,
    JPH_SpringMode_MassNormalizedStiffnessAndDamping = 2
};

typedef int32_t JPH_MotorState;
enum
{
    JPH_MotorState_Off = 0,
    JPH_MotorState_Velocity = 1,
    JPH_MotorState_Position = 2,
    JPH_MotorState_PositionAndVelocity = 3
};

typedef uint32_t JPH_SwingType;
enum
{
    JPH_SwingType_Cone = 0,
    JPH_SwingType_Pyramid = 1
};

typedef uint32_t JPH_SixDOFAxis;
enum
{
    JPH_SixDOFAxis_TranslationX = 0,
    JPH_SixDOFAxis_TranslationY = 1,
    JPH_SixDOFAxis_TranslationZ = 2,
    JPH_SixDOFAxis_RotationX = 3,
    JPH_SixDOFAxis_RotationY = 4,
    JPH_SixDOFAxis_RotationZ = 5,
    JPH_SixDOFAxis_Num = 6,
    JPH_SixDOFAxis_NumTranslation = 3
};

typedef int32_t JPH_RayFilterMode;
enum
{
    JPH_RayFilterMode_None = 0,
    JPH_RayFilterMode_Exclude = 1,
    JPH_RayFilterMode_Include = 2
};

typedef struct JPH_SpringSettings
{
    JPH_SpringMode mode;
    float frequencyOrStiffness;
    float damping;
} JPH_SpringSettings;

typedef struct JPH_MotorSettings
{
    JPH_SpringSettings springSettings;
    float minForceLimit;
    float maxForceLimit;
    float minTorqueLimit;
    float maxTorqueLimit;
} JPH_MotorSettings;

typedef struct JPH_ConstraintSettings
{
    uint8_t enabled;
    uint32_t priority;
    uint32_t numVelocityStepsOverride;
    uint32_t numPositionStepsOverride;
    float drawConstraintSize;
    uint64_t userData;
} JPH_ConstraintSettings;

typedef struct JPH_FixedConstraintSettings
{
    JPH_ConstraintSettings base;
    JPH_ConstraintSpace space;
    uint8_t autoDetectPoint;
    JPH_RVec3 point1;
    JPH_Vec3 axisX1;
    JPH_Vec3 axisY1;
    JPH_RVec3 point2;
    JPH_Vec3 axisX2;
    JPH_Vec3 axisY2;
} JPH_FixedConstraintSettings;

typedef struct JPH_DistanceConstraintSettings
{
    JPH_ConstraintSettings base;
    JPH_ConstraintSpace space;
    JPH_RVec3 point1;
    JPH_RVec3 point2;
    float minDistance;
    float maxDistance;
    JPH_SpringSettings limitsSpringSettings;
} JPH_DistanceConstraintSettings;

typedef struct JPH_HingeConstraintSettings
{
    JPH_ConstraintSettings base;
    JPH_ConstraintSpace space;
    JPH_RVec3 point1;
    JPH_Vec3 hingeAxis1;
    JPH_Vec3 normalAxis1;
    JPH_RVec3 point2;
    JPH_Vec3 hingeAxis2;
    JPH_Vec3 normalAxis2;
    float limitsMin;
    float limitsMax;
    JPH_SpringSettings limitsSpringSettings;
    float maxFrictionTorque;
    JPH_MotorSettings motorSettings;
} JPH_HingeConstraintSettings;

typedef struct JPH_SliderConstraintSettings
{
    JPH_ConstraintSettings base;
    JPH_ConstraintSpace space;
    uint8_t autoDetectPoint;
    JPH_RVec3 point1;
    JPH_Vec3 sliderAxis1;
    JPH_Vec3 normalAxis1;
    JPH_RVec3 point2;
    JPH_Vec3 sliderAxis2;
    JPH_Vec3 normalAxis2;
    float limitsMin;
    float limitsMax;
    JPH_SpringSettings limitsSpringSettings;
    float maxFrictionForce;
    JPH_MotorSettings motorSettings;
} JPH_SliderConstraintSettings;

typedef struct JPH_SixDOFConstraintSettings
{
    JPH_ConstraintSettings base;
    JPH_ConstraintSpace space;
    JPH_RVec3 position1;
    JPH_Vec3 axisX1;
    JPH_Vec3 axisY1;
    JPH_RVec3 position2;
    JPH_Vec3 axisX2;
    JPH_Vec3 axisY2;
    float maxFriction[6];
    JPH_SwingType swingType;
    float limitMin[6];
    float limitMax[6];
    JPH_SpringSettings limitsSpringSettings[3];
    JPH_MotorSettings motorSettings[6];
} JPH_SixDOFConstraintSettings;

typedef struct JPH_RayCastResult
{
    JPH_RVec3 position;
    JPH_Vec3 normal;
    JPH_BodyID bodyID;
    float fraction;
} JPH_RayCastResult;

typedef struct JPH_PhysicsSystemSettings
{
    uint32_t maxBodies;
    uint32_t numBodyMutexes;               // 0 = let Jolt pick a default
    uint32_t maxBodyPairs;
    uint32_t maxContactConstraints;
    uint32_t _padding;
    JPH_BroadPhaseLayerInterfaceRef broadPhaseLayerInterface;
    JPH_ObjectLayerPairFilterRef objectLayerPairFilter;
    JPH_ObjectVsBroadPhaseLayerFilterRef objectVsBroadPhaseLayerFilter;
} JPH_PhysicsSystemSettings;

typedef void (*JPH_QueueJobFunction)(void* context, void* job);
typedef void (*JPH_QueueJobsFunction)(void* context, void** jobs, uint32_t numJobs);

typedef struct JPH_JobSystemConfig
{
    void* context;
    JPH_QueueJobFunction queueJob;
    JPH_QueueJobsFunction queueJobs;
    uint32_t maxConcurrency;
    uint32_t maxBarriers;
} JPH_JobSystemConfig;

typedef struct JPH_ContactManifoldData
{
    JPH_Vec3 normal;             // world-space contact normal, body1 -> body2
    float penetrationDepth;
    uint32_t numContactPoints;   // 0..4, number of valid entries in contactPoints
    JPH_RVec3 contactPoints[4];  // world-space points on body1's surface
} JPH_ContactManifoldData;

typedef void (*JPH_ContactAddedCallback)(
    JPH_BodyID body1,
    JPH_BodyID body2,
    const JPH_ContactManifoldData* manifold
);

typedef void (*JPH_ContactPersistedCallback)(
    JPH_BodyID body1,
    JPH_BodyID body2,
    const JPH_ContactManifoldData* manifold
);

typedef void (*JPH_ContactRemovedCallback)(
    JPH_BodyID body1,
    JPH_BodyID body2,
    uint32_t subShapeID1,
    uint32_t subShapeID2
);

typedef struct JPH_ContactListener_Procs
{
    JPH_ContactAddedCallback OnContactAdded;
    JPH_ContactPersistedCallback OnContactPersisted;
    JPH_ContactRemovedCallback OnContactRemoved;
} JPH_ContactListener_Procs;

// Returns 1 on success, 0 on failure (already initialized counts as failure).
JPH_API int32_t JPH_Init(void);
JPH_API void JPH_Shutdown(void);

JPH_API JPH_JobSystemRef JPH_JobSystemThreadPool_Create(const JPH_JobSystemConfig* config);
JPH_API void JPH_JobSystem_Destroy(JPH_JobSystemRef jobSystem);

JPH_API JPH_BroadPhaseLayerInterfaceRef JPH_BroadPhaseLayerInterfaceTable_Create(
    uint32_t numObjectLayers,
    uint32_t numBroadPhaseLayers
);
JPH_API void JPH_BroadPhaseLayerInterfaceTable_Destroy(JPH_BroadPhaseLayerInterfaceRef bpInterface);

JPH_API void JPH_BroadPhaseLayerInterfaceTable_MapObjectToBroadPhaseLayer(
    JPH_BroadPhaseLayerInterfaceRef bpInterface,
    JPH_ObjectLayer objectLayer,
    JPH_BroadPhaseLayer broadPhaseLayer
);

JPH_API JPH_ObjectLayerPairFilterRef JPH_ObjectLayerPairFilterTable_Create(uint32_t numObjectLayers);
JPH_API void JPH_ObjectLayerPairFilterTable_Destroy(JPH_ObjectLayerPairFilterRef filter);

JPH_API void JPH_ObjectLayerPairFilterTable_EnableCollision(
    JPH_ObjectLayerPairFilterRef filter,
    JPH_ObjectLayer layer1,
    JPH_ObjectLayer layer2
);

JPH_API void JPH_ObjectLayerPairFilterTable_DisableCollision(
    JPH_ObjectLayerPairFilterRef filter,
    JPH_ObjectLayer layer1,
    JPH_ObjectLayer layer2
);

JPH_API int32_t JPH_ObjectLayerPairFilterTable_ShouldCollide(
    JPH_ObjectLayerPairFilterRef filter,
    JPH_ObjectLayer layer1,
    JPH_ObjectLayer layer2
);

JPH_API JPH_ObjectVsBroadPhaseLayerFilterRef JPH_ObjectVsBroadPhaseLayerFilterTable_Create(
    JPH_BroadPhaseLayerInterfaceRef bpInterface,
    uint32_t numBroadPhaseLayers,
    JPH_ObjectLayerPairFilterRef objectLayerPairFilter,
    uint32_t numObjectLayers
);
JPH_API void JPH_ObjectVsBroadPhaseLayerFilterTable_Destroy(JPH_ObjectVsBroadPhaseLayerFilterRef filter);
JPH_API int32_t JPH_ObjectVsBroadPhaseLayerFilterTable_ShouldCollide(
    JPH_ObjectVsBroadPhaseLayerFilterRef filter,
    JPH_ObjectLayer objectLayer,
    JPH_BroadPhaseLayer broadPhaseLayer
);

JPH_API JPH_ShapeRef JPH_BoxShape_Create(const JPH_Vec3* halfExtent, float convexRadius);
JPH_API JPH_ShapeRef JPH_SphereShape_Create(float radius);
JPH_API JPH_ShapeRef JPH_CylinderShape_Create(float halfHeight, float radius, float convexRadius);
JPH_API JPH_ShapeRef JPH_ConvexHullShape_Create(
    const JPH_Vec3* points,
    uint32_t pointCount,
    float maxConvexRadius
);
JPH_API JPH_ShapeRef JPH_MeshShape_Create(const JPH_Triangle* triangles, uint32_t triangleCount);
// Decomposes a triangle mesh (V-HACD) into a compound of convex hulls.
// Triangles is the index array; triangleCount is the number of index values
// (must be a multiple of 3). Hull vertices are scaled by `scale` (mesh is in
// unit space).
JPH_API JPH_ShapeRef JPH_VHACD_Compound_Create(
    const JPH_Vec3* points,
    uint32_t pointCount,
    const uint32_t* triangles,
    uint32_t triangleCount,
    const JPH_Vec3* scale
);
JPH_API void JPH_Shape_AddRef(JPH_ShapeRef shape);
JPH_API void JPH_Shape_Destroy(JPH_ShapeRef shape);

JPH_API JPH_BodyCreationSettingsRef JPH_BodyCreationSettings_Create3(
    JPH_ShapeRef shape,
    const JPH_RVec3* position,
    const JPH_Quat* rotation,
    JPH_MotionType motionType,
    JPH_ObjectLayer objectLayer
);

JPH_API void JPH_BodyCreationSettings_Destroy(JPH_BodyCreationSettingsRef settings);

JPH_API void JPH_BodyCreationSettings_SetAllowSleeping(JPH_BodyCreationSettingsRef settings, int32_t allow);
JPH_API void JPH_BodyCreationSettings_SetAllowDynamicOrKinematic(JPH_BodyCreationSettingsRef settings, int32_t allow);
JPH_API void JPH_BodyCreationSettings_SetFriction(JPH_BodyCreationSettingsRef settings, float friction);
JPH_API void JPH_BodyCreationSettings_SetRestitution(JPH_BodyCreationSettingsRef settings, float restitution);
JPH_API void JPH_BodyCreationSettings_SetLinearDamping(JPH_BodyCreationSettingsRef settings, float damping);
JPH_API void JPH_BodyCreationSettings_SetAngularDamping(JPH_BodyCreationSettingsRef settings, float damping);
JPH_API void JPH_BodyCreationSettings_SetGravityFactor(JPH_BodyCreationSettingsRef settings, float factor);

JPH_API JPH_PhysicsSystemRef JPH_PhysicsSystem_Create(const JPH_PhysicsSystemSettings* settings);
JPH_API void JPH_PhysicsSystem_Destroy(JPH_PhysicsSystemRef system);
JPH_API JPH_BodyInterfaceRef JPH_PhysicsSystem_GetBodyInterface(JPH_PhysicsSystemRef system);
JPH_API void JPH_PhysicsSystem_SetGravity(JPH_PhysicsSystemRef system, const JPH_Vec3* gravity);
JPH_API void JPH_PhysicsSystem_Update(
    JPH_PhysicsSystemRef system,
    float deltaTime,
    int32_t collisionSteps,
    JPH_JobSystemRef jobSystem
);
JPH_API void JPH_PhysicsSystem_UpdateSingleThreaded(
    JPH_PhysicsSystemRef system,
    float deltaTime,
    int32_t collisionSteps
);
JPH_API void JPH_PhysicsSystem_OptimizeBroadPhase(JPH_PhysicsSystemRef system);
JPH_API void JPH_PhysicsSystem_SetContactListener(JPH_PhysicsSystemRef system, JPH_ContactListenerRef listener);

// Capsule aligned with the Y axis. halfHeight = half the straight cylinder section,
// radius = capsule radius. convexRadius is ignored (Jolt 5.x capsules have no
// separate convex radius) and kept only for API symmetry.
JPH_API JPH_ShapeRef JPH_CapsuleShape_Create(float halfHeight, float radius, float convexRadius);

// Sweeps `shape` (identity rotation) from `origin` along `displacement` (the total
// move for this sweep, not a normalized direction), bounded by maxDistance.
// bodyIDs/filterMode behave exactly like JPH_PhysicsSystem_CastRay (0 = no filter,
// 1 = exclude bodyIDs, 2 = include bodyIDs). Returns 1 on hit with the closest
// fraction in outResult.
JPH_API int32_t JPH_PhysicsSystem_CastShape(
    JPH_PhysicsSystemRef system,
    const JPH_RVec3* origin,
    const JPH_Vec3* displacement,
    JPH_ShapeRef shape,
    const JPH_BodyID* bodyIDs,
    uint32_t bodyIDCount,
    JPH_RayFilterMode filterMode,
    float maxDistance,
    JPH_RayCastResult* outResult
);

JPH_API void JPH_PhysicsSystem_AddConstraint(JPH_PhysicsSystemRef system, JPH_ConstraintRef constraint);
JPH_API void JPH_PhysicsSystem_RemoveConstraint(JPH_PhysicsSystemRef system, JPH_ConstraintRef constraint);

JPH_API void JPH_FixedConstraintSettings_Init(JPH_FixedConstraintSettings* settings);
JPH_API JPH_ConstraintRef JPH_FixedConstraint_Create(
    const JPH_FixedConstraintSettings* settings, JPH_BodyRef body1, JPH_BodyRef body2);

JPH_API void JPH_DistanceConstraintSettings_Init(JPH_DistanceConstraintSettings* settings);
JPH_API JPH_ConstraintRef JPH_DistanceConstraint_Create(
    const JPH_DistanceConstraintSettings* settings, JPH_BodyRef body1, JPH_BodyRef body2);
JPH_API void JPH_DistanceConstraint_SetDistance(JPH_ConstraintRef constraint, float minDistance, float maxDistance);
JPH_API void JPH_DistanceConstraint_SetLimitsSpringSettings(
    JPH_ConstraintRef constraint, const JPH_SpringSettings* settings);

JPH_API void JPH_HingeConstraintSettings_Init(JPH_HingeConstraintSettings* settings);
JPH_API JPH_ConstraintRef JPH_HingeConstraint_Create(
    const JPH_HingeConstraintSettings* settings, JPH_BodyRef body1, JPH_BodyRef body2);
JPH_API void JPH_HingeConstraint_SetMotorState(JPH_ConstraintRef constraint, JPH_MotorState state);
JPH_API void JPH_HingeConstraint_SetTargetAngularVelocity(JPH_ConstraintRef constraint, float velocity);
JPH_API void JPH_HingeConstraint_SetTargetAngle(JPH_ConstraintRef constraint, float angle);
JPH_API float JPH_HingeConstraint_GetCurrentAngle(JPH_ConstraintRef constraint);
JPH_API void JPH_HingeConstraint_SetLimits(JPH_ConstraintRef constraint, float minAngle, float maxAngle);
JPH_API void JPH_HingeConstraint_SetMotorSettings(
    JPH_ConstraintRef constraint, const JPH_MotorSettings* settings);

JPH_API void JPH_SliderConstraintSettings_Init(JPH_SliderConstraintSettings* settings);
JPH_API JPH_ConstraintRef JPH_SliderConstraint_Create(
    const JPH_SliderConstraintSettings* settings, JPH_BodyRef body1, JPH_BodyRef body2);
JPH_API void JPH_SliderConstraint_SetLimits(JPH_ConstraintRef constraint, float minDistance, float maxDistance);
JPH_API void JPH_SliderConstraint_SetMotorSettings(
    JPH_ConstraintRef constraint, const JPH_MotorSettings* settings);
JPH_API void JPH_SliderConstraint_SetMotorState(JPH_ConstraintRef constraint, JPH_MotorState state);
JPH_API void JPH_SliderConstraint_SetTargetVelocity(JPH_ConstraintRef constraint, float velocity);
JPH_API void JPH_SliderConstraint_SetTargetPosition(JPH_ConstraintRef constraint, float position);
JPH_API float JPH_SliderConstraint_GetCurrentPosition(JPH_ConstraintRef constraint);

JPH_API void JPH_SixDOFConstraintSettings_Init(JPH_SixDOFConstraintSettings* settings);
JPH_API void JPH_SixDOFConstraintSettings_MakeFixedAxis(JPH_SixDOFConstraintSettings* settings, JPH_SixDOFAxis axis);
JPH_API void JPH_SixDOFConstraintSettings_MakeFreeAxis(JPH_SixDOFConstraintSettings* settings, JPH_SixDOFAxis axis);
JPH_API void JPH_SixDOFConstraintSettings_SetLimitedAxis(
    JPH_SixDOFConstraintSettings* settings, JPH_SixDOFAxis axis, float minValue, float maxValue);
JPH_API void JPH_SixDOFConstraintSettings_SetLimitsSpringSettings(
    JPH_SixDOFConstraintSettings* settings, JPH_SixDOFAxis axis, const JPH_SpringSettings* spring);
JPH_API JPH_ConstraintRef JPH_SixDOFConstraint_Create(
    const JPH_SixDOFConstraintSettings* settings, JPH_BodyRef body1, JPH_BodyRef body2);

// Casts a finite ray where direction is the full displacement of the ray.
// filterMode: 0 = no body filter, 1 = exclude bodyIDs, 2 = include bodyIDs.
JPH_API int32_t JPH_PhysicsSystem_CastRay(
    JPH_PhysicsSystemRef system,
    const JPH_RVec3* origin,
    const JPH_Vec3* direction,
    const JPH_BodyID* bodyIDs,
    uint32_t bodyIDCount,
    JPH_RayFilterMode filterMode,
    JPH_RayCastResult* outResult
);

JPH_API JPH_BodyRef JPH_BodyInterface_CreateBody(JPH_BodyInterfaceRef bodyInterface, JPH_BodyCreationSettingsRef settings);
JPH_API void JPH_BodyInterface_AddBody(JPH_BodyInterfaceRef bodyInterface, JPH_BodyID bodyID, JPH_ActivationMode activationMode);
JPH_API void JPH_BodyInterface_DestroyBody(JPH_BodyInterfaceRef bodyInterface, JPH_BodyRef body);
JPH_API void JPH_BodyInterface_RemoveAndDestroyBody(JPH_BodyInterfaceRef bodyInterface, JPH_BodyID bodyID);

JPH_API void JPH_BodyInterface_SetShape(
    JPH_BodyInterfaceRef bodyInterface,
    JPH_BodyID bodyID,
    JPH_ShapeRef shape,
    int32_t updateMassProperties,
    JPH_ActivationMode activationMode
);

JPH_API void JPH_BodyInterface_SetMotionType(
    JPH_BodyInterfaceRef bodyInterface,
    JPH_BodyID bodyID,
    JPH_MotionType motionType,
    JPH_ActivationMode activationMode
);

JPH_API void JPH_BodyInterface_SetObjectLayer(JPH_BodyInterfaceRef bodyInterface, JPH_BodyID bodyID, JPH_ObjectLayer layer);

JPH_API void JPH_BodyInterface_ActivateBody(JPH_BodyInterfaceRef bodyInterface, JPH_BodyID bodyID);
JPH_API int32_t JPH_BodyInterface_IsActive(JPH_BodyInterfaceRef bodyInterface, JPH_BodyID bodyID);
JPH_API int32_t JPH_BodyInterface_IsAdded(JPH_BodyInterfaceRef bodyInterface, JPH_BodyID bodyID);

JPH_API void JPH_BodyInterface_SetPosition(
    JPH_BodyInterfaceRef bodyInterface,
    JPH_BodyID bodyID,
    const JPH_RVec3* position,
    JPH_ActivationMode activationMode
);

JPH_API void JPH_BodyInterface_SetPositionAndRotation(
    JPH_BodyInterfaceRef bodyInterface,
    JPH_BodyID bodyID,
    const JPH_RVec3* position,
    const JPH_Quat* rotation,
    JPH_ActivationMode activationMode
);

JPH_API void JPH_BodyInterface_SetRotation(
    JPH_BodyInterfaceRef bodyInterface,
    JPH_BodyID bodyID,
    const JPH_Quat* rotation,
    JPH_ActivationMode activationMode
);

JPH_API void JPH_BodyInterface_SetLinearVelocity(JPH_BodyInterfaceRef bodyInterface, JPH_BodyID bodyID, const JPH_Vec3* velocity);
JPH_API void JPH_BodyInterface_SetAngularVelocity(JPH_BodyInterfaceRef bodyInterface, JPH_BodyID bodyID, const JPH_Vec3* velocity);

JPH_API void JPH_BodyInterface_GetPosition(JPH_BodyInterfaceRef bodyInterface, JPH_BodyID bodyID, JPH_RVec3* outPosition);

JPH_API void JPH_BodyInterface_GetPositionAndRotation(
    JPH_BodyInterfaceRef bodyInterface,
    JPH_BodyID bodyID,
    JPH_RVec3* outPosition,
    JPH_Quat* outRotation
);

JPH_API void JPH_BodyInterface_GetRotation(JPH_BodyInterfaceRef bodyInterface, JPH_BodyID bodyID, JPH_Quat* outRotation);
JPH_API void JPH_BodyInterface_GetLinearVelocity(JPH_BodyInterfaceRef bodyInterface, JPH_BodyID bodyID, JPH_Vec3* outVelocity);
JPH_API void JPH_BodyInterface_GetAngularVelocity(JPH_BodyInterfaceRef bodyInterface, JPH_BodyID bodyID, JPH_Vec3* outVelocity);

JPH_API void JPH_BodyInterface_AddImpulse(JPH_BodyInterfaceRef bodyInterface, JPH_BodyID bodyID, const JPH_Vec3* impulse);
JPH_API void JPH_BodyInterface_AddForce(JPH_BodyInterfaceRef bodyInterface, JPH_BodyID bodyID, const JPH_Vec3* force);

JPH_API void JPH_BodyInterface_AddForce2(
    JPH_BodyInterfaceRef bodyInterface,
    JPH_BodyID bodyID,
    const JPH_Vec3* force,
    const JPH_RVec3* position
);

JPH_API void JPH_BodyInterface_AddTorque(JPH_BodyInterfaceRef bodyInterface, JPH_BodyID bodyID, const JPH_Vec3* torque);

JPH_API JPH_BodyID JPH_Body_GetID(JPH_BodyRef body);
JPH_API JPH_MotionPropertiesRef JPH_Body_GetMotionProperties(JPH_BodyRef body);
JPH_API void JPH_Body_SetFriction(JPH_BodyRef body, float friction);

JPH_API void JPH_MotionProperties_ScaleToMass(JPH_MotionPropertiesRef motionProperties, float mass);

JPH_API JPH_ContactListenerRef JPH_ContactListener_Create(void);
JPH_API void JPH_ContactListener_Destroy(JPH_ContactListenerRef listener);
JPH_API uint32_t JPH_ContactListener_PollEvents(
    JPH_ContactListenerRef listener,
    const JPH_ContactListener_Procs* procs,
    uint32_t maxEvents
);

#ifdef __cplusplus
}
#endif
