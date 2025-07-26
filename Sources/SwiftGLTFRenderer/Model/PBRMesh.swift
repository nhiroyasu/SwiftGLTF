import MetalKit

struct PBRMesh {
    let vertexBuffer: MTLBuffer
    let vertexUniformsBuffer: MTLBuffer
    let submeshes: [Submesh]
    let modelBuffer: MTLBuffer
    let pso: MTLRenderPipelineState
    let dso: MTLDepthStencilState

    struct Submesh {
        let primitiveType: MTLPrimitiveType
        let indexCount: Int
        let indexType: MTLIndexType
        let indexBuffer: MTKMeshBuffer
        let baseColorTexture: MTLTexture?
        let baseColorSampler: MTLSamplerState?
        let normalTexture: MTLTexture?
        let normalSampler: MTLSamplerState?
        let metallicRoughnessTexture: MTLTexture?
        let metallicRoughnessSampler: MTLSamplerState?
        let emissiveTexture: MTLTexture?
        let emissiveSampler: MTLSamplerState?
        let occlusionTexture: MTLTexture?
        let occlusionSampler: MTLSamplerState?
    }
}
