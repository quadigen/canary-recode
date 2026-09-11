package datatypes

import "core:strings"
import engine_enums "../enum"

PathWaypoint :: struct {
	Position: Vector3,
	Action:   engine_enums.PathWaypointAction,
	Label:    string,
}

PathWaypoint_New :: proc(
	position: Vector3,
	action: engine_enums.PathWaypointAction = .Walk,
	label: string = "",
) -> PathWaypoint {
	return PathWaypoint{
		Position = position,
		Action   = action,
		Label    = strings.clone(label),
	}
}

PathWaypoint_Clone :: proc(value: PathWaypoint) -> PathWaypoint {
	return PathWaypoint{
		Position = value.Position,
		Action   = value.Action,
		Label    = strings.clone(value.Label),
	}
}

PathWaypoint_Destroy :: proc(value: ^PathWaypoint) {
	if value == nil {
		return
	}
	delete(value.Label)
	value.Label = ""
}
