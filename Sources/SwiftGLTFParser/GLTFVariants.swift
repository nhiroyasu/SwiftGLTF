import ModelIO

public struct GLTFVariant: Equatable {
    public let index: Int
    public let name: String
}

public class GLTFVariants: MDLObject {
    public let variants: [GLTFVariant]

    init(variants: [GLTFVariant]) {
        self.variants = variants
        super.init()
    }
}

public struct GLTFVariantMapping: Equatable {
    public let variants: [Int]
    public let materialIndex: Int
}
