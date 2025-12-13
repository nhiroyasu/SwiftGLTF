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
    let envMapBundle: EnvMapBundle
    let TEX_SIZE = 256

    init() async throws {
        self.device = MTLCreateSystemDefaultDevice()!
        self.commandQueue = device.makeCommandQueue()!
        let (_, _, envMapLoader) = makeRenderTestInstance(
            device: device,
            commandQueue: commandQueue
        )
        self.envMapBundle = try await envMapLoader.makeEnvMapBundle(from: Bundle.module.url(forResource: "env_map", withExtension: "exr")!)
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

    func renderMesh(to output: MTLTexture, meshURL: URL, eye: SIMD3<Float>?) async throws {
        let (renderer, meshLoader, _) = makeRenderTestInstance(
            device: device,
            commandQueue: commandQueue
        )

        let viewport = MTLViewport(
            originX: 0,
            originY: 0,
            width: Double(output.width),
            height: Double(output.height),
            znear: 0,
            zfar: 1
        )
        // Create view-projection matrix buffer
        let eye = eye ?? SIMD3<Float>(-1.41, 1.41, -1.41)
        let aspect: Float = Float(viewport.width / max(viewport.height, 1))
        let fovY = Float.pi / 3.0

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
        let context = await RenderingContextBuilder
            .new()
            .mesh(bundle: try meshLoader.loadMeshes(from: asset))
            .envMap(bundle: envMapBundle)
            .skybox(false)
            .lightPosition(SIMD3<Float>(0, 5, -5))
            .ambientLightColor(SIMD3<Float>(5, 5, 5))
            .freeCameraUniforms(.build(
                eye: eye,
                aspect: aspect,
                fovY: fovY
            ))
            .render(
                renderPassDescriptor: passDesc,
                drawableSize: CGSize(width: output.width, height: output.height),
                viewport: viewport,
            )
            .finalize()

        // Create command buffer and render encoder
        let cmdBuf = commandQueue.makeCommandBuffer()!
        renderer.render(
            commandBuffer: cmdBuf,
            context: context
        )
        cmdBuf.commit()
        await cmdBuf.completed()
    }

    // MARK: - Export golden images

    let goldenFilePrefix = "golden_pbr_mesh_"
    let outputFilePrefix = "pbr_mesh_"
    let meshFiles: [(String, String, SIMD3<Float>?)] = [
        // Mesh Name, Extension, Optional Eye Position
        ("BoxTextured", "glb", nil),
        ("CompareBaseColor", "glb", nil),
        ("CompareEmissiveStrength", "glb", nil),
        ("CompareMetallic", "glb", nil),
        ("CompareNormal", "glb", nil),
        ("CompareRoughness", "glb", nil),
        ("OrientationTest", "glb", SIMD3<Float>(-10.6, 10.6, -10.6)),
        ("TextureCoordinateTest", "glb", SIMD3<Float>(-2.83, 2.83, -2.83)),
        ("VertexColorTest", "glb", nil),
        ("Fox", "glb", SIMD3<Float>(-106, 106, -106)),
        ("MultiUVTest", "glb", SIMD3<Float>(-2.83, 2.83, -2.83)),
        ("TextureSettingsTest", "glb", SIMD3<Float>(-4.24, 4.24, -4.24)),
        ("SimpleSkin", "gltf", SIMD3<Float>(-2.83, 2.83, -2.83)),
        ("MorphPrimitivesTest", "glb", SIMD3<Float>(-0.7, 0.7, -0.7)),
        ("CompareTransmission", "glb", nil),
        ("CompareClearcoat", "glb", nil),
        ("TextureTransformMultiTest", "glb", nil),
        ("CompareVolume", "glb", nil)
    ]

    // Export baseline textures
    // These should be run manually to generate expected textures
    @Test
    func ExportGoldenImages() async throws {
        guard EXPORT_GOLDEN_IMAGES_FLAG, !isCI() else { return }

        for (meshName, ext, eye) in meshFiles {
            let meshTarget = makeRenderTarget(width: TEX_SIZE, height: TEX_SIZE)
            let meshURL = Bundle.module.url(forResource: meshName, withExtension: ext)!
            try await renderMesh(to: meshTarget, meshURL: meshURL, eye: eye)
            try export(texture: meshTarget, name: "\(goldenFilePrefix)\(meshName).png")
        }
    }

    // MARK: - Tests

    private func performMeshRenderingTest(meshName: String, ext: String, eye: SIMD3<Float>?) async throws {
        guard !isCI() else { return }

        let meshTarget = makeRenderTarget(width: TEX_SIZE, height: TEX_SIZE)
        let meshURL = Bundle.module.url(forResource: meshName, withExtension: ext)!
        try await renderMesh(to: meshTarget, meshURL: meshURL, eye: eye)

        assertEqual(output: meshTarget, goldenName: "\(goldenFilePrefix)\(meshName)")

        if EXPORT_OUTPUT_IMAGES_FLAG {
            try export(texture: meshTarget, name: "\(outputFilePrefix)\(meshName).png")
        }
    }

    @Test
    func testBoxTexturedRenderingMatchesGolden() async throws {
        try await performMeshRenderingTest(meshName: "BoxTextured", ext: "glb", eye: nil)
    }

    @Test
    func testCompareBaseColorRenderingMatchesGolden() async throws {
        try await performMeshRenderingTest(meshName: "CompareBaseColor", ext: "glb", eye: nil)
    }

    @Test
    func testCompareEmissiveStrengthRenderingMatchesGolden() async throws {
        try await performMeshRenderingTest(meshName: "CompareEmissiveStrength", ext: "glb", eye: nil)
    }

    @Test
    func testCompareMetallicRenderingMatchesGolden() async throws {
        try await performMeshRenderingTest(meshName: "CompareMetallic", ext: "glb", eye: nil)
    }

    @Test
    func testCompareNormalRenderingMatchesGolden() async throws {
        try await performMeshRenderingTest(meshName: "CompareNormal", ext: "glb", eye: nil)
    }

    @Test
    func testCompareRoughnessRenderingMatchesGolden() async throws {
        try await performMeshRenderingTest(meshName: "CompareRoughness", ext: "glb", eye: nil)
    }

    @Test
    func testOrientationTestRenderingMatchesGolden() async throws {
        try await performMeshRenderingTest(meshName: "OrientationTest", ext: "glb", eye: SIMD3<Float>(-10.6, 10.6, -10.6))
    }

    @Test
    func testTextureCoordinateTestRenderingMatchesGolden() async throws {
        try await performMeshRenderingTest(meshName: "TextureCoordinateTest", ext: "glb", eye: SIMD3<Float>(-2.83, 2.83, -2.83))
    }

    @Test
    func testVertexColorTestRenderingMatchesGolden() async throws {
        try await performMeshRenderingTest(meshName: "VertexColorTest", ext: "glb", eye: nil)
    }

    @Test
    func testFoxRenderingMatchesGolden() async throws {
        try await performMeshRenderingTest(meshName: "Fox", ext: "glb", eye: SIMD3<Float>(-106, 106, -106))
    }

    @Test
    func testMultiUVTestRenderingMatchesGolden() async throws {
        try await performMeshRenderingTest(meshName: "MultiUVTest", ext: "glb", eye: SIMD3<Float>(-2.83, 2.83, -2.83))
    }

    @Test
    func testTextureSettingsTestRenderingMatchesGolden() async throws {
        try await performMeshRenderingTest(meshName: "TextureSettingsTest", ext: "glb", eye: SIMD3<Float>(-4.24, 4.24, -4.24))
    }

    @Test
    func testSimpleSkinRenderingMatchesGolden() async throws {
        try await performMeshRenderingTest(meshName: "SimpleSkin", ext: "gltf", eye: SIMD3<Float>(-2.83, 2.83, -2.83))
    }

    @Test
    func testMorphPrimitivesTestRenderingMatchesGolden() async throws {
        try await performMeshRenderingTest(meshName: "MorphPrimitivesTest", ext: "glb", eye: SIMD3<Float>(-0.7, 0.7, -0.7))
    }

    @Test
    func testCompareTransmissionRenderingMatchesGolden() async throws {
        try await performMeshRenderingTest(meshName: "CompareTransmission", ext: "glb", eye: nil)
    }

    @Test
    func testCompareClearcoatRenderingMatchesGolden() async throws {
        try await performMeshRenderingTest(meshName: "CompareClearcoat", ext: "glb", eye: nil)
    }

    @Test
    func testTextureTransformMultiTestRenderingMatchesGolden() async throws {
        try await performMeshRenderingTest(meshName: "TextureTransformMultiTest", ext: "glb", eye: nil)
    }

    @Test
    func testCompareVolumeRenderingMatchesGolden() async throws {
        try await performMeshRenderingTest(meshName: "CompareVolume", ext: "glb", eye: nil)
    }
}
