package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

Imported_Enum :: struct {
	name:  string,
	value: i64,
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
			{"BackSurface", Imported_Enum{"SurfaceType", 0}},
			{"BottomSurface", Imported_Enum{"SurfaceType", 0}},
			{"FrontSurface", Imported_Enum{"SurfaceType", 0}},
			{"LeftSurface", Imported_Enum{"SurfaceType", 0}},
			{"RightSurface", Imported_Enum{"SurfaceType", 0}},
			{"TopSurface", Imported_Enum{"SurfaceType", 0}},
			{"CollisionGroupId", f64(0)},
			{"EnableFluidForces", true},
			{"Locked", false},
			{"Massless", false},
			{"PivotOffset", datatypes.CFrame_Identity},
			{"Reflectance", f64(0)},
			{"RootPriority", f64(0)},
		},
	},
	{
		{"Part"},
		{
			// A seat exported as a Part can still carry its original Disabled field.
			{"Disabled", false},
		},
	},
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
			{"SelectionOrder", f64(0)},
			{
				"SizeConstraint",
				Imported_Enum{"SizeConstraint", i64(enums.SizeConstraint.RelativeXY)},
			},
		},
	},
	{{"ImageLabel", "ImageButton"}, {{"SliceScale", f64(1)}}},
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

imported_property_get :: proc(
	L: ^vm.State,
	descriptor: ^Class_Descriptor,
	object: ^Object,
	key: string,
) -> bool {
	if descriptor == nil {return false}
	property, found := descriptor.imported_properties[key]
	if !found {return false}
	if value_ref, stored := object.imported_values[key]; stored {
		vm.PushRegistryReference(L, value_ref)
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
	}

	vm.ReleaseValue(L, object.imported_values[property.name])
	if is_default {
		delete_key(&object.imported_values, property.name)
	} else {
		object.imported_values[property.name] = vm.RetainValue(L, index)
	}
	return true
}

Imported_Property_Is_Unset :: proc(
	descriptor: ^Class_Descriptor,
	object: ^Object,
	key: string,
) -> bool {
	return Is_Imported_Property(descriptor, key) && key not_in object.imported_values
}

Is_Imported_Property :: proc(descriptor: ^Class_Descriptor, key: string) -> bool {
	return descriptor != nil && key in descriptor.imported_properties
}
