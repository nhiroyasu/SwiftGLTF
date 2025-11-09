import MetalKit
import SwiftGLTFShaderTypes

extension NodeCameraUniforms {
    static func makeDummyBuffer(device: MTLDevice) -> MTLBuffer {
        var dummy: NodeCameraUniforms = .init(
            projectionType: CameraProjectionTypePerspective,
            nodeHierarchyOffset: 0,
            znear: 0,
            zfar: 1,
            fov: SIMD2<Float>(0, 0),
            aspectRatio: -1,
            xmag: 0,
            ymag: 0
        )
        return device.makeBuffer(
            bytes: &dummy,
            length: MemoryLayout<NodeCameraUniforms>.size
        )!
    }
}
