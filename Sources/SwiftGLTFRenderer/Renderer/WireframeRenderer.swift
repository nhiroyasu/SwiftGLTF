import MetalKit
import simd
import OSLog
import SwiftGLTFCore
import SwiftGLTFShaderTypes

public class WireframeRenderer {
    private var bundle: WireframeMeshBundle?

    private var skyboxMesh: SkyboxMesh?
    private var envMapArgBuffer: MTLBuffer?
    private var envMapHeap: MTLHeap?

    private let meshLoader: WireframeMeshLoader
    private let pipelineConnector: WireframePipelineConnector
    private let skyboxPipelineConnector: SkyboxPipelineConnector
    private let envMapLoader: EnvironmentMapLoader
    private let shaderConnection: ShaderConnection

    private let depthStencilState: MTLDepthStencilState

    let device: MTLDevice
    let library: MTLLibrary
    let commandQueue: MTLCommandQueue

    let sampleCount: Int
    let colorPixelFormat: MTLPixelFormat
    let depthPixelFormat: MTLPixelFormat

    // Variables to prevent deallocation by ARC
    private var _specularCubeMapTexture: MTLTexture?
    private var _irradianceCubeMapTexture: MTLTexture?
    private var _brdfLUT: MTLTexture?
    private var _prefilterSheenTexture: MTLTexture?

    public init(
        commandQueue: MTLCommandQueue,
        sampleCount: Int = 4,
        colorPixelFormat: MTLPixelFormat = .rgba8Unorm_srgb,
        depthPixelFormat: MTLPixelFormat = .depth32Float
    ) throws {
        self.device = commandQueue.device
        self.commandQueue = commandQueue
        self.library = try device.makePackageLibrary()

        self.sampleCount = sampleCount
        self.colorPixelFormat = colorPixelFormat
        self.depthPixelFormat = depthPixelFormat
        self.shaderConnection = try ShaderConnection(commandQueue: commandQueue)

        let pipelineStateConfig = PipelineStateLoaderConfig(
            sampleCount: sampleCount,
            colorPixelFormat: colorPixelFormat,
            depthPixelFormat: depthPixelFormat
        )
        self.pipelineConnector = try WireframePipelineConnector(
            device: device,
            library: library,
            config: pipelineStateConfig,
            shaderConnection: shaderConnection
        )
        self.skyboxPipelineConnector = try SkyboxPipelineConnector(
            device: device,
            library: library,
            config: SkyboxPipelineConfig(
                sampleCount: sampleCount,
                colorPixelFormat: .rgba16Float,
                depthPixelFormat: .depth32Float
            )
        )
        self.meshLoader = WireframeMeshLoader(
            device: device,
            pipelineConnector: pipelineConnector,
            shaderConnection: shaderConnection
        )
        self.envMapLoader = try EnvironmentMapLoader(commandQueue: commandQueue)

        self.depthStencilState = try makeLessEqualDepthStencilState(device: device)
    }

    // MARK: - Rendering

    public func render(
        using renderEncoder: MTLRenderCommandEncoder,
        freeCameraUniformsBuffer: MTLBuffer,
        modelMatrixBuffer: MTLBuffer,
        fragmentParams: MTLBuffer,
    ) {
        guard let bundle else {
            Log.common.error("Mesh not loaded")
            return
        }
        guard let skyboxMesh, let envMapArgBuffer, let envMapHeap else {
            Log.common.error("Skybox or textures not loaded")
            return
        }

        var worldTransformDummy: [SIMD4<Float>] = [SIMD4<Float>(1, 0, 0, 0)]
        let worldTransformBuffer = device.makeBuffer(
            bytes: &worldTransformDummy,
            length: MemoryLayout<SIMD4<Float>>.size,
            options: .storageModeShared
        )!
        var cameraIndex = -1
        let cameraIndexBuffer = device.makeBuffer(
            bytes: &cameraIndex,
            length: MemoryLayout<Int>.size,
            options: .storageModeShared
        )!
        drawSkybox(
            renderEncoder: renderEncoder,
            pso: skyboxPipelineConnector.pso,
            dso: skyboxPipelineConnector.dso,
            mesh: skyboxMesh,
            worldTransformBuffer: worldTransformBuffer,
            cameraIndexBuffer: cameraIndexBuffer,
            freeCameraUniformsBuffer: freeCameraUniformsBuffer,
            nodeCameraUniformsBuffer: NodeCameraUniforms.makeDummyBuffer(device: device),
            envMapArgBuffer: envMapArgBuffer,
            fragmentHeaps: [envMapHeap]
        )

        drawWireframe(
            renderEncoder: renderEncoder,
            pipelineState: pipelineConnector.pipelineState,
            depthStencilState: depthStencilState,
            meshes: bundle.meshes,
            modelBuffer: modelMatrixBuffer,
            worldTransformBuffer: bundle.worldTransformBuffer,
            freeCameraUniformsBuffer: freeCameraUniformsBuffer
        )
    }

    // MARK: - Update states

    public func load(from asset: MDLAsset) async throws {
        _ = try await (
            _loadSkybox(),
            _loadEnvMap(),
            _loadAsset(asset: asset)
        )
    }

    // MARK: - Helper

    private func _loadAsset(asset: MDLAsset) throws {
        self.bundle = try meshLoader.loadMeshes(from: asset)
    }

    private func _loadSkybox() async throws {
        guard skyboxMesh == nil else {
            // Skybox already loaded
            return
        }
        // Create skybox mesh via loader
        let skyboxLoader = try SkyboxMeshLoader(device: device)
        self.skyboxMesh = skyboxLoader.loadMesh()
    }

    private func _loadEnvMap() async throws {
        guard envMapHeap == nil else {
            // Environment map already loaded
            return
        }

        // TODO: env map loading should be optional
        guard let envMapUrl = Bundle.module.url(forResource: "env_map", withExtension: "exr") else {
            throw SwiftGLTFRendererError(description: "Environment map not found")
        }
        let (
            envMapHeap,
            prefilterEnvMap,
            irradianceMap,
            brdfLUT,
            prefilterSheenTexture
        ) = try await envMapLoader.makeEnvMapHeapAndTexture(url: envMapUrl)
        self.envMapHeap = envMapHeap
        self._specularCubeMapTexture = prefilterEnvMap
        self._irradianceCubeMapTexture = irradianceMap
        self._brdfLUT = brdfLUT
        self._prefilterSheenTexture = prefilterSheenTexture

        let envMapArgBuffer = device.makeBuffer(length: MemoryLayout<PBREnvMapArguments>.size)!
        let envMapArg = envMapArgBuffer.contents().bindMemory(to: PBREnvMapArguments.self, capacity: 1)
        envMapArg.pointee.prefilterEnvMap = prefilterEnvMap.gpuResourceID
        envMapArg.pointee.irradianceMap = irradianceMap.gpuResourceID
        envMapArg.pointee.brdfLUT = brdfLUT.gpuResourceID
        envMapArg.pointee.prefilterSheenMap = prefilterSheenTexture.gpuResourceID
    }
}
