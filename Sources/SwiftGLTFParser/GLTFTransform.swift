import Foundation
import ModelIO
import SwiftGLTFCore

public class GLTFTransform: NSObject, MDLTransformComponent {
    public var matrix: matrix_float4x4 {
        get {
            trs2matrix(trs)
        }
        set {
            // Decompose the matrix into translation, rotation, and scale
            let decomposed = decomposeTRS(newValue)
            self.translation = decomposed.translation
            self.rotation = decomposed.rotation
            self.scale = decomposed.scale
        }
    }
    public var resetsTransform: Bool
    public let minimumTime: TimeInterval
    public let maximumTime: TimeInterval
    public let keyTimes: [NSNumber]

    public var translation: SIMD3<Float>
    public var rotation: simd_quatf
    public var scale: SIMD3<Float>
    public var trs: TRS {
        TRS(
            translation: translation,
            rotation: rotation,
            scale: scale
        )
    }


    init(matrix: matrix_float4x4) {
        self.resetsTransform = false
        self.minimumTime = 0.0
        self.maximumTime = 0.0
        self.keyTimes = []

        let decomposed = decomposeTRS(matrix)
        self.translation = decomposed.translation
        self.rotation = decomposed.rotation
        self.scale = decomposed.scale
    }

    init(translation: SIMD3<Float>, rotation: simd_quatf, scale: SIMD3<Float>) {
        self.resetsTransform = false
        self.minimumTime = 0.0
        self.maximumTime = 0.0
        self.keyTimes = []
        self.translation = translation
        self.rotation = rotation
        self.scale = scale
    }
}
