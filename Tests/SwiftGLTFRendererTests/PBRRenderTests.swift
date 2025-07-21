import Testing
import MetalKit
import CoreGraphics
import UniformTypeIdentifiers
import Img2Cubemap
import SwiftGLTF
@testable import SwiftGLTFRenderer

final class PBRRenderTests {
    let device: MTLDevice
    let library: MTLLibrary
    let commandQueue: MTLCommandQueue
    let shaderConnection: ShaderConnection
    let pipelineStateLoader: PBRPipelineStateLoader


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
        self.pipelineStateLoader = PBRPipelineStateLoader(
            device: device,
            library: library,
            config: .init(
                sampleCount: 1,
                colorPixelFormat: .rgba8Unorm_srgb,
                depthPixelFormat: .depth32Float
            )
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

    // Core rendering for skybox
    func renderSkybox(to output: MTLTexture) async throws {
        let vfn = library.makeFunction(name: "skybox_vertex_shader")!
        let ffn = library.makeFunction(name: "skybox_fragment_shader")!
        let psoDesc = MTLRenderPipelineDescriptor()
        psoDesc.vertexFunction = vfn
        psoDesc.fragmentFunction = ffn
        psoDesc.colorAttachments[0].pixelFormat = output.pixelFormat
        let pso = try await device.makeRenderPipelineState(descriptor: psoDesc)
        let dsd = MTLDepthStencilDescriptor()
        dsd.depthCompareFunction = .always
        dsd.isDepthWriteEnabled = false
        let dso = device.makeDepthStencilState(descriptor: dsd)!

        // Create vertex and index buffers for a cube
        let skyboxCube = Cube(size: 1)
        let vbuf = device.makeBuffer(
            bytes: skyboxCube.vertices,
            length: MemoryLayout<Float>.size * skyboxCube.vertices.count,
            options: .storageModeShared
        )!
        let ibuf = device.makeBuffer(
            bytes: skyboxCube.indices,
            length: MemoryLayout<UInt16>.size * skyboxCube.indices.count,
            options: .storageModeShared
        )!
        let skyboxTarget = SIMD3<Float>(0, 0, 1)
        let vMatrix = lookAt(eye: SIMD3<Float>(0, 0, 0), target: skyboxTarget, up: SIMD3<Float>(0, 1, 0))
        let pMatrix = perspectiveMatrix(fov: .pi / 3, aspect: 1, near: 0.1, far: 100.0)
        var vp = pMatrix * vMatrix
        let vpbuf = device.makeBuffer(bytes: &vp, length: MemoryLayout.size(ofValue: vp), options: [])!
        let envMap = try await generateCubeTexture(
            device: device,
            exr: Bundle.module.url(forResource: "env_map", withExtension: "exr")!
        )

        let passDesc = MTLRenderPassDescriptor()
        passDesc.colorAttachments[0].texture = output
        passDesc.colorAttachments[0].loadAction = .clear
        passDesc.colorAttachments[0].storeAction = .store
        passDesc.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)

        let cmdBuf = commandQueue.makeCommandBuffer()!
        let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: passDesc)!
        drawSkybox(
            renderEncoder: encoder,
            pso: pso,
            dso: dso,
            vertexBuffer: vbuf,
            indexBuffer: ibuf,
            indexCount: ibuf.length / MemoryLayout<UInt16>.size,
            indexType: .uint16,
            vpMatrixBuffer: vpbuf,
            specularCubeMapTexture: envMap)
        encoder.endEncoding()
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
    }

    func renderMesh(to output: MTLTexture, meshURL: URL) async throws {
        // Create view-projection matrix buffer
        let eye = SIMD3<Float>(-2.83, 2.83, -2.83)
        var vMatrix = lookAt(eye: eye, target: SIMD3<Float>(0, 0, 0), up: SIMD3<Float>(0, 1, 0))
        let vMatrixBuf = device.makeBuffer(bytes: &vMatrix, length: MemoryLayout.size(ofValue: vMatrix))!
        var pMatrix = perspectiveMatrix(fov: .pi / 3, aspect: 1, near: 0.1, far: 100.0)
        let pMatrixBuf = device.makeBuffer(bytes: &pMatrix, length: MemoryLayout.size(ofValue: pMatrix))!

        // Create a pbr scene uniforms buffer
        var pbrSceneUniforms = PBRSceneUniforms(
            lightPosition: SIMD3<Float>(0, 5, -5),
            viewPosition: eye,
            ambientLightColor: SIMD3<Float>(5, 5, 5)
        )
        let sceneUniformsBuffer = device.makeBuffer(
            bytes: &pbrSceneUniforms,
            length: MemoryLayout<PBRSceneUniforms>.size,
            options: .storageModeShared
        )!

        let envMap = try await generateCubeTexture(
            device: device,
            exr: Bundle.module.url(forResource: "env_map", withExtension: "exr")!
        )
        let irrMap = generateIrradianceTexture(
            commandQueue: commandQueue,
            library: library,
            envMap: envMap,
            size: 128
        )
        let brdfLUT = generateBRDFLUT(
            commandQueue: commandQueue,
            library: library,
            width: envMap.width,
            height: envMap.height
        )

        // Create depth stencil state and texture
        let dsd = MTLDepthStencilDescriptor()
        dsd.depthCompareFunction = .less
        dsd.isDepthWriteEnabled = true
        let dso = device.makeDepthStencilState(descriptor: dsd)!

        let depthTextureDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float,
            width: output.width,
            height: output.height,
            mipmapped: false
        )
        depthTextureDesc.usage = [.renderTarget, .shaderRead]
        depthTextureDesc.storageMode = .private
        let depthTexture = device.makeTexture(descriptor: depthTextureDesc)!

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
        let loader = PBRMeshLoader(
            shaderConnection: shaderConnection,
            pipelineStateLoader: pipelineStateLoader
        )
        let meshes = try loader.loadMeshes(from: asset, using: device)

        // Create command buffer and render encoder
        let cmdBuf = commandQueue.makeCommandBuffer()!
        let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: passDesc)!

        // Draw the mesh
        for mesh in meshes {
            var model = mesh.transform
            mesh.modelBuffer.contents().copyMemory(from: &model, byteCount: MemoryLayout<float4x4>.size)
            var normalMatrix = float3x3(model).transpose.inverse
            mesh.normalMatrixBuffer.contents().copyMemory(from: &normalMatrix, byteCount: MemoryLayout<float3x3>.size)

            drawPBR(
                renderEncoder: encoder,
                mesh: mesh,
                dso: dso,
                viewBuffer: vMatrixBuf,
                projectionBuffer: pMatrixBuf,
                pbrSceneUniformsBuffer: sceneUniformsBuffer,
                specularCubeMapTexture: envMap,
                irradianceCubeMapTexture: irrMap,
                brdfLUT: brdfLUT
            )
        }

        encoder.endEncoding()
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
    }

    // MARK: - Export golden images

    let goldenFilePrefix = "golden_pbr_mesh_"
    let outputFilePrefix = "wireframe_mesh_"
    let meshNames: [String] = [
        "BoxTextured",
        "BoxTextured",
        "CompareBaseColor",
        "CompareEmissiveStrength",
        "CompareMetallic",
        "CompareNormal",
        "CompareRoughness",
        "OrientationTest",
        "TextureCoordinateTest",
        "VertexColorTest",
        "Fox"
    ]

    let switchExportGoldenImages = false

    // Export baseline textures
    // These should be run manually to generate expected textures
    @Test
    func ExportGoldenImages() async throws {
        guard switchExportGoldenImages, !isCI() else { return }

        let skyTarget = makeRenderTarget(width: TEX_SIZE, height: TEX_SIZE)
        try await renderSkybox(to: skyTarget)
        try export(texture: skyTarget, name: "golden_skybox.png")

        for meshName in meshNames {
            let meshTarget = makeRenderTarget(width: TEX_SIZE, height: TEX_SIZE)
            let meshURL = Bundle.module.url(forResource: meshName, withExtension: "glb")!
            try await renderMesh(to: meshTarget, meshURL: meshURL)
            try export(texture: meshTarget, name: "\(goldenFilePrefix)\(meshName).png")
        }
    }

    // MARK: - Tests

    let switchExportResults = false

    @Test
    func testSkyboxRenderingMatchesGolden() async throws {
        let skyTarget = makeRenderTarget(width: TEX_SIZE, height: TEX_SIZE)
        try await renderSkybox(to: skyTarget)

        assertEqual(output: skyTarget, goldenName: "golden_skybox")

        if switchExportResults, !isCI() {
            try export(texture: skyTarget, name: "skybox_output.png")
        }
    }

    @Test
    func testMeshRenderingMatchesGolden() async throws {
        for meshName in meshNames {
            let meshTarget = makeRenderTarget(width: TEX_SIZE, height: TEX_SIZE)
            let meshURL = Bundle.module.url(forResource: meshName, withExtension: "glb")!
            try await renderMesh(to: meshTarget, meshURL: meshURL)

            assertEqual(output: meshTarget, goldenName: "\(goldenFilePrefix)\(meshName)")

            if switchExportResults, !isCI() {
                try export(texture: meshTarget, name: "\(outputFilePrefix)\(meshName).png")
            }
        }
    }
}
