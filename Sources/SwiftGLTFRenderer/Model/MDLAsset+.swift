import ModelIO
import SwiftGLTFParser

extension MDLAsset {
    var primitiveMeshes: [GLTFPrimitiveMesh] {
        var meshes: [GLTFPrimitiveMesh] = []
        for obj in object(atPath: GLTFAssetPath.meshes).children.objects {
            if let primitiveMesh = obj as? GLTFPrimitiveMesh {
                meshes.append(primitiveMesh)
            } else {
                assertionFailure("Expected GLTFPrimitiveMesh at path \(GLTFAssetPath.meshes), found \(type(of: obj))")
            }
        }
        return meshes
    }

    var mdlMeshes: [MDLMesh] {
        var meshes: [MDLMesh] = []
        for obj in object(atPath: GLTFAssetPath.meshes).children.objects {
            if let primitiveMesh = obj as? GLTFPrimitiveMesh {
                for mesh in primitiveMesh.children.objects {
                    if let mesh = mesh as? MDLMesh {
                        meshes.append(mesh)
                    } else {
                        assertionFailure("Expected MDLMesh at path \(GLTFAssetPath.meshes)/Primitive_{N}, found \(type(of: obj))")
                    }
                }
            } else {
                assertionFailure("Expected GLTFPrimitiveMesh at path \(GLTFAssetPath.meshes), found \(type(of: obj))")
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

    var gltfMaterials: GLTFMaterials? {
        objectSafe(atPath: GLTFAssetPath.materials) as? GLTFMaterials
    }

    func objectSafe(atPath: String) -> MDLObject? {
        self.object(atPath: atPath) as? MDLObject
    }
}
