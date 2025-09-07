import MetalKit
import SwiftGLTFCore
import SwiftGLTFParser
import SwiftGLTFShaderTypes

struct PBRMeshBundle {
    let meshes: [PBRMesh]

    // Buffers
    let worldTransformBuffer: MTLBuffer
    let jointsBuffer: MTLBuffer
    let inverseBindMatricesBuffer: MTLBuffer
    let morphWeightsBuffer: MTLBuffer
    let morphDispatchesBuffer: MTLBuffer
    let boundingSpheresBuffer: MTLBuffer

    // Animation
    let animations: [PBRMeshAnimation]

    // Animation related metadata
    let nodeLevelHierarchy: NodeLevelHierarchy
    let originMorphWeights: [Float]
    let morphDispatches: [MorphDispatch]

    // Resources
    let vertexResources: [MTLHeap]
    let fragmentResources: [MTLHeap]
}

struct PBRMeshAnimation {
    let targetNode: NodeHierarchyOffset
    let type: GLTFAnimationType
    let keyframes: [Float]
    let duration: Float
    let interpolation: GLTFInterpolation
}

struct PBRMesh {
    let vertexBuffer: MTLBuffer
    let vertexArgumentBuffer: MTLBuffer
    let submeshes: [Submesh]
    let modelMatrix: float4x4 // TODO: delete
    let transformIndex: Int
    let vertexCount: Int
    let positionStride: Int
    let positionOffset: Int
    let _storedHeapInstance: [MTLResource?]

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
        let doubleSided: Bool
        let _storedHeapInstance: [Any?]
    }
}

enum AlphaMode: UInt32 {
    case opaque = 0
    case mask = 1
    case blend = 2
}
