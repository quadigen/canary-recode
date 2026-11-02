package datatypes

import "core:strings"

import engine_enums "../enum"

OverlapParams :: struct {
	FilterDescendantsInstances: [dynamic]Raycast_Instance_Reference,
	ExcludeInstances:           [dynamic]Raycast_Instance_Reference,
	IncludeInstances:           [dynamic]Raycast_Instance_Reference,
	FilterType:                 engine_enums.RaycastFilterType,
	MaxParts:                   i32,
	CollisionGroup:             string,
	Tolerance:                  f32,
	RespectCanCollide:          bool,
	BruteForceAllSlow:          bool,
	LegacyFilterSet:            bool,
	ExcludeFilterSet:           bool,
	IncludeFilterSet:           bool,
}

OverlapParams_Clone :: proc(params: OverlapParams) -> OverlapParams {
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

OverlapParams_New :: proc() -> OverlapParams {
	return OverlapParams {
		FilterType = .Exclude,
		MaxParts = 0,
		CollisionGroup = "Default",
		Tolerance = 0,
	}
}
