package datatypes
import "core:math"

Vector3 :: struct {
    x, y, z: f32,
}

Vec3_Multiply :: proc(v: Vector3, scalar: f32) -> Vector3 {
    return Vector3{
        x = v.x * scalar,
        y = v.y * scalar,
        z = v.z * scalar,
    }
}

Vec3_Unit :: proc(v: Vector3) -> Vector3 {
    length := math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    if length == 0.0 {
        return Vector3{0.0, 0.0, 0.0}
    }
    return Vec3_Multiply(v, 1.0 / length)
}

Vec3_Magnitude :: proc(v: Vector3) -> f32 {
    return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
}


