import MetalKit
import Accelerate
import SwiftGLTF

class WireframeMeshLoader {
    let pipelineStateLoader: WireframePipelineStateLoader
    let depthStencilStateLoader: DepthStencilStateLoader

    init(
        pipelineStateLoader: WireframePipelineStateLoader,
        depthStencilStateLoader: DepthStencilStateLoader
    ) {
        self.pipelineStateLoader = pipelineStateLoader
        self.depthStencilStateLoader = depthStencilStateLoader
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

            var vertexUniforms = PBRVertexUniforms(
                hasTangent: false, hasUV: false, hasModulationColor: false
            )

            var model = transform

            let pbrMesh = PBRMesh(
                vertexBuffer: mtkMesh.vertexBuffers[0].buffer,
                vertexUniformsBuffer: device.makeBuffer(
                    bytes: &vertexUniforms,
                    length: MemoryLayout<PBRVertexUniforms>.size,
                )!,
                submeshes: submeshes,
                modelBuffer: device.makeBuffer(
                    bytes: &model,
                    length: MemoryLayout<float4x4>.size
                )!,
                pso: try pipelineStateLoader.load(for: mtkMesh.vertexDescriptor),
                dso: try depthStencilStateLoader.load(for: .lessThan)
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
