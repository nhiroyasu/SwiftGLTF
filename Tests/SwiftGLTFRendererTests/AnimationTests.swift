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
    let renderer: PBRRenderer
    let meshLoader: PBRMeshLoader
    let envMapLoader: EnvironmentMapLoader

    let TEX_SIZE = 256

    init() throws {
        self.device = MTLCreateSystemDefaultDevice()!
        self.commandQueue = device.makeCommandQueue()!
        (self.renderer, self.meshLoader, self.envMapLoader) = makeRenderTestInstance(
            device: device,
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

    func renderMesh(
        to output: MTLTexture,
        meshURL: URL,
        eye: SIMD3<Float>,
        animationIndex: Int,
        animationState: RendererAnimationState
    ) throws {
        let viewport = MTLViewport(
            originX: 0,
            originY: 0,
            width: Double(output.width),
            height: Double(output.height),
            znear: 0,
            zfar: 1
        )
        // Create view-projection matrix buffer
        let view = lookAt(eye: eye, target: SIMD3<Float>(0, 0, 0), up: SIMD3<Float>(0, 1, 0))
        let aspect: Float = Float(viewport.width / max(viewport.height, 1))
        let fovY = Float.pi / 3.0
        let fovX = 2 * atan(tan(fovY / 2) * aspect)
        let projection = perspectiveMatrix(fov: fovY, aspect: aspect, near: 0.1, far: 100.0)
        var modelMatrix = simd_float4x4(1)
        let modelMatrixBuffer = device.makeBuffer(
            bytes: &modelMatrix,
            length: MemoryLayout<simd_float4x4>.size,
            options: .storageModeShared
        )!
        let cameraIndexBuffer = device.makeBuffer(
            bytes: [Int(-1)],
            length: MemoryLayout<Int>.size,
            options: .storageModeShared
        )!
        var freeCameraUniforms = FreeCameraUniforms(
            viewMatrix: view,
            projectionMatrix: projection,
            position: eye,
            fov: SIMD2<Float>(fovX, fovY),
            camRight: SIMD3<Float>(1, 0, 0),
            camUp: SIMD3<Float>(0, 1, 0),
            aspectRatio: aspect
        )
        let freeCameraUniformsBuffer = device.makeBuffer(
            bytes: &freeCameraUniforms,
            length: MemoryLayout<FreeCameraUniforms>.size,
            options: .storageModeShared
        )!

        // Create a pbr scene uniforms buffer
        var pbrSceneUniforms = SceneUniforms(
            lightPosition: SIMD3<Float>(0, 5, -5),
            ambientLightColor: SIMD3<Float>(5, 5, 5),
            viewportSize: SIMD2<Float>(Float(viewport.width), Float(viewport.height))
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
        let asset = try makeMDLAsset(from: meshURL, options: .init(autoScale: false))
        let context = RenderingContextBuilder
            .new()
            .mesh(bundle: try meshLoader.loadMeshes(from: asset, animationIndex: animationIndex))
            .envMap(bundle: try envMapLoader.makeEnvMapBundle(from: Bundle.module.url(forResource: "env_map", withExtension: "exr")!))
            .skybox(false)
            .animation(animationState)
            .render(
                renderPassDescriptor: passDesc,
                drawableSize: CGSize(width: output.width, height: output.height),
                viewport: viewport,
                fragmentParams: fragmentParams,
                viewPos: eye,
                cameraIndexBuffer: cameraIndexBuffer,
                freeCameraUniformsBuffer: freeCameraUniformsBuffer,
                modelMatrixBuffer: modelMatrixBuffer
            )
            .finalize()

        // Create command buffer and render encoder
        let cmdBuf = commandQueue.makeCommandBuffer()!
        renderer.render(
            commandBuffer: cmdBuf,
            context: context
        )
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
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
    var currentTime: Float = 0.0
    // Export baseline textures
    // These should be run manually to generate expected textures
    @Test
    func ExportGoldenImages() throws {
        guard EXPORT_GOLDEN_IMAGES_FLAG, !isCI() else { return }

        while time > currentTime {
            for (meshName, ext, eye, animIndex) in meshFiles {
                let meshTarget = makeRenderTarget(width: TEX_SIZE, height: TEX_SIZE)
                let meshURL = Bundle.module.url(forResource: meshName, withExtension: ext)!
                try renderMesh(to: meshTarget, meshURL: meshURL, eye: eye, animationIndex: animIndex, animationState: .init(time: currentTime, speed: 1.0, isLooping: true))
                try export(texture: meshTarget, name: "\(goldenFilePrefix)\(meshName)_\(animIndex)_\(String(format: "%.1f", currentTime)).png")
            }
            currentTime += interval
        }
    }

    // MARK: - Tests

    @Test
    func testMeshRenderingMatchesGolden() throws {
        // This rendering test is not run on CI because it depends on the GPU and the supported Metal version.
        guard !isCI() else { return }

        while time > currentTime {
            for (meshName, ext, eye, animIndex) in meshFiles {
                let meshTarget = makeRenderTarget(width: TEX_SIZE, height: TEX_SIZE)
                let meshURL = Bundle.module.url(forResource: meshName, withExtension: ext)!
                try renderMesh(to: meshTarget, meshURL: meshURL, eye: eye, animationIndex: animIndex, animationState: .init(time: currentTime, speed: 1.0, isLooping: true))

                assertEqual(output: meshTarget, goldenName: "\(goldenFilePrefix)\(meshName)_\(animIndex)_\(String(format: "%.1f", currentTime))")

                if EXPORT_OUTPUT_IMAGES_FLAG, !isCI() {
                    try export(texture: meshTarget, name: "\(outputFilePrefix)\(meshName)_\(animIndex)_\(String(format: "%.1f", currentTime)).png")
                }
            }
            currentTime += interval
        }
    }
}
