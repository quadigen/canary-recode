package materialmanager

import kineffi "../bindings"
import enums "../enum"
import renderer "../renderer"
import tracy "../util/odin-tracy"
import "base:runtime"
import "core:thread"
import "vendor:stb/image"

MATERIAL_COUNT :: enums.MATERIAL_COUNT

Decoded_Image :: struct {
	width:  i32,
	height: i32,
	pixels: [^]u8,
}

Texture_Decode :: struct {
	files: []runtime.Load_Directory_File,
	albedo, normal, orm, height: Decoded_Image,
}

Material :: struct {
	texture:            ^kineffi.KineFilamentTex,
	loaded:             bool,
	decode_worker:      ^thread.Thread,
	material_kind:      i32,
	roughness:          f32,
	metallic:           f32,
	uv_scale:           f32,
	height_scale:       f32,
	ior:                f32,
	thickness:          f32,
	transmission:       f32,
	emissive_intensity: f32,
}

Material_Config :: struct {
	material_kind:      i32,
	roughness:          f32,
	metallic:           f32,
	uv_scale:           f32,
	height_scale:       f32,
	ior:                f32,
	thickness:          f32,
	transmission:       f32,
	emissive_intensity: f32,
}

materials: [MATERIAL_COUNT]Material
active_renderer: ^renderer.RendererObject
initialized: bool
texture_workers: int
MAX_TEXTURE_WORKERS :: 3

decode_image :: proc(data: []u8) -> Decoded_Image {
	if len(data) == 0 {
		return Decoded_Image{}
	}

	width, height, channels: i32
	pixels := image.load_from_memory(raw_data(data), i32(len(data)), &width, &height, &channels, 4)

	if pixels == nil {
		return Decoded_Image{}
	}

	return Decoded_Image{width = width, height = height, pixels = pixels}
}

destroy_decoded_image :: proc(decoded: ^Decoded_Image) {
	if decoded == nil || decoded.pixels == nil {
		return
	}
	image.image_free(decoded.pixels)
	decoded^ = Decoded_Image{}
}

material_from_config :: proc(config: Material_Config) -> Material {
	return Material {
		material_kind = config.material_kind,
		roughness = config.roughness,
		metallic = config.metallic,
		uv_scale = config.uv_scale,
		height_scale = config.height_scale,
		ior = config.ior,
		thickness = config.thickness,
		transmission = config.transmission,
		emissive_intensity = config.emissive_intensity,
	}
}

decode_pbr_texture :: proc(result: ^Texture_Decode) {
	tracy.ZoneNC("Builtin Material Texture Decode", 0xB48EAD)
	for file in result.files {
		switch file.name {
		case "albedo.png", "albedo.jpg", "albedo.jpeg":
			destroy_decoded_image(&result.albedo)
			result.albedo = decode_image(file.data)
		case "normal.png", "normal.jpg", "normal.jpeg":
			destroy_decoded_image(&result.normal)
			result.normal = decode_image(file.data)
		case "orm.png", "orm.jpg", "orm.jpeg":
			destroy_decoded_image(&result.orm)
			result.orm = decode_image(file.data)
		case "height.png", "height.jpg", "height.jpeg":
			destroy_decoded_image(&result.height)
			result.height = decode_image(file.data)
		}
	}
}

texture_decode_worker :: proc(worker: ^thread.Thread) {
	decode_pbr_texture(cast(^Texture_Decode)worker.data)
}

destroy_texture_decode :: proc(result: ^Texture_Decode) {
	destroy_decoded_image(&result.albedo)
	destroy_decoded_image(&result.normal)
	destroy_decoded_image(&result.orm)
	destroy_decoded_image(&result.height)
	free(result)
}

publish_pbr_texture :: proc(entry: ^Material, result: ^Texture_Decode) {
	tracy.ZoneNC("Builtin Material Texture Upload", 0xB48EAD)
	entry.loaded = true
	defer destroy_texture_decode(result)
	if active_renderer == nil || active_renderer.Filament == nil || result.albedo.pixels == nil {return}

	entry.texture = kineffi.Kine_Filament_CreatePbrTexFromPixels(
		active_renderer.Filament,
		result.albedo.width, result.albedo.height, result.albedo.width * 4, result.albedo.pixels,
		result.normal.width, result.normal.height, result.normal.width * 4, result.normal.pixels,
		result.orm.width, result.orm.height, result.orm.width * 4, result.orm.pixels,
		result.height.width, result.height.height, result.height.width * 4, result.height.pixels,
		entry.height_scale,
	)
}

take_texture_decode :: proc(entry: ^Material) -> ^Texture_Decode {
	worker := entry.decode_worker
	thread.join(worker)
	result := cast(^Texture_Decode)worker.data
	thread.destroy(worker)
	entry.decode_worker = nil
	texture_workers -= 1
	return result
}

set_material :: proc(material: enums.Material, config: Material_Config) {
	index := int(material)
	if index < 0 || index >= MATERIAL_COUNT {
		return
	}
	materials[index] = material_from_config(config)
	draw_params_valid[index] = false
}

load_texture :: proc(material: enums.Material, entry: ^Material) {
	if entry.loaded || entry.decode_worker != nil || active_renderer == nil {return}
	files := builtin_material_files(material)
	if len(files) == 0 {entry.loaded = true; return}
	if texture_workers >= MAX_TEXTURE_WORKERS {return}

	result := new(Texture_Decode)
	result.files = files
	if worker := thread.create(texture_decode_worker); worker != nil {
		entry.decode_worker = worker
		texture_workers += 1
		worker.data = result
		thread.start(worker)
		return
	}
	decode_pbr_texture(result)
	publish_pbr_texture(entry, result)
}

Get :: proc(material: enums.Material) -> ^Material {
	resolved_material := material
	index := int(resolved_material)

	if index < 0 || index >= MATERIAL_COUNT {
		resolved_material = enums.Material.SmoothPlastic
		index = int(resolved_material)
	}

	entry := &materials[index]
	load_texture(resolved_material, entry)
	return entry
}

Draw_Parameters :: proc(
	material: ^Material,
) -> (
	material_kind: i32,
	param1: f32,
	param2: f32,
	param3: f32,
	transmission: f32,
) {
	if material == nil {
		return kineffi.KINE_MAT_DEFAULT, 0.35, 0, 1, 0
	}

	switch material.material_kind {
	case kineffi.KINE_MAT_GLASS, kineffi.KINE_MAT_WATER:
		return material.material_kind,
			material.roughness,
			material.ior,
			material.thickness,
			material.transmission
	case kineffi.KINE_MAT_NEON:
		return material.material_kind, material.emissive_intensity, 0, 0, 0
	case:
		return material.material_kind, material.roughness, material.metallic, material.uv_scale, 0
	}
}


Draw_Params :: struct {
	kind:         i32,
	param1:       f32,
	param2:       f32,
	param3:       f32,
	transmission: f32,
}

draw_params_cache: [MATERIAL_COUNT]Draw_Params
draw_params_valid: [MATERIAL_COUNT]bool


Lookup :: proc(material: enums.Material) -> (^Material, Draw_Params) {
	index := int(material)
	if index < 0 || index >= MATERIAL_COUNT {
		index = int(enums.Material.SmoothPlastic)
	}

	entry := Get(enums.Material(index))
	if !draw_params_valid[index] {
		kind, param1, param2, param3, transmission := Draw_Parameters(entry)
		draw_params_cache[index] = Draw_Params{kind, param1, param2, param3, transmission}
		draw_params_valid[index] = true
	}

	return &materials[index], draw_params_cache[index]
}

init :: proc(renderer_object: ^renderer.RendererObject) {
	if renderer_object == nil || renderer_object.Filament == nil {
		return
	}

	active_renderer = renderer_object
	if initialized {
		for &entry in materials {
			if entry.decode_worker != nil && thread.is_done(entry.decode_worker) {
				publish_pbr_texture(&entry, take_texture_decode(&entry))
				break
			}
		}
		return
	}

	for config, index in builtin_material_configs {set_material(enums.Material(index), config)}

	initialized = true
}

shutdown :: proc(renderer_object: ^renderer.RendererObject) {
	if !initialized {
		return
	}

	for &entry in materials {
		if entry.decode_worker != nil {destroy_texture_decode(take_texture_decode(&entry))}
	}

	if renderer_object != nil && renderer_object.Filament != nil {
		for index in 0 ..< MATERIAL_COUNT {
			entry := &materials[index]
			if entry.texture != nil {
				_ = kineffi.Kine_Filament_DestroyTex(renderer_object.Filament, entry.texture)
				entry.texture = nil
			}
		}
	}

	materials = [MATERIAL_COUNT]Material{}
	draw_params_valid = [MATERIAL_COUNT]bool{}
	active_renderer = nil
	initialized = false
}
