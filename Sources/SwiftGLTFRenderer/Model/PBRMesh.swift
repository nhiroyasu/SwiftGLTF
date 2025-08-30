import MetalKit
import SwiftGLTFCore
import SwiftGLTFParser

struct PBRMeshContainer {
    let meshes: [PBRMesh]
    let vertexResources: [MTLHeap]
    let fragmentResources: [MTLHeap]
}

struct PBRMesh {
    let vertexBuffer: MTLBuffer
    let vertexArgumentBuffer: MTLBuffer
    let submeshes: [Submesh]
    let animation: Animation?
    let modelMatrix: float4x4
    let modelMatrixTree: [float4x4]
    let skeleton: Skeleton?
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

    struct Animation {
        let channels: [AnimationChannel]
        let duration: Float
        let animatableBuffers: AnimatableBuffers
    }

    struct AnimationChannel {
        let type: GLTFAnimationType
        let interpolation: GLTFInterpolation
        let input: [Float]
        let modelMatrixTreeEffectIndex: Int?
        let globalJointNodeTreeEffectIndex: Int?
        let globalJointMatrixTreeEffectIndex: Int?

        var hint: Hint = .init()
        class Hint {
            var cursor: Int = 0
        }
    }

    struct AnimatableBuffers {
        let modelBuffer: MTLBuffer
        let inverseModelBuffer: MTLBuffer
        let globalJointMatricesBuffer: MTLBuffer?
        let morphWeightsBuffer: MTLBuffer?
    }

    struct AnimateMatrixEffectTree {
        private let matrixTree: [float4x4]
        private let targetIndex: Int

        func transform(_ animation: float4x4) -> float4x4 {
            var t = float4x4(1)
            for (i, parent) in matrixTree.enumerated() {
                if i == targetIndex {
                    t = animation * t
                } else {
                    t = parent * t
                }
            }
            return t
        }
    }

    struct Skeleton {
        let buffer: MTLBuffer
        let jointMatrices: [float4x4]
        let joints: [Joint]

        struct Joint {
            let node: MDLObject
            let inverseBindMatrix: float4x4
            let globalJointMatrixTree: [float4x4]
            let globalJointTRSTree: [TRS]
        }
    }
}

enum AlphaMode: UInt32 {
    case opaque = 0
    case mask = 1
    case blend = 2
}
