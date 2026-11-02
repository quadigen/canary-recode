package materialmanager

import kineffi "../bindings"
import enums "../enum"
import renderer "../renderer"
import "base:runtime"
import "vendor:stb/image"

MATERIAL_COUNT :: enums.MATERIAL_COUNT

Decoded_Image :: struct {
	width:  i32,
	height: i32,
	pixels: [^]u8,
}

Material :: struct {
	texture:            ^kineffi.KineFilamentTex,
	loaded:             bool,
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

create_pbr_texture :: proc(
	loaded: []runtime.Load_Directory_File,
	renderer_object: ^renderer.RendererObject,
	height_scale: f32,
) -> ^kineffi.KineFilamentTex {
	if renderer_object == nil || renderer_object.Filament == nil {
		return nil
	}

	albedo: Decoded_Image
	normal: Decoded_Image
	orm: Decoded_Image
	height: Decoded_Image

	for file in loaded {
		switch file.name {
		case "albedo.png", "albedo.jpg", "albedo.jpeg":
			destroy_decoded_image(&albedo)
			albedo = decode_image(file.data)
		case "normal.png", "normal.jpg", "normal.jpeg":
			destroy_decoded_image(&normal)
			normal = decode_image(file.data)
		case "orm.png", "orm.jpg", "orm.jpeg":
			destroy_decoded_image(&orm)
			orm = decode_image(file.data)
		case "height.png", "height.jpg", "height.jpeg":
			destroy_decoded_image(&height)
			height = decode_image(file.data)
		}
	}

	defer destroy_decoded_image(&albedo)
	defer destroy_decoded_image(&normal)
	defer destroy_decoded_image(&orm)
	defer destroy_decoded_image(&height)

	if albedo.pixels == nil {
		return nil
	}

	return kineffi.Kine_Filament_CreatePbrTexFromPixels(
		renderer_object.Filament,
		albedo.width,
		albedo.height,
		albedo.width * 4,
		albedo.pixels,
		normal.width,
		normal.height,
		normal.width * 4,
		normal.pixels,
		orm.width,
		orm.height,
		orm.width * 4,
		orm.pixels,
		height.width,
		height.height,
		height.width * 4,
		height.pixels,
		height_scale,
	)
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
	if entry == nil || entry.loaded {
		return
	}

	entry.texture = builtin_material_texture(material, entry.height_scale)

	entry.loaded = true
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

	if !draw_params_valid[index] {
		entry := Get(enums.Material(index))
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
		return
	}

	for config, index in builtin_material_configs {set_material(enums.Material(index), config)}

	initialized = true
}

shutdown :: proc(renderer_object: ^renderer.RendererObject) {
	if !initialized {
		return
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
