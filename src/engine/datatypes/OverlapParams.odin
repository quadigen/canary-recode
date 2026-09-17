package datatypes

import engine_enums "../enum"

OverlapParams :: struct {
	FilterDescendantsInstances: [dynamic]Raycast_Instance_Reference,
	ExcludeInstances:           [dynamic]Raycast_Instance_Reference,
	IncludeInstances:           [dynamic]Raycast_Instance_Reference,

	FilterType: engine_enums.RaycastFilterType,

	MaxParts:          i32,
	CollisionGroup:    string,
	Tolerance:         f32,
	RespectCanCollide: bool,
	BruteForceAllSlow: bool,

	LegacyFilterSet:  bool,
	ExcludeFilterSet: bool,
	IncludeFilterSet: bool,
}

OverlapParams_New :: proc() -> OverlapParams {
	return OverlapParams{
		FilterType     = .Exclude,
		MaxParts       = 0,
		CollisionGroup = "Default",
		Tolerance      = 0,
	}
}