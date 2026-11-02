package classes

import assetstore "../assetstore"
import kineffi "../bindings"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:fmt"
import "core:math"
import "core:strings"
import image "vendor:stb/image"

MaterialVariant_Class := Class_Info {
	name   = "MaterialVariant",
	parent = &Instance_Class,
}

MATERIAL_VARIANT_SOURCE :: #load("MaterialVariant.mat", string)

MaterialVariant :: struct {
	using object:                                                  Object,
	using shader_state:                                            Runtime_Shader,
	enabled:                                                       bool,
	maps:                                                          [7]string,
	maps_dirty:                                                    [7]bool,
	maps_loaded:                                                   [7]bool,
	studs_per_tile:                                                f32,
	tiling_dirty:                                                  bool,
	height_scale, height_midlevel, parallax_depth, parallax_steps: f32,
	normal_strength, ao_strength, emissive_strength:               f32,
	displacement_subdivisions, displacement_bounds:                f32,
	emissive_color:                                                datatypes.Color3,
	vertex_source, fragment_source:                                string,
}

MaterialVariant_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	variant := new(MaterialVariant)
	variant.object = Object_Init(&MaterialVariant_Class, "MaterialVariant")
	variant.enabled = true
	variant.source = strings.clone(MATERIAL_VARIANT_SOURCE)
	variant.dirty = true
	variant.maps_dirty = {true, true, true, true, true, true, true}
	variant.studs_per_tile = 4
	variant.tiling_dirty = true
	variant.height_midlevel = 0.5
	variant.parallax_steps = 24
	variant.normal_strength = 1
	variant.ao_strength = 1
	variant.emissive_strength = 1
	variant.emissive_color = {1, 1, 1}
	variant.displacement_subdivisions = 2
	append(
		&variant.uniforms,
		Runtime_Shader_Uniform{strings.clone("baseColor"), {1, 1, 1, 1}, 4, true},
		Runtime_Shader_Uniform{strings.clone("roughness"), {0.5, 0, 0, 0}, 1, true},
		Runtime_Shader_Uniform{strings.clone("metallic"), {}, 1, true},
	)
	return &variant.object
}

MaterialVariant_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	variant := cast(^MaterialVariant)object
	Runtime_Shader_Destroy(&variant.shader_state)
	for path in variant.maps {delete(path)}
	delete(variant.vertex_source)
	delete(variant.fragment_source)
	Object_Destroy(object)
	free(variant)
}

MaterialVariant_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	variant := cast(^MaterialVariant)object
	if key == "Enabled" {vm.PushBoolean(L, variant.enabled); return true}
	if index := MaterialVariant_Map_Index(key);
	   index >= 0 {vm.PushString(L, variant.maps[index]); return true}
	if key == "StudsPerTile" {vm.PushNumber(L, f64(variant.studs_per_tile)); return true}
	if value := MaterialVariant_Number_Property(variant, key);
	   value != nil {vm.PushNumber(L, f64(value^)); return true}
	if key == "VertexSource" {vm.PushString(L, variant.vertex_source); return true}
	if key == "FragmentSource" {vm.PushString(L, variant.fragment_source); return true}
	if key == "EmissiveColor" {
		if datatype_registry == nil {return false}
		datatypes.Push_Color3(L, datatype_registry, variant.emissive_color)
		return true
	}
	if key == "Color" {
		if datatype_registry == nil {return false}
		v := variant.uniforms[0].values
		datatypes.Push_Color3(L, datatype_registry, datatypes.Color3{v[0], v[1], v[2]})
		return true
	}
	if key == "Roughness" {vm.PushNumber(L, f64(variant.uniforms[1].values[0])); return true}
	if key == "Metalness" {vm.PushNumber(L, f64(variant.uniforms[2].values[0])); return true}
	return Runtime_Shader_Get(L, &variant.shader_state, key)
}

MaterialVariant_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	index: int,
) -> bool {
	variant := cast(^MaterialVariant)object
	if key == "Enabled" {variant.enabled = vm.ArgBoolean(L, index); return true}
	if key == "VertexSource" || key == "FragmentSource" {
		value := strings.clone(vm.ArgString(L, index))
		if key ==
		   "VertexSource" {delete(variant.vertex_source); variant.vertex_source = value} else {
			delete(variant.fragment_source); variant.fragment_source = value
		}
		variant.dirty = true
		variant.source_failed = false
		Runtime_Shader_Error(&variant.shader_state, "")
		return true
	}
	if key == "EmissiveColor" {
		if datatype_registry == nil {return false}
		variant.emissive_color = datatypes.Arg_Color3(L, index, datatype_registry)
		variant.tiling_dirty = true
		return true
	}
	if field := MaterialVariant_Number_Property(variant, key); field != nil {
		value := f32(vm.ArgNumber(L, index))
		if math.is_nan(value) ||
		   math.is_inf(
			   value,
		   ) {_ = vm.RaiseError(L, "Material controls require a finite number"); return true}
		switch key {
		case "HeightMidlevel", "AOStrength":
			value = clamp(value, 0, 1)
		case "ParallaxSteps":
			value = math.floor(clamp(value, 8, 64))
		case "DisplacementSubdivisions":
			value = math.floor(clamp(value, 0, 4))
		case "HeightScale":
		case:
			value = max(f32(0), value)
		}
		field^ = value
		variant.tiling_dirty = true
		return true
	}
	if map_index := MaterialVariant_Map_Index(key); map_index >= 0 {
		copy := strings.clone(vm.ArgString(L, index))
		delete(variant.maps[map_index])
		variant.maps[map_index] = copy
		variant.maps_dirty[map_index] = true
		if !variant.source_failed {Runtime_Shader_Error(&variant.shader_state, "")}
		return true
	}
	if key == "StudsPerTile" {
		value := f32(vm.ArgNumber(L, index))
		if value <= 0 || math.is_nan(value) || math.is_inf(value) {
			_ = vm.RaiseError(L, "StudsPerTile must be a finite number greater than zero")
			return true
		}
		variant.studs_per_tile = value
		variant.tiling_dirty = true
		return true
	}
	if key == "Color" {
		if datatype_registry == nil {return false}
		color := datatypes.Arg_Color3(L, index, datatype_registry)
		variant.uniforms[0].values = {color.R, color.G, color.B, 1}
		variant.uniforms[0].count = 4
		variant.uniforms[0].optional = true
		variant.uniforms_dirty = true
		return true
	}
	if key == "Roughness" || key == "Metalness" {
		i := key == "Roughness" ? 1 : 2
		variant.uniforms[i].values[0] = clamp(f32(vm.ArgNumber(L, index)), 0, 1)
		variant.uniforms[i].count = 1
		variant.uniforms[i].optional = true
		variant.uniforms_dirty = true
		return true
	}
	return Runtime_Shader_Set(L, &variant.shader_state, key, index)
}

MaterialVariant_namecall :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	variant := cast(^MaterialVariant)object
	if method == "ResetShader" {
		delete(variant.vertex_source); variant.vertex_source = ""
		delete(variant.fragment_source); variant.fragment_source = ""
		for i in 3 ..< len(variant.uniforms) {delete(variant.uniforms[i].name)}
		resize(&variant.uniforms, 3)
		Runtime_Shader_Set_Source(&variant.shader_state, MATERIAL_VARIANT_SOURCE)
		return 0, true
	}
	return Runtime_Shader_Namecall(L, &variant.shader_state, method)
}

MaterialVariant_clone :: proc(source: ^Object, destination: ^Object) {
	src, dst := cast(^MaterialVariant)source, cast(^MaterialVariant)destination
	dst.enabled = src.enabled
	Runtime_Shader_Clone(&src.shader_state, &dst.shader_state)
	for path, i in src.maps {
		delete(dst.maps[i])
		dst.maps[i] = strings.clone(path)
	}
	dst.maps_dirty = {true, true, true, true, true, true, true}
	dst.maps_loaded = {}
	dst.studs_per_tile = src.studs_per_tile
	dst.tiling_dirty = true
	dst.height_scale = src.height_scale; dst.height_midlevel = src.height_midlevel
	dst.parallax_depth = src.parallax_depth; dst.parallax_steps = src.parallax_steps
	dst.normal_strength = src.normal_strength; dst.ao_strength = src.ao_strength
	dst.emissive_strength = src.emissive_strength; dst.emissive_color = src.emissive_color
	dst.displacement_subdivisions =
		src.displacement_subdivisions; dst.displacement_bounds = src.displacement_bounds
	delete(dst.vertex_source); dst.vertex_source = strings.clone(src.vertex_source)
	delete(dst.fragment_source); dst.fragment_source = strings.clone(src.fragment_source)
}

MaterialVariant_Number_Property :: proc(variant: ^MaterialVariant, key: string) -> ^f32 {
	switch key {
	case "HeightScale":
		return &variant.height_scale
	case "HeightMidlevel":
		return &variant.height_midlevel
	case "ParallaxDepth":
		return &variant.parallax_depth
	case "ParallaxSteps":
		return &variant.parallax_steps
	case "NormalStrength":
		return &variant.normal_strength
	case "AOStrength":
		return &variant.ao_strength
	case "EmissiveStrength":
		return &variant.emissive_strength
	case "DisplacementSubdivisions":
		return &variant.displacement_subdivisions
	case "DisplacementBounds":
		return &variant.displacement_bounds
	}
	return nil
}

MaterialVariant_Map_Index :: proc(key: string) -> int {
	switch key {
	case "ColorMap", "AlbedoMap":
		return 0
	case "NormalMap":
		return 1
	case "RoughnessMap":
		return 2
	case "MetalnessMap":
		return 3
	case "HeightMap":
		return 4
	case "AOMap", "AmbientOcclusionMap":
		return 5
	case "EmissiveMap":
		return 6
	}
	return -1
}

MATERIAL_VARIANT_SAMPLERS := [7]cstring {
	"colorMap",
	"normalMap",
	"roughnessMap",
	"metalnessMap",
	"heightMap",
	"aoMap",
	"emissiveMap",
}
MATERIAL_VARIANT_MAP_FLAGS := [7]cstring {
	"",
	"hasNormalMap",
	"hasRoughnessMap",
	"hasMetalnessMap",
	"hasHeightMap",
	"hasAOMap",
	"",
}

MATERIAL_VARIANT_VERTEX_HOOK :: "// MATERIAL_VARIANT_VERTEX_HOOK"
MATERIAL_VARIANT_FRAGMENT_HOOK :: "// MATERIAL_VARIANT_FRAGMENT_HOOK"

MaterialVariant_Hooked_Source :: proc(variant: ^MaterialVariant) -> (string, bool) {
	if (len(variant.vertex_source) > 0 &&
		   !strings.contains(variant.source, MATERIAL_VARIANT_VERTEX_HOOK)) ||
	   (len(variant.fragment_source) > 0 &&
			   !strings.contains(variant.source, MATERIAL_VARIANT_FRAGMENT_HOOK)) {
		Runtime_Shader_Error(
			&variant.shader_state,
			"Shader hooks need the default Source or matching hook markers; use ResetShader() to restore the textured shader",
		)
		variant.source_failed = true; variant.dirty = false
		return "", false
	}
	vertex, allocated := strings.replace_all(
		variant.source,
		MATERIAL_VARIANT_VERTEX_HOOK,
		variant.vertex_source,
	)
	defer if allocated {delete(vertex)}
	fragment, fragment_allocated := strings.replace_all(
		vertex,
		MATERIAL_VARIANT_FRAGMENT_HOOK,
		variant.fragment_source,
	)
	if fragment_allocated {return fragment, true}
	return strings.clone(fragment), true
}

MaterialVariant_Prepare :: proc(
	variant: ^MaterialVariant,
	filament: ^kineffi.KineFilamentContext,
) {
	override: string
	if variant.dirty &&
	   len(variant.source) > 0 &&
	   (len(variant.vertex_source) > 0 || len(variant.fragment_source) > 0) {
		generated, ok := MaterialVariant_Hooked_Source(variant)
		if ok {override = generated}
	}
	defer delete(override)
	changed := Runtime_Shader_Prepare(&variant.shader_state, filament, override)
	if variant.filament_shader == nil {return}
	if changed {
		for &loaded, i in variant.maps_loaded {
			loaded =
				loaded &&
				kineffi.Kine_Filament_Shader_HasTexture(
					variant.filament_shader,
					MATERIAL_VARIANT_SAMPLERS[i],
				)
			if !loaded {variant.maps_dirty[i] = true}
		}
		variant.tiling_dirty = true
	}
	maps_changed := changed
	for dirty, i in variant.maps_dirty {
		if !dirty {continue}
		maps_changed = true
		variant.maps_dirty[i] = false
		path := variant.maps[i]
		loaded := false
		if len(path) > 0 {
			when ODIN_OS != .JS {
				resolved := assetstore.Resolve_C_Path(path)
				defer delete(resolved)
				width, height, channels: i32
				pixels: [^]u8
				if resolved != nil {pixels = image.load(resolved, &width, &height, &channels, 4)}
				if pixels != nil {
					defer image.image_free(pixels)
					loaded = kineffi.Kine_Filament_Shader_SetTextureFromPixels(
						variant.filament_shader,
						MATERIAL_VARIANT_SAMPLERS[i],
						width,
						height,
						width * 4,
						pixels,
						i == 0 || i == 6,
					)
				} else if !variant.source_failed {
					Runtime_Shader_Error(
						&variant.shader_state,
						fmt.tprintf("Could not load material texture: %s", path),
					)
				}
			}
		}
		// Bind every declared sampler even without a map. A failed replacement
		// keeps its previous texture; a cleared slot gets a neutral fallback.
		if !loaded && (len(path) == 0 || !variant.maps_loaded[i]) {
			pixel := [4]u8{255, 255, 255, 255}
			if i == 1 {pixel = {128, 128, 255, 255}}
			if i == 4 {pixel = {128, 128, 128, 255}}
			if i == 6 {pixel = {0, 0, 0, 255}}
			kineffi.Kine_Filament_Shader_SetTextureFromPixels(
				variant.filament_shader,
				MATERIAL_VARIANT_SAMPLERS[i],
				1,
				1,
				4,
				&pixel[0],
				i == 0 || i == 6,
			)
			variant.maps_loaded[i] = false
		} else if loaded {variant.maps_loaded[i] = true}
		variant.revision += 1
	}
	if maps_changed {
		for i in 1 ..< 6 {
			flag := variant.maps_loaded[i] ? f32(1) : f32(0)
			kineffi.Kine_Filament_Shader_SetUniform(
				variant.filament_shader,
				MATERIAL_VARIANT_MAP_FLAGS[i],
				&flag,
				1,
			)
		}
	}
	if variant.tiling_dirty {
		variant.tiling_dirty = false
		kineffi.Kine_Filament_Shader_SetUniform(
			variant.filament_shader,
			"studsPerTile",
			&variant.studs_per_tile,
			1,
		)
		kineffi.Kine_Filament_Shader_SetUniform(
			variant.filament_shader,
			"heightScale",
			&variant.height_scale,
			1,
		)
		kineffi.Kine_Filament_Shader_SetUniform(
			variant.filament_shader,
			"heightMidlevel",
			&variant.height_midlevel,
			1,
		)
		kineffi.Kine_Filament_Shader_SetUniform(
			variant.filament_shader,
			"parallaxDepth",
			&variant.parallax_depth,
			1,
		)
		kineffi.Kine_Filament_Shader_SetUniform(
			variant.filament_shader,
			"parallaxSteps",
			&variant.parallax_steps,
			1,
		)
		kineffi.Kine_Filament_Shader_SetUniform(
			variant.filament_shader,
			"normalStrength",
			&variant.normal_strength,
			1,
		)
		kineffi.Kine_Filament_Shader_SetUniform(
			variant.filament_shader,
			"aoStrength",
			&variant.ao_strength,
			1,
		)
		kineffi.Kine_Filament_Shader_SetUniform(
			variant.filament_shader,
			"emissiveStrength",
			&variant.emissive_strength,
			1,
		)
		color := [3]f32 {
			variant.emissive_color.R,
			variant.emissive_color.G,
			variant.emissive_color.B,
		}
		kineffi.Kine_Filament_Shader_SetUniform(
			variant.filament_shader,
			"emissiveColor",
			&color[0],
			3,
		)
		padding := abs(variant.height_scale) + variant.displacement_bounds
		levels :=
			abs(variant.height_scale) > 0 || len(variant.vertex_source) > 0 ? i32(variant.displacement_subdivisions) : 0
		kineffi.Kine_Filament_Shader_SetGeometryOptions(variant.filament_shader, levels, padding)
		variant.revision += 1
	}
}

// Resolve at submission time so edits, renames, destruction and reparenting
// cannot leave cached native shader pointers in parts or terrain.
MaterialVariant_Resolve :: proc(
	registry: ^Registry,
	name: string,
	filament: ^kineffi.KineFilamentContext,
) -> (
	shader: ^kineffi.KineFilamentShader,
	revision: u64,
) {
	if len(name) == 0 || filament == nil {return}
	variant := MaterialVariant_Find(registry, name)
	if variant != nil {
		MaterialVariant_Prepare(variant, filament)
		return variant.filament_shader, variant.revision
	}
	return
}

MaterialVariant_Find :: proc(registry: ^Registry, name: string) -> ^MaterialVariant {
	if len(name) == 0 {return nil}
	descriptor := Find_Class(registry, "MaterialVariant")
	if descriptor == nil {return nil}
	for object in descriptor.instances {
		if object == nil ||
		   object.destroyed ||
		   object.parent == nil ||
		   object.name != name {continue}
		variant := cast(^MaterialVariant)object
		if !variant.enabled {continue}
		return variant
	}
	return nil
}

Register_MaterialVariant :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&MaterialVariant_Class,
		MaterialVariant_construct,
		MaterialVariant_destroy,
		get = MaterialVariant_get,
		set = MaterialVariant_set,
		clone = MaterialVariant_clone,
		namecall = MaterialVariant_namecall,
		properties = {
			"Source",
			"Enabled",
			"Color",
			"Roughness",
			"Metalness",
			"ColorMap",
			"AlbedoMap",
			"NormalMap",
			"RoughnessMap",
			"MetalnessMap",
			"StudsPerTile",
			"LastError",
			"Compiled",
			"HeightMap",
			"HeightScale",
			"HeightMidlevel",
			"DisplacementSubdivisions",
			"DisplacementBounds",
			"ParallaxDepth",
			"ParallaxSteps",
			"NormalStrength",
			"AOMap",
			"AmbientOcclusionMap",
			"AOStrength",
			"EmissiveMap",
			"EmissiveColor",
			"EmissiveStrength",
			"VertexSource",
			"FragmentSource",
		},
		methods = {"SetUniform", "GetUniform", "ResetShader"},
	)
}
