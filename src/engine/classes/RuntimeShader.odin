package classes

import kineffi "../bindings"
import vm "../vm"
import "core:fmt"
import "core:strings"

Runtime_Shader_Uniform :: struct {
	name:     string,
	values:   [4]f32,
	count:    i32,
	optional: bool,
}


Runtime_Shader :: struct {
	source:          string,
	last_error:      string,
	filament_shader: ^kineffi.KineFilamentShader,
	dirty:           bool,
	source_failed:   bool,
	uniforms_dirty:  bool,
	uniforms:        [dynamic]Runtime_Shader_Uniform,
	revision:        u64,
}

Runtime_Shader_Error :: proc(shader: ^Runtime_Shader, message: string) {
	delete(shader.last_error)
	shader.last_error = strings.clone(message)
	if len(message) > 0 {fmt.eprintln("Shader:", message)}
}

Runtime_Shader_Set_Source :: proc(shader: ^Runtime_Shader, source: string) {
	copy := strings.clone(source)
	delete(shader.source)
	shader.source = copy
	shader.dirty = true
	shader.source_failed = false
	Runtime_Shader_Error(shader, "")
}

Runtime_Shader_Destroy :: proc(shader: ^Runtime_Shader) {
	if shader.filament_shader != nil {kineffi.Kine_Filament_Shader_Destroy(shader.filament_shader)}
	delete(shader.source)
	delete(shader.last_error)
	for uniform in shader.uniforms {delete(uniform.name)}
	delete(shader.uniforms)
	shader^ = {}
}

Runtime_Shader_Clone :: proc(src, dst: ^Runtime_Shader) {
	Runtime_Shader_Destroy(dst)
	Runtime_Shader_Set_Source(dst, src.source)
	for uniform in src.uniforms {
		copy := uniform
		copy.name = strings.clone(uniform.name)
		append(&dst.uniforms, copy)
	}
	dst.uniforms_dirty = true
}


Runtime_Shader_Prepare :: proc(
	shader: ^Runtime_Shader,
	filament: ^kineffi.KineFilamentContext,
	source_override: string = "",
) -> bool {
	if filament == nil {return false}
	changed := false
	if shader.dirty {
		shader.dirty = false
		compiled: ^kineffi.KineFilamentShader
		if len(shader.source) > 0 {
			source := strings.clone_to_cstring(
				len(source_override) > 0 ? source_override : shader.source,
			)
			defer delete(source)
			compiled = kineffi.Kine_Filament_Shader_Create(filament, source)
			if compiled == nil {
				shader.source_failed = true
				Runtime_Shader_Error(shader, string(kineffi.Kine_Filament_Shader_GetLastError()))
				return false
			}
		}
		if shader.filament_shader != nil {
			if compiled !=
			   nil {kineffi.Kine_Filament_Shader_TransferTextures(shader.filament_shader, compiled)}
			kineffi.Kine_Filament_Shader_Destroy(shader.filament_shader)
		}
		shader.filament_shader = compiled
		shader.source_failed = false
		shader.revision += 1
		shader.uniforms_dirty = true
		Runtime_Shader_Error(shader, "")
		changed = true
	}
	if shader.uniforms_dirty && shader.filament_shader != nil {
		shader.uniforms_dirty = false
		if !shader.source_failed {Runtime_Shader_Error(shader, "")}
		for &uniform in shader.uniforms {
			name := strings.clone_to_cstring(uniform.name)
			ok := kineffi.Kine_Filament_Shader_SetUniform(
				shader.filament_shader,
				name,
				&uniform.values[0],
				uniform.count,
			)
			delete(name)
			if !ok && !uniform.optional {
				message := fmt.tprintf(
					"Uniform is missing or has an incompatible type: %s",
					uniform.name,
				)
				Runtime_Shader_Error(shader, message)
			}
		}
		shader.revision += 1
	}
	return changed
}

Runtime_Shader_Get :: proc(L: ^vm.State, shader: ^Runtime_Shader, key: string) -> bool {
	switch key {
	case "Source":
		vm.PushString(L, shader.source)
	case "LastError":
		vm.PushString(L, shader.last_error)
	case "Compiled":
		vm.PushBoolean(L, shader.filament_shader != nil)
	case:
		return false
	}
	return true
}

Runtime_Shader_Set :: proc(
	L: ^vm.State,
	shader: ^Runtime_Shader,
	key: string,
	index: int,
) -> bool {
	switch key {
	case "Source":
		Runtime_Shader_Set_Source(shader, vm.ArgString(L, index))
	case "LastError", "Compiled":
		_ = vm.RaiseError(L, "Shader status properties are read-only")
	case:
		return false
	}
	return true
}

Runtime_Shader_Namecall :: proc(
	L: ^vm.State,
	shader: ^Runtime_Shader,
	method: string,
) -> (
	i32,
	bool,
) {
	switch method {
	case "SetUniform":
		name := vm.ArgString(L, 2)
		if len(name) == 0 {return vm.RaiseError(L, "Uniform name must not be empty"), true}
		uniform: Runtime_Shader_Uniform
		if vm.IsTable(L, 3) {
			count := vm.RawLen(L, 3)
			if count < 1 ||
			   count > 4 {return vm.RaiseError(L, "Uniform requires 1 to 4 numbers"), true}
			uniform.count = i32(count)
			for i in 0 ..< count {
				vm.RawGetIndex(L, 3, i + 1)
				uniform.values[i] = f32(vm.ArgNumber(L, -1))
				vm.Pop(L)
			}
		} else {
			uniform.count = 1
			uniform.values[0] = f32(vm.ArgNumber(L, 3))
		}
		for &entry in shader.uniforms {
			if entry.name == name {
				entry.values = uniform.values
				entry.count = uniform.count
				entry.optional = false
				shader.uniforms_dirty = true
				return 0, true
			}
		}
		uniform.name = strings.clone(name)
		append(&shader.uniforms, uniform)
		shader.uniforms_dirty = true
		return 0, true
	case "GetUniform":
		name := vm.ArgString(L, 2)
		for uniform in shader.uniforms {
			if uniform.name != name {continue}
			if uniform.count == 1 {
				vm.PushNumber(L, f64(uniform.values[0]))
			} else {
				vm.NewTable(L, int(uniform.count), 0)
				for i in 0 ..< int(uniform.count) {
					vm.PushNumber(L, f64(uniform.values[i]))
					vm.RawSetIndex(L, -2, i + 1)
				}
			}
			return 1, true
		}
		vm.PushNil(L)
		return 1, true
	}
	return 0, false
}
