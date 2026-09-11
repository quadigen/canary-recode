package datatypes

import "base:runtime"
import "core:fmt"
import engine_enums "../enum"
import vm "../vm"

push_path_waypoint :: proc(
	L: ^vm.State,
	binding: ^vm.Userdata_Binding,
	value: PathWaypoint,
) {
	push_value(L, binding, PathWaypoint_Clone(value))
}

Push_PathWaypoint :: proc(
	L: ^vm.State,
	registry: ^Registry,
	value: PathWaypoint,
) {
	push_path_waypoint(L, &registry.path_waypoint, value)
}

Arg_PathWaypoint :: proc(
	L: ^vm.State,
	index: int,
	registry: ^Registry,
) -> PathWaypoint {
	return require_path_waypoint(L, index, &registry.path_waypoint)^
}

require_path_waypoint :: proc(
	L: ^vm.State,
	index: int,
	binding: ^vm.Userdata_Binding,
) -> ^PathWaypoint {
	if !vm.IsUserdataType(L, index, binding) {
		_ = vm.RaiseError(L, "expected PathWaypoint")
		return nil
	}
	return cast(^PathWaypoint)vm.UserdataValue(L, index)
}

path_waypoint_new :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()

	binding := binding_from_upvalue(L)
	registry := registry_from_binding(binding)
	if registry == nil || registry.enums == nil {
		return vm.RaiseError(L, "PathWaypoint enum registry is unavailable")
	}

	x, y, z := vm.ArgVector3(L, 1)
	action := engine_enums.PathWaypointAction.Walk

	if !vm.IsNoneOrNil(L, 2) {
		item := engine_enums.Arg_Item(
			L,
			2,
			registry.enums,
			"PathWaypointAction",
		)
		action = engine_enums.PathWaypointAction(item.value)
	}

	label := ""
	if !vm.IsNoneOrNil(L, 3) {
		label = vm.ArgString(L, 3)
	}

	value := PathWaypoint_New(
		Vector3{x, y, z},
		action,
		label,
	)
	defer PathWaypoint_Destroy(&value)

	push_path_waypoint(L, binding, value)
	return 1
}

path_waypoint_get :: proc(
	L: ^vm.State,
	value,
	ctx: rawptr,
	key: string,
) -> bool {
	waypoint := cast(^PathWaypoint)value
	binding := cast(^vm.Userdata_Binding)ctx
	registry := registry_from_binding(binding)

	switch key {
	case "Position":
		vm.PushVector3(
			L,
			waypoint.Position.x,
			waypoint.Position.y,
			waypoint.Position.z,
		)

	case "Action":
		if registry == nil || registry.enums == nil {
			return false
		}
		_ = engine_enums.Push_Item_By_Value(
			L,
			registry.enums,
			"PathWaypointAction",
			i64(waypoint.Action),
		)

	case "Label":
		vm.PushString(L, waypoint.Label)

	case:
		return false
	}

	return true
}

path_waypoint_equal :: proc(value, other, ctx: rawptr) -> bool {
	a := cast(^PathWaypoint)value
	b := cast(^PathWaypoint)other

	return a.Position == b.Position &&
	       a.Action == b.Action &&
	       a.Label == b.Label
}

path_waypoint_string :: proc(value, ctx: rawptr) -> string {
	waypoint := cast(^PathWaypoint)value
	return fmt.tprintf(
		"%g, %g, %g [%s]",
		waypoint.Position.x,
		waypoint.Position.y,
		waypoint.Position.z,
		waypoint.Label,
	)
}

path_waypoint_destroy :: proc(value, ctx: rawptr) {
	waypoint := cast(^PathWaypoint)value
	PathWaypoint_Destroy(waypoint)
	free(waypoint)
}

PathWaypoint_Luau_Binding :: proc() -> vm.Userdata_Binding {
	return vm.Userdata_Binding{
		name    = "PathWaypoint",
		get     = path_waypoint_get,
		string  = path_waypoint_string,
		destroy = path_waypoint_destroy,
		equal   = path_waypoint_equal,
	}
}

PathWaypoint_Install_Fields :: proc(
	L: ^vm.State,
	binding: ^vm.Userdata_Binding,
) {
	add_library_function(L, binding, "new", path_waypoint_new)
}
