import MetalKit
import simd
import os.log
import SwiftGLTFCore
import SwiftGLTFShaderTypes

public class WireframeRenderer {
    private var bundle: WireframeMeshBundle?

    private var skyboxMesh: SkyboxMesh?
    private var envMapArgBuffer: MTLBuffer?
    private var envMapHeap: MTLHeap?

    private let meshLoader: WireframeMeshLoader
    private let pipelineConnector: WireframePipelineConnector
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
        self.shaderConnection = ShaderConnection(
            device: device,
            library: library,
            commandQueue: commandQueue
        )

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
        self.meshLoader = WireframeMeshLoader(
            device: device,
            pipelineConnector: pipelineConnector,
            shaderConnection: shaderConnection
        )
        self.envMapLoader = EnvironmentMapLoader(
            device: device,
            library: library,
            shaderConnection: shaderConnection
        )

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
            os_log("Mesh not loaded", log: .default, type: .error)
            return
        }
        guard let skyboxMesh, let _specularCubeMapTexture else {
            os_log("Skybox or textures not loaded", log: .default, type: .error)
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
        var nodeCameraUniformsDummy: [NodeCameraUniforms] = [.init(
            nodeHierarchyOffset: 0,
            fov: SIMD2<Float>(1,1),
            aspectRatio: -1,
            znear: 0,
            zfar: 1
        )]
        let nodeCameraUniformsBuffer = device.makeBuffer(
            bytes: &nodeCameraUniformsDummy,
            length: MemoryLayout<NodeCameraUniforms>.size,
            options: .storageModeShared
        )!
        drawSkybox(
            renderEncoder: renderEncoder,
            mesh: skyboxMesh,
            worldTransformBuffer: worldTransformBuffer,
            cameraIndexBuffer: cameraIndexBuffer,
            freeCameraUniformsBuffer: freeCameraUniformsBuffer,
            nodeCameraUniformsBuffer: nodeCameraUniformsBuffer,
            specularCubeMapTexture: _specularCubeMapTexture
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
        let skyboxConfig = SkyboxPipelineConfig(
            sampleCount: sampleCount,
            colorPixelFormat: colorPixelFormat,
            depthPixelFormat: depthPixelFormat
        )
        let skyboxLoader = try SkyboxMeshLoader(
            device: device,
            library: library,
            config: skyboxConfig
        )
        self.skyboxMesh = skyboxLoader.loadMesh()
    }

    private func _loadEnvMap() async throws {
        guard envMapHeap == nil else {
            // Environment map already loaded
            return
        }

        // TODO: env map loading should be optional
        guard let envMapUrl = Bundle.module.url(forResource: "env_map", withExtension: "exr") else {
            throw SwiftGLTFError.makeRender(.environmentMapNotFound, context: .capture(stage: .render))
        }
        let (
            envMapHeap,
            prefilterEnvMap,
            irradianceMap,
            brdfLUT,
            prefilterSheenTexture
        ) = try envMapLoader.makeEnvMapHeapAndTexture(url: envMapUrl)
        self.envMapHeap = envMapHeap
        self._specularCubeMapTexture = prefilterEnvMap
        self._irradianceCubeMapTexture = irradianceMap
        self._brdfLUT = brdfLUT
        self._prefilterSheenTexture = prefilterSheenTexture
    }
}
