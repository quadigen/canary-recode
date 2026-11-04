package materialmanager

import kineffi "../bindings"
import enums "../enum"
import "base:runtime"


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
builtin_material_files :: proc(material: enums.Material) -> []runtime.Load_Directory_File {
	#partial switch material {
	case .SmoothPlastic:
		return #load_directory("../assets/materials/compressed/smoothplastic")
	case .Wood:
		return #load_directory("../assets/materials/compressed/wood")
	case .Brick:
		return #load_directory("../assets/materials/compressed/brick")
	case .Grass:
		return #load_directory("../assets/materials/compressed/grass")
	case .Concrete:
		return #load_directory("../assets/materials/compressed/concrete")
	case .Slate:
		return #load_directory("../assets/materials/compressed/slate")
	case .Sand:
		return #load_directory("../assets/materials/compressed/sand")
	case .debug:
		return #load_directory("../assets/materials/compressed/debug")
	case .Plastic:
		return #load_directory("../assets/materials/compressed/plastic")
	case .WoodPlanks:
		return #load_directory("../assets/materials/compressed/woodplanks")
	case .Marble:
		return #load_directory("../assets/materials/compressed/marble")
	case .Basalt:
		return #load_directory("../assets/materials/compressed/basalt")
	case .CrackedLava:
		return #load_directory("../assets/materials/compressed/crackedlava")
	case .Limestone:
		return #load_directory("../assets/materials/compressed/limestone")
	case .Granite:
		return #load_directory("../assets/materials/compressed/granite")
	case .Pavement:
		return #load_directory("../assets/materials/compressed/pavement")
	case .Pebble:
		return #load_directory("../assets/materials/compressed/pebble")
	case .Cobblestone:
		return #load_directory("../assets/materials/compressed/cobblestone")
	case .Rock:
		return #load_directory("../assets/materials/compressed/rock")
	case .Sandstone:
		return #load_directory("../assets/materials/compressed/sandstone")
	case .CorrodedMetal:
		return #load_directory("../assets/materials/compressed/corrodedmetal")
	case .DiamondPlate:
		return #load_directory("../assets/materials/compressed/diamondplate")
	case .Foil:
		return #load_directory("../assets/materials/compressed/foil")
	case .Metal:
		return #load_directory("../assets/materials/compressed/metal")
	case .LeafyGrass:
		return #load_directory("../assets/materials/compressed/leafygrass")
	case .Fabric:
		return #load_directory("../assets/materials/compressed/fabric")
	case .Snow:
		return #load_directory("../assets/materials/compressed/snow")
	case .Mud:
		return #load_directory("../assets/materials/compressed/mud")
	case .Ground:
		return #load_directory("../assets/materials/compressed/ground")
	case .Asphalt:
		return #load_directory("../assets/materials/compressed/asphalt")
	case .Salt:
		return #load_directory("../assets/materials/compressed/salt")
	case .Ice:
		return #load_directory("../assets/materials/compressed/ice")
	case .Glacier:
		return #load_directory("../assets/materials/compressed/glacier")
	case .Cardboard:
		return #load_directory("../assets/materials/compressed/cardboard")
	case .Carpet:
		return #load_directory("../assets/materials/compressed/carpet")
	case .CeramicTiles:
		return #load_directory("../assets/materials/compressed/ceramictiles")
	case .ClayRoofTiles:
		return #load_directory("../assets/materials/compressed/clayrooftiles")
	case .RoofShingles:
		return #load_directory("../assets/materials/compressed/roofshingles")
	case .Leather:
		return #load_directory("../assets/materials/compressed/leather")
	case .Plaster:
		return #load_directory("../assets/materials/compressed/plaster")
	case .Rubber:
		return #load_directory("../assets/materials/compressed/rubber")
	}
	return nil
}
