import UniformTypeIdentifiers

public extension UTType {
    static var gltf: UTType {
        UTType(importedAs: "org.khronos.gltf")
    }

    static var glb: UTType {
        UTType(importedAs: "org.khronos.glb")
    }

    static var vrm: UTType {
        UTType(importedAs: "org.khronos.vrm")
    }
}
