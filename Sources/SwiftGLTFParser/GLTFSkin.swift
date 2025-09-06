import SwiftGLTFCore
import ModelIO

public class GLTFSkin: MDLSkeleton {
    public let joints: [NodeIndex]
    public let inverseBindMatrices: MDLMatrix4x4Array

    private var _jointObjects: [MDLObject] = []
    public var jointObjects: [MDLObject] {
        _jointObjects
    }

    public override var jointPaths: [String] { _jointObjects.map { $0.path } }

    public override var jointBindTransforms: MDLMatrix4x4Array {
        let matrixArray = MDLMatrix4x4Array(elementCount: inverseBindMatrices.elementCount)
        matrixArray.float4x4Array = inverseBindMatrices.float4x4Array.map { $0.inverse }
        return matrixArray
    }

    init(name: String, joins: [NodeIndex], inverseBindMatrices: MDLMatrix4x4Array) {
        self.joints = joins
        self.inverseBindMatrices = inverseBindMatrices
        self._jointObjects = Array(repeating: MDLObject(), count: joins.count)
        super.init(name: name, jointPaths: [])
    }

    func bind(_ obj: MDLObject, for index: Int) {
        guard index >= 0 && index < _jointObjects.count else {
            fatalError("Index out of bounds for joint objects")
        }
        _jointObjects[index] = obj
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
