import SwiftGLTFShaderTypes

extension FreeCameraUniforms {
    public static func build(
        eye: simd_float3,
        target: simd_float3 = simd_float3(0, 0, 0),
        upSign: Float = 1.0,
        aspect: Float,
        fovY: Float
    ) -> Self {
        let view = lookAt(
            eye: eye,
            target: target,
            up: simd_float3(0, upSign, 0)
        )
        let fovX = 2 * atan(tan(fovY / 2) * aspect)
        let projection = perspectiveMatrix(
            fov: fovY,
            aspect: aspect,
            near: 0.1,
            far: 1000.0
        )
        
        let camRight = simd_float3(1, 0, 0)
        let camUp = simd_float3(0, 1, 0)

        return FreeCameraUniforms(
            viewMatrix: view,
            projectionMatrix: projection,
            position: eye,
            fov: SIMD2<Float>(fovX, fovY),
            camRight: camRight,
            camUp: camUp,
            aspectRatio: aspect
        )
    }
}
