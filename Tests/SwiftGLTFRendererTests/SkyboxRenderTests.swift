import Testing
import MetalKit
import CoreGraphics
import UniformTypeIdentifiers
import Img2Cubemap
import SwiftGLTFParser
import SwiftGLTFShaderTypes
@testable import SwiftGLTFRenderer

final class SkyboxRenderTests {
    let device: MTLDevice
    let library: MTLLibrary
    let commandQueue: MTLCommandQueue
    let shaderConnection: ShaderConnection
    let envMapLoader: EnvironmentMapLoader

    let TEX_SIZE = 256

    init() {
        self.device = MTLCreateSystemDefaultDevice()!
        self.library = try! device.makePackageLibrary()
        self.commandQueue = device.makeCommandQueue()!

        self.shaderConnection = try! ShaderConnection(
            device: device,
            commandQueue: commandQueue
        )
        self.envMapLoader = EnvironmentMapLoader(
            device: device,
            library: library,
            shaderConnection: shaderConnection
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
        let pipelineConnection = try! SkyboxPipelineConnector(
            device: device,
            library: library,
            config: SkyboxPipelineConfig(colorPixelFormat: output.pixelFormat)
        )
        // Create vertex and index buffers for a cube
        let vbuf = device.makeBuffer(
            bytes: skyboxVertices,
            length: MemoryLayout<Float>.size * skyboxVertices.count,
            options: .storageModeShared
        )!
        let ibuf = device.makeBuffer(
            bytes: skyboxIndices,
            length: MemoryLayout<UInt16>.size * skyboxIndices.count,
            options: .storageModeShared
        )!
        let skyboxTarget = SIMD3<Float>(0, 0, 1)
        let aspect: Float = 1.0
        let vMatrix = lookAt(eye: SIMD3<Float>(0, 0, 0), target: skyboxTarget, up: SIMD3<Float>(0, 1, 0))
        let pMatrix = perspectiveMatrix(fov: .pi / 3, aspect: aspect, near: 0.1, far: 100.0)
        let envMapBundle = try envMapLoader.makeEnvMapBundle(from: Bundle.module.url(forResource: "env_map", withExtension: "exr")!)
        var cameraIndex = -1
        let cameraIndexBuffer = device.makeBuffer(
            bytes: &cameraIndex,
            length: MemoryLayout<Int>.size,
            options: .storageModeShared
        )!
        var freeCameraUniforms = FreeCameraUniforms(
            viewMatrix: vMatrix,
            projectionMatrix: pMatrix,
            position: SIMD3<Float>(0, 0, 0),
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

        let passDesc = MTLRenderPassDescriptor()
        passDesc.colorAttachments[0].texture = output
        passDesc.colorAttachments[0].loadAction = .clear
        passDesc.colorAttachments[0].storeAction = .store
        passDesc.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)

        let cmdBuf = commandQueue.makeCommandBuffer()!
        let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: passDesc)!
        let skyboxMesh = SkyboxMesh(
            vertexBuffer: vbuf,
            indexBuffer: ibuf,
            indexCount: ibuf.length / MemoryLayout<UInt16>.size,
            indexType: .uint16
        )
        drawSkybox(
            renderEncoder: encoder,
            pso: pipelineConnection.pso,
            dso: pipelineConnection.dso,
            mesh: skyboxMesh,
            worldTransformBuffer: worldTransformDummyBuffer(device: device),
            cameraIndexBuffer: cameraIndexBuffer,
            freeCameraUniformsBuffer: freeCameraUniformsBuffer,
            nodeCameraUniformsBuffer: NodeCameraUniforms.makeDummyBuffer(device: device),
            envMapArgBuffer: envMapBundle.argBuffer,
            fragmentHeaps: [envMapBundle.heap]
        )
        encoder.endEncoding()
        cmdBuf.commit()
        await cmdBuf.completed()
    }

    // MARK: - Export golden images

    // Export baseline textures
    // These should be run manually to generate expected textures
    @Test
    func ExportGoldenImages() async throws {
        guard EXPORT_GOLDEN_IMAGES_FLAG, !isCI() else { return }

        let skyTarget = makeRenderTarget(width: TEX_SIZE, height: TEX_SIZE)
        try await renderSkybox(to: skyTarget)
        try export(texture: skyTarget, name: "golden_skybox.png")
    }

    // MARK: - Tests

    @Test
    func testSkyboxRenderingMatchesGolden() async throws {
        let skyTarget = makeRenderTarget(width: TEX_SIZE, height: TEX_SIZE)
        try await renderSkybox(to: skyTarget)

        assertEqual(output: skyTarget, goldenName: "golden_skybox")

        if EXPORT_OUTPUT_IMAGES_FLAG, !isCI() {
            try export(texture: skyTarget, name: "skybox_output.png")
        }
    }
}
