package datatypes
import "core:math"

CFrame :: struct {
    x, y, z: f32,

    r00, r01, r02: f32,
    r10, r11, r12: f32,
    r20, r21, r22: f32,
}


RotationOrder :: enum {
    XYZ,
    XZY,
    YXZ,
    YZX,
    ZXY,
    ZYX,
}


CFrame_Identity :: CFrame{
    x = 0,
    y = 0,
    z = 0,

    r00 = 1,
    r01 = 0,
    r02 = 0,

    r10 = 0,
    r11 = 1,
    r12 = 0,

    r20 = 0,
    r21 = 0,
    r22 = 1,
}

CFRAME_EPSILON :: 1.0e-6

cframe_v3_add :: proc(a, b: Vector3) -> Vector3 {
    return Vector3{
        a.x + b.x,
        a.y + b.y,
        a.z + b.z,
    }
}


cframe_v3_sub :: proc(a, b: Vector3) -> Vector3 {
    return Vector3{
        a.x - b.x,
        a.y - b.y,
        a.z - b.z,
    }
}


cframe_v3_mul :: proc(v: Vector3, scalar: f32) -> Vector3 {
    return Vector3{
        v.x * scalar,
        v.y * scalar,
        v.z * scalar,
    }
}


cframe_v3_dot :: proc(a, b: Vector3) -> f32 {
    return a.x * b.x +
           a.y * b.y +
           a.z * b.z
}


cframe_v3_cross :: proc(a, b: Vector3) -> Vector3 {
    return Vector3{
        a.y * b.z - a.z * b.y,
        a.z * b.x - a.x * b.z,
        a.x * b.y - a.y * b.x,
    }
}


cframe_v3_magnitude_squared :: proc(v: Vector3) -> f32 {
    return cframe_v3_dot(v, v)
}


cframe_v3_magnitude :: proc(v: Vector3) -> f32 {
    return math.sqrt(cframe_v3_magnitude_squared(v))
}


cframe_v3_unit :: proc(v: Vector3) -> Vector3 {
    magnitude := cframe_v3_magnitude(v)

    if magnitude <= CFRAME_EPSILON {
        return Vector3{}
    }

    return cframe_v3_mul(v, 1.0 / magnitude)
}


cframe_clamp :: proc(x, minimum, maximum: f32) -> f32 {
    if x < minimum {
        return minimum
    }

    if x > maximum {
        return maximum
    }

    return x
}


//
// Internal quaternion
//

cframe_quat :: struct {
    x, y, z, w: f32,
}


cframe_quat_normalize :: proc(q: cframe_quat) -> cframe_quat {
    magnitude_squared :=
        q.x * q.x +
        q.y * q.y +
        q.z * q.z +
        q.w * q.w

    if magnitude_squared <= CFRAME_EPSILON * CFRAME_EPSILON {
        return cframe_quat{0, 0, 0, 1}
    }

    inverse_magnitude := 1.0 / math.sqrt(magnitude_squared)

    return cframe_quat{
        q.x * inverse_magnitude,
        q.y * inverse_magnitude,
        q.z * inverse_magnitude,
        q.w * inverse_magnitude,
    }
}


cframe_quat_from_cframe :: proc(cf: CFrame) -> cframe_quat {
    trace := cf.r00 + cf.r11 + cf.r22

    q: cframe_quat

    if trace > 0 {
        s := math.sqrt(trace + 1.0) * 2.0

        q.w = 0.25 * s
        q.x = (cf.r21 - cf.r12) / s
        q.y = (cf.r02 - cf.r20) / s
        q.z = (cf.r10 - cf.r01) / s

    } else if cf.r00 > cf.r11 && cf.r00 > cf.r22 {
        s := math.sqrt(1.0 + cf.r00 - cf.r11 - cf.r22) * 2.0

        q.w = (cf.r21 - cf.r12) / s
        q.x = 0.25 * s
        q.y = (cf.r01 + cf.r10) / s
        q.z = (cf.r02 + cf.r20) / s

    } else if cf.r11 > cf.r22 {
        s := math.sqrt(1.0 + cf.r11 - cf.r00 - cf.r22) * 2.0

        q.w = (cf.r02 - cf.r20) / s
        q.x = (cf.r01 + cf.r10) / s
        q.y = 0.25 * s
        q.z = (cf.r12 + cf.r21) / s

    } else {
        s := math.sqrt(1.0 + cf.r22 - cf.r00 - cf.r11) * 2.0

        q.w = (cf.r10 - cf.r01) / s
        q.x = (cf.r02 + cf.r20) / s
        q.y = (cf.r12 + cf.r21) / s
        q.z = 0.25 * s
    }

    return cframe_quat_normalize(q)
}


cframe_from_quat :: proc(position: Vector3, input: cframe_quat) -> CFrame {
    q := cframe_quat_normalize(input)

    xx := q.x * q.x
    yy := q.y * q.y
    zz := q.z * q.z

    xy := q.x * q.y
    xz := q.x * q.z
    yz := q.y * q.z

    wx := q.w * q.x
    wy := q.w * q.y
    wz := q.w * q.z

    return CFrame{
        x = position.x,
        y = position.y,
        z = position.z,

        r00 = 1.0 - 2.0 * (yy + zz),
        r01 = 2.0 * (xy - wz),
        r02 = 2.0 * (xz + wy),

        r10 = 2.0 * (xy + wz),
        r11 = 1.0 - 2.0 * (xx + zz),
        r12 = 2.0 * (yz - wx),

        r20 = 2.0 * (xz - wy),
        r21 = 2.0 * (yz + wx),
        r22 = 1.0 - 2.0 * (xx + yy),
    }
}


cframe_quat_slerp :: proc(a_input, b_input: cframe_quat, alpha: f32) -> cframe_quat {
    a := cframe_quat_normalize(a_input)
    b := cframe_quat_normalize(b_input)

    dot :=
        a.x * b.x +
        a.y * b.y +
        a.z * b.z +
        a.w * b.w

    // q and -q represent the same rotation.
    if dot < 0 {
        b.x = -b.x
        b.y = -b.y
        b.z = -b.z
        b.w = -b.w

        dot = -dot
    }

    dot = cframe_clamp(dot, -1, 1)

    // Nearly identical rotations.
    if dot > 0.9995 {
        result := cframe_quat{
            a.x + (b.x - a.x) * alpha,
            a.y + (b.y - a.y) * alpha,
            a.z + (b.z - a.z) * alpha,
            a.w + (b.w - a.w) * alpha,
        }

        return cframe_quat_normalize(result)
    }

    theta_0 := math.acos(dot)
    theta := theta_0 * alpha

    sin_theta := math.sin(theta)
    sin_theta_0 := math.sin(theta_0)

    s0 := math.cos(theta) - dot * sin_theta / sin_theta_0
    s1 := sin_theta / sin_theta_0

    return cframe_quat_normalize(cframe_quat{
        a.x * s0 + b.x * s1,
        a.y * s0 + b.y * s1,
        a.z * s0 + b.z * s1,
        a.w * s0 + b.w * s1,
    })
}


//
// Constructors
//

CFrame_New_Empty :: proc() -> CFrame {
    return CFrame_Identity
}


CFrame_New_Position :: proc(position: Vector3) -> CFrame {
    result := CFrame_Identity

    result.x = position.x
    result.y = position.y
    result.z = position.z

    return result
}


CFrame_New_XYZ :: proc(x, y, z: f32) -> CFrame {
    result := CFrame_Identity

    result.x = x
    result.y = y
    result.z = z

    return result
}


CFrame_New_Quaternion :: proc(
    x, y, z: f32,
    qx, qy, qz, qw: f32,
) -> CFrame {
    return cframe_from_quat(
        Vector3{x, y, z},
        cframe_quat{qx, qy, qz, qw},
    )
}


CFrame_New_Matrix :: proc(
    x, y, z: f32,

    r00, r01, r02: f32,
    r10, r11, r12: f32,
    r20, r21, r22: f32,
) -> CFrame {
    return CFrame{
        x = x,
        y = y,
        z = z,

        r00 = r00,
        r01 = r01,
        r02 = r02,

        r10 = r10,
        r11 = r11,
        r12 = r12,

        r20 = r20,
        r21 = r21,
        r22 = r22,
    }
}


//
// Properties
//

CFrame_Position :: proc(cf: CFrame) -> Vector3 {
    return Vector3{cf.x, cf.y, cf.z}
}


CFrame_Rotation :: proc(cf: CFrame) -> CFrame {
    result := cf

    result.x = 0
    result.y = 0
    result.z = 0

    return result
}


CFrame_RightVector :: proc(cf: CFrame) -> Vector3 {
    return Vector3{
        cf.r00,
        cf.r10,
        cf.r20,
    }
}


CFrame_UpVector :: proc(cf: CFrame) -> Vector3 {
    return Vector3{
        cf.r01,
        cf.r11,
        cf.r21,
    }
}


CFrame_ZVector :: proc(cf: CFrame) -> Vector3 {
    return Vector3{
        cf.r02,
        cf.r12,
        cf.r22,
    }
}


CFrame_LookVector :: proc(cf: CFrame) -> Vector3 {
    // Roblox forward is local -Z.
    return Vector3{
        -cf.r02,
        -cf.r12,
        -cf.r22,
    }
}


CFrame_XVector :: proc(cf: CFrame) -> Vector3 {
    return CFrame_RightVector(cf)
}


CFrame_YVector :: proc(cf: CFrame) -> Vector3 {
    return CFrame_UpVector(cf)
}


//
// Matrix construction
//

CFrame_FromMatrix :: proc(
    position: Vector3,
    x_vector: Vector3,
    y_vector: Vector3,
    z_vector: Vector3,
) -> CFrame {
    return CFrame{
        x = position.x,
        y = position.y,
        z = position.z,

        // basis vectors are matrix columns

        r00 = x_vector.x,
        r01 = y_vector.x,
        r02 = z_vector.x,

        r10 = x_vector.y,
        r11 = y_vector.y,
        r12 = z_vector.y,

        r20 = x_vector.z,
        r21 = y_vector.z,
        r22 = z_vector.z,
    }
}


//
// Multiplication
//

CFrame_Mul_CFrame :: proc(a, b: CFrame) -> CFrame {
    return CFrame{
        x =
            a.r00 * b.x +
            a.r01 * b.y +
            a.r02 * b.z +
            a.x,

        y =
            a.r10 * b.x +
            a.r11 * b.y +
            a.r12 * b.z +
            a.y,

        z =
            a.r20 * b.x +
            a.r21 * b.y +
            a.r22 * b.z +
            a.z,

        r00 =
            a.r00 * b.r00 +
            a.r01 * b.r10 +
            a.r02 * b.r20,

        r01 =
            a.r00 * b.r01 +
            a.r01 * b.r11 +
            a.r02 * b.r21,

        r02 =
            a.r00 * b.r02 +
            a.r01 * b.r12 +
            a.r02 * b.r22,

        r10 =
            a.r10 * b.r00 +
            a.r11 * b.r10 +
            a.r12 * b.r20,

        r11 =
            a.r10 * b.r01 +
            a.r11 * b.r11 +
            a.r12 * b.r21,

        r12 =
            a.r10 * b.r02 +
            a.r11 * b.r12 +
            a.r12 * b.r22,

        r20 =
            a.r20 * b.r00 +
            a.r21 * b.r10 +
            a.r22 * b.r20,

        r21 =
            a.r20 * b.r01 +
            a.r21 * b.r11 +
            a.r22 * b.r21,

        r22 =
            a.r20 * b.r02 +
            a.r21 * b.r12 +
            a.r22 * b.r22,
    }
}


CFrame_Mul_Vector3 :: proc(cf: CFrame, point: Vector3) -> Vector3 {
    return Vector3{
        cf.r00 * point.x +
        cf.r01 * point.y +
        cf.r02 * point.z +
        cf.x,

        cf.r10 * point.x +
        cf.r11 * point.y +
        cf.r12 * point.z +
        cf.y,

        cf.r20 * point.x +
        cf.r21 * point.y +
        cf.r22 * point.z +
        cf.z,
    }
}


CFrame_Add_Vector3 :: proc(cf: CFrame, offset: Vector3) -> CFrame {
    result := cf

    result.x += offset.x
    result.y += offset.y
    result.z += offset.z

    return result
}


CFrame_Sub_Vector3 :: proc(cf: CFrame, offset: Vector3) -> CFrame {
    result := cf

    result.x -= offset.x
    result.y -= offset.y
    result.z -= offset.z

    return result
}


//
// Axis rotations
//

cframe_rotation_x :: proc(angle: f32) -> CFrame {
    c := math.cos(angle)
    s := math.sin(angle)

    return CFrame{
        r00 = 1,

        r11 = c,
        r12 = -s,

        r21 = s,
        r22 = c,
    }
}


cframe_rotation_y :: proc(angle: f32) -> CFrame {
    c := math.cos(angle)
    s := math.sin(angle)

    return CFrame{
        r00 = c,
        r02 = s,

        r11 = 1,

        r20 = -s,
        r22 = c,
    }
}


cframe_rotation_z :: proc(angle: f32) -> CFrame {
    c := math.cos(angle)
    s := math.sin(angle)

    return CFrame{
        r00 = c,
        r01 = -s,

        r10 = s,
        r11 = c,

        r22 = 1,
    }
}


//
// Euler constructors
//

CFrame_FromEulerAngles_Order :: proc(
    rx, ry, rz: f32,
    order: RotationOrder,
) -> CFrame {
    x_cf := cframe_rotation_x(rx)
    y_cf := cframe_rotation_y(ry)
    z_cf := cframe_rotation_z(rz)

    switch order {
    case .XYZ:
        return CFrame_Mul_CFrame(
            CFrame_Mul_CFrame(x_cf, y_cf),
            z_cf,
        )

    case .XZY:
        return CFrame_Mul_CFrame(
            CFrame_Mul_CFrame(x_cf, z_cf),
            y_cf,
        )

    case .YXZ:
        return CFrame_Mul_CFrame(
            CFrame_Mul_CFrame(y_cf, x_cf),
            z_cf,
        )

    case .YZX:
        return CFrame_Mul_CFrame(
            CFrame_Mul_CFrame(y_cf, z_cf),
            x_cf,
        )

    case .ZXY:
        return CFrame_Mul_CFrame(
            CFrame_Mul_CFrame(z_cf, x_cf),
            y_cf,
        )

    case .ZYX:
        return CFrame_Mul_CFrame(
            CFrame_Mul_CFrame(z_cf, y_cf),
            x_cf,
        )
    }

    return CFrame_Identity
}


CFrame_FromEulerAngles_Default :: proc(
    rx, ry, rz: f32,
) -> CFrame {
    return CFrame_FromEulerAngles_Order(
        rx,
        ry,
        rz,
        .XYZ,
    )
}


CFrame_FromEulerAngles :: proc{
    CFrame_FromEulerAngles_Default,
    CFrame_FromEulerAngles_Order,
}


CFrame_FromEulerAnglesXYZ :: proc(
    rx, ry, rz: f32,
) -> CFrame {
    return CFrame_FromEulerAngles_Order(
        rx,
        ry,
        rz,
        .XYZ,
    )
}


CFrame_Angles :: proc(
    rx, ry, rz: f32,
) -> CFrame {
    return CFrame_FromEulerAnglesXYZ(rx, ry, rz)
}


CFrame_FromEulerAnglesYXZ :: proc(
    rx, ry, rz: f32,
) -> CFrame {
    return CFrame_FromEulerAngles_Order(
        rx,
        ry,
        rz,
        .YXZ,
    )
}


CFrame_FromOrientation :: proc(
    rx, ry, rz: f32,
) -> CFrame {
    return CFrame_FromEulerAnglesYXZ(rx, ry, rz)
}


//
// Axis angle
//

CFrame_FromAxisAngle :: proc(
    axis_input: Vector3,
    angle: f32,
) -> CFrame {
    axis := cframe_v3_unit(axis_input)

    if cframe_v3_magnitude_squared(axis) <= CFRAME_EPSILON {
        return CFrame_Identity
    }

    c := math.cos(angle)
    s := math.sin(angle)
    t := 1.0 - c

    x := axis.x
    y := axis.y
    z := axis.z

    return CFrame{
        r00 = t * x * x + c,
        r01 = t * x * y - s * z,
        r02 = t * x * z + s * y,

        r10 = t * x * y + s * z,
        r11 = t * y * y + c,
        r12 = t * y * z - s * x,

        r20 = t * x * z - s * y,
        r21 = t * y * z + s * x,
        r22 = t * z * z + c,
    }
}


//
// lookAt / lookAlong
//

CFrame_LookAt_Up :: proc(
    at: Vector3,
    target: Vector3,
    up_input: Vector3,
) -> CFrame {
    direction := cframe_v3_sub(target, at)

    if cframe_v3_magnitude_squared(direction) <= CFRAME_EPSILON {
        return CFrame_New_Position(at)
    }

    // Roblox faces local -Z.
    back := cframe_v3_unit(cframe_v3_mul(direction, -1))

    up := cframe_v3_unit(up_input)

    if cframe_v3_magnitude_squared(up) <= CFRAME_EPSILON {
        up = Vector3{0, 1, 0}
    }

    right := cframe_v3_cross(up, back)

    // up and direction are parallel.
    if cframe_v3_magnitude_squared(right) <= CFRAME_EPSILON {
        fallback := Vector3{1, 0, 0}

        if math.abs(back.x) > 0.999 {
            fallback = Vector3{0, 0, 1}
        }

        right = cframe_v3_cross(fallback, back)
    }

    right = cframe_v3_unit(right)

    true_up := cframe_v3_unit(
        cframe_v3_cross(back, right),
    )

    return CFrame_FromMatrix(
        at,
        right,
        true_up,
        back,
    )
}


CFrame_LookAt_Default :: proc(
    at: Vector3,
    target: Vector3,
) -> CFrame {
    return CFrame_LookAt_Up(
        at,
        target,
        Vector3{0, 1, 0},
    )
}


CFrame_LookAt :: proc{
    CFrame_LookAt_Default,
    CFrame_LookAt_Up,
}


CFrame_New_LookAt :: proc(
    position: Vector3,
    look_at: Vector3,
) -> CFrame {
    return CFrame_LookAt_Default(position, look_at)
}


CFrame_LookAlong_Up :: proc(
    at: Vector3,
    direction: Vector3,
    up: Vector3,
) -> CFrame {
    return CFrame_LookAt_Up(
        at,
        cframe_v3_add(at, direction),
        up,
    )
}


CFrame_LookAlong_Default :: proc(
    at: Vector3,
    direction: Vector3,
) -> CFrame {
    return CFrame_LookAlong_Up(
        at,
        direction,
        Vector3{0, 1, 0},
    )
}


CFrame_LookAlong :: proc{
    CFrame_LookAlong_Default,
    CFrame_LookAlong_Up,
}


//
// Rotation between vectors
//

CFrame_FromRotationBetweenVectors :: proc(
    from_input: Vector3,
    to_input: Vector3,
) -> CFrame {
    from := cframe_v3_unit(from_input)
    to := cframe_v3_unit(to_input)

    if cframe_v3_magnitude_squared(from) <= CFRAME_EPSILON ||
       cframe_v3_magnitude_squared(to) <= CFRAME_EPSILON {
        return CFrame_Identity
    }

    dot := cframe_clamp(
        cframe_v3_dot(from, to),
        -1,
        1,
    )

    if dot > 1.0 - CFRAME_EPSILON {
        return CFrame_Identity
    }

    if dot < -1.0 + CFRAME_EPSILON {
        axis := cframe_v3_cross(
            from,
            Vector3{1, 0, 0},
        )

        if cframe_v3_magnitude_squared(axis) <= CFRAME_EPSILON {
            axis = cframe_v3_cross(
                from,
                Vector3{0, 1, 0},
            )
        }

        return CFrame_FromAxisAngle(
            cframe_v3_unit(axis),
            f32(math.PI),
        )
    }

    cross := cframe_v3_cross(from, to)

    q := cframe_quat_normalize(cframe_quat{
        cross.x,
        cross.y,
        cross.z,
        1.0 + dot,
    })

    return cframe_from_quat(Vector3{}, q)
}


CFrame_Inverse :: proc(cf: CFrame) -> CFrame {
    // Rotation inverse = transpose.

    result := CFrame{
        r00 = cf.r00,
        r01 = cf.r10,
        r02 = cf.r20,

        r10 = cf.r01,
        r11 = cf.r11,
        r12 = cf.r21,

        r20 = cf.r02,
        r21 = cf.r12,
        r22 = cf.r22,
    }

    result.x = -(
        result.r00 * cf.x +
        result.r01 * cf.y +
        result.r02 * cf.z
    )

    result.y = -(
        result.r10 * cf.x +
        result.r11 * cf.y +
        result.r12 * cf.z
    )

    result.z = -(
        result.r20 * cf.x +
        result.r21 * cf.y +
        result.r22 * cf.z
    )

    return result
}


//
// Coordinate conversion
//

CFrame_ToWorldSpace :: proc(
    cf: CFrame,
    other: CFrame,
) -> CFrame {
    return CFrame_Mul_CFrame(cf, other)
}


CFrame_ToObjectSpace :: proc(
    cf: CFrame,
    other: CFrame,
) -> CFrame {
    return CFrame_Mul_CFrame(
        CFrame_Inverse(cf),
        other,
    )
}


CFrame_PointToWorldSpace :: proc(
    cf: CFrame,
    point: Vector3,
) -> Vector3 {
    return CFrame_Mul_Vector3(cf, point)
}


CFrame_PointToObjectSpace :: proc(
    cf: CFrame,
    point: Vector3,
) -> Vector3 {
    return CFrame_Mul_Vector3(
        CFrame_Inverse(cf),
        point,
    )
}


CFrame_VectorToWorldSpace :: proc(
    cf: CFrame,
    vector: Vector3,
) -> Vector3 {
    return Vector3{
        cf.r00 * vector.x +
        cf.r01 * vector.y +
        cf.r02 * vector.z,

        cf.r10 * vector.x +
        cf.r11 * vector.y +
        cf.r12 * vector.z,

        cf.r20 * vector.x +
        cf.r21 * vector.y +
        cf.r22 * vector.z,
    }
}


CFrame_VectorToObjectSpace :: proc(
    cf: CFrame,
    vector: Vector3,
) -> Vector3 {
    // Multiply by transposed rotation.

    return Vector3{
        cf.r00 * vector.x +
        cf.r10 * vector.y +
        cf.r20 * vector.z,

        cf.r01 * vector.x +
        cf.r11 * vector.y +
        cf.r21 * vector.z,

        cf.r02 * vector.x +
        cf.r12 * vector.y +
        cf.r22 * vector.z,
    }
}


CFrame_Orthonormalize :: proc(cf: CFrame) -> CFrame {
    right := cframe_v3_unit(
        CFrame_RightVector(cf),
    )

    up_original := CFrame_UpVector(cf)

    up := cframe_v3_sub(
        up_original,
        cframe_v3_mul(
            right,
            cframe_v3_dot(up_original, right),
        ),
    )

    up = cframe_v3_unit(up)

    if cframe_v3_magnitude_squared(up) <= CFRAME_EPSILON {
        return cf
    }

    back := cframe_v3_unit(
        cframe_v3_cross(right, up),
    )

    up = cframe_v3_unit(
        cframe_v3_cross(back, right),
    )

    return CFrame_FromMatrix(
        CFrame_Position(cf),
        right,
        up,
        back,
    )
}


//
// Lerp
//

CFrame_Lerp :: proc(
    cf: CFrame,
    goal: CFrame,
    alpha: f32,
) -> CFrame {
    position := Vector3{
        cf.x + (goal.x - cf.x) * alpha,
        cf.y + (goal.y - cf.y) * alpha,
        cf.z + (goal.z - cf.z) * alpha,
    }

    a := cframe_quat_from_cframe(cf)
    b := cframe_quat_from_cframe(goal)

    rotation := cframe_quat_slerp(a, b, alpha)

    return cframe_from_quat(position, rotation)
}


//
// Components
//

CFrame_GetComponents :: proc(
    cf: CFrame,
) -> (
    x, y, z: f32,
    r00, r01, r02: f32,
    r10, r11, r12: f32,
    r20, r21, r22: f32,
) {
    return cf.x, cf.y, cf.z,
        cf.r00, cf.r01, cf.r02,
        cf.r10, cf.r11, cf.r12,
        cf.r20, cf.r21, cf.r22
}


CFrame_Components :: proc(
    cf: CFrame,
) -> (
    x, y, z: f32,
    r00, r01, r02: f32,
    r10, r11, r12: f32,
    r20, r21, r22: f32,
) {
    return CFrame_GetComponents(cf)
}


//
// Euler extraction
//

CFrame_ToEulerAngles_Order :: proc(
    cf: CFrame,
    order: RotationOrder,
) -> (rx, ry, rz: f32) {
    switch order {

    case .XYZ:
        ry = math.asin(
            cframe_clamp(cf.r02, -1, 1),
        )

        rx = math.atan2(
            -cf.r12,
            cf.r22,
        )

        rz = math.atan2(
            -cf.r01,
            cf.r00,
        )


    case .XZY:
        rz = math.asin(
            cframe_clamp(-cf.r01, -1, 1),
        )

        rx = math.atan2(
            cf.r21,
            cf.r11,
        )

        ry = math.atan2(
            cf.r02,
            cf.r00,
        )


    case .YXZ:
        rx = math.asin(
            cframe_clamp(-cf.r12, -1, 1),
        )

        ry = math.atan2(
            cf.r02,
            cf.r22,
        )

        rz = math.atan2(
            cf.r10,
            cf.r11,
        )


    case .YZX:
        rz = math.asin(
            cframe_clamp(cf.r10, -1, 1),
        )

        ry = math.atan2(
            -cf.r20,
            cf.r00,
        )

        rx = math.atan2(
            -cf.r12,
            cf.r11,
        )


    case .ZXY:
        rx = math.asin(
            cframe_clamp(cf.r21, -1, 1),
        )

        rz = math.atan2(
            -cf.r01,
            cf.r11,
        )

        ry = math.atan2(
            -cf.r20,
            cf.r22,
        )


    case .ZYX:
        ry = math.asin(
            cframe_clamp(-cf.r20, -1, 1),
        )

        rz = math.atan2(
            cf.r10,
            cf.r00,
        )

        rx = math.atan2(
            cf.r21,
            cf.r22,
        )
    }

    return
}


CFrame_ToEulerAngles_Default :: proc(
    cf: CFrame,
) -> (rx, ry, rz: f32) {
    return CFrame_ToEulerAngles_Order(
        cf,
        .XYZ,
    )
}


CFrame_ToEulerAngles :: proc{
    CFrame_ToEulerAngles_Default,
    CFrame_ToEulerAngles_Order,
}


CFrame_ToEulerAnglesXYZ :: proc(
    cf: CFrame,
) -> (rx, ry, rz: f32) {
    return CFrame_ToEulerAngles_Order(
        cf,
        .XYZ,
    )
}


CFrame_ToEulerAnglesYXZ :: proc(
    cf: CFrame,
) -> (rx, ry, rz: f32) {
    return CFrame_ToEulerAngles_Order(
        cf,
        .YXZ,
    )
}


CFrame_ToOrientation :: proc(
    cf: CFrame,
) -> (rx, ry, rz: f32) {
    return CFrame_ToEulerAnglesYXZ(cf)
}


//
// Axis angle extraction
//

CFrame_ToAxisAngle :: proc(
    cf: CFrame,
) -> (axis: Vector3, angle: f32) {
    q := cframe_quat_from_cframe(cf)

    // Keep result angle in [0, pi].
    if q.w < 0 {
        q.x = -q.x
        q.y = -q.y
        q.z = -q.z
        q.w = -q.w
    }

    q.w = cframe_clamp(q.w, -1, 1)

    angle = 2.0 * math.acos(q.w)

    sin_half_squared := 1.0 - q.w * q.w

    if sin_half_squared <= CFRAME_EPSILON {
        return Vector3{1, 0, 0}, 0
    }

    inverse := 1.0 / math.sqrt(sin_half_squared)

    axis = Vector3{
        q.x * inverse,
        q.y * inverse,
        q.z * inverse,
    }

    return
}


//
// AngleBetween
//

CFrame_AngleBetween :: proc(
    a, b: CFrame,
) -> f32 {
    relative := CFrame_Mul_CFrame(
        CFrame_Inverse(a),
        b,
    )

    _, angle := CFrame_ToAxisAngle(relative)

    return angle
}


//
// FuzzyEq
//

cframe_float_fuzzy_eq :: proc(
    a, b, epsilon: f32,
) -> bool {
    if a == b {
        return true
    }

    return math.abs(a - b) <=
        (math.abs(a) + 1.0) * epsilon
}


CFrame_FuzzyEq_Epsilon :: proc(
    a, b: CFrame,
    epsilon: f32,
) -> bool {
    if !cframe_float_fuzzy_eq(a.x, b.x, epsilon) ||
       !cframe_float_fuzzy_eq(a.y, b.y, epsilon) ||
       !cframe_float_fuzzy_eq(a.z, b.z, epsilon) {
        return false
    }

    return CFrame_AngleBetween(a, b) <= epsilon
}


CFrame_FuzzyEq_Default :: proc(
    a, b: CFrame,
) -> bool {
    return CFrame_FuzzyEq_Epsilon(
        a,
        b,
        1.0e-5,
    )
}


CFrame_FuzzyEq :: proc{
    CFrame_FuzzyEq_Default,
    CFrame_FuzzyEq_Epsilon,
}


CFrame_New :: proc{
    CFrame_New_Empty,
    CFrame_New_Position,
    CFrame_New_LookAt,
    CFrame_New_XYZ,
    CFrame_New_Quaternion,
    CFrame_New_Matrix,
}