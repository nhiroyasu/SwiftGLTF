import os.log
import simd
import Metal
import ModelIO
import SwiftGLTFCore
import SwiftGLTFParser
import SwiftGLTFShaderTypes

public struct PBRIndirectCommandBufferState {
    let icb: MTLIndirectCommandBuffer
    let renderPassContext: RenderPassContext
}

public struct PBRIndirectRenderState {
    // Mesh
    let meshBundle: PBRMeshBundle
    let skyboxMesh: SkyboxMesh

    // ICB Buffers
    let skyboxICBState: PBRIndirectCommandBufferState
    let screenColorICBState: PBRIndirectCommandBufferState
    let transmissionICBState: PBRIndirectCommandBufferState

    // ICB Resources
    let indirectHeap: MTLHeap
    let indirectSceneUniformsBuffer: MTLBuffer
    let indirectCameraIndexBuffer: MTLBuffer
    let indirectFreeCameraUniformsBuffer: MTLBuffer
    let indirectModelMatrixBuffer: MTLBuffer
    let indirectEnvMapArgumentBuffer: MTLBuffer
    let indirectScreenColorArgumentBuffer: MTLBuffer
    let indirectNoScreenColorArgumentBuffer: MTLBuffer
}

public class PBRIndirectRenderStateBuilder {
    private let device: MTLDevice

    public init(device: MTLDevice) {
        self.device = device
    }

    public func build(
        meshBundle: PBRMeshBundle,
        sampleCount: Int = 4,
        colorPixelFormat: MTLPixelFormat = .rgba8Unorm_srgb,
        depthPixelFormat: MTLPixelFormat = .depth32Float
    ) throws -> PBRIndirectRenderState {
        let library = try device.makePackageLibrary()
        let pbrPipelineConnector = try PBRPipelineConnector(device: device)
        let writeDSO = try makeLessEqualDepthStencilState(device: device)

        // setup skybox
        let skyboxConfig = SkyboxPipelineConfig(
            sampleCount: sampleCount,
            colorPixelFormat: .rgba16Float,
            depthPixelFormat: .depth32Float
        )
        let skyboxPipelineConnector = try SkyboxPipelineConnector(
            device: device,
            library: library,
            config: skyboxConfig
        )
        let skyboxLoader = try SkyboxMeshLoader(device: device)
        let skyboxMesh = skyboxLoader.loadMesh()

        // ICB
        let indirectHeap = {
            let desc = MTLHeapDescriptor()
            desc.storageMode = .private
            desc.size =
            device.heapBufferSizeAndAlign(length:MemoryLayout<SceneUniforms>.size).alignedSize +
            device.heapBufferSizeAndAlign(length:MemoryLayout<simd_float4x4>.size).alignedSize +
            device.heapBufferSizeAndAlign(length:MemoryLayout<Int>.size).alignedSize +
            device.heapBufferSizeAndAlign(length:MemoryLayout<FreeCameraUniforms>.size).alignedSize +
            device.heapBufferSizeAndAlign(length:MemoryLayout<PBREnvMapArguments>.size).alignedSize +
            device.heapBufferSizeAndAlign(length: MemoryLayout<PBRScreenColorArguments>.size).alignedSize * 2
            let heap = device.makeHeap(descriptor: desc)!
            heap.label = "[SwiftGLTF] PBR Indirect Command Heap"
            return heap
        }()
        let indirectSceneUniformsBuffer = indirectHeap.makeBuffer(
            length: MemoryLayout<SceneUniforms>.size,
            options: .storageModePrivate
        )!
        let indirectModelMatrixBuffer = indirectHeap.makeBuffer(
            length: MemoryLayout<simd_float4x4>.size,
            options: .storageModePrivate
        )!
        let indirectCameraIndexBuffer = indirectHeap.makeBuffer(
            length: MemoryLayout<Int>.size,
            options: .storageModePrivate
        )!
        let indirectFreeCameraUniformsBuffer = indirectHeap.makeBuffer(
            length: MemoryLayout<FreeCameraUniforms>.size,
            options: .storageModePrivate
        )!
        let indirectEnvMapArgumentBuffer = indirectHeap.makeBuffer(
            length: MemoryLayout<PBREnvMapArguments>.size,
            options: .storageModePrivate
        )!
        let indirectScreenColorArgumentBuffer = indirectHeap.makeBuffer(
            length: MemoryLayout<PBRScreenColorArguments>.size,
            options: .storageModePrivate
        )!
        let indirectNoScreenColorArgumentBuffer = indirectHeap.makeBuffer(
            length: MemoryLayout<PBRScreenColorArguments>.size,
            options: .storageModePrivate
        )!

        // Build ICBs
        let skyboxICBState = buildSkyBoxIndirectCommandBuffer(
            device: device,
            skyboxMesh: skyboxMesh,
            bundle: meshBundle,
            fragmentArgumentsBuffer: indirectEnvMapArgumentBuffer,
            skyboxPipelineConnector: skyboxPipelineConnector,
            indirectCameraIndexBuffer: indirectCameraIndexBuffer,
            indirectFreeCameraUniformsBuffer: indirectFreeCameraUniformsBuffer
        )
        let screenColorICBState = buildRenderScreenColorIndirectCommandBuffer(
            device: device,
            bundle: meshBundle,
            pbrPipelineConnector: pbrPipelineConnector,
            writeDSO: writeDSO,
            indirectCameraIndexBuffer: indirectCameraIndexBuffer,
            indirectFreeCameraUniformsBuffer: indirectFreeCameraUniformsBuffer,
            indirectEnvMapArgumentBuffer: indirectEnvMapArgumentBuffer,
            indirectSceneUniformsBuffer: indirectSceneUniformsBuffer,
            indirectModelMatrixBuffer: indirectModelMatrixBuffer,
            indirectScreenColorArgumentBuffer: indirectNoScreenColorArgumentBuffer
        )
        let transmissionICBState = buildRenderTransmissionIndirectCommandBuffer(
            device: device,
            bundle: meshBundle,
            pbrPipelineConnector: pbrPipelineConnector,
            writeDSO: writeDSO,
            indirectCameraIndexBuffer: indirectCameraIndexBuffer,
            indirectFreeCameraUniformsBuffer: indirectFreeCameraUniformsBuffer,
            indirectEnvMapArgumentBuffer: indirectEnvMapArgumentBuffer,
            indirectSceneUniformsBuffer: indirectSceneUniformsBuffer,
            indirectModelMatrixBuffer: indirectModelMatrixBuffer,
            indirectScreenColorArgumentBuffer: indirectScreenColorArgumentBuffer,
        )

        return PBRIndirectRenderState(
            meshBundle: meshBundle,
            skyboxMesh: skyboxMesh,
            skyboxICBState: skyboxICBState,
            screenColorICBState: screenColorICBState,
            transmissionICBState: transmissionICBState,
            indirectHeap: indirectHeap,
            indirectSceneUniformsBuffer: indirectSceneUniformsBuffer,
            indirectCameraIndexBuffer: indirectCameraIndexBuffer,
            indirectFreeCameraUniformsBuffer: indirectFreeCameraUniformsBuffer,
            indirectModelMatrixBuffer: indirectModelMatrixBuffer,
            indirectEnvMapArgumentBuffer: indirectEnvMapArgumentBuffer,
            indirectScreenColorArgumentBuffer: indirectScreenColorArgumentBuffer,
            indirectNoScreenColorArgumentBuffer: indirectNoScreenColorArgumentBuffer
        )
    }

    private func buildSkyBoxIndirectCommandBuffer(
        device: MTLDevice,
        skyboxMesh: SkyboxMesh,
        bundle: PBRMeshBundle,
        fragmentArgumentsBuffer: MTLBuffer,
        skyboxPipelineConnector: SkyboxPipelineConnector,
        indirectCameraIndexBuffer: MTLBuffer,
        indirectFreeCameraUniformsBuffer: MTLBuffer
    ) -> PBRIndirectCommandBufferState {
        let icbDesc = MTLIndirectCommandBufferDescriptor()
        icbDesc.commandTypes = .drawIndexed
        icbDesc.inheritBuffers = false
        icbDesc.maxVertexBufferBindCount = 5
        icbDesc.maxFragmentBufferBindCount = 1
        icbDesc.inheritPipelineState = true

        let icb = device.makeIndirectCommandBuffer(
            descriptor: icbDesc,
            maxCommandCount: 1,
            options: []
        )!

        icb.label = "[SwiftGLTF] Skybox Indirect Command Buffer"
        let skyboxRenderPassContext = encodeDrawingSkybox(
            icb: icb,
            mesh: skyboxMesh,
            pso: skyboxPipelineConnector.pso,
            dso: skyboxPipelineConnector.dso,
            worldTransformBuffer: bundle.worldTransformBuffer,
            cameraIndexBuffer: indirectCameraIndexBuffer,
            freeCameraUniformsBuffer: indirectFreeCameraUniformsBuffer,
            nodeCameraUniformsBuffer: bundle.nodeCameraUniformsBuffer,
            fragmentArgumentsBuffer: fragmentArgumentsBuffer
        )
        return PBRIndirectCommandBufferState(
            icb: icb,
            renderPassContext: skyboxRenderPassContext
        )
    }

    private func buildRenderScreenColorIndirectCommandBuffer(
        device: MTLDevice,
        bundle: PBRMeshBundle,
        pbrPipelineConnector: PBRPipelineConnector,
        writeDSO: MTLDepthStencilState,
        indirectCameraIndexBuffer: MTLBuffer,
        indirectFreeCameraUniformsBuffer: MTLBuffer,
        indirectEnvMapArgumentBuffer: MTLBuffer,
        indirectSceneUniformsBuffer: MTLBuffer,
        indirectModelMatrixBuffer: MTLBuffer,
        indirectScreenColorArgumentBuffer: MTLBuffer
    ) -> PBRIndirectCommandBufferState {
        let icbDesc = MTLIndirectCommandBufferDescriptor()
        icbDesc.commandTypes = .drawIndexed
        icbDesc.inheritBuffers = false
        icbDesc.inheritPipelineState = true
        icbDesc.maxVertexBufferBindCount = Int(PBRVertexShaderBufferCount.rawValue)
        icbDesc.maxFragmentBufferBindCount = Int(PBRFragmentShaderBufferCount.rawValue)

        let icb = device.makeIndirectCommandBuffer(
            descriptor: icbDesc,
            maxCommandCount: computePBRScreenDrawingCount(meshes: bundle.meshes),
            options: [.storageModeShared]
        )!
        icb.label = "[SwiftGLTF] PBR Indirect Command Buffer"

        let renderContext = encodeDrawingPBRScreen(
            icb: icb,
            meshes: bundle.meshes,
            opaquePSO: pbrPipelineConnector.opaquePSO,
            alphaBlendPSO: pbrPipelineConnector.alphaBlendPSO,
            writeDSO: writeDSO,
            worldTransformBuffer: bundle.worldTransformBuffer,
            boundingSpheresBuffer: bundle.boundingSpheresBuffer,
            jointsBuffer: bundle.jointsBuffer,
            inverseBindMatricesBuffer: bundle.inverseBindMatricesBuffer,
            morphWeightsBuffer: bundle.morphWeightsBuffer,
            morphDispatchesBuffer: bundle.morphDispatchesBuffer,
            cameraIndexBuffer: indirectCameraIndexBuffer,
            freeCameraUniformsBuffer: indirectFreeCameraUniformsBuffer,
            nodeCameraUniformsBuffer: bundle.nodeCameraUniformsBuffer,
            materialBuffer: bundle.materialBuffer,
            envMapArgBuffer: indirectEnvMapArgumentBuffer,
            fragmentParams: indirectSceneUniformsBuffer,
            modelMatrixBuffer: indirectModelMatrixBuffer,
            screenColorArgsBuffer: indirectScreenColorArgumentBuffer
        )

        return PBRIndirectCommandBufferState(
            icb: icb,
            renderPassContext: renderContext
        )
    }

    private func buildRenderTransmissionIndirectCommandBuffer(
        device: MTLDevice,
        bundle: PBRMeshBundle,
        pbrPipelineConnector: PBRPipelineConnector,
        writeDSO: MTLDepthStencilState,
        indirectCameraIndexBuffer: MTLBuffer,
        indirectFreeCameraUniformsBuffer: MTLBuffer,
        indirectEnvMapArgumentBuffer: MTLBuffer,
        indirectSceneUniformsBuffer: MTLBuffer,
        indirectModelMatrixBuffer: MTLBuffer,
        indirectScreenColorArgumentBuffer: MTLBuffer
    ) -> PBRIndirectCommandBufferState {
        let icbDesc = MTLIndirectCommandBufferDescriptor()
        icbDesc.commandTypes = .drawIndexed
        icbDesc.inheritBuffers = false
        icbDesc.inheritPipelineState = true
        icbDesc.maxVertexBufferBindCount = Int(PBRVertexShaderBufferCount.rawValue)
        icbDesc.maxFragmentBufferBindCount = Int(PBRFragmentShaderBufferCount.rawValue)

        let icb = device.makeIndirectCommandBuffer(
            descriptor: icbDesc,
            maxCommandCount: computeTransmissionDrawingCount(meshes: bundle.meshes),
            options: [.storageModeShared]
        )!
        icb.label = "[SwiftGLTF] PBR Indirect Command Buffer"

        let renderContext = encodeDrawingTransmission(
            icb: icb,
            meshes: bundle.meshes,
            alphaBlendPSO: pbrPipelineConnector.alphaBlendPSO,
            writeDSO: writeDSO,
            worldTransformBuffer: bundle.worldTransformBuffer,
            boundingSpheresBuffer: bundle.boundingSpheresBuffer,
            jointsBuffer: bundle.jointsBuffer,
            inverseBindMatricesBuffer: bundle.inverseBindMatricesBuffer,
            morphWeightsBuffer: bundle.morphWeightsBuffer,
            morphDispatchesBuffer: bundle.morphDispatchesBuffer,
            cameraIndexBuffer: indirectCameraIndexBuffer,
            freeCameraUniformsBuffer: indirectFreeCameraUniformsBuffer,
            nodeCameraUniformsBuffer: bundle.nodeCameraUniformsBuffer,
            materialBuffer: bundle.materialBuffer,
            envMapArgBuffer: indirectEnvMapArgumentBuffer,
            fragmentParams: indirectSceneUniformsBuffer,
            modelMatrixBuffer: indirectModelMatrixBuffer,
            screenColorArgsBuffer: indirectScreenColorArgumentBuffer
        )

        return PBRIndirectCommandBufferState(
            icb: icb,
            renderPassContext: renderContext
        )
    }
}
