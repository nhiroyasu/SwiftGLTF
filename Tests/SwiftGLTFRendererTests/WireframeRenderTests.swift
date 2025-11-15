import Testing
import MetalKit
import CoreGraphics
import UniformTypeIdentifiers
import Img2Cubemap
import SwiftGLTFParser
import SwiftGLTFShaderTypes
@testable import SwiftGLTFRenderer

final class WireframeRenderTests {
    let device: MTLDevice
    let library: MTLLibrary
    let commandQueue: MTLCommandQueue
    let shaderConnection: ShaderConnection

    let TEX_SIZE = 256

    init() {
        self.device = MTLCreateSystemDefaultDevice()!
        self.library = try! device.makePackageLibrary()
        self.commandQueue = device.makeCommandQueue()!

        self.shaderConnection = ShaderConnection(
            device: device,
            library: library,
            commandQueue: commandQueue
        )
    }

    // Helper to create a render target texture
    func makeRenderTarget(width: Int, height: Int) -> MTLTexture {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm_srgb,
            width: width,
            height: height,
            mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        return device.makeTexture(descriptor: desc)!
    }

    func renderMesh(to output: MTLTexture, meshURL: URL, eye: SIMD3<Float>) async throws {
        let pipelineConnector = try WireframePipelineConnector(
            device: device,
            library: library,
            config: PipelineStateLoaderConfig(
                sampleCount: 1,
                colorPixelFormat: output.pixelFormat,
                depthPixelFormat: .depth32Float
            ),
            shaderConnection: shaderConnection
        )
        let loader = WireframeMeshLoader(
            device: device,
            pipelineConnector: pipelineConnector,
            shaderConnection: shaderConnection
        )
        
        // Create view-projection matrix buffer
        let aspect: Float = 1.0
        let view = lookAt(eye: eye, target: SIMD3<Float>(0, 0, 0), up: SIMD3<Float>(0, 1, 0))
        let projection = perspectiveMatrix(fov: .pi / 3, aspect: aspect, near: 0.1, far: 1000.0)
        var modelMatrix = simd_float4x4(1)
        let modelMatrixBuffer = device.makeBuffer(
            bytes: &modelMatrix,
            length: MemoryLayout<simd_float4x4>.size,
            options: .storageModeShared
        )!

        // pipeline state
        let pipelineStateDescriptor = MTLRenderPipelineDescriptor()
        pipelineStateDescriptor.vertexFunction = library.makeFunction(name: "wireframe_vertex_shader")!
        pipelineStateDescriptor.fragmentFunction = library.makeFunction(name: "wireframe_fragment_shader")!
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = output.pixelFormat
        pipelineStateDescriptor.depthAttachmentPixelFormat = .depth32Float
        pipelineStateDescriptor.vertexDescriptor = makeGLTFVertexDescriptor()
        let pipelineState = try await device.makeRenderPipelineState(descriptor: pipelineStateDescriptor)

        // depth stencil state
        let depthStencilDescriptor = MTLDepthStencilDescriptor()
        depthStencilDescriptor.depthCompareFunction = .less
        depthStencilDescriptor.isDepthWriteEnabled = true
        let depthStencilState = device.makeDepthStencilState(descriptor: depthStencilDescriptor)!

        let depthTextureDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float,
            width: output.width,
            height: output.height,
            mipmapped: false
        )
        depthTextureDesc.usage = [.renderTarget, .shaderRead]
        depthTextureDesc.storageMode = .private
        let depthTexture = device.makeTexture(descriptor: depthTextureDesc)!

        var freeCameraUniforms = FreeCameraUniforms(
            viewMatrix: view,
            projectionMatrix: projection,
            position: eye,
            fov: SIMD2<Float>(.pi / 3, .pi / 3),
            camRight: SIMD3<Float>(1, 0, 0),
            camUp: SIMD3<Float>(0, 1, 0),
            aspectRatio: aspect
        )
        let freeCameraUniformsBuffer = device.makeBuffer(
            bytes: &freeCameraUniforms,
            length: MemoryLayout<FreeCameraUniforms>.size,
            options: .storageModeShared
        )!


        // Set up render pass descriptor
        let passDesc = MTLRenderPassDescriptor()
        passDesc.colorAttachments[0].texture = output
        passDesc.colorAttachments[0].loadAction = .clear
        passDesc.colorAttachments[0].storeAction = .store
        passDesc.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        passDesc.depthAttachment.texture = depthTexture
        passDesc.depthAttachment.loadAction = .clear
        passDesc.depthAttachment.storeAction = .store
        passDesc.depthAttachment.clearDepth = 1.0

        // Load a sample mesh
        let asset = try makeMDLAsset(from: meshURL)
        let bundle = try loader.loadMeshes(from: asset)

        // Create command buffer and render encoder
        let cmdBuf = commandQueue.makeCommandBuffer()!
        let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: passDesc)!

        // Draw the mesh
        drawWireframe(
            renderEncoder: encoder,
            pipelineState: pipelineState,
            depthStencilState: depthStencilState,
            meshes: bundle.meshes,
            modelBuffer: modelMatrixBuffer,
            worldTransformBuffer: bundle.worldTransformBuffer,
            freeCameraUniformsBuffer: freeCameraUniformsBuffer
        )

        encoder.endEncoding()
        cmdBuf.commit()
        await cmdBuf.completed()
    }

    // MARK: - Export golden images

    let goldenFilePrefix = "golden_wireframe_mesh_"
    let outputFilePrefix = "wireframe_mesh_"
    let meshNames: [(String, SIMD3<Float>)] = [
        // name, eye
        ("BoxTextured", SIMD3<Float>(-1.41, 1.41, -1.41)),
        ("CompareBaseColor", SIMD3<Float>(-1.41, 1.41, -1.41)),
        ("OrientationTest", SIMD3<Float>(-10.6, 10.6, -10.6)),
        ("TextureCoordinateTest", SIMD3<Float>(-2.83, 2.83, -2.83)),
        ("VertexColorTest", SIMD3<Float>(-1.41, 1.41, -1.41)),
        ("Fox", SIMD3<Float>(-106, 106, -106)),
    ]

    // Export baseline textures
    // These should be run manually to generate expected textures
    @Test
    func ExportGoldenImages() async throws {
        guard EXPORT_GOLDEN_IMAGES_FLAG, !isCI() else { return }

        for (meshName, eye) in meshNames {
            let meshTarget = makeRenderTarget(width: TEX_SIZE, height: TEX_SIZE)
            let meshURL = Bundle.module.url(forResource: meshName, withExtension: "glb")!
            try await renderMesh(to: meshTarget, meshURL: meshURL, eye: eye)
            try export(texture: meshTarget, name: "\(goldenFilePrefix)\(meshName).png")
        }
    }

    // MARK: - Tests

    @Test
    func testMeshRenderingMatchesGolden() async throws {
        for (meshName, eye) in meshNames {
            let meshTarget = makeRenderTarget(width: TEX_SIZE, height: TEX_SIZE)
            let meshURL = Bundle.module.url(forResource: meshName, withExtension: "glb")!
            try await renderMesh(to: meshTarget, meshURL: meshURL, eye: eye)

            assertEqual(output: meshTarget, goldenName: "\(goldenFilePrefix)\(meshName)")

            if EXPORT_OUTPUT_IMAGES_FLAG, !isCI() {
                try export(texture: meshTarget, name: "\(outputFilePrefix)\(meshName).png")
            }
        }
    }
}
