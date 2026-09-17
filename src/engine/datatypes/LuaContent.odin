package datatypes

import "base:runtime"
import "core:fmt"

import vm "../vm"

push_content :: proc(L: ^vm.State, binding: ^vm.Userdata_Binding, value: Content) {
	push_value(L, binding, value)
}

Push_Content :: proc(L: ^vm.State, registry: ^Registry, value: Content) {
	push_content(L, &registry.content, value)
}

Arg_Content :: proc(L: ^vm.State, index: int, registry: ^Registry) -> Content {
	if !vm.IsUserdataType(L, index, &registry.content) {
		_ = vm.RaiseError(L, "expected Content")
		return Content{}
	}
	return (cast(^Content)vm.UserdataValue(L, index))^
}

content_from_uri :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	binding := binding_from_upvalue(L)
	push_content(L, binding, Content_From_URI(vm.ArgString(L, 1)))
	return 1
}

content_get :: proc(L: ^vm.State, value, ctx: rawptr, key: string) -> bool {
	content := cast(^Content)value
	switch key {
	case "Uri":
		vm.PushString(L, content.uri)
	case:
		return false
	}
	return true
}

content_equal :: proc(value, other, ctx: rawptr) -> bool {
	return (cast(^Content)value).uri == (cast(^Content)other).uri
}

content_string :: proc(value, ctx: rawptr) -> string {
	return fmt.tprintf("%s", (cast(^Content)value).uri)
}

content_destroy :: proc(value, ctx: rawptr) {
	content := cast(^Content)value
	delete(content.uri)
	free(content)
}

Content_Luau_Binding :: proc() -> vm.Userdata_Binding {
	return vm.Userdata_Binding{
		name    = "Content",
		get     = content_get,
		string  = content_string,
		destroy = content_destroy,
		equal   = content_equal,
	}
}

Content_Install_Fields :: proc(L: ^vm.State, binding: ^vm.Userdata_Binding) {
	add_library_function(L, binding, "fromUri", content_from_uri)
}
