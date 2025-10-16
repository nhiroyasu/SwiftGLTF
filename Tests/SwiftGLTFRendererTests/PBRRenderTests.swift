import Testing
import MetalKit
import CoreGraphics
import UniformTypeIdentifiers
import Img2Cubemap
import SwiftGLTFParser
import SwiftGLTFShaderTypes
@testable import SwiftGLTFRenderer

final class PBRRenderTests {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let renderer: PBRRenderer

    let TEX_SIZE = 256

    init() throws {
        self.device = MTLCreateSystemDefaultDevice()!
        self.commandQueue = device.makeCommandQueue()!
        self.renderer = try PBRRenderer(commandQueue: commandQueue)
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
        let view = lookAt(eye: eye, target: SIMD3<Float>(0, 0, 0), up: SIMD3<Float>(0, 1, 0))
        let aspect: Float = Float(output.width) / Float(output.height)
        let fovY = Float.pi / 3.0
        let fovX = 2 * atan(tan(fovY / 2) * aspect)
        let projection = perspectiveMatrix(fov: fovY, aspect: aspect, near: 0.1, far: 100.0)
        var vertexVariableParams = MVPUniform(
            view: view,
            projection: projection,
            externalTransform: simd_float4x4(1)
        )
        let mvpUniformBuffer = device.makeBuffer(
            bytes: &vertexVariableParams,
            length: MemoryLayout<MVPUniform>.size,
            options: .storageModeShared
        )!

        // Create a pbr scene uniforms buffer
        var pbrSceneUniforms = SceneUniforms(
            lightPosition: SIMD3<Float>(0, 5, -5),
            viewPosition: eye,
            ambientLightColor: SIMD3<Float>(5, 5, 5),
            viewportSize: SIMD2<Float>(Float(output.width), Float(output.height)),
            fov: SIMD2<Float>(fovX, fovY),
            camRight: SIMD3<Float>(1, 0, 0),
            camUp: SIMD3<Float>(0, 1, 0)
        )
        let fragmentParams = device.makeBuffer(
            bytes: &pbrSceneUniforms,
            length: MemoryLayout<SceneUniforms>.size,
            options: .storageModeShared
        )!

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
        let asset = try await makeMDLAsset(from: meshURL)
        try await renderer.load(from: asset)
        try await renderer.setEnvironment(url: Bundle.module.url(forResource: "env_map", withExtension: "exr")!)

        // Create command buffer and render encoder
        let cmdBuf = commandQueue.makeCommandBuffer()!

        renderer.render(
            commandBuffer: cmdBuf,
            viewRenderPassDescriptor: passDesc,
            drawableSize: CGSize(width: output.width, height: output.height),
            mvpUniformBuffer: mvpUniformBuffer,
            fragmentParams: fragmentParams,
            viewPos: eye,
            showsSkybox: false
        )

        cmdBuf.commit()
        await cmdBuf.completed()
    }

    // MARK: - Export golden images

    let goldenFilePrefix = "golden_pbr_mesh_"
    let outputFilePrefix = "pbr_mesh_"
    let meshFiles: [(String, String)] = [
        ("BoxTextured", "glb"),
        ("CompareBaseColor", "glb"),
        ("CompareEmissiveStrength", "glb"),
        ("CompareMetallic", "glb"),
        ("CompareNormal", "glb"),
        ("CompareRoughness", "glb"),
        ("OrientationTest", "glb"),
        ("TextureCoordinateTest", "glb"),
        ("VertexColorTest", "glb"),
        ("Fox", "glb"),
        ("MultiUVTest", "glb"),
        ("TextureSettingsTest", "glb"),
        ("SimpleSkin", "gltf"),
        ("MorphPrimitivesTest", "glb"),
        ("CompareTransmission", "glb"),
        ("CompareClearcoat", "glb"),
        ("TextureTransformMultiTest", "glb"),
    ]

    // Export baseline textures
    // These should be run manually to generate expected textures
    @Test
    func ExportGoldenImages() async throws {
        guard EXPORT_GOLDEN_IMAGES_FLAG, !isCI() else { return }

        for (meshName, ext) in meshFiles {
            let meshTarget = makeRenderTarget(width: TEX_SIZE, height: TEX_SIZE)
            let meshURL = Bundle.module.url(forResource: meshName, withExtension: ext)!
            try await renderMesh(to: meshTarget, meshURL: meshURL)
            try export(texture: meshTarget, name: "\(goldenFilePrefix)\(meshName).png")
        }
    }

    // MARK: - Tests

    @Test
    func testMeshRenderingMatchesGolden() async throws {
        // This rendering test is not run on CI because it depends on the GPU and the supported Metal version.
        guard !isCI() else { return }

        for (meshName, ext) in meshFiles {
            let meshTarget = makeRenderTarget(width: TEX_SIZE, height: TEX_SIZE)
            let meshURL = Bundle.module.url(forResource: meshName, withExtension: ext)!
            try await renderMesh(to: meshTarget, meshURL: meshURL)

            assertEqual(output: meshTarget, goldenName: "\(goldenFilePrefix)\(meshName)")

            if EXPORT_OUTPUT_IMAGES_FLAG, !isCI() {
                try export(texture: meshTarget, name: "\(outputFilePrefix)\(meshName).png")
            }
        }
    }
}
