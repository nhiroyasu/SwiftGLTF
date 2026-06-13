import MetalKit
import SwiftGLTFCore
import SwiftGLTFParser
import SwiftGLTFShaderTypes

public struct PBRMeshBundle: Identifiable {
    public let id: UUID = UUID()
    let meshes: [PBRMesh]
    let opaqueMeshes: [PBRMesh]
    let maskedMeshes: [PBRMesh]
    let blendedMeshes: [PBRMesh]
    let transmissionMeshes: [PBRMesh]

    // Relation table buffers
    let worldTransformBuffer: MTLBuffer
    let jointsBuffer: MTLBuffer
    let inverseBindMatricesBuffer: MTLBuffer
    let morphWeightsBuffer: MTLBuffer
    let morphDispatchesBuffer: MTLBuffer
    let boundingSpheresBuffer: MTLBuffer
    let nodeCameraUniformsBuffer: MTLBuffer
    let materialBuffer: MTLBuffer
    let materialResources: [Any?]

    var relationTableResources: [MTLResource] {
        [
            worldTransformBuffer,
            jointsBuffer,
            inverseBindMatricesBuffer,
            morphWeightsBuffer,
            morphDispatchesBuffer,
            boundingSpheresBuffer,
            nodeCameraUniformsBuffer,
            materialBuffer
        ]
    }

    // Animation
    let animations: [PBRMeshAnimation]

    // Animation related metadata
    let nodeLevelHierarchy: NodeLevelHierarchy
    let originMorphWeights: [Float]
    let morphDispatches: [MorphDispatch]
    let vrmHumanoidNodeMap: [VRMHumanoidBoneName: NodeHierarchyOffset]
    let vrmExpressions: [VRMExpression]

    // Resources
    let vertexHeaps: [MTLHeap]
    let fragmentHeaps: [MTLHeap]

    var heaps: [MTLHeap] {
        vertexHeaps + fragmentHeaps
    }

    var needsTransmissionPass: Bool {
        transmissionMeshes.count > 0
    }
    var needsAnimationPass: Bool {
        animations.count > 0
    }
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
    let _storedHeapInstance: [MTLResource?]

    struct Submesh {
        let primitiveType: MTLPrimitiveType
        let indexCount: Int
        let indexType: MTLIndexType
        let indexBuffer: MTLBuffer
        let indexBufferOffset: Int
        let materialIndex: Int
        let materialIndexBuffer: MTLBuffer
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
