import ModelIO

public enum GLTFAssetPath {
    public static var scenes: String {
        "/\(GLTFAssetName.scenes)"
    }
    public static func scene(_ i: Int) -> String {
        "/\(GLTFAssetName.scenes)/\(GLTFAssetName.scene(i))"
    }
    public static func nodes(atScene: Int) -> String {
        "\(Self.scene(atScene))/\(GLTFAssetName.nodes)"
    }
    public static var cameras: String {
        "/\(GLTFAssetName.cameras)"
    }
    public static var libraries: String {
        "/\(GLTFAssetName.libraries)"
    }
    public static var materials: String {
        "/\(GLTFAssetName.libraries)/\(GLTFAssetName.materials)"
    }
    public static var variants: String {
        "/\(GLTFAssetName.libraries)/\(GLTFAssetName.variants)"
    }
    public static var skins: String {
        "/\(GLTFAssetName.libraries)/\(GLTFAssetName.skins)"
    }
    public static var meshes: String {
        "/\(GLTFAssetName.libraries)/\(GLTFAssetName.meshes)"
    }
    public static func primitiveMesh(_ i: Int) -> String {
        "/\(GLTFAssetName.libraries)/\(GLTFAssetName.meshes)/\(GLTFAssetName.primitive(i))"
    }
}

public enum GLTFAssetName {
    public static let scenes = "Scenes"
    public static func scene(_ i: Int) -> String { "Scene_\(i)" }
    public static let nodes = "Nodes"
    public static let libraries = "Libraries"
    public static let materials = "Materials"
    public static let variants = "Variants"
    public static let skins = "Skins"
    public static let meshes = "Meshes"
    public static let cameras = "Cameras"
    public static func primitive(_ i: Int) -> String { "Primitive_\(i)" }
}
