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
    public static var libraries: String {
        "/\(GLTFAssetName.libraries)"
    }
    public static var skins: String {
        "/\(GLTFAssetName.libraries)/\(GLTFAssetName.skins)"
    }
}

public enum GLTFAssetName {
    public static let scenes = "Scenes"
    public static func scene(_ i: Int) -> String { "Scene_\(i)" }
    public static let nodes = "Nodes"
    public static let libraries = "Libraries"
    public static let skins = "Skins"
}
