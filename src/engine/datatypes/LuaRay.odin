package datatypes

import "base:runtime"
import "core:fmt"
import vm "../vm"

push_ray :: proc(L: ^vm.State, binding: ^vm.Userdata_Binding, value: Ray) {
	push_value(L, binding, value)
}

Push_Ray :: proc(L: ^vm.State, registry: ^Registry, value: Ray) {
	push_ray(L, &registry.ray, value)
}

ray_new :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	push_ray(L, binding_from_upvalue(L), Ray{arg_vector3(L, 1), arg_vector3(L, 2)})
	return 1
}

ray_get :: proc(L: ^vm.State, value, ctx: rawptr, key: string) -> bool {
	ray := cast(^Ray)value
	switch key {
	case "Origin": push_vector3(L, ray.Origin)
	case "Direction": push_vector3(L, ray.Direction)
	case "Unit": push_ray(L, cast(^vm.Userdata_Binding)ctx, Ray_Unit(ray^))
	case "ClosestPoint", "Distance": vm.PushUserdataMethod(L, key)
	case: return false
	}
	return true
}

ray_namecall :: proc(L: ^vm.State, value, ctx: rawptr, method: string) -> (i32, bool) {
	ray := cast(^Ray)value
	switch method {
	case "ClosestPoint":
		push_vector3(L, Ray_ClosestPoint(ray^, arg_vector3(L, 2)))
		return 1, true
	case "Distance":
		vm.PushNumber(L, f64(Ray_Distance(ray^, arg_vector3(L, 2))))
		return 1, true
	}
	return 0, false
}

ray_equal :: proc(value, other, ctx: rawptr) -> bool {
	return (cast(^Ray)value)^ == (cast(^Ray)other)^
}

ray_string :: proc(value, ctx: rawptr) -> string {
	ray := cast(^Ray)value
	return fmt.tprintf("{%g, %g, %g}, {%g, %g, %g}", ray.Origin.x, ray.Origin.y, ray.Origin.z, ray.Direction.x, ray.Direction.y, ray.Direction.z)
}

ray_destroy :: proc(value, ctx: rawptr) {
	free(cast(^Ray)value)
}

Ray_Luau_Binding :: proc() -> vm.Userdata_Binding {
	return vm.Userdata_Binding{
		name     = "Ray",
		get      = ray_get,
		namecall = ray_namecall,
		string   = ray_string,
		destroy  = ray_destroy,
		equal    = ray_equal,
	}
}

Ray_Install_Fields :: proc(L: ^vm.State, binding: ^vm.Userdata_Binding) {
	add_library_function(L, binding, "new", ray_new)
}
