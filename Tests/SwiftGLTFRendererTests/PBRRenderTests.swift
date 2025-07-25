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
    let depthStencilStateLoader: DepthStencilStateLoader

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
        self.depthStencilStateLoader = DepthStencilStateLoader(device: device)
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
            pipelineStateLoader: pipelineStateLoader,
            depthStencilStateLoader: depthStencilStateLoader
        )
        let meshes = try loader.loadMeshes(from: asset, using: device)

        // Create command buffer and render encoder
        let cmdBuf = commandQueue.makeCommandBuffer()!
        let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: passDesc)!

        var externalTransform: simd_float4x4 = simd_float4x4(1)
        let externalTransformBuf = device.makeBuffer(bytes: &externalTransform, length: MemoryLayout<simd_float4x4>.size)!

        // Draw the mesh
        for mesh in meshes {
            drawPBR(
                renderEncoder: encoder,
                mesh: mesh,
                view: vMatrixBuf,
                projection: pMatrixBuf,
                externalTransform: externalTransformBuf,
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

    // Export baseline textures
    // These should be run manually to generate expected textures
    @Test
    func ExportGoldenImages() async throws {
        guard EXPORT_GOLDEN_IMAGES_FLAG, !isCI() else { return }

        for meshName in meshNames {
            let meshTarget = makeRenderTarget(width: TEX_SIZE, height: TEX_SIZE)
            let meshURL = Bundle.module.url(forResource: meshName, withExtension: "glb")!
            try await renderMesh(to: meshTarget, meshURL: meshURL)
            try export(texture: meshTarget, name: "\(goldenFilePrefix)\(meshName).png")
        }
    }

    // MARK: - Tests

    @Test
    func testMeshRenderingMatchesGolden() async throws {
        for meshName in meshNames {
            let meshTarget = makeRenderTarget(width: TEX_SIZE, height: TEX_SIZE)
            let meshURL = Bundle.module.url(forResource: meshName, withExtension: "glb")!
            try await renderMesh(to: meshTarget, meshURL: meshURL)

            assertEqual(output: meshTarget, goldenName: "\(goldenFilePrefix)\(meshName)")

            if EXPORT_OUTPUT_IMAGES_FLAG, !isCI() {
                try export(texture: meshTarget, name: "\(outputFilePrefix)\(meshName).png")
            }
        }
    }
}
