import MetalKit

struct PBRMesh {
    let vertexBuffer: MTLBuffer
    let modelBuffer: MTLBuffer
    let submeshes: [Submesh]

    struct Submesh {
        let primitiveType: MTLPrimitiveType
        let indexCount: Int
        let indexType: MTLIndexType
        let indexBuffer: MTKMeshBuffer
        let fragmentArgumentBuffer: MTLBuffer
        let _storedHeapInstance: [Any?]
    }
}

struct PBRMeshContainer {
    let meshes: [PBRMesh]
    let vertexResources: [MTLHeap]
    let fragmentResources: [MTLHeap]
}
