package datatypes

import "core:math"

Ray :: struct {
	Origin:    Vector3,
	Direction: Vector3,
}

Ray_Unit :: proc(ray: Ray) -> Ray {
	return Ray{ray.Origin, Vec3_Unit(ray.Direction)}
}

Ray_ClosestPoint :: proc(ray: Ray, point: Vector3) -> Vector3 {
	direction_length_squared := ray.Direction.x*ray.Direction.x + ray.Direction.y*ray.Direction.y + ray.Direction.z*ray.Direction.z
	if direction_length_squared == 0 { return ray.Origin }
	delta := Vector3{point.x-ray.Origin.x, point.y-ray.Origin.y, point.z-ray.Origin.z}
	distance_along := (delta.x*ray.Direction.x + delta.y*ray.Direction.y + delta.z*ray.Direction.z) / direction_length_squared
	distance_along = max(distance_along, 0)
	return Vector3{
		ray.Origin.x + ray.Direction.x*distance_along,
		ray.Origin.y + ray.Direction.y*distance_along,
		ray.Origin.z + ray.Direction.z*distance_along,
	}
}

Ray_Distance :: proc(ray: Ray, point: Vector3) -> f32 {
	closest := Ray_ClosestPoint(ray, point)
	dx, dy, dz := point.x-closest.x, point.y-closest.y, point.z-closest.z
	return math.sqrt(dx*dx + dy*dy + dz*dz)
}

