import Foundation

public struct GLTFDecodeOptions: Sendable {
    /// Converts the model to left-handed coordinate system if true.
    public let convertToLeftHanded: Bool
    /// Automatically scales the model based on the maximum position value.
    public let autoScale: Bool

    public static let `default` = GLTFDecodeOptions()

    public init(
        convertToLeftHanded: Bool = true,
        autoScale: Bool = true
    ) {
        self.convertToLeftHanded = convertToLeftHanded
        self.autoScale = autoScale
    }
}
