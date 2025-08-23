import Foundation
import ModelIO

@objc public protocol GLTFMorphTargetsProtocol: MDLComponent {}

public class GLTFMorphTargets: NSObject, GLTFMorphTargetsProtocol {
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

@objc public protocol GLTFMorphWeightsProtocol: MDLComponent {}

public class GLTFMorphWeights: NSObject, GLTFMorphWeightsProtocol {
    public var weights: [Float]

    public init(weights: [Float]) {
        self.weights = weights
    }
}
