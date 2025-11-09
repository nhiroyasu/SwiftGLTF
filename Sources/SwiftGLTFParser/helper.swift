import simd
import SwiftGLTFCore

func float4x4(_ m: [Float]) -> float4x4 {
    precondition(m.count == 16)
    return float4x4([
        SIMD4<Float>(m[0], m[1], m[2], m[3]),
        SIMD4<Float>(m[4], m[5], m[6], m[7]),
        SIMD4<Float>(m[8], m[9], m[10], m[11]),
        SIMD4<Float>(m[12], m[13], m[14], m[15])
    ])
}

func quaternionToMatrix3x3(_ q: simd_quatf) -> simd_float3x3 {
    let x = q.imag.x
    let y = q.imag.y
    let z = q.imag.z
    let w = q.real

    return simd_float3x3(
        SIMD3(1 - 2*y*y - 2*z*z, 2*x*y + 2*z*w,     2*x*z - 2*y*w),
        SIMD3(2*x*y - 2*z*w,     1 - 2*x*x - 2*z*z, 2*y*z + 2*x*w),
        SIMD3(2*x*z + 2*y*w,     2*y*z - 2*x*w,     1 - 2*x*x - 2*y*y)
    )
}

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

func translationMatrix(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
    return simd_float4x4(
        SIMD4(1, 0, 0, 0),
        SIMD4(0, 1, 0, 0),
        SIMD4(0, 0, 1, 0),
        SIMD4(x, y, z, 1)
    )
}

@inlinable @inline(__always)
func translationMatrix(_ f3: SIMD3<Float>) -> simd_float4x4 {
    // Construct directly without touching matrix_identity_float4x4
    // to avoid an extra copy + write to columns.3.
    return simd_float4x4(
        SIMD4(1, 0, 0, 0),
        SIMD4(0, 1, 0, 0),
        SIMD4(0, 0, 1, 0),
        SIMD4(f3.x, f3.y, f3.z, 1)
    )
}

public func scaleMatrix(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
    return simd_float4x4(
        SIMD4(x, 0, 0, 0),
        SIMD4(0, y, 0, 0),
        SIMD4(0, 0, z, 0),
        SIMD4(0, 0, 0, 1)
    )
}

public func scaleMatrix(_ f3: SIMD3<Float>) -> simd_float4x4 {
    return simd_float4x4(
        SIMD4(f3.x, 0, 0, 0),
        SIMD4(0, f3.y, 0, 0),
        SIMD4(0, 0, f3.z, 0),
        SIMD4(0, 0, 0, 1)
    )
}

public func trs2matrix(_ trs: TRS) -> simd_float4x4 {
    return translationMatrix(trs.translation) * simd_float4x4(trs.rotation) * scaleMatrix(trs.scale)
}

public func trs2matrix(
    _ t: SIMD3<Float>,
    _ r: simd_quatf,
    _ s: SIMD3<Float>
) -> simd_float4x4 {
    return translationMatrix(t) * simd_float4x4(r) * scaleMatrix(s)
}

public func decomposeTRS(_ m: simd_float4x4) -> TRS {
    let translation = SIMD3(m.columns.3.x, m.columns.3.y, m.columns.3.z)

    let col0 = SIMD3(m.columns.0.x, m.columns.0.y, m.columns.0.z)
    let col1 = SIMD3(m.columns.1.x, m.columns.1.y, m.columns.1.z)
    let col2 = SIMD3(m.columns.2.x, m.columns.2.y, m.columns.2.z)

    let scaleX = length(col0)
    let scaleY = length(col1)
    let scaleZ = length(col2)

    var rotationMatrix = simd_float3x3(columns: (
        col0 / scaleX,
        col1 / scaleY,
        col2 / scaleZ
    ))

    let determinant = simd_determinant(rotationMatrix)
    var scale = SIMD3(scaleX, scaleY, scaleZ)

    if determinant < 0 {
        scale.z *= -1
        rotationMatrix.columns.2 *= -1
    }

    let rotation = simd_quatf(rotationMatrix)

    return TRS(translation: translation, rotation: rotation, scale: scale)
}

func flipToLeftHanded(_ trs: TRS) -> TRS {
    let flippedTranslation = SIMD3(trs.translation.x, trs.translation.y, -trs.translation.z)
    let flippedScale = SIMD3(trs.scale.x, trs.scale.y, trs.scale.z)
    let flippedRotation = simd_quatf(ix: -trs.rotation.imag.x,
                                     iy: -trs.rotation.imag.y,
                                     iz: trs.rotation.imag.z,
                                     r: trs.rotation.real)

    return TRS(translation: flippedTranslation,
               rotation: flippedRotation,
               scale: flippedScale)
}

func composeTRS(_ trs: TRS) -> simd_float4x4 {
    let translationMatrix = float4x4(translation: trs.translation)
    let rotationMatrix = float4x4(trs.rotation)
    let scaleMatrix = float4x4(scale: trs.scale)

    return translationMatrix * rotationMatrix * scaleMatrix
}

extension float4x4 {
    init(translation t: SIMD3<Float>) {
        self = simd_float4x4(
            SIMD4(1, 0, 0, 0),
            SIMD4(0, 1, 0, 0),
            SIMD4(0, 0, 1, 0),
            SIMD4(t, 1)
        )
    }

    init(scale s: SIMD3<Float>) {
        self = simd_float4x4(
            SIMD4(s.x, 0, 0, 0),
            SIMD4(0, s.y, 0, 0),
            SIMD4(0, 0, s.z, 0),
            SIMD4(0, 0, 0, 1)
        )
    }
}

func flipToLeftHanded(_ transform: simd_float4x4) -> simd_float4x4 {
    let trsRH = decomposeTRS(transform)
    let trsLH = flipToLeftHanded(trsRH)
    let modelMatrixLH = composeTRS(trsLH)

    return modelMatrixLH
}

func orthographicMatrix(xmag: Float, ymag: Float, near: Float, far: Float) -> simd_float4x4 {
    return simd_float4x4(
        SIMD4<Float>(2 / xmag, 0, 0, 0),
        SIMD4<Float>(0, 2 / ymag, 0, 0),
        SIMD4<Float>(0, 0, 1 / (far - near), 0),
        SIMD4<Float>(0, 0, -near / (far - near), 1)
    )
}

func perspectiveMatrix(fov: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
    let f = 1.0 / tan(fov / 2.0)
    return simd_float4x4(
        simd_float4(f / aspect, 0,  0,  0),
        simd_float4(0, f,  0,  0),
        simd_float4(0, 0, far / (far - near), 1),
        simd_float4(0, 0, -far * near / (far - near), 0)
    )
}
