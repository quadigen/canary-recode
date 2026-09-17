package kineffi

when ODIN_OS == .JS {
	foreign import lib "../../../build/web-native/lib/kine_jolt_web.o"
} else when ODIN_OS == .Windows {
	foreign import lib {
		"../../../vendor/build/lib/kine_jolt.lib",
		"../../../vendor/build/lib/kine_jolt_core.lib",
	}
} else when #config(KINE_ANDROID, false) {
	foreign import lib "../../../build/android-native/lib/libJoltWrapper.a"
} else {
	foreign import lib "../../../vendor/build/lib/KinemiumLibs.a"
}

JPH_Vec3 :: struct {
	x: f32,
	y: f32,
	z: f32,
}

JPH_RVec3 :: struct {
	x: f64,
	y: f64,
	z: f64,
}

JPH_Quat :: struct {
	x: f32,
	y: f32,
	z: f32,
	w: f32,
}

JPH_Triangle :: struct {
	v1:            JPH_Vec3,
	v2:            JPH_Vec3,
	v3:            JPH_Vec3,
	materialIndex: u32,
}

JPH_ShapeRef                         :: rawptr
JPH_BodyCreationSettingsRef          :: rawptr
JPH_BodyRef                          :: rawptr // JPH::Body*
JPH_BodyID                           :: u32    // packed JPH::BodyID
JPH_ObjectLayer                      :: u32
JPH_BroadPhaseLayer                  :: u32
JPH_PhysicsSystemRef                 :: rawptr
JPH_BodyInterfaceRef                 :: rawptr
JPH_JobSystemRef                     :: rawptr
JPH_BroadPhaseLayerInterfaceRef      :: rawptr
JPH_ObjectLayerPairFilterRef         :: rawptr
JPH_ObjectVsBroadPhaseLayerFilterRef :: rawptr
JPH_MotionPropertiesRef              :: rawptr
JPH_ContactListenerRef               :: rawptr
JPH_ConstraintRef                    :: rawptr

JPH_BODY_ID_INVALID :: JPH_BodyID(0xffffffff)

JPH_MotionType :: enum i32 {
	Static = 0,
	Kinematic = 1,
	Dynamic = 2,
}

JPH_ActivationMode :: enum i32 {
	Activate = 0,
	DontActivate = 1,
}

JPH_ConstraintSpace :: enum i32 {
	LocalToBodyCOM = 0,
	WorldSpace = 1,
}

JPH_SpringMode :: enum u32 {
	FrequencyAndDamping = 0,
	StiffnessAndDamping = 1,
	MassNormalizedStiffnessAndDamping = 2,
}

JPH_MotorState :: enum i32 {
	Off = 0,
	Velocity = 1,
	Position = 2,
	PositionAndVelocity = 3,
}

JPH_SwingType :: enum u32 {
	Cone = 0,
	Pyramid = 1,
}

JPH_SixDOFAxis :: enum u32 {
	TranslationX = 0,
	TranslationY = 1,
	TranslationZ = 2,
	RotationX = 3,
	RotationY = 4,
	RotationZ = 5,
}

JPH_SIX_DOF_AXIS_COUNT             :: u32(6)
JPH_SIX_DOF_TRANSLATION_AXIS_COUNT :: u32(3)

JPH_RayFilterMode :: enum i32 {
	None = 0,
	Exclude = 1,
	Include = 2,
}

JPH_SpringSettings :: struct {
	mode:                 JPH_SpringMode,
	frequencyOrStiffness: f32,
	damping:              f32,
}

JPH_MotorSettings :: struct {
	springSettings: JPH_SpringSettings,
	minForceLimit:  f32,
	maxForceLimit:  f32,
	minTorqueLimit: f32,
	maxTorqueLimit: f32,
}

JPH_ConstraintSettings :: struct {
	enabled:                  u8,
	priority:                 u32,
	numVelocityStepsOverride: u32,
	numPositionStepsOverride: u32,
	drawConstraintSize:       f32,
	userData:                 u64,
}

JPH_FixedConstraintSettings :: struct {
	base:            JPH_ConstraintSettings,
	space:           JPH_ConstraintSpace,
	autoDetectPoint: u8,
	point1:          JPH_RVec3,
	axisX1:          JPH_Vec3,
	axisY1:          JPH_Vec3,
	point2:          JPH_RVec3,
	axisX2:          JPH_Vec3,
	axisY2:          JPH_Vec3,
}

JPH_DistanceConstraintSettings :: struct {
	base:                 JPH_ConstraintSettings,
	space:                JPH_ConstraintSpace,
	point1:               JPH_RVec3,
	point2:               JPH_RVec3,
	minDistance:          f32,
	maxDistance:          f32,
	limitsSpringSettings: JPH_SpringSettings,
}

JPH_HingeConstraintSettings :: struct {
	base:                 JPH_ConstraintSettings,
	space:                JPH_ConstraintSpace,
	point1:               JPH_RVec3,
	hingeAxis1:           JPH_Vec3,
	normalAxis1:          JPH_Vec3,
	point2:               JPH_RVec3,
	hingeAxis2:           JPH_Vec3,
	normalAxis2:          JPH_Vec3,
	limitsMin:            f32,
	limitsMax:            f32,
	limitsSpringSettings: JPH_SpringSettings,
	maxFrictionTorque:    f32,
	motorSettings:        JPH_MotorSettings,
}

JPH_SliderConstraintSettings :: struct {
	base:                 JPH_ConstraintSettings,
	space:                JPH_ConstraintSpace,
	autoDetectPoint:      u8,
	point1:               JPH_RVec3,
	sliderAxis1:          JPH_Vec3,
	normalAxis1:          JPH_Vec3,
	point2:               JPH_RVec3,
	sliderAxis2:          JPH_Vec3,
	normalAxis2:          JPH_Vec3,
	limitsMin:            f32,
	limitsMax:            f32,
	limitsSpringSettings: JPH_SpringSettings,
	maxFrictionForce:     f32,
	motorSettings:        JPH_MotorSettings,
}

JPH_SixDOFConstraintSettings :: struct {
	base:                 JPH_ConstraintSettings,
	space:                JPH_ConstraintSpace,
	position1:            JPH_RVec3,
	axisX1:               JPH_Vec3,
	axisY1:               JPH_Vec3,
	position2:            JPH_RVec3,
	axisX2:               JPH_Vec3,
	axisY2:               JPH_Vec3,
	maxFriction:          [6]f32,
	swingType:            JPH_SwingType,
	limitMin:             [6]f32,
	limitMax:             [6]f32,
	limitsSpringSettings: [3]JPH_SpringSettings,
	motorSettings:        [6]JPH_MotorSettings,
}

JPH_RayCastResult :: struct {
	position: JPH_RVec3,
	normal:   JPH_Vec3,
	bodyID:   JPH_BodyID,
	fraction: f32,
}

JPH_PhysicsSystemSettings :: struct {
	maxBodies:                     u32,
	numBodyMutexes:                u32, // 0 = let Jolt pick a default
	maxBodyPairs:                  u32,
	maxContactConstraints:         u32,
	_padding:                      u32,
	broadPhaseLayerInterface:      JPH_BroadPhaseLayerInterfaceRef,
	objectLayerPairFilter:         JPH_ObjectLayerPairFilterRef,
	objectVsBroadPhaseLayerFilter: JPH_ObjectVsBroadPhaseLayerFilterRef,
}

JPH_QueueJobFunction  :: proc "c" (_context: rawptr, job: rawptr)
JPH_QueueJobsFunction :: proc "c" (_context: rawptr, jobs: ^rawptr, numJobs: u32)

JPH_JobSystemConfig :: struct {
	_context:       rawptr,
	queueJob:       JPH_QueueJobFunction,
	queueJobs:      JPH_QueueJobsFunction,
	maxConcurrency: u32,
	maxBarriers:    u32,
}

JPH_ContactManifoldData :: struct {
	normal:           JPH_Vec3,     // world-space contact normal, body1 -> body2
	penetrationDepth: f32,
	numContactPoints: u32,          // 0..4, number of valid entries in contactPoints
	contactPoints:    [4]JPH_RVec3, // world-space points on body1's surface
}

JPH_ContactAddedCallback     :: proc "c" (body1: JPH_BodyID, body2: JPH_BodyID, manifold: ^JPH_ContactManifoldData)
JPH_ContactPersistedCallback :: proc "c" (body1: JPH_BodyID, body2: JPH_BodyID, manifold: ^JPH_ContactManifoldData)
JPH_ContactRemovedCallback   :: proc "c" (body1: JPH_BodyID, body2: JPH_BodyID, subShapeID1: u32, subShapeID2: u32)

JPH_ContactListener_Procs :: struct {
	OnContactAdded:     JPH_ContactAddedCallback,
	OnContactPersisted: JPH_ContactPersistedCallback,
	OnContactRemoved:   JPH_ContactRemovedCallback,
}

@(default_calling_convention="c")
foreign lib {
	// Returns 1 on success, 0 on failure (already initialized counts as failure).
	JPH_Init                                                     :: proc() -> i32 ---
	JPH_Shutdown                                                 :: proc() ---
	JPH_JobSystemThreadPool_Create                               :: proc(config: ^JPH_JobSystemConfig) -> JPH_JobSystemRef ---
	JPH_JobSystem_Destroy                                        :: proc(jobSystem: JPH_JobSystemRef) ---
	JPH_BroadPhaseLayerInterfaceTable_Create                     :: proc(numObjectLayers: u32, numBroadPhaseLayers: u32) -> JPH_BroadPhaseLayerInterfaceRef ---
	JPH_BroadPhaseLayerInterfaceTable_Destroy                    :: proc(bpInterface: JPH_BroadPhaseLayerInterfaceRef) ---
	JPH_BroadPhaseLayerInterfaceTable_MapObjectToBroadPhaseLayer :: proc(bpInterface: JPH_BroadPhaseLayerInterfaceRef, objectLayer: JPH_ObjectLayer, broadPhaseLayer: JPH_BroadPhaseLayer) ---
	JPH_ObjectLayerPairFilterTable_Create                        :: proc(numObjectLayers: u32) -> JPH_ObjectLayerPairFilterRef ---
	JPH_ObjectLayerPairFilterTable_Destroy                       :: proc(filter: JPH_ObjectLayerPairFilterRef) ---
	JPH_ObjectLayerPairFilterTable_EnableCollision               :: proc(filter: JPH_ObjectLayerPairFilterRef, layer1: JPH_ObjectLayer, layer2: JPH_ObjectLayer) ---
	JPH_ObjectLayerPairFilterTable_DisableCollision              :: proc(filter: JPH_ObjectLayerPairFilterRef, layer1: JPH_ObjectLayer, layer2: JPH_ObjectLayer) ---
	JPH_ObjectLayerPairFilterTable_ShouldCollide                 :: proc(filter: JPH_ObjectLayerPairFilterRef, layer1: JPH_ObjectLayer, layer2: JPH_ObjectLayer) -> i32 ---
	JPH_ObjectVsBroadPhaseLayerFilterTable_Create                :: proc(bpInterface: JPH_BroadPhaseLayerInterfaceRef, numBroadPhaseLayers: u32, objectLayerPairFilter: JPH_ObjectLayerPairFilterRef, numObjectLayers: u32) -> JPH_ObjectVsBroadPhaseLayerFilterRef ---
	JPH_ObjectVsBroadPhaseLayerFilterTable_Destroy               :: proc(filter: JPH_ObjectVsBroadPhaseLayerFilterRef) ---
	JPH_ObjectVsBroadPhaseLayerFilterTable_ShouldCollide         :: proc(filter: JPH_ObjectVsBroadPhaseLayerFilterRef, objectLayer: JPH_ObjectLayer, broadPhaseLayer: JPH_BroadPhaseLayer) -> i32 ---
	JPH_BoxShape_Create                                          :: proc(halfExtent: ^JPH_Vec3, convexRadius: f32) -> JPH_ShapeRef ---
	JPH_SphereShape_Create                                       :: proc(radius: f32) -> JPH_ShapeRef ---
	JPH_CylinderShape_Create                                     :: proc(halfHeight: f32, radius: f32, convexRadius: f32) -> JPH_ShapeRef ---
	JPH_ConvexHullShape_Create                                   :: proc(points: ^JPH_Vec3, pointCount: u32, maxConvexRadius: f32) -> JPH_ShapeRef ---
	JPH_MeshShape_Create                                         :: proc(triangles: ^JPH_Triangle, triangleCount: u32) -> JPH_ShapeRef ---
	JPH_Shape_Destroy                                            :: proc(shape: JPH_ShapeRef) ---
	JPH_BodyCreationSettings_Create3                             :: proc(shape: JPH_ShapeRef, position: ^JPH_RVec3, rotation: ^JPH_Quat, motionType: JPH_MotionType, objectLayer: JPH_ObjectLayer) -> JPH_BodyCreationSettingsRef ---
	JPH_BodyCreationSettings_Destroy                             :: proc(settings: JPH_BodyCreationSettingsRef) ---
	JPH_BodyCreationSettings_SetAllowSleeping                    :: proc(settings: JPH_BodyCreationSettingsRef, allow: i32) ---
	JPH_BodyCreationSettings_SetAllowDynamicOrKinematic          :: proc(settings: JPH_BodyCreationSettingsRef, allow: i32) ---
	JPH_BodyCreationSettings_SetFriction                         :: proc(settings: JPH_BodyCreationSettingsRef, friction: f32) ---
	JPH_BodyCreationSettings_SetRestitution                      :: proc(settings: JPH_BodyCreationSettingsRef, restitution: f32) ---
	JPH_BodyCreationSettings_SetLinearDamping                    :: proc(settings: JPH_BodyCreationSettingsRef, damping: f32) ---
	JPH_BodyCreationSettings_SetAngularDamping                   :: proc(settings: JPH_BodyCreationSettingsRef, damping: f32) ---
	JPH_BodyCreationSettings_SetGravityFactor                    :: proc(settings: JPH_BodyCreationSettingsRef, factor: f32) ---
	JPH_PhysicsSystem_Create                                     :: proc(settings: ^JPH_PhysicsSystemSettings) -> JPH_PhysicsSystemRef ---
	JPH_PhysicsSystem_Destroy                                    :: proc(system: JPH_PhysicsSystemRef) ---
	JPH_PhysicsSystem_GetBodyInterface                           :: proc(system: JPH_PhysicsSystemRef) -> JPH_BodyInterfaceRef ---
	JPH_PhysicsSystem_SetGravity                                 :: proc(system: JPH_PhysicsSystemRef, gravity: ^JPH_Vec3) ---
	JPH_PhysicsSystem_Update                                     :: proc(system: JPH_PhysicsSystemRef, deltaTime: f32, collisionSteps: i32, jobSystem: JPH_JobSystemRef) ---
	JPH_PhysicsSystem_UpdateSingleThreaded                       :: proc(system: JPH_PhysicsSystemRef, deltaTime: f32, collisionSteps: i32) ---
	JPH_PhysicsSystem_OptimizeBroadPhase                         :: proc(system: JPH_PhysicsSystemRef) ---
	JPH_PhysicsSystem_SetContactListener                         :: proc(system: JPH_PhysicsSystemRef, listener: JPH_ContactListenerRef) ---
	JPH_PhysicsSystem_AddConstraint                              :: proc(system: JPH_PhysicsSystemRef, constraint: JPH_ConstraintRef) ---
	JPH_PhysicsSystem_RemoveConstraint                           :: proc(system: JPH_PhysicsSystemRef, constraint: JPH_ConstraintRef) ---
	JPH_FixedConstraintSettings_Init                             :: proc(settings: ^JPH_FixedConstraintSettings) ---
	JPH_FixedConstraint_Create                                   :: proc(settings: ^JPH_FixedConstraintSettings, body1: JPH_BodyRef, body2: JPH_BodyRef) -> JPH_ConstraintRef ---
	JPH_DistanceConstraintSettings_Init                          :: proc(settings: ^JPH_DistanceConstraintSettings) ---
	JPH_DistanceConstraint_Create                                :: proc(settings: ^JPH_DistanceConstraintSettings, body1: JPH_BodyRef, body2: JPH_BodyRef) -> JPH_ConstraintRef ---
	JPH_DistanceConstraint_SetDistance                           :: proc(constraint: JPH_ConstraintRef, minDistance: f32, maxDistance: f32) ---
	JPH_DistanceConstraint_SetLimitsSpringSettings               :: proc(constraint: JPH_ConstraintRef, settings: ^JPH_SpringSettings) ---
	JPH_HingeConstraintSettings_Init                             :: proc(settings: ^JPH_HingeConstraintSettings) ---
	JPH_HingeConstraint_Create                                   :: proc(settings: ^JPH_HingeConstraintSettings, body1: JPH_BodyRef, body2: JPH_BodyRef) -> JPH_ConstraintRef ---
	JPH_HingeConstraint_SetMotorState                            :: proc(constraint: JPH_ConstraintRef, state: JPH_MotorState) ---
	JPH_HingeConstraint_SetTargetAngularVelocity                 :: proc(constraint: JPH_ConstraintRef, velocity: f32) ---
	JPH_HingeConstraint_SetTargetAngle                           :: proc(constraint: JPH_ConstraintRef, angle: f32) ---
	JPH_HingeConstraint_GetCurrentAngle                          :: proc(constraint: JPH_ConstraintRef) -> f32 ---
	JPH_HingeConstraint_SetLimits                                :: proc(constraint: JPH_ConstraintRef, minAngle: f32, maxAngle: f32) ---
	JPH_HingeConstraint_SetMotorSettings                         :: proc(constraint: JPH_ConstraintRef, settings: ^JPH_MotorSettings) ---
	JPH_SliderConstraintSettings_Init                            :: proc(settings: ^JPH_SliderConstraintSettings) ---
	JPH_SliderConstraint_Create                                  :: proc(settings: ^JPH_SliderConstraintSettings, body1: JPH_BodyRef, body2: JPH_BodyRef) -> JPH_ConstraintRef ---
	JPH_SliderConstraint_SetLimits                               :: proc(constraint: JPH_ConstraintRef, minDistance: f32, maxDistance: f32) ---
	JPH_SliderConstraint_SetMotorSettings                        :: proc(constraint: JPH_ConstraintRef, settings: ^JPH_MotorSettings) ---
	JPH_SliderConstraint_SetMotorState                           :: proc(constraint: JPH_ConstraintRef, state: JPH_MotorState) ---
	JPH_SliderConstraint_SetTargetVelocity                       :: proc(constraint: JPH_ConstraintRef, velocity: f32) ---
	JPH_SliderConstraint_SetTargetPosition                       :: proc(constraint: JPH_ConstraintRef, position: f32) ---
	JPH_SliderConstraint_GetCurrentPosition                      :: proc(constraint: JPH_ConstraintRef) -> f32 ---
	JPH_SixDOFConstraintSettings_Init                            :: proc(settings: ^JPH_SixDOFConstraintSettings) ---
	JPH_SixDOFConstraintSettings_MakeFixedAxis                   :: proc(settings: ^JPH_SixDOFConstraintSettings, axis: JPH_SixDOFAxis) ---
	JPH_SixDOFConstraintSettings_MakeFreeAxis                    :: proc(settings: ^JPH_SixDOFConstraintSettings, axis: JPH_SixDOFAxis) ---
	JPH_SixDOFConstraintSettings_SetLimitedAxis                  :: proc(settings: ^JPH_SixDOFConstraintSettings, axis: JPH_SixDOFAxis, minValue: f32, maxValue: f32) ---
	JPH_SixDOFConstraintSettings_SetLimitsSpringSettings         :: proc(settings: ^JPH_SixDOFConstraintSettings, axis: JPH_SixDOFAxis, spring: ^JPH_SpringSettings) ---
	JPH_SixDOFConstraint_Create                                  :: proc(settings: ^JPH_SixDOFConstraintSettings, body1: JPH_BodyRef, body2: JPH_BodyRef) -> JPH_ConstraintRef ---

	// Casts a finite ray where direction is the full displacement of the ray.
	// filterMode: 0 = no body filter, 1 = exclude bodyIDs, 2 = include bodyIDs.
	JPH_PhysicsSystem_CastRay                :: proc(system: JPH_PhysicsSystemRef, origin: ^JPH_RVec3, direction: ^JPH_Vec3, bodyIDs: ^JPH_BodyID, bodyIDCount: u32, filterMode: JPH_RayFilterMode, outResult: ^JPH_RayCastResult) -> i32 ---
	JPH_BodyInterface_CreateBody             :: proc(bodyInterface: JPH_BodyInterfaceRef, settings: JPH_BodyCreationSettingsRef) -> JPH_BodyRef ---
	JPH_BodyInterface_AddBody                :: proc(bodyInterface: JPH_BodyInterfaceRef, bodyID: JPH_BodyID, activationMode: JPH_ActivationMode) ---
	JPH_BodyInterface_DestroyBody            :: proc(bodyInterface: JPH_BodyInterfaceRef, body: JPH_BodyRef) ---
	JPH_BodyInterface_RemoveAndDestroyBody   :: proc(bodyInterface: JPH_BodyInterfaceRef, bodyID: JPH_BodyID) ---
	JPH_BodyInterface_SetShape               :: proc(bodyInterface: JPH_BodyInterfaceRef, bodyID: JPH_BodyID, shape: JPH_ShapeRef, updateMassProperties: i32, activationMode: JPH_ActivationMode) ---
	JPH_BodyInterface_SetMotionType          :: proc(bodyInterface: JPH_BodyInterfaceRef, bodyID: JPH_BodyID, motionType: JPH_MotionType, activationMode: JPH_ActivationMode) ---
	JPH_BodyInterface_SetObjectLayer         :: proc(bodyInterface: JPH_BodyInterfaceRef, bodyID: JPH_BodyID, layer: JPH_ObjectLayer) ---
	JPH_BodyInterface_ActivateBody           :: proc(bodyInterface: JPH_BodyInterfaceRef, bodyID: JPH_BodyID) ---
	JPH_BodyInterface_IsActive               :: proc(bodyInterface: JPH_BodyInterfaceRef, bodyID: JPH_BodyID) -> i32 ---
	JPH_BodyInterface_IsAdded                :: proc(bodyInterface: JPH_BodyInterfaceRef, bodyID: JPH_BodyID) -> i32 ---
	JPH_BodyInterface_SetPosition            :: proc(bodyInterface: JPH_BodyInterfaceRef, bodyID: JPH_BodyID, position: ^JPH_RVec3, activationMode: JPH_ActivationMode) ---
	JPH_BodyInterface_SetPositionAndRotation :: proc(bodyInterface: JPH_BodyInterfaceRef, bodyID: JPH_BodyID, position: ^JPH_RVec3, rotation: ^JPH_Quat, activationMode: JPH_ActivationMode) ---
	JPH_BodyInterface_SetRotation            :: proc(bodyInterface: JPH_BodyInterfaceRef, bodyID: JPH_BodyID, rotation: ^JPH_Quat, activationMode: JPH_ActivationMode) ---
	JPH_BodyInterface_SetLinearVelocity      :: proc(bodyInterface: JPH_BodyInterfaceRef, bodyID: JPH_BodyID, velocity: ^JPH_Vec3) ---
	JPH_BodyInterface_SetAngularVelocity     :: proc(bodyInterface: JPH_BodyInterfaceRef, bodyID: JPH_BodyID, velocity: ^JPH_Vec3) ---
	JPH_BodyInterface_GetPosition            :: proc(bodyInterface: JPH_BodyInterfaceRef, bodyID: JPH_BodyID, outPosition: ^JPH_RVec3) ---
	JPH_BodyInterface_GetPositionAndRotation :: proc(bodyInterface: JPH_BodyInterfaceRef, bodyID: JPH_BodyID, outPosition: ^JPH_RVec3, outRotation: ^JPH_Quat) ---
	JPH_BodyInterface_GetRotation            :: proc(bodyInterface: JPH_BodyInterfaceRef, bodyID: JPH_BodyID, outRotation: ^JPH_Quat) ---
	JPH_BodyInterface_GetLinearVelocity      :: proc(bodyInterface: JPH_BodyInterfaceRef, bodyID: JPH_BodyID, outVelocity: ^JPH_Vec3) ---
	JPH_BodyInterface_GetAngularVelocity     :: proc(bodyInterface: JPH_BodyInterfaceRef, bodyID: JPH_BodyID, outVelocity: ^JPH_Vec3) ---
	JPH_BodyInterface_AddImpulse             :: proc(bodyInterface: JPH_BodyInterfaceRef, bodyID: JPH_BodyID, impulse: ^JPH_Vec3) ---
	JPH_BodyInterface_AddForce               :: proc(bodyInterface: JPH_BodyInterfaceRef, bodyID: JPH_BodyID, force: ^JPH_Vec3) ---
	JPH_BodyInterface_AddForce2              :: proc(bodyInterface: JPH_BodyInterfaceRef, bodyID: JPH_BodyID, force: ^JPH_Vec3, position: ^JPH_RVec3) ---
	JPH_BodyInterface_AddTorque              :: proc(bodyInterface: JPH_BodyInterfaceRef, bodyID: JPH_BodyID, torque: ^JPH_Vec3) ---
	JPH_Body_GetID                           :: proc(body: JPH_BodyRef) -> JPH_BodyID ---
	JPH_Body_GetMotionProperties             :: proc(body: JPH_BodyRef) -> JPH_MotionPropertiesRef ---
	JPH_Body_SetFriction                     :: proc(body: JPH_BodyRef, friction: f32) ---
	JPH_MotionProperties_ScaleToMass         :: proc(motionProperties: JPH_MotionPropertiesRef, mass: f32) ---
	JPH_ContactListener_Create               :: proc() -> JPH_ContactListenerRef ---
	JPH_ContactListener_Destroy              :: proc(listener: JPH_ContactListenerRef) ---
	JPH_ContactListener_PollEvents           :: proc(listener: JPH_ContactListenerRef, procs: ^JPH_ContactListener_Procs, maxEvents: u32) -> u32 ---
}
