package materialmanager

import "base:runtime"
import enums "../enum"
import kineffi "../bindings"
import renderer "../renderer"
import "vendor:stb/image"

MATERIAL_COUNT :: 11

Decoded_Image :: struct {
	width:  i32,
	height: i32,
	pixels: [^]u8,
}

Material :: struct {
	texture: ^kineffi.KineFilamentTex,
	loaded:  bool,

	material_kind: i32,
	roughness:     f32,
	metallic:      f32,
	uv_scale:      f32,
	height_scale:  f32,

	ior:                f32,
	thickness:          f32,
	transmission:       f32,
	emissive_intensity: f32,
}

Material_Config :: struct {
	material_kind: i32,
	roughness:     f32,
	metallic:      f32,
	uv_scale:      f32,
	height_scale:  f32,

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
	pixels := image.load_from_memory(
		raw_data(data),
		i32(len(data)),
		&width,
		&height,
		&channels,
		4,
	)

	if pixels == nil {
		return Decoded_Image{}
	}

	return Decoded_Image{
		width = width,
		height = height,
		pixels = pixels,
	}
}

destroy_decoded_image :: proc(decoded: ^Decoded_Image) {
	if decoded == nil || decoded.pixels == nil {
		return
	}
	image.image_free(decoded.pixels)
	decoded^ = Decoded_Image{}
}

material_from_config :: proc(config: Material_Config) -> Material {
	return Material{
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
		albedo.width*4,
		albedo.pixels,
		normal.width,
		normal.height,
		normal.width*4,
		normal.pixels,
		orm.width,
		orm.height,
		orm.width*4,
		orm.pixels,
		height.width,
		height.height,
		height.width*4,
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
}

load_texture :: proc(material: enums.Material, entry: ^Material) {
	if entry == nil || entry.loaded {
		return
	}

	switch material {
	case .Glass, .Neon, .Water:
		entry.loaded = true
		return
	case .SmoothPlastic:
		entry.texture = create_pbr_texture(
			#load_directory("../assets/materials/compressed/smoothplastic"),
			active_renderer,
			entry.height_scale,
		)
	case .Wood:
		entry.texture = create_pbr_texture(
			#load_directory("../assets/materials/compressed/wood"),
			active_renderer,
			entry.height_scale,
		)
	case .Brick:
		entry.texture = create_pbr_texture(
			#load_directory("../assets/materials/compressed/brick"),
			active_renderer,
			entry.height_scale,
		)
	case .Grass:
		entry.texture = create_pbr_texture(
			#load_directory("../assets/materials/compressed/grass"),
			active_renderer,
			entry.height_scale,
		)
	case .Concrete:
		entry.texture = create_pbr_texture(
			#load_directory("../assets/materials/compressed/concrete"),
			active_renderer,
			entry.height_scale,
		)
	case .Slate:
		entry.texture = create_pbr_texture(
			#load_directory("../assets/materials/compressed/slate"),
			active_renderer,
			entry.height_scale,
		)
	case .Sand:
		entry.texture = create_pbr_texture(
			#load_directory("../assets/materials/compressed/sand"),
			active_renderer,
			entry.height_scale,
		)
	case .debug:
		entry.texture = create_pbr_texture(
			#load_directory("../assets/materials/compressed/debug"),
			active_renderer,
			entry.height_scale,
		)
	}

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

Draw_Parameters :: proc(material: ^Material) -> (
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
		return material.material_kind,
		       material.emissive_intensity,
		       0,
		       0,
		       0
	case:
		return material.material_kind,
		       material.roughness,
		       material.metallic,
		       material.uv_scale,
		       0
	}
}

init :: proc(renderer_object: ^renderer.RendererObject) {
	if renderer_object == nil || renderer_object.Filament == nil {
		return
	}

	active_renderer = renderer_object
	if initialized {
		return
	}

	set_material(.SmoothPlastic, Material_Config{
		material_kind = kineffi.KINE_MAT_DEFAULT,
		roughness = 0.35,
		metallic = 0,
		uv_scale = 1,
		height_scale = 0.005,
	})
	set_material(.Wood, Material_Config{
		material_kind = kineffi.KINE_MAT_DEFAULT,
		roughness = 0.72,
		metallic = 0,
		uv_scale = 1,
		height_scale = 0.025,
	})
	set_material(.Brick, Material_Config{
		material_kind = kineffi.KINE_MAT_DEFAULT,
		roughness = 0.80,
		metallic = 0,
		uv_scale = 1,
		height_scale = 0.055,
	})
	set_material(.Grass, Material_Config{
		material_kind = kineffi.KINE_MAT_DEFAULT,
		roughness = 0.92,
		metallic = 0,
		uv_scale = 1,
		height_scale = 0.025,
	})
	set_material(.Concrete, Material_Config{
		material_kind = kineffi.KINE_MAT_DEFAULT,
		roughness = 0.85,
		metallic = 0,
		uv_scale = 1,
		height_scale = 0.020,
	})
	set_material(.Slate, Material_Config{
		material_kind = kineffi.KINE_MAT_DEFAULT,
		roughness = 0.72,
		metallic = 0,
		uv_scale = 1,
		height_scale = 0.020,
	})
	set_material(.Glass, Material_Config{
		material_kind = kineffi.KINE_MAT_GLASS,
		roughness = 0.08,
		ior = 1.50,
		thickness = 0.08,
		transmission = 0.92,
		uv_scale = 1,
	})
	set_material(.Neon, Material_Config{
		material_kind = kineffi.KINE_MAT_NEON,
		emissive_intensity = 6,
		uv_scale = 1,
	})
	set_material(.Sand, Material_Config{
		material_kind = kineffi.KINE_MAT_DEFAULT,
		roughness = 0.95,
		metallic = 0,
		uv_scale = 1,
		height_scale = 0.018,
	})
	set_material(.Water, Material_Config{
		material_kind = kineffi.KINE_MAT_WATER,
		roughness = 0.08,
		ior = 1.333,
		thickness = 0.12,
		transmission = 0.88,
		uv_scale = 1,
	})
	set_material(.debug, Material_Config{
		material_kind = kineffi.KINE_MAT_DEFAULT,
		roughness = 0.55,
		metallic = 0,
		uv_scale = 1,
		height_scale = 0,
	})

	initialized = true
}

shutdown :: proc(renderer_object: ^renderer.RendererObject) {
	if !initialized {
		return
	}

	if renderer_object != nil && renderer_object.Filament != nil {
		for index in 0..<MATERIAL_COUNT {
			entry := &materials[index]
			if entry.texture != nil {
				_ = kineffi.Kine_Filament_DestroyTex(
					renderer_object.Filament,
					entry.texture,
				)
				entry.texture = nil
			}
		}
	}

	materials = [MATERIAL_COUNT]Material{}
	active_renderer = nil
	initialized = false
}
