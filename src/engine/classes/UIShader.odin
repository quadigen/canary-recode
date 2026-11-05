package classes

import kineffi "../bindings"
import datatypes "../datatypes"
import enums "../enum"
import guilib "../gui"
import vm "../vm"
import "core:fmt"
import "core:math"
import "core:strings"

UIShader_Class := Class_Info {
	name   = "UIShader",
	parent = &Instance_Class,
}

UIShader :: struct {
	using object:    Object,
	enabled:         bool,
	source:          string,
	sample_radius:   f32,
	last_error:      string,
	compiled:        ^kineffi.KineSkiaRuntimeShader,
	samples_content: bool,
	source_dirty:    bool,
	uniforms_dirty:  bool,
	uniforms:        [dynamic]Runtime_Shader_Uniform,
}

UIShader_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	shader := new(UIShader)
	shader.object = Object_Init(&UIShader_Class, "UIShader")
	shader.enabled = true
	return &shader.object
}

UIShader_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	shader := cast(^UIShader)object
	if shader.compiled != nil {
		kineffi.Kine_Skia_RuntimeShader_Destroy(shader.compiled)
	}
	delete(shader.source)
	delete(shader.last_error)
	for uniform in shader.uniforms {delete(uniform.name)}
	delete(shader.uniforms)
	Object_Destroy(object)
	free(shader)
}

UIShader_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	shader := cast(^UIShader)object
	switch key {
	case "Enabled":
		vm.PushBoolean(L, shader.enabled)
	case "Source":
		vm.PushString(L, shader.source)
	case "SampleRadius":
		vm.PushNumber(L, f64(shader.sample_radius))
	case "Compiled":
		vm.PushBoolean(L, shader.compiled != nil)
	case "LastError":
		vm.PushString(L, shader.last_error)
	case:
		return false
	}
	return true
}

UIShader_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	shader := cast(^UIShader)object
	switch key {
	case "Enabled":
		shader.enabled = vm.ArgBoolean(L, value_index)
	case "Source":
		source := vm.ArgString(L, value_index)
		if source == shader.source {return true}
		if strings.contains(source, "\x00") {
			_ = vm.RaiseError(L, "UIShader source cannot contain NUL bytes")
			return true
		}
		copy := strings.clone(source)
		delete(shader.source)
		delete(shader.last_error)
		if shader.compiled != nil {
			kineffi.Kine_Skia_RuntimeShader_Destroy(shader.compiled)
			shader.compiled = nil
		}
		shader.source = copy
		shader.last_error = ""
		shader.source_dirty = true
	case "SampleRadius":
		radius := vm.ArgNumber(L, value_index)
		if math.is_nan(radius) {
			_ = vm.RaiseError(L, "SampleRadius must be a number between 0 and 128")
			return true
		}
		shader.sample_radius = f32(clamp(radius, 0, 128))
	case "Compiled", "LastError":
		_ = vm.RaiseError(L, "Shader status properties are read-only")
	case:
		return false
	}
	return true
}

UIShader_namecall :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	shader := cast(^UIShader)object
	if method == "SetUniform" {
		name := vm.ArgString(L, 2)
		if name == "size" || name == "backgroundColor" || strings.contains(name, "\x00") {
			return vm.RaiseError(L, "Invalid or reserved UIShader uniform name"), true
		}
		result, handled := Shader_Uniform_Namecall(L, &shader.uniforms, method)
		shader.uniforms_dirty = true
		surfacegui_mark_dirty_for(object)
		return result, handled
	}
	return Shader_Uniform_Namecall(L, &shader.uniforms, method)
}

UIShader_clone :: proc(source, destination: ^Object) {
	src, dst := cast(^UIShader)source, cast(^UIShader)destination
	dst.enabled = src.enabled
	dst.source = strings.clone(src.source)
	dst.sample_radius = src.sample_radius
	dst.source_dirty = true
	for uniform in src.uniforms {
		copy := uniform
		copy.name = strings.clone(uniform.name)
		append(&dst.uniforms, copy)
	}
}

UIShader_Find :: proc(object: ^Object) -> ^UIShader {
	for child in object.children {
		if child != nil && !child.destroyed && child.class == &UIShader_Class {
			shader := cast(^UIShader)child
			if shader.enabled && shader.source != "" {
				return shader
			}
		}
	}
	return nil
}

UIShader_Prepare :: proc(shader: ^UIShader) -> bool {
	if shader.source_dirty {
		shader.source_dirty = false
		when ODIN_OS == .JS {
			shader.last_error = strings.clone("UIShader requires a native Skia renderer")
		} else {
			source := strings.clone_to_cstring(shader.source)
			defer delete(source)
			shader.compiled = kineffi.Kine_Skia_UIShader_Create(source, &shader.samples_content)
			if shader.compiled == nil {
				shader.last_error = strings.clone(
					string(kineffi.Kine_Skia_RuntimeShader_GetLastError()),
				)
			}
		}
		shader.uniforms_dirty = true
	}
	if shader.compiled == nil {return false}
	if shader.uniforms_dirty {
		shader.uniforms_dirty = false
		delete(shader.last_error)
		shader.last_error = ""
		for &uniform in shader.uniforms {
			name := strings.clone_to_cstring(uniform.name)
			ok := kineffi.Kine_Skia_RuntimeShader_SetUniform(
				shader.compiled,
				name,
				&uniform.values[0],
				uniform.count,
			)
			delete(name)
			if !ok && shader.last_error == "" {
				shader.last_error = fmt.aprintf(
					"Uniform is missing or has an incompatible type: %s",
					uniform.name,
				)
			}
		}
	}
	return true
}

UIShader_Apply :: proc(
	shader: ^UIShader,
	ctx: ^Class_Step_Context,
	rect: guilib.Rect,
	content_pass: bool,
) -> bool {
	when ODIN_OS == .JS {
		return false
	} else {
		color := [4]f32{rect.color.R, rect.color.G, rect.color.B, 1 - rect.bgTransparency}
		surface := ctx.renderer.SkiaSurface
		if content_pass {
			return kineffi.Kine_Skia_Surface_BeginUIShader(
				surface,
				shader.compiled,
				rect.x,
				rect.y,
				rect.width,
				rect.height,
				&color[0],
				shader.sample_radius,
			)
		}
		return kineffi.Kine_Skia_Surface_DrawUIShader(
			surface,
			shader.compiled,
			rect.x,
			rect.y,
			rect.width,
			rect.height,
			&color[0],
		)
	}
}

Register_UIShader :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&UIShader_Class,
		UIShader_construct,
		UIShader_destroy,
		get = UIShader_get,
		set = UIShader_set,
		clone = UIShader_clone,
		namecall = UIShader_namecall,
		properties = []string{"Enabled", "Source", "SampleRadius", "Compiled", "LastError"},
		methods = []string{"SetUniform", "GetUniform"},
	)
}
