import simd

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

func quaternionMatrix(_ q: simd_quatf) -> simd_float4x4 {
    let r = quaternionToMatrix3x3(q)
    return simd_float4x4(
        SIMD4(r.columns.0, 0),
        SIMD4(r.columns.1, 0),
        SIMD4(r.columns.2, 0),
        SIMD4(0, 0, 0, 1)
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
    var matrix = matrix_identity_float4x4
    matrix.columns.3 = simd_float4(x, y, z, 1.0)
    return matrix
}

func scaleMatrix(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
    var matrix = matrix_identity_float4x4
    matrix.columns.0.x = x
    matrix.columns.1.y = y
    matrix.columns.2.z = z
    return matrix
}

struct TRS {
    var translation: SIMD3<Float>
    var rotation: simd_quatf
    var scale: SIMD3<Float>
}

func decomposeTRS(_ m: simd_float4x4) -> TRS {
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
        self = matrix_identity_float4x4
        columns.3 = SIMD4(t.x, t.y, t.z, 1.0)
    }

    init(scale s: SIMD3<Float>) {
        self = matrix_identity_float4x4
        columns.0.x = s.x
        columns.1.y = s.y
        columns.2.z = s.z
    }

    init(_ q: simd_quatf) {
        self = quaternionMatrix(q)
    }
}

func flipToLeftHanded(_ transform: simd_float4x4) -> simd_float4x4 {
    let trsRH = decomposeTRS(transform)
    let trsLH = flipToLeftHanded(trsRH)
    let modelMatrixLH = composeTRS(trsLH)

    return modelMatrixLH
}
