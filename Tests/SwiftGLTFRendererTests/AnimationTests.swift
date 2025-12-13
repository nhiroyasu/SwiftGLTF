import Testing
import MetalKit
import CoreGraphics
import UniformTypeIdentifiers
import Img2Cubemap
import SwiftGLTFParser
import SwiftGLTFShaderTypes
@testable import SwiftGLTFRenderer

final class AnimationTests {
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

    func renderMesh(
        to output: MTLTexture,
        meshURL: URL,
        eye: SIMD3<Float>,
        animationIndex: Int,
        animationState: RendererAnimationState
    ) async throws {
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
        let asset = try makeMDLAsset(from: meshURL, options: .init(autoScale: false))
        let context = await RenderingContextBuilder
            .new()
            .mesh(bundle: try meshLoader.loadMeshes(from: asset, animationIndex: animationIndex))
            .envMap(bundle: envMapBundle)
            .skybox(false)
            .animation(animationState)
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
                viewport: viewport
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

    let goldenFilePrefix = "golden_animation_mesh_"
    let outputFilePrefix = "animation_mesh_"
    let meshFiles: [(String, String, SIMD3<Float>, Int)] = [
        // Mesh name, extension, eye, animationIndex
        ("AnimatedColorsCube", "glb", SIMD3<Float>(-5.66, 5.66, -5.66), 0),
        ("AnimatedMorphCube", "glb", SIMD3<Float>(-2.83, 2.83, -2.83), 0),
        ("InterpolationTest", "glb", SIMD3<Float>(-14.1, 14.1, -14.1), 2),
        ("InterpolationTest", "glb", SIMD3<Float>(-14.1, 14.1, -14.1), 4),
        ("InterpolationTest", "glb", SIMD3<Float>(-14.1, 14.1, -14.1), 7),
    ]


    let time: Float = 4
    let interval: Float = 0.4
    // Export baseline textures
    // These should be run manually to generate expected textures
    @Test
    func ExportGoldenImages() async throws {
        guard EXPORT_GOLDEN_IMAGES_FLAG, !isCI() else { return }

        var currentTime: Float = 0.0
        while time > currentTime {
            for (meshName, ext, eye, animIndex) in meshFiles {
                let meshTarget = makeRenderTarget(width: TEX_SIZE, height: TEX_SIZE)
                let meshURL = Bundle.module.url(forResource: meshName, withExtension: ext)!
                try await renderMesh(to: meshTarget, meshURL: meshURL, eye: eye, animationIndex: animIndex, animationState: .init(time: currentTime, speed: 1.0, isLooping: true))
                try export(texture: meshTarget, name: "\(goldenFilePrefix)\(meshName)_\(animIndex)_\(String(format: "%.1f", currentTime)).png")
            }
            currentTime += interval
        }
    }

    // MARK: - Tests

    private func performAnimationRenderingTest(meshName: String, ext: String, eye: SIMD3<Float>, animIndex: Int) async throws {
        guard !isCI() else { return }

        try await withThrowingTaskGroup { group in
            for currentTime in stride(from: 0.0, to: time, by: interval) {
                group.addTask {
                    let meshTarget = self.makeRenderTarget(width: self.TEX_SIZE, height: self.TEX_SIZE)
                    let meshURL = Bundle.module.url(forResource: meshName, withExtension: ext)!
                    try await self.renderMesh(
                        to: meshTarget,
                        meshURL: meshURL,
                        eye: eye,
                        animationIndex: animIndex,
                        animationState: .init(time: currentTime, speed: 1.0, isLooping: true)
                    )

                    assertEqual(output: meshTarget, goldenName: "\(self.goldenFilePrefix)\(meshName)_\(animIndex)_\(String(format: "%.1f", currentTime))")

                    if EXPORT_OUTPUT_IMAGES_FLAG {
                        try export(texture: meshTarget, name: "\(self.outputFilePrefix)\(meshName)_\(animIndex)_\(String(format: "%.1f", currentTime)).png")
                    }
                }
            }
            try await group.waitForAll()
        }
    }

    @Test
    func testAnimatedColorsCubeRenderingMatchesGolden() async throws {
        try await performAnimationRenderingTest(meshName: "AnimatedColorsCube", ext: "glb", eye: SIMD3<Float>(-5.66, 5.66, -5.66), animIndex: 0)
    }

    @Test
    func testAnimatedMorphCubeRenderingMatchesGolden() async throws {
        try await performAnimationRenderingTest(meshName: "AnimatedMorphCube", ext: "glb", eye: SIMD3<Float>(-2.83, 2.83, -2.83), animIndex: 0)
    }

    @Test
    func testInterpolationTestIndex2RenderingMatchesGolden() async throws {
        try await performAnimationRenderingTest(meshName: "InterpolationTest", ext: "glb", eye: SIMD3<Float>(-14.1, 14.1, -14.1), animIndex: 2)
    }

    @Test
    func testInterpolationTestIndex4RenderingMatchesGolden() async throws {
        try await performAnimationRenderingTest(meshName: "InterpolationTest", ext: "glb", eye: SIMD3<Float>(-14.1, 14.1, -14.1), animIndex: 4)
    }

    @Test
    func testInterpolationTestIndex7RenderingMatchesGolden() async throws {
        try await performAnimationRenderingTest(meshName: "InterpolationTest", ext: "glb", eye: SIMD3<Float>(-14.1, 14.1, -14.1), animIndex: 7)
    }
}
