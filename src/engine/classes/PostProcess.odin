package classes

import kineffi "../bindings"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

PostProcess_Class := Class_Info {
	name   = "PostProcess",
	parent = &Instance_Class,
}

PostProcess :: struct {
	using object:       Object,
	using shader_state: Runtime_Shader,
	enabled:            bool,
}

PostProcess_Init :: proc() -> PostProcess {
	return PostProcess{object = Object_Init(&PostProcess_Class, "PostProcess"), enabled = true}
}

PostProcess_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	process := new(PostProcess)
	process^ = PostProcess_Init()
	return &process.object
}

PostProcess_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	process := cast(^PostProcess)object
	if object.signal_registry != nil && object.signal_registry.active_post_process == object {
		object.signal_registry.active_post_process = nil
	}

	Runtime_Shader_Destroy(&process.shader_state)
	Object_Destroy(object)
	free(process)
}

PostProcess_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	process := cast(^PostProcess)object
	if key == "Enabled" {vm.PushBoolean(L, process.enabled); return true}
	return Runtime_Shader_Get(L, &process.shader_state, key)
}

PostProcess_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	index: int,
) -> bool {
	process := cast(^PostProcess)object
	if key == "Enabled" {process.enabled = vm.ArgBoolean(L, index); return true}
	return Runtime_Shader_Set(L, &process.shader_state, key, index)
}

PostProcess_namecall :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	process := cast(^PostProcess)object
	return Runtime_Shader_Namecall(L, &process.shader_state, method)
}

PostProcess_clone :: proc(source: ^Object, destination: ^Object) {
	src, dst := cast(^PostProcess)source, cast(^PostProcess)destination
	dst.enabled = src.enabled
	Runtime_Shader_Clone(&src.shader_state, &dst.shader_state)
}

PostProcess_Step :: proc(object: ^Object, ctx: ^Class_Step_Context) {
	if ctx == nil || ctx.renderer == nil || ctx.renderer.Filament == nil {return}
	registry := object.signal_registry
	if registry == nil {return}


	selected: ^Object
	descriptor := Find_Class(registry, "PostProcess")
	for candidate in descriptor.instances {
		if candidate == nil || candidate.destroyed || candidate.parent == nil {continue}
		process := cast(^PostProcess)candidate
		if process.enabled && len(process.source) > 0 {selected = candidate; break}
	}
	filament := ctx.renderer.Filament
	if selected == nil {
		if registry.active_post_process != nil {
			kineffi.Kine_Filament_SetPostProcessShader(filament, nil)
			registry.active_post_process = nil
		}
		return
	}
	if selected != object {return}
	if registry.active_post_process != nil && registry.active_post_process != object {
		kineffi.Kine_Filament_SetPostProcessShader(filament, nil)
		registry.active_post_process = nil
	}
	process := cast(^PostProcess)object
	changed := Runtime_Shader_Prepare(&process.shader_state, filament)
	if process.filament_shader == nil {return}
	if registry.active_post_process != object || changed {
		if kineffi.Kine_Filament_SetPostProcessShader(filament, process.filament_shader) {
			registry.active_post_process = object
		} else {
			Runtime_Shader_Error(
				&process.shader_state,
				string(kineffi.Kine_Filament_Shader_GetLastError()),
			)
			registry.active_post_process = nil
			process.enabled = false
		}
	}
}

Register_PostProcess :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&PostProcess_Class,
		PostProcess_construct,
		PostProcess_destroy,
		get = PostProcess_get,
		set = PostProcess_set,
		clone = PostProcess_clone,
		namecall = PostProcess_namecall,
		_step = PostProcess_Step,
		_step_phase = .Render_3D,
		properties = {"Source", "Enabled", "LastError", "Compiled"},
		methods = {"SetUniform", "GetUniform"},
	)
}
