import Testing
import MetalKit
import CoreGraphics
import UniformTypeIdentifiers
import Img2Cubemap
import SwiftGLTF
import SwiftGLTFShaderTypes
@testable import SwiftGLTFRenderer

final class PBRRenderTests {
    let device: MTLDevice
    let library: MTLLibrary
    let commandQueue: MTLCommandQueue
    let shaderConnection: ShaderConnection
    let depthStencilState: MTLDepthStencilState

    var _prefilterEnvMap: MTLTexture!
    var _irradianceMap: MTLTexture!
    var _brdfLUT: MTLTexture!
    var _pbrMeshContainer: PBRMeshContainer!

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
        self.depthStencilState = try! makeLessEqualDepthStencilState(device: device)
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
        let pipelineConnector = try PBRPipelineConnector(
            device: device,
            library: library,
            config: .init(
                sampleCount: 1,
                colorPixelFormat: output.pixelFormat,
                depthPixelFormat: .depth32Float
            ),
            shaderConnection: shaderConnection
        )
        let loader = PBRMeshLoader(
            device: device,
            shaderConnection: shaderConnection,
            pipelineConnector: pipelineConnector
        )
        let envMapLoader = EnvironmentMapLoader(
            device: device,
            library: library,
            commandQueue: commandQueue,
            shaderConnection: shaderConnection
        )

        // Create view-projection matrix buffer
        let eye = SIMD3<Float>(-2.83, 2.83, -2.83)
        let view = lookAt(eye: eye, target: SIMD3<Float>(0, 0, 0), up: SIMD3<Float>(0, 1, 0))
        let projection = perspectiveMatrix(fov: .pi / 3, aspect: 1, near: 0.1, far: 100.0)
        var vertexVariableParams = PBRVertexVariableParameters(
            view: view,
            projection: projection,
            externalTransform: simd_float4x4(1)
        )
        let vertexParams = device.makeBuffer(
            bytes: &vertexVariableParams,
            length: MemoryLayout<PBRVertexVariableParameters>.size,
            options: .storageModeShared
        )!

        // Create a pbr scene uniforms buffer
        var pbrSceneUniforms = PBRFragmentVariableParameters(
            lightPosition: SIMD3<Float>(0, 5, -5),
            viewPosition: eye,
            ambientLightColor: SIMD3<Float>(5, 5, 5)
        )
        let fragmentParams = device.makeBuffer(
            bytes: &pbrSceneUniforms,
            length: MemoryLayout<PBRFragmentVariableParameters>.size,
            options: .storageModeShared
        )!

        let envMapHeap: MTLHeap
        (
            envMapHeap,
            self._prefilterEnvMap,
            self._irradianceMap,
            self._brdfLUT
        ) = try await envMapLoader.makeEnvMapHeapAndTexture(
            url: Bundle.module.url(forResource: "env_map", withExtension: "exr")!
        )
        let envMapArgBuffer = try pipelineConnector.makeEnvMapArgBuffer(
            prefilterEnvMap: _prefilterEnvMap,
            irradianceMap: _irradianceMap,
            brdfLUT: _brdfLUT
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
        let asset = try await makeMDLAsset(from: meshURL)
        self._pbrMeshContainer = try await loader.loadMeshes(from: asset)

        // Create command buffer and render encoder
        let cmdBuf = commandQueue.makeCommandBuffer()!
        let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: passDesc)!

        // Draw the mesh
        drawPBR(
            renderEncoder: encoder,
            pipelineState: pipelineConnector.pipelineState,
            depthStencilState: depthStencilState,
            vertexResources: _pbrMeshContainer.vertexResources,
            fragmentResources: _pbrMeshContainer.fragmentResources + [envMapHeap],
            meshes: _pbrMeshContainer.meshes,
            vertexParams: vertexParams,
            envMapArgBuffer: envMapArgBuffer,
            fragmentParams: fragmentParams
        )

        encoder.endEncoding()
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
    }

    // MARK: - Export golden images

    let goldenFilePrefix = "golden_pbr_mesh_"
    let outputFilePrefix = "wireframe_mesh_"
    let meshNames: [String] = [
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
        // This rendering test is not run on CI because it depends on the GPU and the supported Metal version.
        guard !isCI() else { return }

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
