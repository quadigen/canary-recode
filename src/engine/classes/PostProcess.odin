package classes

import kineffi "../bindings"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:fmt"
import "core:strings"

PostProcess_Class := Class_Info {
	name   = "PostProcess",
	parent = &Instance_Class,
}

PostProcess_Texture :: struct {
	name:          string,
	pixels:        []u8,
	width, height: i32,
	srgb, dirty:   bool,
}

POST_PROCESS_SCENE_UNIFORMS :: [?]string {
	"inputTexture",
	"depthTexture",
	"time",
	"deltaTime",
	"resolution",
	"texelSize",
	"focal",
	"nearPlane",
	"farPlane",
	"cameraPosition",
	"cameraRight",
	"cameraUp",
	"cameraForward",
	"sunDirection",
	"sunIntensity",
	"sunLightIntensity",
	"sunColor",
	"skyColor",
	"viewMatrix",
	"projectionMatrix",
	"inverseViewMatrix",
	"inverseProjectionMatrix",
	"viewProjectionMatrix",
	"inverseViewProjectionMatrix",
	"viewportOrigin",
}

post_process_reserved :: proc(name: string) -> bool {
	if len(name) == 0 || strings.contains(name, "\x00") {return true}
	for item in POST_PROCESS_SCENE_UNIFORMS {if item == name {return true}}
	return false
}

PostProcess :: struct {
	using object:       Object,
	using shader_state: Runtime_Shader,
	enabled:            bool,
	textures:           [dynamic]PostProcess_Texture,
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

	for texture in process.textures {delete(texture.name); delete(texture.pixels)}
	delete(process.textures)
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
	if method == "SetTexture" {
		name := vm.ArgString(L, 2)
		if post_process_reserved(
			name,
		) {return vm.RaiseError(L, "Invalid or reserved post-process sampler name"), true}
		source := object_from_argument(L, 3)
		if source == nil || source.destroyed || !Is_A_Class(source, &EditableImage_Class) {
			return vm.RaiseError(L, "SetTexture expects an Image"), true
		}
		image := cast(^EditableImage)source
		srgb := vm.ArgOptionalBoolean(L, 4, false)
		for &entry in process.textures {
			if entry.name != name {continue}
			delete(entry.pixels)
			entry.pixels = make([]u8, len(image.pixels))
			copy(entry.pixels, image.pixels)
			entry.width, entry.height, entry.srgb, entry.dirty =
				i32(image.width), i32(image.height), srgb, true
			return 0, true
		}
		if len(process.textures) >=
		   16 {return vm.RaiseError(L, "PostProcess supports at most 16 custom textures"), true}
		pixels := make([]u8, len(image.pixels))
		copy(pixels, image.pixels)
		append(
			&process.textures,
			PostProcess_Texture {
				strings.clone(name),
				pixels,
				i32(image.width),
				i32(image.height),
				srgb,
				true,
			},
		)
		return 0, true
	}
	if method == "SetUniform" && post_process_reserved(vm.ArgString(L, 2)) {
		return vm.RaiseError(L, "Invalid or reserved post-process uniform name"), true
	}
	if method == "SetUniform" && datatype_registry != nil {

		values: [3]f32
		count := 0
		if vm.IsUserdataType(L, 3, &datatype_registry.vector2) {
			v := datatypes.Arg_Vector2(L, 3, datatype_registry)
			values[0], values[1] = v.X, v.Y; count = 2
		} else if vm.TypeOf(L, 3) == .Vector {
			v := datatypes.Arg_Vector3(L, 3)
			values = {f32(v.x), f32(v.y), f32(v.z)}; count = 3
		} else if vm.IsUserdataType(L, 3, &datatype_registry.color3) {
			v := datatypes.Arg_Color3(L, 3, datatype_registry)
			values = {v.R, v.G, v.B}; count = 3
		}
		if count > 0 {
			vm.SetStackTop(L, 2)
			vm.NewTable(L, count, 0)
			for i in 0 ..< count {
				vm.PushNumber(L, f64(values[i]))
				vm.RawSetIndex(L, -2, i + 1)
			}
		}
	}
	return Runtime_Shader_Namecall(L, &process.shader_state, method)
}

PostProcess_clone :: proc(source: ^Object, destination: ^Object) {
	src, dst := cast(^PostProcess)source, cast(^PostProcess)destination
	dst.enabled = src.enabled
	Runtime_Shader_Clone(&src.shader_state, &dst.shader_state)
	for texture in src.textures {
		pixels := make([]u8, len(texture.pixels))
		copy(pixels, texture.pixels)
		append(
			&dst.textures,
			PostProcess_Texture {
				strings.clone(texture.name),
				pixels,
				texture.width,
				texture.height,
				texture.srgb,
				true,
			},
		)
	}
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
	for &texture in process.textures {
		if !changed && !texture.dirty {continue}
		texture.dirty = false
		name := strings.clone_to_cstring(texture.name)
		ok := kineffi.Kine_Filament_Shader_SetTextureFromPixels(
			process.filament_shader,
			name,
			texture.width,
			texture.height,
			texture.width * 4,
			raw_data(texture.pixels),
			texture.srgb,
		)
		delete(name)
		if !ok && !process.source_failed {
			Runtime_Shader_Error(
				&process.shader_state,
				fmt.tprintf("Texture is missing or incompatible: %s", texture.name),
			)
		}
	}
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
		methods = {"SetUniform", "GetUniform", "SetTexture"},
	)
}
