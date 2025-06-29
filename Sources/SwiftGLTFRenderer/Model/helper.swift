import simd

public let simd4x4Identity: simd_float4x4 = simd_float4x4(
    [1, 0, 0, 0],
    [0, 1, 0, 0],
    [0, 0, 1, 0],
    [0, 0, 0, 1]
)

// 平行移動行列
public func translationMatrix(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
    var matrix = matrix_identity_float4x4
    matrix.columns.3 = simd_float4(x, y, z, 1.0)
    return matrix
}

// 回転行列 (Z軸回転)
public func rotationZMatrix(_ angle: Float) -> simd_float4x4 {
    let c = cos(angle)
    let s = sin(angle)
    return simd_float4x4(
        simd_float4(c, s, 0, 0),
        simd_float4(-s,  c, 0, 0),
        simd_float4(0,  0, 1, 0),
        simd_float4(0,  0, 0, 1)
    )
}

// 回転行列（Y軸回転）
public func rotationYMatrix(_ angle: Float) -> simd_float4x4 {
    let c = cos(angle)
    let s = sin(angle)
    return simd_float4x4(
        simd_float4(c, 0, s, 0),
        simd_float4(0, 1,  0, 0),
        simd_float4(-s, 0,  c, 0),
        simd_float4(0, 0,  0, 1)
    )
}

// 回転行列（X軸回転）
public func rotationXMatrix(_ angle: Float) -> simd_float4x4 {
    let c = cos(angle)
    let s = sin(angle)
    return simd_float4x4(
        simd_float4(1, 0,  0, 0),
        simd_float4(0, c,  s, 0),
        simd_float4(0, -s, c, 0),
        simd_float4(0, 0,  0, 1)
    )
}

public func orthographicMatrix(left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float) -> simd_float4x4 {
    return simd_float4x4(
        SIMD4<Float>(2 / (right - left), 0, 0, 0),
        SIMD4<Float>(0, 2 / (top - bottom), 0, 0),
        SIMD4<Float>(0, 0, 1 / (far - near), 0),
        SIMD4<Float>(-(right + left) / (right - left), -(top + bottom) / (top - bottom), -near / (far - near), 1)
    )
}

// 透視投影行列
public func perspectiveMatrix(fov: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
    let f = 1.0 / tan(fov / 2.0)
    return simd_float4x4(
        simd_float4(f / aspect, 0,  0,  0),
        simd_float4(0, f,  0,  0),
        simd_float4(0, 0, far / (far - near), 1),
        simd_float4(0, 0, -far * near / (far - near), 0)
    )
}

public func lookAt(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
    let forward = simd_normalize(target - eye) // カメラの向き
    let right = simd_normalize(simd_cross(up, forward)) // カメラの右方向
    let newUp = simd_cross(forward, right) // 新しい上方向

    return simd_float4x4(
        SIMD4<Float>(right.x, newUp.x, forward.x, 0),
        SIMD4<Float>(right.y, newUp.y, forward.y, 0),
        SIMD4<Float>(right.z, newUp.z, forward.z, 0),
        SIMD4<Float>(-simd_dot(right, eye), -simd_dot(newUp, eye), -simd_dot(forward, eye), 1)
    )
}

public func projection2D(width: Float, height: Float) -> simd_float4x4 {
    return simd_float4x4(
        SIMD4<Float>(2 / width,           0, 0, 0),
        SIMD4<Float>(        0, -2 / height, 0, 0),
        SIMD4<Float>(        0,           0, 1, 0),
        SIMD4<Float>(        0,           0, 0, 1)
    )
}

public func projection2DForNSView(width: Float, height: Float) -> simd_float4x4 {
    return simd_float4x4(
        SIMD4<Float>(2 / width,           0, 0, 0),
        SIMD4<Float>(        0,  2 / height, 0, 0),
        SIMD4<Float>(        0,           0, 1, 0),
        SIMD4<Float>(       -1,          -1, 0, 1)
    )
}

public func float3x3(_ float4x4: simd_float4x4) -> simd_float3x3 {
    return simd_float3x3(
        SIMD3<Float>(float4x4[0].x, float4x4[0].y, float4x4[0].z),
        SIMD3<Float>(float4x4[1].x, float4x4[1].y, float4x4[1].z),
        SIMD3<Float>(float4x4[2].x, float4x4[2].y, float4x4[2].z)
    )
}

func srgbToLinear(_ c: Float) -> Float {
    if c <= 0.04045 {
        return c / 12.92
    } else {
        return pow((c + 0.055) / 1.055, 2.4)
    }
}

func srgbToLinear(_ c: Double) -> Double {
    if c <= 0.04045 {
        return c / 12.92
    } else {
        return pow((c + 0.055) / 1.055, 2.4)
    }
}

func linearToSrgb(_ c: Float) -> Float {
    if c <= 0.0031308 {
        return c * 12.92
    } else {
        return 1.055 * pow(c, 1.0 / 2.4) - 0.055
    }
}

func srgbToLinear(_ rgb: (Float, Float, Float)) -> (Float, Float, Float) {
    return (
        srgbToLinear(rgb.0),
        srgbToLinear(rgb.1),
        srgbToLinear(rgb.2)
    )
}

func linearToSrgb(_ rgb: (Float, Float, Float)) -> (Float, Float, Float) {
    return (
        linearToSrgb(rgb.0),
        linearToSrgb(rgb.1),
        linearToSrgb(rgb.2)
    )
}
