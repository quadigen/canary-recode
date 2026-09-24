package classes

import "core:strings"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import kineffi "../bindings"

PostProcessShader_Class := Class_Info{
	name   = "PostProcessShader",
	parent = &ValueBase_Class,
}

Uniform :: struct {
    name: string,
    type: string,
    value: any,
}

PostProcessShader :: struct {
	using object: Object,

	shader: string,
    uniforms: []Uniform,
	enabled: bool,
    filament_shader: ^kineffi.KineFilamentShader,
	dirty: bool
}

PostProcessShader_Init :: proc() -> PostProcessShader {
	return PostProcessShader{
		object = Object_Init(&PostProcessShader_Class),
		shader = "",
        uniforms = {}
	}
}

PostProcessShader_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	value := new(PostProcessShader)
	value^ = PostProcessShader_Init()
	value.name = "PostProcessShader"

	return &value.object
}

PostProcessShader_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^PostProcessShader)object)
}

PostProcessShader_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	val := cast(^PostProcessShader)object

	switch key {
	case "Shader":
		if datatype_registry == nil { return false }
		vm.PushString(L, val.shader)
	case "Enabled":
		if datatype_registry == nil { return false }
		vm.PushBoolean(L, val.enabled)
	case:
		return false
	}
	return true
}

PostProcessShader_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	val := cast(^PostProcessShader)object

	switch key {
	case "Shader":
		if datatype_registry == nil { return false }
		code := vm.ArgString(L, value_index)
        val.shader = code
		val.dirty = true
	case "Enabled":
		val.enabled = vm.ArgBoolean(L, value_index)
	case:
		return false
	}
	return true
}

PostProcessShader_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^PostProcessShader)source
	dst := cast(^PostProcessShader)destination

	dst.enabled = src.enabled
	dst.shader = src.shader
}

PostProcessShader_Step :: proc(
	object: ^Object,
	ctx: ^Class_Step_Context,
) {
	process := cast(^PostProcessShader)object

	if process.dirty {
		if process.filament_shader != nil {
			kineffi.Kine_Filament_Shader_Destroy(process.filament_shader)
			process.filament_shader = nil
		}
		str := strings.clone_to_cstring(process.shader)
		process.filament_shader = kineffi.Kine_Filament_Shader_Create(ctx.renderer.Filament, str)
		kineffi.Kine_Filament_SetPostProcessShader(ctx.renderer.Filament, process.filament_shader)
		delete(str)
		process.dirty = false
	}
}

Register_PostProcessShader :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&PostProcessShader_Class,
		PostProcessShader_construct,
		PostProcessShader_destroy,
		get = PostProcessShader_get,
		set = PostProcessShader_set,
		clone = PostProcessShader_clone,
		properties = []string{"Value"},
	)
}