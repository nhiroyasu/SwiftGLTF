import MetalKit
import Accelerate
import SwiftGLTF

class WireframeMeshLoader {
    let pipelineStateLoader: WireframePipelineStateLoader

    init(pipelineStateLoader: WireframePipelineStateLoader) {
        self.pipelineStateLoader = pipelineStateLoader
    }

    func loadMeshes(from asset: MDLAsset, using device: MTLDevice) throws -> [PBRMesh] {
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
                let submeshData = PBRMesh.Submesh(
                    primitiveType: mtkSubmesh.primitiveType,
                    indexCount: mtkSubmesh.indexCount,
                    indexType: mtkSubmesh.indexType,
                    indexBuffer: mtkSubmesh.indexBuffer,
                    baseColorTexture: nil,
                    baseColorSampler: nil,
                    normalTexture: nil,
                    normalSampler: nil,
                    metallicRoughnessTexture: nil,
                    metallicRoughnessSampler: nil,
                    emissiveTexture: nil,
                    emissiveSampler: nil,
                    occlusionTexture: nil,
                    occlusionSampler: nil
                )
                submeshes.append(submeshData)
            }

            let pbrMesh = PBRMesh(
                vertexBuffer: mtkMesh.vertexBuffers[0].buffer,
                submeshes: submeshes,
                transform: transform,
                modelBuffer: device.makeBuffer(
                    length: MemoryLayout<float4x4>.size,
                    options: []
                )!,
                normalMatrixBuffer: device.makeBuffer(
                    length: MemoryLayout<float3x3>.size,
                    options: []
                )!,
                pso: try pipelineStateLoader.load(for: mtkMesh.vertexDescriptor)
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
