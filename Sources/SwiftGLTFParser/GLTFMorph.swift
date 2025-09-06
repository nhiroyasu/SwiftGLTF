import Foundation
import ModelIO

@objc public protocol GLTFMorphTargets: MDLComponent {
    var vertexCount: Int { get }
    var targetCount: Int { get }
    var targetMeshes: [MDLMesh] { get }
    var defaultWeights: [Float] { get }
    var targetNames: [String]? { get }
}

public class GLTFMorphTargetsImpl: NSObject, GLTFMorphTargets {
    public let vertexCount: Int
    public let targetCount: Int

    /// One mesh per glTF primitive target. Each mesh's vertex buffer packs
    /// float3 positionDelta, float3 normalDelta, float3 tangentDelta per vertex.
    public let targetMeshes: [MDLMesh]

    public let defaultWeights: [Float]
    public let targetNames: [String]?

    public init(
        vertexCount: Int,
        targetCount: Int,
        targetMeshes: [MDLMesh],
        defaultWeights: [Float],
        targetNames: [String]? = nil
    ) {
        self.vertexCount = vertexCount
        self.targetCount = targetCount
        self.targetMeshes = targetMeshes
        self.defaultWeights = defaultWeights
        self.targetNames = targetNames
    }
}

@objc public protocol GLTFMorphWeights: MDLComponent {
    var weights: [Float] { get }
}

public class GLTFMorphWeightsImpl: NSObject, GLTFMorphWeights {
    public let weights: [Float]

    public init(weights: [Float]) {
        self.weights = weights
    }
}
