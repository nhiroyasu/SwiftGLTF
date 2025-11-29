import MetalKit

struct SkyboxMesh {
    let vertexBuffer: MTLBuffer
    let indexBuffer: MTLBuffer
    let indexCount: Int
    let indexType: MTLIndexType
}
