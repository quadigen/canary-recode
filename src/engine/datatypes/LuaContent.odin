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

content_object_resolver: proc(object: rawptr) -> (u32, u8)
content_object_of_id:    proc(id: u32, kind: u8) -> rawptr
content_push_object:     proc(L: ^vm.State, object: rawptr) -> bool

Set_Content_Object_Resolver :: proc(
	resolver: proc(object: rawptr) -> (u32, u8),
	of_id: proc(id: u32, kind: u8) -> rawptr,
	push: proc(L: ^vm.State, object: rawptr) -> bool,
) {
	content_object_resolver = resolver
	content_object_of_id = of_id
	content_push_object = push
}

content_from_object :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	binding := binding_from_upvalue(L)
	object := rawptr(nil)
	argument := vm.UserdataBindingOf(L, 1)
	if argument != nil && argument.name == "Instance" {
		object = vm.UserdataValue(L, 1)
	}
	push_content(L, binding, Content_From_Object(object))
	return 1
}

content_get :: proc(L: ^vm.State, value, ctx: rawptr, key: string) -> bool {
	content := cast(^Content)value
	switch key {
	case "Uri":
		vm.PushString(L, content.uri)
	case "IsObject":
		vm.PushBoolean(L, content.object_id != 0)
	case "IsUri":
		vm.PushBoolean(L, content.uri != "")
	case "ObjectId":
		vm.PushNumber(L, f64(content.object_id))
	case "GetObject":
		object := rawptr(nil)
		if content_object_of_id != nil {
			object = content_object_of_id(content.object_id, content.object_kind)
		}
		if object == nil || content_push_object == nil || !content_push_object(L, object) {
			vm.PushNil(L)
		}
	case:
		return false
	}
	return true
}

content_equal :: proc(value, other, ctx: rawptr) -> bool {
	a := cast(^Content)value
	b := cast(^Content)other
	if a.object_id != 0 || b.object_id != 0 {
		return a.object_id != 0 && a.object_kind == b.object_kind && a.object_id == b.object_id
	}
	return a.uri == b.uri
}

content_string :: proc(value, ctx: rawptr) -> string {
	content := cast(^Content)value
	if content.object_id != 0 {
		return fmt.tprintf("object:%d", content.object_id)
	}
	return fmt.tprintf("%s", content.uri)
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
	add_library_function(L, binding, "fromObject", content_from_object)
}
