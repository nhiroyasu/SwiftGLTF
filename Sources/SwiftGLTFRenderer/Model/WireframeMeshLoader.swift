import MetalKit
import Accelerate
import SwiftGLTFParser

class WireframeMeshLoader {
    private let device: MTLDevice
    private let pipelineConnector: WireframePipelineConnector

    init(device: MTLDevice, pipelineConnector: WireframePipelineConnector) {
        self.device = device
        self.pipelineConnector = pipelineConnector
    }

    func loadMeshes(from asset: MDLAsset) throws -> [PBRMesh] {
        var pbrMeshes: [PBRMesh] = []

        for i in 0..<asset.count {
            let rootObj = asset.object(at: i)
            let meshes = try loadRecursiveMeshes(
                device: device,
                obj: rootObj,
                parentTransform: simd_float4x4(1),
                parentTransformTree: []
            )
            pbrMeshes.append(contentsOf: meshes)
        }

        return pbrMeshes
    }

    private func loadRecursiveMeshes(
        device: MTLDevice,
        obj: MDLObject,
        parentTransform: simd_float4x4,
        parentTransformTree: [simd_float4x4]
    ) throws -> [PBRMesh] {
        var pbrMeshes: [PBRMesh] = []

        let selfTransform = obj.transform?.matrix ?? simd_float4x4(1)
        let totalTransform = parentTransform * selfTransform
        let transformTree = parentTransformTree + [selfTransform]

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
                    centerModelSpace: .zero,
                    doubleSided: true,
                    _storedHeapInstance: []
                )
                submeshes.append(submeshData)
            }

            var model = totalTransform
            let modelBuffer = device.makeBuffer(bytes: &model, length: MemoryLayout<simd_float4x4>.size, options: [.storageModeShared])!
            let vertexArgumentBuffer = try pipelineConnector.makeVertexArgumentsBuffer(
                modelBuffer: modelBuffer
            )

            let pbrMesh = PBRMesh(
                vertexBuffer: mtkMesh.vertexBuffers[0].buffer,
                vertexArgumentBuffer: vertexArgumentBuffer,
                submeshes: submeshes,
                animation: nil,
                modelMatrix: model,
                modelMatrixTree: transformTree,
                skeleton: nil,
                _storedHeapInstance: [modelBuffer]
            )
            pbrMeshes.append(pbrMesh)
        }

        for childObj in obj.children.objects {
            let childMeshes = try loadRecursiveMeshes(
                device: device,
                obj: childObj,
                parentTransform: totalTransform,
                parentTransformTree: transformTree
            )
            pbrMeshes.append(contentsOf: childMeshes)
        }

        return pbrMeshes
    }
}
