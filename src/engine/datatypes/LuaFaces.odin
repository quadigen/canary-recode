package datatypes

import "base:runtime"
import "core:fmt"
import engine_enums "../enum"
import vm "../vm"

push_faces :: proc(L: ^vm.State, binding: ^vm.Userdata_Binding, value: Faces) {
	push_value(L, binding, value)
}

Push_Faces :: proc(L: ^vm.State, registry: ^Registry, value: Faces) {
	push_faces(L, &registry.faces, value)
}

Arg_Faces :: proc(L: ^vm.State, index: int, registry: ^Registry) -> Faces {
	return require_faces(L, index, &registry.faces)^
}

require_faces :: proc(
	L: ^vm.State,
	index: int,
	binding: ^vm.Userdata_Binding,
) -> ^Faces {
	if !vm.IsUserdataType(L, index, binding) {
		_ = vm.RaiseError(L, "expected Faces")
		return nil
	}
	return cast(^Faces)vm.UserdataValue(L, index)
}

faces_new :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()

	binding := binding_from_upvalue(L)
	registry := registry_from_binding(binding)
	if registry == nil || registry.enums == nil {
		return vm.RaiseError(L, "Faces enum registry is unavailable")
	}

	result := Faces{}

	for index in 1 ..= 6 {
		if vm.IsNoneOrNil(L, index) {
			break
		}

		item := engine_enums.Arg_Item(L, index, registry.enums, "NormalId")
		switch engine_enums.NormalId(item.value) {
		case .Top:
			result.Top = true
		case .Bottom:
			result.Bottom = true
		case .Left:
			result.Left = true
		case .Right:
			result.Right = true
		case .Front:
			result.Front = true
		case .Back:
			result.Back = true
		}
	}

	push_faces(L, binding, result)
	return 1
}

faces_get :: proc(L: ^vm.State, value, ctx: rawptr, key: string) -> bool {
	faces := cast(^Faces)value

	switch key {
	case "Top":
		vm.PushBoolean(L, faces.Top)
	case "Bottom":
		vm.PushBoolean(L, faces.Bottom)
	case "Left":
		vm.PushBoolean(L, faces.Left)
	case "Right":
		vm.PushBoolean(L, faces.Right)
	case "Front":
		vm.PushBoolean(L, faces.Front)
	case "Back":
		vm.PushBoolean(L, faces.Back)
	case:
		return false
	}

	return true
}

faces_equal :: proc(value, other, ctx: rawptr) -> bool {
	return (cast(^Faces)value)^ == (cast(^Faces)other)^
}

faces_string :: proc(value, ctx: rawptr) -> string {
	faces := cast(^Faces)value
	return fmt.tprintf(
		"Top=%v, Bottom=%v, Left=%v, Right=%v, Front=%v, Back=%v",
		faces.Top,
		faces.Bottom,
		faces.Left,
		faces.Right,
		faces.Front,
		faces.Back,
	)
}

faces_destroy :: proc(value, ctx: rawptr) {
	free(cast(^Faces)value)
}

Faces_Luau_Binding :: proc() -> vm.Userdata_Binding {
	return vm.Userdata_Binding{
		name    = "Faces",
		get     = faces_get,
		string  = faces_string,
		destroy = faces_destroy,
		equal   = faces_equal,
	}
}

Faces_Install_Fields :: proc(L: ^vm.State, binding: ^vm.Userdata_Binding) {
	add_library_function(L, binding, "new", faces_new)

	push_faces(L, binding, Faces_None)
	vm.SetField(L, -2, "none")

	push_faces(L, binding, Faces_All)
	vm.SetField(L, -2, "all")
}
