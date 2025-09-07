import MetalKit
import SwiftGLTFCore
import SwiftGLTFParser
import SwiftGLTFShaderTypes

struct WireframeMeshBundle {
    let meshes: [WireframeMesh]

    // Buffers
    let worldTransformBuffer: MTLBuffer
}


struct WireframeMesh {
    let vertexBuffer: MTLBuffer
    let transformIndex: Int
    let submeshes: [Submesh]

    struct Submesh {
        let primitiveType: MTLPrimitiveType
        let indexCount: Int
        let indexType: MTLIndexType
        let indexBuffer: MTKMeshBuffer
    }
}
