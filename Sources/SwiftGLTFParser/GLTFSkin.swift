import SwiftGLTFCore
import ModelIO

public class GLTFSkin: MDLSkeleton {
    public let joints: [NodeIndex]
    public let inverseBindMatrices: MDLMatrix4x4Array

    public override var jointPaths: [String] {
        joints.map { "\(GLTFAssetPath.nodes)/\(GLTFAssetName.node($0))" }
    }

    public override var jointBindTransforms: MDLMatrix4x4Array {
        let matrixArray = MDLMatrix4x4Array(elementCount: inverseBindMatrices.elementCount)
        matrixArray.float4x4Array = inverseBindMatrices.float4x4Array.map { $0.inverse }
        return matrixArray
    }

    init(name: String, joins: [NodeIndex], inverseBindMatrices: MDLMatrix4x4Array) {
        self.joints = joins
        self.inverseBindMatrices = inverseBindMatrices
        super.init(name: name, jointPaths: [])
    }
}

@objc public protocol GLTFSkeletonRef: MDLComponent {
    var skeleton: GLTFSkin { get }
}

class GLTFSkeletonRefImpl: NSObject, GLTFSkeletonRef {
    let skeleton: GLTFSkin
    init(skeleton: GLTFSkin) {
        self.skeleton = skeleton
    }
}
