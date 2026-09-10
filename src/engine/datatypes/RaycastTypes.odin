package datatypes

import engine_enums "../enum"

Raycast_Instance_Reference :: struct {
	object:  rawptr,
	lua_ref: i32,
}

RaycastParams :: struct {
	FilterDescendantsInstances: [dynamic]Raycast_Instance_Reference,
	ExcludeInstances:           [dynamic]Raycast_Instance_Reference,
	IncludeInstances:           [dynamic]Raycast_Instance_Reference,
	FilterType:                 engine_enums.RaycastFilterType,
	IgnoreWater:                bool,
	RespectCanCollide:          bool,
	BruteForceAllSlow:          bool,
	CollisionGroup:             string,
	LegacyFilterSet:            bool,
	ExcludeFilterSet:           bool,
	IncludeFilterSet:           bool,
}

RaycastResult :: struct {
	Position:     Vector3,
	Normal:       Vector3,
	Distance:     f32,
	Material:     engine_enums.Material,
	InstanceRef:  i32,
}

RaycastParams_New :: proc() -> RaycastParams {
	return RaycastParams{
		FilterType = .Exclude,
		CollisionGroup = "Default",
	}
}

Raycast_Instance_Matches :: proc(object: rawptr, filters: []Raycast_Instance_Reference) -> bool {
	for filter in filters {
		if filter.object == object { return true }
	}
	return false
}

