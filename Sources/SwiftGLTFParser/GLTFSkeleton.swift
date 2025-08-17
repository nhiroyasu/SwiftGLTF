import SwiftGLTFCore
import ModelIO

public class GLTFSkeleton: MDLSkeleton {
    public let joins: [NodeIndex]
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
        self.joins = joins
        self.inverseBindMatrices = inverseBindMatrices
        self._jointObjects = Array(repeating: MDLObject(), count: joins.count)
        super.init(name: name, jointPaths: [])
    }

    func setJointObject(_ obj: MDLObject, for index: Int) {
        guard index >= 0 && index < _jointObjects.count else {
            fatalError("Index out of bounds for joint objects")
        }
        _jointObjects[index] = obj
    }
}
