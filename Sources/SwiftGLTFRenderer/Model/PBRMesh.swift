import MetalKit
import SwiftGLTFCore
import SwiftGLTFParser
import SwiftGLTFShaderTypes

struct PBRMeshBundle {
    let meshes: [PBRMesh]
    let opaqueMeshes: [PBRMesh]
    let maskedMeshes: [PBRMesh]
    let blendedMeshes: [PBRMesh]
    let transmissionMeshes: [PBRMesh]

    // Buffers
    let worldTransformBuffer: MTLBuffer
    let jointsBuffer: MTLBuffer
    let inverseBindMatricesBuffer: MTLBuffer
    let morphWeightsBuffer: MTLBuffer
    let morphDispatchesBuffer: MTLBuffer
    let boundingSpheresBuffer: MTLBuffer

    // Materials
    let materialBuffer: MTLBuffer
    let materialResources: [Any?]

    // Animation
    let animations: [PBRMeshAnimation]

    // Animation related metadata
    let nodeLevelHierarchy: NodeLevelHierarchy
    let originMorphWeights: [Float]
    let morphDispatches: [MorphDispatch]

    // Cameras
    let nodeCameraUniformsBuffer: MTLBuffer

    // Resources
    let vertexResources: [MTLResource]
    let vertexHeaps: [MTLHeap]
    let fragmentHeaps: [MTLHeap]
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
    let renderingType: RenderingType
    let vertexResources: [MTLResource?]
    let _storedHeapInstance: [MTLResource?]

    struct Submesh {
        let primitiveType: MTLPrimitiveType
        let indexCount: Int
        let indexType: MTLIndexType
        let indexBuffer: MTKMeshBuffer
        let materialIndex: Int
        let alphaMode: SwiftGLTFShaderTypes.AlphaMode
        let alphaCutoff: Float
        // Center of the mesh primitive in model space
        let centerModelSpace: SIMD3<Float>
        let doubleSided: Bool
        let _storedHeapInstance: [Any?]
    }

    enum RenderingType {
        case opaque
        case masked
        case blended
        case transmission
    }
}
