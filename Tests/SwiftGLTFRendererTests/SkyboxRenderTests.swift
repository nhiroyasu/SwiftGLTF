//
//  SkyboxRenderTests.swift
//  SwiftGLTF
//
//  Created by NH on 2025/07/21.
//

import Testing
import MetalKit
import CoreGraphics
import UniformTypeIdentifiers
import Img2Cubemap
import SwiftGLTF
@testable import SwiftGLTFRenderer

final class SkyboxRenderTests {
    let device: MTLDevice
    let library: MTLLibrary
    let commandQueue: MTLCommandQueue
    let shaderConnection: ShaderConnection

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
        let skyboxMesh = SkyboxMesh(
            vertexBuffer: vbuf,
            indexBuffer: ibuf,
            indexCount: ibuf.length / MemoryLayout<UInt16>.size,
            indexType: .uint16,
            pso: pso,
            dso: dso
        )
        drawSkybox(
            renderEncoder: encoder,
            mesh: skyboxMesh,
            vpMatrixBuffer: vpbuf,
            specularCubeMapTexture: envMap
        )
        encoder.endEncoding()
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
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
