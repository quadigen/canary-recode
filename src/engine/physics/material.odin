package physics

import enums "../enum"

Material_Properties :: struct {
	density:     f32,
	friction:    f32,
	restitution: f32,
}

Material_Get_Properties :: proc(material: enums.Material) -> Material_Properties {
	#partial switch material {
	case .SmoothPlastic:
		return {0.7, 0.30, 0.20}

	case .Wood:
		return {0.7, 0.50, 0.15}

	case .Brick:
		return {1.8, 0.70, 0.10}

	case .Grass:
		return {0.5, 0.80, 0.05}

	case .Concrete:
		return {2.4, 0.75, 0.05}

	case .Slate:
		return {2.7, 0.65, 0.05}

	case .Glass:
		return {2.5, 0.30, 0.10}

	case .Sand:
		return {1.6, 0.90, 0.00}

	case:
		return {1.0, 0.30, 0.10}
	}
}