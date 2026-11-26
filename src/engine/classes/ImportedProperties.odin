package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

Imported_Enum :: struct {
	name:  string,
	value: i64,
}

Imported_Instance :: struct {
	class: ^Class_Info,
}

Imported_Value :: union {
	bool,
	f64,
	string,
	datatypes.CFrame,
	datatypes.Color3,
	datatypes.UDim,
	datatypes.Vector2,
	datatypes.Vector3,
	Imported_Enum,
	Imported_Instance,
}

Imported_Property :: struct {
	name:          string,
	default_value: Imported_Value,
}

IMPORTED_PROPERTY_GROUPS := [?]struct {
	classes:    []string,
	properties: []Imported_Property,
} {
	{{"Instance"}, {{"DefinesCapabilities", false}, {"SerializedOverrides", ""}}},
	{{"BaseScript", "ModuleScript"}, {{"LinkedSource", ""}, {"ScriptGuid", ""}}},
	{
		{"BasePart"},
		{
			{"AudioCanCollide", true},
			{"BackParamA", f64(-0.5)},
			{"BackParamB", f64(0.5)},
			{"BottomParamA", f64(-0.5)},
			{"BottomParamB", f64(0.5)},
			{"FrontParamA", f64(-0.5)},
			{"FrontParamB", f64(0.5)},
			{"LeftParamA", f64(-0.5)},
			{"LeftParamB", f64(0.5)},
			{"RightParamA", f64(-0.5)},
			{"RightParamB", f64(0.5)},
			{"TopParamA", f64(-0.5)},
			{"TopParamB", f64(0.5)},
			{"CollisionGroupId", f64(0)},
			{"EnableFluidForces", true},
			{"Locked", false},
			{"Massless", false},
			{"Reflectance", f64(0)},
			{"RootPriority", f64(0)},
		},
	},
	{{"Part"}, {{"Disabled", false}}},
	{
		{"MeshPart"},
		{
			{"DoubleSided", false},
			{"HasJointOffset", false},
			{"HasSkinnedMesh", false},
			{"InertiaMigrated", false},
			{"InitialSize", datatypes.Vector3{}},
			{"JointOffset", datatypes.Vector3{}},
			{"PhysicsData", ""},
			{
				"RenderFidelity",
				Imported_Enum{"RenderFidelity", i64(enums.RenderFidelity.Automatic)},
			},
			{"UnscaledCofm", datatypes.Vector3{}},
			{"UnscaledVolInertiaDiags", datatypes.Vector3{}},
			{"UnscaledVolInertiaOffDiags", datatypes.Vector3{}},
			{"UnscaledVolume", f64(0)},
			{"VertexCount", f64(0)},
		},
	},
	{
		{"Model", "Workspace"},
		{
			{"ModelMeshCFrame", datatypes.CFrame_Identity},
			{"ModelMeshSize", datatypes.Vector3{}},
			{"NeedsPivotMigration", false},
			{"ScaleFactor", f64(1)},
		},
	},
	{{"Folder"}, {{"IconTint", datatypes.Color3{}}}},
	{
		{"Camera"},
		{
			{
				"FieldOfViewMode",
				Imported_Enum{"FieldOfViewMode", i64(enums.FieldOfViewMode.Vertical)},
			},
			{"HeadLocked", true},
			{"HeadScale", f64(1)},
			{"OrthographicSize", f64(35)},
			{"VRTiltAndRollEnabled", false},
			{"ViewStretch", f64(1)},
		},
	},
	{{"Decal", "GuiObject"}, {{"AutoLocalize", true}}},
	{
		{"ScrollingFrame"},
		{
			{
				"ElasticBehavior",
				Imported_Enum{"ElasticBehavior", i64(enums.ElasticBehavior.WhenScrollable)},
			},
		},
	},
	{
		{"Decal"},
		{
			{"EmissiveStrength", f64(1)},
			{"EmissiveTint", datatypes.Color3{1, 1, 1}},
			{"MetalnessMap", ""},
			{"NormalMap", ""},
			{"ResampleMode", Imported_Enum{"ResamplerMode", i64(enums.ResamplerMode.Default)}},
			{"Rotation", f64(0)},
			{"RoughnessMap", ""},
			{"TexturePack", ""},
			{"TexturePackMetadata", ""},
			{"UVOffset", datatypes.Vector2{}},
			{"UVScale", datatypes.Vector2{1, 1}},
			{"ZIndex", f64(1)},
		},
	},
	{
		{"GuiObject", "ScreenGui"},
		{
			{
				"SelectionBehaviorDown",
				Imported_Enum{"SelectionBehavior", i64(enums.SelectionBehavior.Escape)},
			},
			{
				"SelectionBehaviorLeft",
				Imported_Enum{"SelectionBehavior", i64(enums.SelectionBehavior.Escape)},
			},
			{
				"SelectionBehaviorRight",
				Imported_Enum{"SelectionBehavior", i64(enums.SelectionBehavior.Escape)},
			},
			{
				"SelectionBehaviorUp",
				Imported_Enum{"SelectionBehavior", i64(enums.SelectionBehavior.Escape)},
			},
			{"SelectionGroup", false},
		},
	},
	{
		{"GuiObject"},
		{
			{"Draggable", false},
			{"Interactable", true},
			{"SelectionImageObject", Imported_Instance{&GuiObject_Class}},
			{"SelectionOrder", f64(0)},
			{
				"SizeConstraint",
				Imported_Enum{"SizeConstraint", i64(enums.SizeConstraint.RelativeXY)},
			},
		},
	},
	{{"ImageLabel", "ImageButton"}, {{"SliceScale", f64(1)}}},
	{
		{"TextBox"},
		{
			{"RichText", false},
			{"TextTruncate", Imported_Enum{"TextTruncate", i64(enums.TextTruncate.None)}},
		},
	},
	{
		{"ScreenGui"},
		{{"ZIndexBehavior", Imported_Enum{"ZIndexBehavior", i64(enums.ZIndexBehavior.Sibling)}}},
	},
	{
		{"TextLabel"},
		{
			{"LocalizationMatchIdentifier", ""},
			{"LocalizationMatchedSourceText", ""},
			{"MaxVisibleGraphemes", f64(-1)},
			{"OpenTypeFeatures", ""},
			{"TextTruncate", Imported_Enum{"TextTruncate", i64(enums.TextTruncate.None)}},
		},
	},
	{
		{"UIStroke"},
		{
			{"BorderOffset", datatypes.UDim{}},
			{"LineJoinMode", Imported_Enum{"LineJoinMode", i64(enums.LineJoinMode.Round)}},
			{"ZIndex", f64(1)},
		},
	},
	{
		{"Lighting"},
		{
			{"ColorShift_Bottom", datatypes.Color3{}},
			{"ColorShift_Top", datatypes.Color3{}},
			{"EnvironmentDiffuseScale", f64(0)},
			{"EnvironmentSpecularScale", f64(0)},
			{"FogColor", datatypes.Color3{0.75, 0.75, 0.75}},
			{"FogEnd", f64(100_000)},
			{"FogStart", f64(0)},
			{"GeographicLatitude", f64(41.733)},
			{"Outlines", false},
			{"PrioritizeLightingQuality", true},
			{"Technology", Imported_Enum{"Technology", i64(enums.Technology.Legacy)}},
		},
	},
	{{"ServerScriptService"}, {{"LoadStringEnabled", false}}},
	{
		{"SoundService"},
		{
			{"AcousticSimulationEnabled", false},
			{"DiffractionEnabled", true},
			{"DistanceFactor", f64(3.33)},
			{"DopplerScale", f64(1)},
			{"IsNewExpForAudioApiByDefault", false},
			{"ListenerCFrame", datatypes.CFrame_Identity},
			{"OcclusionEnabled", true},
			{"RespectFilteringEnabled", true},
			{"ReverbEnabled", true},
			{"RolloffScale", f64(1)},
		},
	},
	{{"StarterGui"}, {{"ResetPlayerGuiOnSpawn", true}, {"ShowDevelopmentGui", true}}},
	{
		{"StarterPlayer"},
		{
			{"AllowCustomAnimations", true},
			{"CameraMaxZoomDistance", f64(128)},
			{"CameraMinZoomDistance", f64(0.5)},
			{"CharacterBreakJointsOnDeath", true},
			{"CharacterJumpHeight", f64(7.2)},
			{"CharacterUseJumpPower", false},
			{"ClassicDeath", true},
			{"CreateDefaultPlayerModule", true},
			{"EnableMouseLockOption", true},
			{"HealthDisplayDistance", f64(100)},
			{"NameDisplayDistance", f64(100)},
			{"PlayerModuleStatus", f64(0)},
			{"UserEmotesEnabled", true},
		},
	},
	{
		{"Workspace"},
		{
			{"AirDensity", f64(0.0012)},
			{"AirTurbulenceIntensity", f64(0)},
			{"AllowThirdPartySales", false},
			{"CollisionGroupData", ""},
			{"ExplicitAutoJoints", true},
			{"GravityDirection", datatypes.Vector3{0, -1, 0}},
			{"SimulationRate", f64(1)},
			{"StreamingAdaptiveRadius", false},
			{"StreamingEnabled", false},
			{"StreamingMinRadius", f64(64)},
			{"StreamingTargetRadius", f64(1024)},
			{"TerrainWeldsFixed", true},
			{"TouchesUseCollisionGroups", false},
			{"Wind", f64(0)},
			{"WindDirection", datatypes.Vector3{}},
		},
	},
	{
		{"BasePart"},
		{
			{"BackSurfaceInput", Imported_Enum{"InputType", -1}},
			{"BottomSurfaceInput", Imported_Enum{"InputType", -1}},
			{"FrontSurfaceInput", Imported_Enum{"InputType", -1}},
			{"LeftSurfaceInput", Imported_Enum{"InputType", -1}},
			{"RightSurfaceInput", Imported_Enum{"InputType", -1}},
			{"TopSurfaceInput", Imported_Enum{"InputType", -1}},
		},
	},
	{{"Part"}, {{"formFactorRaw", Imported_Enum{"FormFactor", 3}}}},
	{{"MeshPart"}, {{"FluidFidelityInternal", Imported_Enum{"FluidFidelity", -1}}}},
	{{"PartOperation"}, {{"FluidFidelityInternal", Imported_Enum{"FluidFidelity", -1}}}},
	{
		{"Camera"},
		{
			{"OrthographicMode", Imported_Enum{"OrthographicMode", 0}},
			{"ProjectionType", Imported_Enum{"ProjectionType", 0}},
		},
	},
	{{"Frame"}, {{"Style", Imported_Enum{"FrameStyle", -1}}}},
	{{"GuiObject"}, {{"Sink", Imported_Enum{"InputSink", 0}}}},
	{{"ScreenGui"}, {{"InputSinkEnabled", Imported_Enum{"RolloutState", 0}}}},
	{
		{"SurfaceGui"},
		{
			{"InputSinkEnabled", Imported_Enum{"RolloutState", 0}},
			{"SizingMode", Imported_Enum{"SurfaceGuiSizingMode", -1}},
		},
	},
	{{"TextLabel"}, {{"TextDirection", Imported_Enum{"TextDirection", -1}}}},
	{
		{"Lighting"},
		{
			{"ExtendLightRangeTo120", Imported_Enum{"RolloutState", 0}},
			{"LightAttenuationMode", Imported_Enum{"LightAttenuationMode", -1}},
			{"LightingStyle", Imported_Enum{"LightingStyle", -1}},
		},
	},
	{
		{"MaterialVariant"},
		{
			{"AlphaMode", Imported_Enum{"AlphaMode", 0}},
			{"BaseMaterial", Imported_Enum{"Material", 12}},
			{"MaterialPattern", Imported_Enum{"MaterialPattern", 0}},
		},
	},
	{
		{"Model"},
		{
			{"LevelOfDetail", Imported_Enum{"ModelLevelOfDetail", 0}},
			{"ModelStreamingMode", Imported_Enum{"ModelStreamingMode", 0}},
		},
	},
	{
		{"Terrain"},
		{
			{"AcquisitionMethod", Imported_Enum{"TerrainAcquisitionMethod", 0}},
			{"BackSurfaceInput", Imported_Enum{"InputType", -1}},
			{"BottomSurfaceInput", Imported_Enum{"InputType", -1}},
			{"FrontSurfaceInput", Imported_Enum{"InputType", -1}},
			{"LeftSurfaceInput", Imported_Enum{"InputType", -1}},
			{"RightSurfaceInput", Imported_Enum{"InputType", -1}},
			{"TopSurfaceInput", Imported_Enum{"InputType", -1}},
		},
	},
	{
		{"SoundService"},
		{
			{"AmbientReverb", Imported_Enum{"ReverbType", -1}},
			{"AudioApiByDefault", Imported_Enum{"RolloutState", 0}},
			{"CharacterSoundsUseNewApi", Imported_Enum{"RolloutState", 0}},
			{"DefaultListenerLocation", Imported_Enum{"ListenerLocation", 0}},
			{"ListenerType", Imported_Enum{"ListenerType", -1}},
			{"VolumetricAudio", Imported_Enum{"VolumetricAudio", -1}},
		},
	},
	{
		{"CylinderHandleAdornment"},
		{
			{"AdornCullingMode", Imported_Enum{"AdornCullingMode", -1}},
			{"Shading", Imported_Enum{"AdornShading", 0}},
		},
	},
	{
		{"SphereHandleAdornment"},
		{
			{"AdornCullingMode", Imported_Enum{"AdornCullingMode", -1}},
			{"Shading", Imported_Enum{"AdornShading", 0}},
		},
	},
	{
		{"StarterGui"},
		{
			{"ClipsDescendantsSupportsRotation", Imported_Enum{"RolloutState", 0}},
			{"RtlTextSupport", Imported_Enum{"RtlTextSupport", 0}},
			{"ScreenOrientation", Imported_Enum{"ScreenOrientation", -1}},
			{"VirtualCursorMode", Imported_Enum{"VirtualCursorMode", 0}},
		},
	},
	{
		{"StarterPlayer"},
		{
			{"AvatarJointUpgrade_SerializedRollout", Imported_Enum{"RolloutState", 0}},
			{"CameraMode", Imported_Enum{"CameraMode", -1}},
			{"DevCameraOcclusionMode", Imported_Enum{"DevCameraOcclusionMode", -1}},
			{"DevComputerCameraMovementMode", Imported_Enum{"DevComputerCameraMovementMode", -1}},
			{"DevComputerMovementMode", Imported_Enum{"DevComputerMovementMode", -1}},
			{"DevTouchCameraMovementMode", Imported_Enum{"DevTouchCameraMovementMode", -1}},
			{"DevTouchMovementMode", Imported_Enum{"DevTouchMovementMode", -1}},
			{"EnableDynamicHeads", Imported_Enum{"LoadDynamicHeads", 0}},
			{"GameSettingsAvatar", Imported_Enum{"GameAvatarType", -1}},
			{"GameSettingsR15Collision", Imported_Enum{"R15CollisionType", -1}},
			{"LoadCharacterLayeredClothing", Imported_Enum{"LoadCharacterLayeredClothing", 0}},
			{"LuaCharacterController", Imported_Enum{"CharacterControlMode", 0}},
			{"UseImprovedCharacterEvents", Imported_Enum{"RolloutState", 0}},
		},
	},
	{
		{"UIGradient"},
		{
			{"TileMode", Imported_Enum{"GradientTileMode", 0}},
			{"Type", Imported_Enum{"GradientType", 0}},
		},
	},
	{
		{"UIStroke"},
		{
			{"BorderStrokePosition", Imported_Enum{"BorderStrokePosition", -1}},
			{"StrokeSizingMode", Imported_Enum{"StrokeSizingMode", -1}},
		},
	},
	{
		{"Workspace"},
		{
			{"AuthorityMode", Imported_Enum{"AuthorityMode", -1}},
			{"AvatarUnificationMode", Imported_Enum{"AvatarUnificationMode", 0}},
			{"ClientAnimatorThrottling", Imported_Enum{"ClientAnimatorThrottlingMode", 0}},
			{"EnableSLIMAvatars", Imported_Enum{"RolloutState", 0}},
			{"ExpandedTerrain", Imported_Enum{"RolloutState", 0}},
			{"IKControlConstraintSupport", Imported_Enum{"IKControlConstraintSupport", 0}},
			{"ImprovedPhysicsReplication", Imported_Enum{"RolloutState", 0}},
			{"InputSinkEnabled", Imported_Enum{"RolloutState", 0}},
			{"LayeredClothingCacheOptimizations", Imported_Enum{"RolloutState", 0}},
			{"LevelOfDetail", Imported_Enum{"ModelLevelOfDetail", 0}},
			{"LuauTypeCheckMode", Imported_Enum{"LuauTypeCheckMode", 0}},
			{"MapTVRemoteToGamepadKeycodes", Imported_Enum{"RolloutState", 0}},
			{"MeshPartHeadsAndAccessories", Imported_Enum{"MeshPartHeadsAndAccessories", 0}},
			{"MeshStreamingAndImprovedLods", Imported_Enum{"RolloutState", 0}},
			{"ModelStreamingBehavior", Imported_Enum{"ModelStreamingBehavior", 0}},
			{"ModelStreamingMode", Imported_Enum{"ModelStreamingMode", 0}},
			{"NextGenerationPhysicsSolver", Imported_Enum{"RolloutState", 0}},
			{"NextGenerationReplication", Imported_Enum{"RolloutState", 0}},
			{"ParticlesUseDynamicWind", Imported_Enum{"RolloutState", 0}},
			{"PathfindingUseImprovedSearch", Imported_Enum{"PathfindingUseImprovedSearch", 0}},
			{"PhysicsSteppingMethod", Imported_Enum{"PhysicsSteppingMethod", 0}},
			{"PlayerCharacterDestroyBehavior", Imported_Enum{"PlayerCharacterDestroyBehavior", 0}},
			{"PlayerScriptsUseInputActionSystem", Imported_Enum{"RolloutState", 0}},
			{"PredictiveStreamingMode", Imported_Enum{"PredictiveStreamingMode", 0}},
			{"RejectCharacterDeletions", Imported_Enum{"RejectCharacterDeletions", 0}},
			{"RenderingCacheOptimizations", Imported_Enum{"RenderingCacheOptimizationMode", 0}},
			{
				"ReplicateInstanceDestroySetting",
				Imported_Enum{"ReplicateInstanceDestroySetting", 0},
			},
			{"ReplicationFrequency", Imported_Enum{"ReplicationMode", -1}},
			{"ReplicationThroughput", Imported_Enum{"ReplicationMode", -1}},
			{"Retargeting", Imported_Enum{"AnimatorRetargetingMode", 0}},
			{"SandboxedInstanceMode", Imported_Enum{"SandboxedInstanceMode", 0}},
			{"SignalBehavior2", Imported_Enum{"SignalBehavior", 0}},
			{"StreamOutBehavior", Imported_Enum{"StreamOutBehavior", 0}},
			{"StreamingIntegrityMode", Imported_Enum{"StreamingIntegrityMode", 0}},
			{"TouchEventsUseCollisionGroups", Imported_Enum{"RolloutState", 0}},
			{"UseFixedSimulation", Imported_Enum{"RolloutState", 0}},
			{"UseNewLuauTypeSolver", Imported_Enum{"RolloutState", 0}},
			{"ValidateEnabledProximityPrompt", Imported_Enum{"RolloutState", 0}},
		},
	},
}

register_imported_properties :: proc(descriptor: ^Class_Descriptor) {
	for group in IMPORTED_PROPERTY_GROUPS {
		for class_name in group.classes {
			for class := descriptor.info; class != nil; class = class.parent {
				if class.name != class_name {continue}
				for property in group.properties {
					descriptor.imported_properties[property.name] = property
					if class == descriptor.info {
						append(&descriptor.properties, property.name)
					}
				}
				break
			}
		}
	}
}


Object_Ensure_Imported_Values :: proc(object: ^Object) -> ^map[string]i32 {
	if object.imported_values == nil {object.imported_values = new(map[string]i32)}
	return object.imported_values
}

object_imported_value :: proc(object: ^Object, name: string) -> (i32, bool) {
	if object.imported_values == nil {return 0, false}
	value, found := object.imported_values^[name]
	return value, found
}

imported_property_get :: proc(
	L: ^vm.State,
	descriptor: ^Class_Descriptor,
	object: ^Object,
	key: string,
) -> bool {
	if descriptor == nil {return false}
	property, found := descriptor.imported_properties[key]
	if !found {return false}
	if value_ref, stored := object_imported_value(object, key); stored {
		vm.PushRegistryReference(L, value_ref)
		if _, is_reference := property.default_value.(Imported_Instance); is_reference {
			value := object_from_argument(L, -1)
			vm.Pop(L)
			Push_Object(L, value)
		}
		return true
	}

	dt := descriptor.registry.datatypes
	switch value in property.default_value {
	case bool:
		vm.PushBoolean(L, value)
	case f64:
		vm.PushNumber(L, value)
	case string:
		vm.PushString(L, value)
	case datatypes.CFrame:
		datatypes.Push_CFrame(L, dt, value)
	case datatypes.Color3:
		datatypes.Push_Color3(L, dt, value)
	case datatypes.UDim:
		datatypes.Push_UDim(L, dt, value)
	case datatypes.Vector2:
		datatypes.Push_Vector2(L, dt, value)
	case datatypes.Vector3:
		datatypes.Push_Vector3(L, value)
	case Imported_Enum:
		_ = enums.Push_Item_By_Value(L, descriptor.registry.enums, value.name, value.value)
	case Imported_Instance:
		vm.PushNil(L)
	}
	return true
}

imported_property_set :: proc(
	L: ^vm.State,
	descriptor: ^Class_Descriptor,
	object: ^Object,
	key: string,
	index: int,
) -> bool {
	if descriptor == nil {return false}
	property, found := descriptor.imported_properties[key]
	if !found {return false}

	dt := descriptor.registry.datatypes
	is_default: bool
	switch value in property.default_value {
	case bool:
		is_default = vm.ArgBoolean(L, index) == value
	case f64:
		if type := vm.TypeOf(L, index); type != .Number && type != .Integer {
			_ = vm.RaiseError(L, "expected number")
			return true
		}
		is_default = vm.ArgNumber(L, index) == value
	case string:
		if vm.TypeOf(L, index) != .String {
			_ = vm.RaiseError(L, "expected string")
			return true
		}
		is_default = vm.ArgString(L, index) == value
	case datatypes.CFrame:
		is_default = datatypes.Arg_CFrame(L, index, dt) == value
	case datatypes.Color3:
		is_default = datatypes.Arg_Color3(L, index, dt) == value
	case datatypes.UDim:
		is_default = datatypes.Arg_UDim(L, index, dt) == value
	case datatypes.Vector2:
		is_default = datatypes.Arg_Vector2(L, index, dt) == value
	case datatypes.Vector3:
		is_default = datatypes.Arg_Vector3(L, index) == value
	case Imported_Enum:
		is_default =
			enums.Arg_Item(L, index, descriptor.registry.enums, value.name).value == value.value
	case Imported_Instance:
		is_default = vm.IsNil(L, index)
		if !is_default && !Is_A_Class(object_from_argument(L, index), value.class) {
			_ = vm.RaiseError(L, "expected an instance of the required class or nil")
			return true
		}
	}

	if previous, found := object_imported_value(object, property.name); found {
		vm.ReleaseValue(L, previous)
	}
	if is_default {
		if values := object.imported_values; values != nil {
			delete_key(values, property.name)
			if len(values^) == 0 {
				delete(values^)
				free(values)
				object.imported_values = nil
			}
		}
	} else {
		values := Object_Ensure_Imported_Values(object)
		values^[property.name] = vm.RetainValue(L, index)
	}
	return true
}

Imported_Property_Is_Unset :: proc(
	descriptor: ^Class_Descriptor,
	object: ^Object,
	key: string,
) -> bool {
	return(
		Is_Imported_Property(descriptor, key) &&
		(object.imported_values == nil || key not_in object.imported_values^) \
	)
}

imported_remap_references :: proc(
	L: ^vm.State,
	descriptor: ^Class_Descriptor,
	object: ^Object,
	clones: map[^Object]^Object,
) {
	if object.imported_values == nil {return}
	for name, &value_ref in object.imported_values^ {
		if _, reference := descriptor.imported_properties[name].default_value.(Imported_Instance);
		   !reference {continue}
		vm.PushRegistryReference(L, value_ref)
		mapped := clones[object_from_argument(L, -1)]
		vm.Pop(L)
		if mapped == nil {continue}
		vm.ReleaseValue(L, value_ref)
		Push_Object(L, mapped)
		value_ref = vm.RetainValue(L)
		vm.Pop(L)
	}
}

Is_Imported_Property :: proc(descriptor: ^Class_Descriptor, key: string) -> bool {
	return descriptor != nil && key in descriptor.imported_properties
}
