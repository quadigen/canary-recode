package datatypes

import "core:math"

Region3 :: struct {
	Min: Vector3,
	Max: Vector3,
}

Region3_New :: proc(a, b: Vector3) -> Region3 {
	return Region3{
		Min = Vector3{
			min(a.x, b.x),
			min(a.y, b.y),
			min(a.z, b.z),
		},
		Max = Vector3{
			max(a.x, b.x),
			max(a.y, b.y),
			max(a.z, b.z),
		},
	}
}

Region3_Center :: proc(region: Region3) -> Vector3 {
	return Vector3{
		(region.Min.x + region.Max.x) * 0.5,
		(region.Min.y + region.Max.y) * 0.5,
		(region.Min.z + region.Max.z) * 0.5,
	}
}

Region3_Size :: proc(region: Region3) -> Vector3 {
	return Vector3{
		region.Max.x - region.Min.x,
		region.Max.y - region.Min.y,
		region.Max.z - region.Min.z,
	}
}

Region3_ExpandToGrid :: proc(region: Region3, resolution: f32) -> (Region3, bool) {
	if resolution <= 0 || resolution != resolution {
		return Region3{}, false
	}

	return Region3{
		Min = Vector3{
			math.floor(region.Min.x / resolution) * resolution,
			math.floor(region.Min.y / resolution) * resolution,
			math.floor(region.Min.z / resolution) * resolution,
		},
		Max = Vector3{
			math.ceil(region.Max.x / resolution) * resolution,
			math.ceil(region.Max.y / resolution) * resolution,
			math.ceil(region.Max.z / resolution) * resolution,
		},
	}, true
}
