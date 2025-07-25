import Foundation
import ModelIO

public class GLTFTransform: NSObject, MDLTransformComponent {
    public var matrix: matrix_float4x4

    public var resetsTransform: Bool

    public let minimumTime: TimeInterval

    public let maximumTime: TimeInterval

    public let keyTimes: [NSNumber]


    init(matrix: matrix_float4x4) {
        self.matrix = matrix
        self.resetsTransform = false
        self.minimumTime = 0.0
        self.maximumTime = 0.0
        self.keyTimes = []
    }
}
