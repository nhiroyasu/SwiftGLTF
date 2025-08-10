import MetalKit

struct PBRMesh {
    let vertexBuffer: MTLBuffer
    let modelBuffer: MTLBuffer
    let modelMatrix: simd_float4x4
    let submeshes: [Submesh]

    struct Submesh {
        let primitiveType: MTLPrimitiveType
        let indexCount: Int
        let indexType: MTLIndexType
        let indexBuffer: MTKMeshBuffer
        let fragmentArgumentBuffer: MTLBuffer
        let alphaMode: AlphaMode
        let alphaCutoff: Float
        // Center of the mesh primitive in model space
        let centerModelSpace: SIMD3<Float>
        let _storedHeapInstance: [Any?]
    }
}

struct PBRMeshContainer {
    let meshes: [PBRMesh]
    let vertexResources: [MTLHeap]
    let fragmentResources: [MTLHeap]
}

enum AlphaMode: UInt32 {
    case opaque = 0
    case mask = 1
    case blend = 2
}
