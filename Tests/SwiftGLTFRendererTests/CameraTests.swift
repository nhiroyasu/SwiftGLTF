import Testing
import MetalKit
import CoreGraphics
import UniformTypeIdentifiers
import Img2Cubemap
import SwiftGLTFParser
import SwiftGLTFShaderTypes
@testable import SwiftGLTFRenderer

final class CameraTests {
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
        cameraIndex: Int
    ) async throws {
        let viewport = MTLViewport(
            originX: 0,
            originY: 0,
            width: Double(output.width),
            height: Double(output.height),
            znear: 0,
            zfar: 1
        )
        let eye: SIMD3<Float> = SIMD3<Float>(-1.41, 1.41, -1.41)
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
            .mesh(bundle: try meshLoader.loadMeshes(from: asset))
            .envMap(bundle: try envMapLoader.makeEnvMapBundle(from: Bundle.module.url(forResource: "env_map", withExtension: "exr")!))
            .skybox(false)
            .lightPosition(SIMD3<Float>(0, 5, -5))
            .ambientLightColor(SIMD3<Float>(5, 5, 5))
            .cameraIndex(cameraIndex)
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

    let goldenFilePrefix = "golden_camera_mesh_"
    let outputFilePrefix = "camera_mesh_"
    let meshFiles: [(String, String, Int)] = [
        // Mesh name, extension, camera
        ("Cameras", "gltf", -1),
        ("Cameras", "gltf", 0),
        ("Cameras", "gltf", 1),
    ]


    // Export baseline textures
    // These should be run manually to generate expected textures
    @Test
    func ExportGoldenImages() async throws {
        guard EXPORT_GOLDEN_IMAGES_FLAG, !isCI() else { return }

        for (meshName, ext, cameraIndex) in meshFiles {
            let meshTarget = makeRenderTarget(width: TEX_SIZE, height: TEX_SIZE)
            let meshURL = Bundle.module.url(forResource: meshName, withExtension: ext)!
            try await renderMesh(to: meshTarget, meshURL: meshURL, cameraIndex: cameraIndex)
            try export(texture: meshTarget, name: "\(goldenFilePrefix)\(meshName)_\(String(cameraIndex)).png")
        }
    }

    // MARK: - Tests

    @Test
    func testMeshRenderingMatchesGolden() async throws {
        // This rendering test is not run on CI because it depends on the GPU and the supported Metal version.
        guard !isCI() else { return }

        for (meshName, ext, cameraIndex) in meshFiles {
            let meshTarget = makeRenderTarget(width: TEX_SIZE, height: TEX_SIZE)
            let meshURL = Bundle.module.url(forResource: meshName, withExtension: ext)!
            try await renderMesh(
                to: meshTarget,
                meshURL: meshURL,
                cameraIndex: cameraIndex
            )

            assertEqual(output: meshTarget, goldenName: "\(goldenFilePrefix)\(meshName)_\(String(cameraIndex))")

            if EXPORT_OUTPUT_IMAGES_FLAG, !isCI() {
                try export(texture: meshTarget, name: "\(outputFilePrefix)\(meshName)_\(String(cameraIndex)).png")
            }
        }
    }
}
