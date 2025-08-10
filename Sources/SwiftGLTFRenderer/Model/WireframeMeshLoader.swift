import MetalKit
import Accelerate
import SwiftGLTFParser

class WireframeMeshLoader {
    private let device: MTLDevice

    init(device: MTLDevice) {
        self.device = device
    }

    func loadMeshes(from asset: MDLAsset) throws -> [PBRMesh] {
        var pbrMeshes: [PBRMesh] = []

        for i in 0..<asset.count {
            let rootObj = asset.object(at: i)
            let meshes = try loadRecursiveMeshes(
                device: device,
                obj: rootObj,
                parentTransform: simd_float4x4(1)
            )
            pbrMeshes.append(contentsOf: meshes)
        }

        return pbrMeshes
    }

    private func loadRecursiveMeshes(
        device: MTLDevice,
        obj: MDLObject,
        parentTransform: simd_float4x4
    ) throws -> [PBRMesh] {
        var pbrMeshes: [PBRMesh] = []

        let transform = parentTransform * (obj.transform?.matrix ?? simd_float4x4(1))

        if let mdlMesh = obj as? MDLMesh {
            let mtkMesh = try MTKMesh(mesh: mdlMesh, device: device)

            var submeshes: [PBRMesh.Submesh] = []
            for mtkSubmesh in mtkMesh.submeshes {
                // Create a dummy material uniforms buffer (unused in wireframe rendering)
                let submeshData = PBRMesh.Submesh(
                    primitiveType: mtkSubmesh.primitiveType,
                    indexCount: mtkSubmesh.indexCount,
                    indexType: mtkSubmesh.indexType,
                    indexBuffer: mtkSubmesh.indexBuffer,
                    fragmentArgumentBuffer: device.makeBuffer(length: MemoryLayout<Int>.size, options: [])!,
                    alphaMode: .opaque,
                    alphaCutoff: 0.5,
                    _storedHeapInstance: []
                )
                submeshes.append(submeshData)
            }

            var model = transform

            let pbrMesh = PBRMesh(
                vertexBuffer: mtkMesh.vertexBuffers[0].buffer,
                modelBuffer: device.makeBuffer(
                    bytes: &model,
                    length: MemoryLayout<float4x4>.size
                )!,
                modelMatrix: model,
                submeshes: submeshes
            )
            pbrMeshes.append(pbrMesh)
        }

        for childObj in obj.children.objects {
            let childMeshes = try loadRecursiveMeshes(
                device: device,
                obj: childObj,
                parentTransform: transform
            )
            pbrMeshes.append(contentsOf: childMeshes)
        }

        return pbrMeshes
    }
}
