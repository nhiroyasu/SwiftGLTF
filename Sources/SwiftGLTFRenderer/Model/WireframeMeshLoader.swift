import MetalKit
import Accelerate
import SwiftGLTF

class WireframeMeshLoader {
    private let device: MTLDevice

    let vertexFunction: MTLFunction
    let fragmentFunction: MTLFunction
    let pipelineState: MTLRenderPipelineState
    let depthStencilState: MTLDepthStencilState

    init(
        device: MTLDevice,
        library: MTLLibrary,
        config: PipelineStateLoaderConfig
    ) throws {
        self.device = device
        self.vertexFunction = library.makeFunction(name: "wireframe_vertex_shader")!
        self.fragmentFunction = library.makeFunction(name: "wireframe_shader")!

        let psoDescriptor = MTLRenderPipelineDescriptor()
        psoDescriptor.vertexFunction = vertexFunction
        psoDescriptor.fragmentFunction = fragmentFunction
        psoDescriptor.colorAttachments[0].pixelFormat = config.colorPixelFormat
        psoDescriptor.depthAttachmentPixelFormat = config.depthPixelFormat
        psoDescriptor.rasterSampleCount = config.sampleCount
        psoDescriptor.vertexDescriptor = makeGLTFVertexDescriptor()
        self.pipelineState = try device.makeRenderPipelineState(descriptor: psoDescriptor)

        let descriptor = MTLDepthStencilDescriptor()
        descriptor.label = "Less Than Depth Stencil State"
        descriptor.depthCompareFunction = .less
        descriptor.isDepthWriteEnabled = true
        if let depthStencilState = device.makeDepthStencilState(descriptor: descriptor) {
            self.depthStencilState = depthStencilState
        } else {
            throw NSError(domain: "DepthStencilStateLoader", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create depth stencil state"])
        }
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
