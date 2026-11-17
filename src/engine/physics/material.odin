package physics

import enums "../enum"

Material_Get_Properties :: proc(material: enums.Material) -> enums.Material_Properties {
	if enums.Material_Is_Valid(int(material)) {
		return enums.Material_Physical_Properties[material]
	}
	return {1, 0.3, 0.1, 1, 1}
}
