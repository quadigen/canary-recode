package classes

import kineffi "../bindings"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:math"
import "core:strings"


CharacterPhysicsSolver_Class := Class_Info {
	name   = "CharacterPhysicsSolver",
	parent = &Instance_Class,
}

CharacterPhysicsFoot :: struct {
	platform_id:            kineffi.JPH_BodyID,
	target_platform_id:     kineffi.JPH_BodyID,
	platform_anchor:        datatypes.Vector3,
	platform_normal:        datatypes.Vector3,
	target_platform_anchor: datatypes.Vector3,
	target_platform_normal: datatypes.Vector3,
	planted:                bool,
	swinging:               bool,
	progress:               f32,
	duration:               f32,
	current:                datatypes.Vector3,
	start:                  datatypes.Vector3,
	target:                 datatypes.Vector3,
	normal:                 datatypes.Vector3,
}

CharacterPhysicsHand :: struct {
	active: bool,
	weight: f32,
	target: datatypes.Vector3,
	normal: datatypes.Vector3,
}

CharacterPhysicsSolver :: struct {
	using object:               Object,
	enabled:                    bool,
	foot_ik_enabled:            bool,
	balance_enabled:            bool,
	hand_ik_enabled:            bool,
	arm_swing_enabled:          bool,
	head_stabilization_enabled: bool,
	balance_strength:           f32,
	contact_reach:              f32,
	reaction_strength:          f32,
	pose_blend:                 f32,
	stride_length:              f32,
	foot_lift:                  f32,
	step_duration:              f32,
	rig_mesh:                   ^Object,
	rig_name:                   string,
	status:                     string,
	grounded:                   bool,
	ground_normal:              datatypes.Vector3,
	horizontal_speed:           f32,
	calibrated_size:            datatypes.Vector3,
	last_facing:                datatypes.Vector3,
	facing_valid:               bool,
	leg_length:                 f64,
	sole_height:                f64,
	pelvis_height:              f64,
	standing_height:            f64,
	height_initialized:         bool,
	gait_phase:                 f64,
	gait_weight:                f64,
	next_step:                  int,
	motion_velocity:            datatypes.Vector3,
	air_weight:                 f64,
	solve_count:                u32,
	cached_mesh:                ^kineffi.KineFilamentMesh,
	bind_local:                 [][16]f32,
	bind_global:                [][16]f32,
	leg_bones:                  [2][3]i32,
	pelvis_bone:                i32,
	spine_bone:                 i32,
	spine_upper_bone:           i32,
	neck_bone:                  i32,
	head_bone:                  i32,
	arm_bones:                  [2][3]i32,
	hand:                       [2]CharacterPhysicsHand,
	center_of_mass:             datatypes.Vector3,
	support_center:             datatypes.Vector3,
	has_support:                bool,
	impact_compression:         f64,
	previous_grounded:          bool,
	previous_vertical_speed:    f64,
	last_velocity:              datatypes.Vector3,
	reaction_acceleration:      datatypes.Vector3,
	reaction_yaw:               f64,
	frame_time:                 f64,
	hand_contact_count:         u32,
	balance_pitch:              f64,
	balance_roll:               f64,
	foot:                       [2]CharacterPhysicsFoot,
	last_root:                  datatypes.Vector3,
	last_root_valid:            bool,
}

CharacterPhysicsSolver_Clear_Rig :: proc(s: ^CharacterPhysicsSolver) {
	if s == nil {return}
	delete(s.bind_local)
	delete(s.bind_global)
	s.bind_local = nil
	s.bind_global = nil
	s.cached_mesh = nil
	s.last_root_valid = false
	s.calibrated_size = {}
	s.last_facing = {}
	s.facing_valid = false
	s.leg_length = 0
	s.sole_height = 0.07
	s.pelvis_height = 0
	s.standing_height = 0
	s.height_initialized = false
	s.gait_phase = 0
	s.gait_weight = 0
	s.next_step = 0
	s.motion_velocity = {}
	s.air_weight = 0
	s.leg_bones = {{-1, -1, -1}, {-1, -1, -1}}
	s.arm_bones = {{-1, -1, -1}, {-1, -1, -1}}
	s.spine_upper_bone = -1
	s.neck_bone = -1
	s.head_bone = -1
	s.center_of_mass = {}
	s.support_center = {}
	s.has_support = false
	s.impact_compression = 0
	s.previous_grounded = false
	s.previous_vertical_speed = 0
	s.last_velocity = {}
	s.reaction_acceleration = {}
	s.reaction_yaw = 0
	s.frame_time = 0
	s.hand_contact_count = 0
	for &hand in s.hand {hand = {}}
	s.pelvis_bone = -1
	s.spine_bone = -1
	s.balance_pitch = 0
	s.balance_roll = 0
	for &foot in s.foot {
		foot = {}
		foot.platform_id = kineffi.JPH_BODY_ID_INVALID
		foot.target_platform_id = kineffi.JPH_BODY_ID_INVALID
	}
}

character_physics_solver_construct :: proc(
	renderer: ^Renderer_Object,
	data_model: rawptr,
) -> ^Object {
	s := new(CharacterPhysicsSolver)
	s.object = Object_Init(&CharacterPhysicsSolver_Class, "CharacterPhysicsSolver")
	s.enabled = false
	s.foot_ik_enabled = true
	s.balance_enabled = true
	s.hand_ik_enabled = true
	s.arm_swing_enabled = true
	s.head_stabilization_enabled = true
	s.balance_strength = 0.65
	s.contact_reach = 1.3
	s.reaction_strength = 0.65
	s.pose_blend = 1
	s.stride_length = 1.6
	s.foot_lift = 0.5
	s.step_duration = 0.26
	s.status = "Disabled"
	s.ground_normal = {0, 1, 0}
	CharacterPhysicsSolver_Clear_Rig(s)
	return &s.object
}

character_physics_solver_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	s := cast(^CharacterPhysicsSolver)object
	CharacterPhysicsSolver_Clear_Native_Pose(s)
	CharacterPhysicsSolver_Clear_Rig(s)
	delete(s.rig_name)
	Object_Destroy(object)
	free(s)
}

character_physics_solver_clone :: proc(source, destination: ^Object) {
	src := cast(^CharacterPhysicsSolver)source
	dst := cast(^CharacterPhysicsSolver)destination
	dst.enabled = src.enabled
	dst.foot_ik_enabled = src.foot_ik_enabled
	dst.balance_enabled = src.balance_enabled
	dst.hand_ik_enabled = src.hand_ik_enabled
	dst.arm_swing_enabled = src.arm_swing_enabled
	dst.head_stabilization_enabled = src.head_stabilization_enabled
	dst.balance_strength = src.balance_strength
	dst.contact_reach = src.contact_reach
	dst.reaction_strength = src.reaction_strength
	dst.pose_blend = src.pose_blend
	dst.stride_length = src.stride_length
	dst.foot_lift = src.foot_lift
	dst.step_duration = src.step_duration
	dst.rig_mesh = src.rig_mesh
	dst.rig_name = strings.clone(src.rig_name)
	dst.status = "WaitingForRig"
	CharacterPhysicsSolver_Clear_Rig(dst)
}


CharacterPhysicsSolver_Live_Rig :: proc(s: ^CharacterPhysicsSolver) -> ^Object {
	if s == nil || s.rig_mesh == nil || s.object.signal_registry == nil {return nil}
	descriptor := Find_Class(s.object.signal_registry, "MeshPart")
	if descriptor == nil {return nil}
	for object in descriptor.instances {
		if object == s.rig_mesh && object != nil && !object.destroyed {return object}
	}
	return nil
}

CharacterPhysicsSolver_Find_Named_Rig :: proc(node: ^Object, name: string) -> ^Object {
	if node == nil || node.destroyed || name == "" {return nil}
	if Is_A_Class(node, &MeshPart_Class) && node.name == name {return node}
	for child in node.children {
		if found := CharacterPhysicsSolver_Find_Named_Rig(child, name); found != nil {return found}
	}
	return nil
}

CharacterPhysicsSolver_Clear_Native_Pose :: proc(s: ^CharacterPhysicsSolver) {
	if s == nil {return}
	rig := CharacterPhysicsSolver_Live_Rig(s)
	if rig == nil && s.rig_name != "" && s.parent != nil && s.parent.parent != nil {
		rig = CharacterPhysicsSolver_Find_Named_Rig(s.parent.parent, s.rig_name)
	}
	if rig == nil || !Is_A_Class(rig, &MeshPart_Class) {return}
	mesh := cast(^MeshPart)rig
	if mesh.native_mesh == nil || mesh.native_context == nil {return}
	_ = kineffi.Kine_Filament_ClearMeshProceduralPose(mesh.native_context, mesh.native_mesh)
	MeshPart_Reset_Bone_Transforms(mesh)
}

character_physics_solver_get :: proc(
	L: ^vm.State,
	object: ^Object,
	dt: ^datatypes.Registry,
	en: ^enums.Registry,
	key: string,
) -> bool {
	s := cast(^CharacterPhysicsSolver)object
	switch key {
	case "Enabled":
		vm.PushBoolean(L, s.enabled)
	case "RigMesh":
		resolved := CharacterPhysicsSolver_Live_Rig(s)
		if resolved == nil &&
		   s.rig_name != "" &&
		   object.parent != nil &&
		   object.parent.parent != nil {
			resolved = CharacterPhysicsSolver_Find_Named_Rig(object.parent.parent, s.rig_name)
		}
		if resolved != nil && !resolved.destroyed {Push_Object(L, resolved)} else {vm.PushNil(L)}
	case "RigMeshName":
		vm.PushString(L, s.rig_name)
	case "FootIKEnabled":
		vm.PushBoolean(L, s.foot_ik_enabled)
	case "BalanceEnabled":
		vm.PushBoolean(L, s.balance_enabled)
	case "HandIKEnabled":
		vm.PushBoolean(L, s.hand_ik_enabled)
	case "ArmSwingEnabled":
		vm.PushBoolean(L, s.arm_swing_enabled)
	case "HeadStabilizationEnabled":
		vm.PushBoolean(L, s.head_stabilization_enabled)
	case "BalanceStrength":
		vm.PushNumber(L, f64(s.balance_strength))
	case "ContactReach":
		vm.PushNumber(L, f64(s.contact_reach))
	case "ReactionStrength":
		vm.PushNumber(L, f64(s.reaction_strength))
	case "PoseBlend":
		vm.PushNumber(L, f64(s.pose_blend))
	case "StrideLength":
		vm.PushNumber(L, f64(s.stride_length))
	case "FootLift":
		vm.PushNumber(L, f64(s.foot_lift))
	case "StepDuration":
		vm.PushNumber(L, f64(s.step_duration))
	case "Status":
		vm.PushString(L, s.status)
	case "IsReady":
		vm.PushBoolean(L, s.cached_mesh != nil && len(s.bind_local) > 0)
	case "IsGrounded":
		vm.PushBoolean(L, s.grounded)
	case "GroundNormal":
		datatypes.Push_Vector3(L, s.ground_normal)
	case "HorizontalSpeed":
		vm.PushNumber(L, f64(s.horizontal_speed))
	case "SolveCount":
		vm.PushNumber(L, f64(s.solve_count))
	case "LeftFootTarget":
		datatypes.Push_Vector3(L, s.foot[0].current)
	case "RightFootTarget":
		datatypes.Push_Vector3(L, s.foot[1].current)
	case "LeftHandTarget":
		datatypes.Push_Vector3(L, s.hand[0].target)
	case "RightHandTarget":
		datatypes.Push_Vector3(L, s.hand[1].target)
	case "HandContactCount":
		vm.PushNumber(L, f64(s.hand_contact_count))
	case "CenterOfMass":
		datatypes.Push_Vector3(L, s.center_of_mass)
	case "SupportCenter":
		datatypes.Push_Vector3(L, s.support_center)
	case "HasSupport":
		vm.PushBoolean(L, s.has_support)
	case "ImpactCompression":
		vm.PushNumber(L, s.impact_compression)
	case:
		return false
	}
	return true
}

character_physics_solver_set :: proc(
	L: ^vm.State,
	object: ^Object,
	dt: ^datatypes.Registry,
	en: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	s := cast(^CharacterPhysicsSolver)object
	switch key {
	case "Enabled":
		new_value := vm.ArgBoolean(L, value_index)
		if new_value != s.enabled {
			if !new_value {CharacterPhysicsSolver_Clear_Native_Pose(s)}
			s.enabled = new_value
			CharacterPhysicsSolver_Clear_Rig(s)


			if new_value {s.status = "WaitingForRig"}
		}
	case "RigMesh":
		candidate := object_from_argument(L, value_index)
		if candidate != nil && !Is_A_Class(candidate, &MeshPart_Class) {
			_ = vm.RaiseError(L, "CharacterPhysicsSolver.RigMesh must be a MeshPart or nil")
			return true
		}
		if candidate != s.rig_mesh || (candidate != nil && s.rig_name != candidate.name) {
			CharacterPhysicsSolver_Clear_Native_Pose(s)
			s.rig_mesh = candidate
			delete(s.rig_name)
			s.rig_name = candidate != nil ? strings.clone(candidate.name) : ""
			CharacterPhysicsSolver_Clear_Rig(s)
			s.status = "WaitingForRig"
		}
	case "RigMeshName":
		requested := vm.ArgString(L, value_index)
		if requested != s.rig_name {
			CharacterPhysicsSolver_Clear_Native_Pose(s)
			delete(s.rig_name)
			s.rig_name = strings.clone(requested)
			s.rig_mesh = nil
			CharacterPhysicsSolver_Clear_Rig(s)
			s.status = "WaitingForRig"
		}
	case "FootIKEnabled":
		s.foot_ik_enabled = vm.ArgBoolean(L, value_index)
	case "BalanceEnabled":
		s.balance_enabled = vm.ArgBoolean(L, value_index)
	case "HandIKEnabled":
		s.hand_ik_enabled = vm.ArgBoolean(L, value_index)
	case "ArmSwingEnabled":
		s.arm_swing_enabled = vm.ArgBoolean(L, value_index)
	case "HeadStabilizationEnabled":
		s.head_stabilization_enabled = vm.ArgBoolean(L, value_index)
	case "BalanceStrength":
		s.balance_strength = f32(
			character_tuning_number(L, value_index, 0, 1, f64(s.balance_strength)),
		)
	case "ContactReach":
		s.contact_reach = f32(character_tuning_number(L, value_index, 0, 5, f64(s.contact_reach)))
	case "ReactionStrength":
		s.reaction_strength = f32(
			character_tuning_number(L, value_index, 0, 2, f64(s.reaction_strength)),
		)
	case "PoseBlend":
		s.pose_blend = f32(character_tuning_number(L, value_index, 0, 1, f64(s.pose_blend)))
	case "StrideLength":
		s.stride_length = f32(
			character_tuning_number(L, value_index, 0.1, 12, f64(s.stride_length)),
		)
	case "FootLift":
		s.foot_lift = f32(character_tuning_number(L, value_index, 0, 4, f64(s.foot_lift)))
	case "StepDuration":
		s.step_duration = f32(
			character_tuning_number(L, value_index, 0.08, 2, f64(s.step_duration)),
		)
	case:
		return false
	}
	return true
}

Register_CharacterPhysicsSolver :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&CharacterPhysicsSolver_Class,
		character_physics_solver_construct,
		character_physics_solver_destroy,
		clone = character_physics_solver_clone,
		get = character_physics_solver_get,
		set = character_physics_solver_set,
		properties = []string {
			"Enabled",
			"RigMesh",
			"RigMeshName",
			"FootIKEnabled",
			"BalanceEnabled",
			"HandIKEnabled",
			"ArmSwingEnabled",
			"HeadStabilizationEnabled",
			"BalanceStrength",
			"ContactReach",
			"ReactionStrength",
			"PoseBlend",
			"StrideLength",
			"FootLift",
			"StepDuration",
			"Status",
			"IsReady",
			"IsGrounded",
			"GroundNormal",
			"HorizontalSpeed",
			"SolveCount",
			"LeftFootTarget",
			"RightFootTarget",
			"LeftHandTarget",
			"RightHandTarget",
			"HandContactCount",
			"CenterOfMass",
			"SupportCenter",
			"HasSupport",
			"ImpactCompression",
		},
	)
}
