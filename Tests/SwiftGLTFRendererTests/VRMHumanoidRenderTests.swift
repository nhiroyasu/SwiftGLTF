import Testing
import MetalKit
import CoreGraphics
import UniformTypeIdentifiers
import Img2Cubemap
import SwiftGLTFCore
import SwiftGLTFParser
import SwiftGLTFShaderTypes
@testable import SwiftGLTFRenderer

private let aliciaSolidHumanoidPreparationComment = Comment(stringLiteral: "To run VRM tests, download Alice_VRM from https://3d.nicovideo.jp/works/td32797 and place the VRM data in the project.")

private func hasAliciaSolidHumanoidVRM() -> Bool {
    Bundle.module.url(forResource: "AliciaSolid", withExtension: "vrm") != nil
}

@Suite(.enabled(if: hasAliciaSolidHumanoidVRM(), aliciaSolidHumanoidPreparationComment))
final class VRMHumanoidRenderTests {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let meshLoader: PBRMeshLoader
    let envMapBundle: EnvMapBundle
    let indirectRenderStateBuilder: PBRIndirectRenderStateBuilder
    let TEX_SIZE = 256
    let SAMPLE_COUNT = 4

    init() async throws {
        self.device = MTLCreateSystemDefaultDevice()!
        self.commandQueue = device.makeCommandQueue()!
        self.meshLoader = try PBRMeshLoader(commandQueue: commandQueue)
        let envMapLoader = try EnvironmentMapLoader(commandQueue: commandQueue)
        self.envMapBundle = try await envMapLoader.makeEnvMapBundle(from: Bundle.module.url(forResource: "env_map", withExtension: "exr")!)
        self.indirectRenderStateBuilder = PBRIndirectRenderStateBuilder(device: device)
    }

    func makeRenderTarget(width: Int, height: Int) -> MTLTexture {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm_srgb,
            width: width,
            height: height,
            mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        return device.makeTexture(descriptor: desc)!
    }

    func renderVRM(
        to output: MTLTexture,
        asset: MDLAsset,
        humanoidRotations: [VRMHumanoidBoneName: SIMD3<Float>],
        eye: SIMD3<Float>,
        modelMatrix: float4x4 = matrix_identity_float4x4
    ) async throws {
        let renderer = try PBRRenderer(commandQueue: commandQueue, sampleCount: SAMPLE_COUNT)

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

        let passDesc = MTLRenderPassDescriptor()
        passDesc.colorAttachments[0].texture = output
        passDesc.colorAttachments[0].loadAction = .clear
        passDesc.colorAttachments[0].storeAction = .store
        passDesc.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        passDesc.depthAttachment.texture = depthTexture
        passDesc.depthAttachment.loadAction = .clear
        passDesc.depthAttachment.storeAction = .store
        passDesc.depthAttachment.clearDepth = 1.0

        let mesh = try await meshLoader.loadMeshes(from: asset)
        let context = RenderingContextBuilder
            .new()
            .modelMatrix(modelMatrix)
            .envMap(bundle: envMapBundle)
            .skybox(false)
            .lightPosition(SIMD3<Float>(0, 5, -5))
            .ambientLightColor(SIMD3<Float>(5, 5, 5))
            .freeCameraUniforms(.build(
                eye: eye,
                aspect: aspect,
                fovY: fovY
            ))
            .vrmHumanoidRotations(humanoidRotations)
            .finalizeWithICB(
                state: try indirectRenderStateBuilder.build(
                    meshBundle: mesh,
                    sampleCount: SAMPLE_COUNT
                ),
                renderPassDescriptor: passDesc,
                drawableSize: CGSize(width: output.width, height: output.height),
                viewport: viewport,
            )

        let cmdBuf = commandQueue.makeCommandBuffer()!
        renderer.render(
            commandBuffer: cmdBuf,
            context: context
        )
        cmdBuf.commit()
        await cmdBuf.completed()
    }

    let goldenFilePrefix = "golden_vrm_humanoid_"
    let outputFilePrefix = "vrm_humanoid_"
    let vrmName = "AliciaSolid"
    let vrmExt = "vrm"
    let aliciaSolidEye = SIMD3<Float>(0, 0, 1.8)
    let aliciaSolidModelMatrix = translationMatrix(0, -1.0, 0)
    let humanoidCases: [(rotations: [VRMHumanoidBoneName: SIMD3<Float>], name: String)] = [
        (
            [
                .spine: SIMD3<Float>(0, 0, -8.0),
                .chest: SIMD3<Float>(0, 16.4, 0),
                .leftUpperLeg: SIMD3<Float>(0, 0, -34.5),
                .leftShoulder: SIMD3<Float>(0, 0, 38.2),
                .rightShoulder: SIMD3<Float>(0, 0, -41.8)
            ],
            "test_pose"
        )
    ]

    func makeAliciaSolidAsset() -> MDLAsset? {
        // To run VRM tests, download Alice_VRM from https://3d.nicovideo.jp/works/td32797 and place the VRM data in the project.
        guard let vrmURL = Bundle.module.url(forResource: vrmName, withExtension: vrmExt) else {
            return nil
        }
        return try? makeMDLAsset(from: vrmURL)
    }

    @Test
    func ExportGoldenImages() async throws {
        guard EXPORT_GOLDEN_IMAGES_FLAG, !isCI() else { return }
        guard let asset = makeAliciaSolidAsset() else { return }

        for humanoidCase in humanoidCases {
            let meshTarget = makeRenderTarget(width: TEX_SIZE, height: TEX_SIZE)
            try await renderVRM(
                to: meshTarget,
                asset: asset,
                humanoidRotations: humanoidCase.rotations,
                eye: aliciaSolidEye,
                modelMatrix: aliciaSolidModelMatrix
            )
            try export(texture: meshTarget, name: "\(goldenFilePrefix)\(vrmName)_\(humanoidCase.name).png")
        }
    }

    private func performAliciaSolidHumanoidRenderingTest(
        humanoidRotations: [VRMHumanoidBoneName: SIMD3<Float>],
        name: String
    ) async throws {
        guard !isCI() else { return }
        guard let asset = makeAliciaSolidAsset() else { return }

        let meshTarget = makeRenderTarget(width: TEX_SIZE, height: TEX_SIZE)
        try await renderVRM(
            to: meshTarget,
            asset: asset,
            humanoidRotations: humanoidRotations,
            eye: aliciaSolidEye,
            modelMatrix: aliciaSolidModelMatrix
        )

        assertEqual(output: meshTarget, goldenName: "\(goldenFilePrefix)\(vrmName)_\(name)")

        if EXPORT_OUTPUT_IMAGES_FLAG {
            try export(texture: meshTarget, name: "\(outputFilePrefix)\(vrmName)_\(name).png")
        }
    }

    @Test
    func testAliciaSolidContrappostoPeaceHumanoidRenderingMatchesGolden() async throws {
        let humanoidCase = humanoidCases[0]
        try await performAliciaSolidHumanoidRenderingTest(
            humanoidRotations: humanoidCase.rotations,
            name: humanoidCase.name
        )
    }
}
