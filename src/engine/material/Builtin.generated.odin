package materialmanager

import kineffi "../bindings"
import enums "../enum"


builtin_material_configs := [enums.MATERIAL_COUNT]Material_Config {
	{
		material_kind = kineffi.KINE_MAT_DEFAULT,
		roughness = 0.35,
		metallic = 0,
		uv_scale = 1,
		height_scale = 0.005,
	},
	{
		material_kind = kineffi.KINE_MAT_DEFAULT,
		roughness = 0.72,
		metallic = 0,
		uv_scale = 1,
		height_scale = 0.025,
	},
	{
		material_kind = kineffi.KINE_MAT_DEFAULT,
		roughness = 0.8,
		metallic = 0,
		uv_scale = 1,
		height_scale = 0.055,
	},
	{
		material_kind = kineffi.KINE_MAT_DEFAULT,
		roughness = 0.92,
		metallic = 0,
		uv_scale = 1,
		height_scale = 0.025,
	},
	{
		material_kind = kineffi.KINE_MAT_DEFAULT,
		roughness = 0.85,
		metallic = 0,
		uv_scale = 1,
		height_scale = 0.02,
	},
	{
		material_kind = kineffi.KINE_MAT_DEFAULT,
		roughness = 0.72,
		metallic = 0,
		uv_scale = 1,
		height_scale = 0.02,
	},
	{
		material_kind = kineffi.KINE_MAT_GLASS,
		roughness = 0.08,
		metallic = 0,
		uv_scale = 1,
		height_scale = 0.02,
		ior = 1.5,
		thickness = 0.08,
		transmission = 0.92,
	},
	{
		material_kind = kineffi.KINE_MAT_NEON,
		roughness = 0,
		metallic = 0,
		uv_scale = 1,
		height_scale = 0.02,
		emissive_intensity = 6,
	},
	{
		material_kind = kineffi.KINE_MAT_DEFAULT,
		roughness = 0.95,
		metallic = 0,
		uv_scale = 1,
		height_scale = 0.018,
	},
	{
		material_kind = kineffi.KINE_MAT_WATER,
		roughness = 0.08,
		metallic = 0,
		uv_scale = 1,
		height_scale = 0.02,
		ior = 1.333,
		thickness = 0.12,
		transmission = 0.88,
	},
	{
		material_kind = kineffi.KINE_MAT_DEFAULT,
		roughness = 0.55,
		metallic = 0,
		uv_scale = 1,
		height_scale = 0.02,
	},
	{
		material_kind = kineffi.KINE_MAT_DEFAULT,
		roughness = 0.9,
		metallic = 0,
		uv_scale = 1,
		height_scale = 0.02,
	},
	{
		material_kind = kineffi.KINE_MAT_DEFAULT,
		roughness = 0.3,
		metallic = 0,
		uv_scale = 1,
		height_scale = 0,
	},
	{
		material_kind = kineffi.KINE_MAT_DEFAULT,
		roughness = 0.8,
		metallic = 0,
		uv_scale = 1,
		height_scale = 0.025,
	},
	{
		material_kind = kineffi.KINE_MAT_DEFAULT,
		roughness = 0.3,
		metallic = 0,
		uv_scale = 1,
		height_scale = 0,
	},
	{
		material_kind = kineffi.KINE_MAT_DEFAULT,
		roughness = 0.9,
		metallic = 0,
		uv_scale = 1,
		height_scale = 0.02,
	},
	{
		material_kind = kineffi.KINE_MAT_DEFAULT,
		roughness = 0.9,
		metallic = 0,
		uv_scale = 1,
		height_scale = 0.045,
	},
	{
		material_kind = kineffi.KINE_MAT_DEFAULT,
		roughness = 0.9,
		metallic = 0,
		uv_scale = 1,
		height_scale = 0.02,
	},
	{
		material_kind = kineffi.KINE_MAT_DEFAULT,
		roughness = 0.45,
		metallic = 0,
		uv_scale = 1,
		height_scale = 0.02,
	},
	{
		material_kind = kineffi.KINE_MAT_DEFAULT,
		roughness = 0.9,
		metallic = 0,
		uv_scale = 1,
		height_scale = 0.045,
	},
	{
		material_kind = kineffi.KINE_MAT_DEFAULT,
		roughness = 0.9,
		metallic = 0,
		uv_scale = 1,
		height_scale = 0.04,
	},
	{
		material_kind = kineffi.KINE_MAT_DEFAULT,
		roughness = 0.9,
		metallic = 0,
		uv_scale = 1,
		height_scale = 0.065,
	},
	{
		material_kind = kineffi.KINE_MAT_DEFAULT,
		roughness = 0.9,
		metallic = 0,
		uv_scale = 1,
		height_scale = 0.02,
	},
	{
		material_kind = kineffi.KINE_MAT_DEFAULT,
		roughness = 0.9,
		metallic = 0,
		uv_scale = 1,
		height_scale = 0.02,
	},
	{
		material_kind = kineffi.KINE_MAT_DEFAULT,
		roughness = 0.85,
		metallic = 1,
		uv_scale = 1,
		height_scale = 0.02,
	},
	{
		material_kind = kineffi.KINE_MAT_DEFAULT,
		roughness = 0.5,
		metallic = 1,
		uv_scale = 1,
		height_scale = 0.035,
	},
	{
		material_kind = kineffi.KINE_MAT_DEFAULT,
		roughness = 0.35,
		metallic = 1,
		uv_scale = 1,
		height_scale = 0.02,
	},
	{
		material_kind = kineffi.KINE_MAT_DEFAULT,
		roughness = 0.3,
		metallic = 1,
		uv_scale = 1,
		height_scale = 0.02,
	},
	{
		material_kind = kineffi.KINE_MAT_DEFAULT,
		roughness = 0.9,
		metallic = 0,
		uv_scale = 1,
		height_scale = 0.02,
	},
	{
		material_kind = kineffi.KINE_MAT_DEFAULT,
		roughness = 1,
		metallic = 0,
		uv_scale = 1,
		height_scale = 0.02,
	},
	{
		material_kind = kineffi.KINE_MAT_DEFAULT,
		roughness = 0.9,
		metallic = 0,
		uv_scale = 1,
		height_scale = 0.02,
	},
	{
		material_kind = kineffi.KINE_MAT_DEFAULT,
		roughness = 0.9,
		metallic = 0,
		uv_scale = 1,
		height_scale = 0.02,
	},
	{
		material_kind = kineffi.KINE_MAT_DEFAULT,
		roughness = 0.9,
		metallic = 0,
		uv_scale = 1,
		height_scale = 0.02,
	},
	{
		material_kind = kineffi.KINE_MAT_DEFAULT,
		roughness = 0.9,
		metallic = 0,
		uv_scale = 1,
		height_scale = 0.02,
	},
	{
		material_kind = kineffi.KINE_MAT_DEFAULT,
		roughness = 0.9,
		metallic = 0,
		uv_scale = 1,
		height_scale = 0.02,
	},
	{
		material_kind = kineffi.KINE_MAT_DEFAULT,
		roughness = 0.2,
		metallic = 0,
		uv_scale = 1,
		height_scale = 0.01,
	},
	{
		material_kind = kineffi.KINE_MAT_DEFAULT,
		roughness = 0.45,
		metallic = 0,
		uv_scale = 1,
		height_scale = 0.02,
	},
	{
		material_kind = kineffi.KINE_MAT_FORCEFIELD,
		roughness = 0.08,
		metallic = 0,
		uv_scale = 1,
		height_scale = 0.02,
	},
	{
		material_kind = kineffi.KINE_MAT_DEFAULT,
		roughness = 0.9,
		metallic = 0,
		uv_scale = 1,
		height_scale = 0.012,
	},
	{
		material_kind = kineffi.KINE_MAT_DEFAULT,
		roughness = 1,
		metallic = 0,
		uv_scale = 1,
		height_scale = 0.02,
	},
	{
		material_kind = kineffi.KINE_MAT_DEFAULT,
		roughness = 0.4,
		metallic = 0,
		uv_scale = 1,
		height_scale = 0.02,
	},
	{
		material_kind = kineffi.KINE_MAT_DEFAULT,
		roughness = 0.9,
		metallic = 0,
		uv_scale = 1,
		height_scale = 0.07,
	},
	{
		material_kind = kineffi.KINE_MAT_DEFAULT,
		roughness = 0.9,
		metallic = 0,
		uv_scale = 1,
		height_scale = 0.025,
	},
	{
		material_kind = kineffi.KINE_MAT_DEFAULT,
		roughness = 0.65,
		metallic = 0,
		uv_scale = 1,
		height_scale = 0.02,
	},
	{
		material_kind = kineffi.KINE_MAT_DEFAULT,
		roughness = 0.9,
		metallic = 0,
		uv_scale = 1,
		height_scale = 0.02,
	},
	{
		material_kind = kineffi.KINE_MAT_DEFAULT,
		roughness = 0.95,
		metallic = 0,
		uv_scale = 1,
		height_scale = 0.02,
	},
}
builtin_material_texture :: proc(
	material: enums.Material,
	height_scale: f32,
) -> ^kineffi.KineFilamentTex {
	#partial switch material {
	case .SmoothPlastic:
		return create_pbr_texture(
			#load_directory("../assets/materials/compressed/smoothplastic"),
			active_renderer,
			height_scale,
		)
	case .Wood:
		return create_pbr_texture(
			#load_directory("../assets/materials/compressed/wood"),
			active_renderer,
			height_scale,
		)
	case .Brick:
		return create_pbr_texture(
			#load_directory("../assets/materials/compressed/brick"),
			active_renderer,
			height_scale,
		)
	case .Grass:
		return create_pbr_texture(
			#load_directory("../assets/materials/compressed/grass"),
			active_renderer,
			height_scale,
		)
	case .Concrete:
		return create_pbr_texture(
			#load_directory("../assets/materials/compressed/concrete"),
			active_renderer,
			height_scale,
		)
	case .Slate:
		return create_pbr_texture(
			#load_directory("../assets/materials/compressed/slate"),
			active_renderer,
			height_scale,
		)
	case .Sand:
		return create_pbr_texture(
			#load_directory("../assets/materials/compressed/sand"),
			active_renderer,
			height_scale,
		)
	case .debug:
		return create_pbr_texture(
			#load_directory("../assets/materials/compressed/debug"),
			active_renderer,
			height_scale,
		)
	case .Plastic:
		return create_pbr_texture(
			#load_directory("../assets/materials/compressed/plastic"),
			active_renderer,
			height_scale,
		)
	case .WoodPlanks:
		return create_pbr_texture(
			#load_directory("../assets/materials/compressed/woodplanks"),
			active_renderer,
			height_scale,
		)
	case .Marble:
		return create_pbr_texture(
			#load_directory("../assets/materials/compressed/marble"),
			active_renderer,
			height_scale,
		)
	case .Basalt:
		return create_pbr_texture(
			#load_directory("../assets/materials/compressed/basalt"),
			active_renderer,
			height_scale,
		)
	case .CrackedLava:
		return create_pbr_texture(
			#load_directory("../assets/materials/compressed/crackedlava"),
			active_renderer,
			height_scale,
		)
	case .Limestone:
		return create_pbr_texture(
			#load_directory("../assets/materials/compressed/limestone"),
			active_renderer,
			height_scale,
		)
	case .Granite:
		return create_pbr_texture(
			#load_directory("../assets/materials/compressed/granite"),
			active_renderer,
			height_scale,
		)
	case .Pavement:
		return create_pbr_texture(
			#load_directory("../assets/materials/compressed/pavement"),
			active_renderer,
			height_scale,
		)
	case .Pebble:
		return create_pbr_texture(
			#load_directory("../assets/materials/compressed/pebble"),
			active_renderer,
			height_scale,
		)
	case .Cobblestone:
		return create_pbr_texture(
			#load_directory("../assets/materials/compressed/cobblestone"),
			active_renderer,
			height_scale,
		)
	case .Rock:
		return create_pbr_texture(
			#load_directory("../assets/materials/compressed/rock"),
			active_renderer,
			height_scale,
		)
	case .Sandstone:
		return create_pbr_texture(
			#load_directory("../assets/materials/compressed/sandstone"),
			active_renderer,
			height_scale,
		)
	case .CorrodedMetal:
		return create_pbr_texture(
			#load_directory("../assets/materials/compressed/corrodedmetal"),
			active_renderer,
			height_scale,
		)
	case .DiamondPlate:
		return create_pbr_texture(
			#load_directory("../assets/materials/compressed/diamondplate"),
			active_renderer,
			height_scale,
		)
	case .Foil:
		return create_pbr_texture(
			#load_directory("../assets/materials/compressed/foil"),
			active_renderer,
			height_scale,
		)
	case .Metal:
		return create_pbr_texture(
			#load_directory("../assets/materials/compressed/metal"),
			active_renderer,
			height_scale,
		)
	case .LeafyGrass:
		return create_pbr_texture(
			#load_directory("../assets/materials/compressed/leafygrass"),
			active_renderer,
			height_scale,
		)
	case .Fabric:
		return create_pbr_texture(
			#load_directory("../assets/materials/compressed/fabric"),
			active_renderer,
			height_scale,
		)
	case .Snow:
		return create_pbr_texture(
			#load_directory("../assets/materials/compressed/snow"),
			active_renderer,
			height_scale,
		)
	case .Mud:
		return create_pbr_texture(
			#load_directory("../assets/materials/compressed/mud"),
			active_renderer,
			height_scale,
		)
	case .Ground:
		return create_pbr_texture(
			#load_directory("../assets/materials/compressed/ground"),
			active_renderer,
			height_scale,
		)
	case .Asphalt:
		return create_pbr_texture(
			#load_directory("../assets/materials/compressed/asphalt"),
			active_renderer,
			height_scale,
		)
	case .Salt:
		return create_pbr_texture(
			#load_directory("../assets/materials/compressed/salt"),
			active_renderer,
			height_scale,
		)
	case .Ice:
		return create_pbr_texture(
			#load_directory("../assets/materials/compressed/ice"),
			active_renderer,
			height_scale,
		)
	case .Glacier:
		return create_pbr_texture(
			#load_directory("../assets/materials/compressed/glacier"),
			active_renderer,
			height_scale,
		)
	case .Cardboard:
		return create_pbr_texture(
			#load_directory("../assets/materials/compressed/cardboard"),
			active_renderer,
			height_scale,
		)
	case .Carpet:
		return create_pbr_texture(
			#load_directory("../assets/materials/compressed/carpet"),
			active_renderer,
			height_scale,
		)
	case .CeramicTiles:
		return create_pbr_texture(
			#load_directory("../assets/materials/compressed/ceramictiles"),
			active_renderer,
			height_scale,
		)
	case .ClayRoofTiles:
		return create_pbr_texture(
			#load_directory("../assets/materials/compressed/clayrooftiles"),
			active_renderer,
			height_scale,
		)
	case .RoofShingles:
		return create_pbr_texture(
			#load_directory("../assets/materials/compressed/roofshingles"),
			active_renderer,
			height_scale,
		)
	case .Leather:
		return create_pbr_texture(
			#load_directory("../assets/materials/compressed/leather"),
			active_renderer,
			height_scale,
		)
	case .Plaster:
		return create_pbr_texture(
			#load_directory("../assets/materials/compressed/plaster"),
			active_renderer,
			height_scale,
		)
	case .Rubber:
		return create_pbr_texture(
			#load_directory("../assets/materials/compressed/rubber"),
			active_renderer,
			height_scale,
		)
	}
	return nil
}
