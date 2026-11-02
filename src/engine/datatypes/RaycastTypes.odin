package datatypes

import "core:strings"

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
	Position:    Vector3,
	Normal:      Vector3,
	Distance:    f32,
	Material:    engine_enums.Material,
	InstanceRef: i32,
	ObjectRef:   rawptr,
}

RaycastParams_Clone :: proc(params: RaycastParams) -> RaycastParams {
	result := params
	result.FilterDescendantsInstances = make(
		[dynamic]Raycast_Instance_Reference,
		0,
		len(params.FilterDescendantsInstances),
	)
	append(&result.FilterDescendantsInstances, ..params.FilterDescendantsInstances[:])
	result.ExcludeInstances = make(
		[dynamic]Raycast_Instance_Reference,
		0,
		len(params.ExcludeInstances),
	)
	append(&result.ExcludeInstances, ..params.ExcludeInstances[:])
	result.IncludeInstances = make(
		[dynamic]Raycast_Instance_Reference,
		0,
		len(params.IncludeInstances),
	)
	append(&result.IncludeInstances, ..params.IncludeInstances[:])
	result.CollisionGroup = strings.clone(params.CollisionGroup)
	return result
}

RaycastParams_New :: proc() -> RaycastParams {
	return RaycastParams{FilterType = .Exclude, CollisionGroup = "Default"}
}

Raycast_Instance_Matches :: proc(object: rawptr, filters: []Raycast_Instance_Reference) -> bool {
	for filter in filters {
		if filter.object == object {return true}
	}
	return false
}
