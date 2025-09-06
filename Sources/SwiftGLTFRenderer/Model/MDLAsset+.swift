import ModelIO
import SwiftGLTFParser

extension MDLAsset {
    var gltfMeshes: [MDLMesh] {
        var meshes: [MDLMesh] = []
        for obj in object(atPath: GLTFAssetPath.meshes).children.objects {
            if let mesh = obj as? MDLMesh {
                meshes.append(mesh)
            } else {
                assertionFailure("Expected MDLMesh at path \(GLTFAssetPath.meshes), found \(type(of: obj))")
            }
        }
        return meshes
    }

    var skins: [GLTFSkin] {
        var skins: [GLTFSkin] = []
        for obj in object(atPath: GLTFAssetPath.skins).children.objects {
            if let skin = obj as? GLTFSkin {
                skins.append(skin)
            } else {
                assertionFailure("Expected GLTFSkeleton at path \(GLTFAssetPath.skins), found \(type(of: obj))")
            }
        }
        return skins
    }
}
