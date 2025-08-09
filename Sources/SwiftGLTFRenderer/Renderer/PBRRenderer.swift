import MetalKit
import Img2Cubemap
import simd
import OSLog

public class PBRRenderer {
    private var meshes: [PBRMesh] = []
    private var vertexResources: [MTLHeap] = []
    private var fragmentResources: [MTLHeap] = []

    private var skyboxMesh: SkyboxMesh?
    private var envMapArgBuffer: MTLBuffer?
    private var envMapHeap: MTLHeap?

    private let meshLoader: PBRMeshLoader
    private let pipelineConnector: PBRPipelineConnector
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
        self.pipelineConnector = try PBRPipelineConnector(
            device: device,
            library: library,
            config: pipelineStateConfig,
            shaderConnection: shaderConnection
        )
        self.meshLoader = PBRMeshLoader(
            device: device,
            shaderConnection: shaderConnection,
            pipelineConnector: pipelineConnector
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
        vertexParams: MTLBuffer,
        fragmentParams: MTLBuffer,
        skyboxVP: MTLBuffer
    ) {
        guard let skyboxMesh, let _specularCubeMapTexture, let envMapHeap, let envMapArgBuffer else {
            os_log("Skybox or textures not loaded", log: .default, type: .error)
            return
        }

        drawSkybox(
            renderEncoder: renderEncoder,
            mesh: skyboxMesh,
            vpMatrixBuffer: skyboxVP,
            specularCubeMapTexture: _specularCubeMapTexture
        )

        drawPBR(
            renderEncoder: renderEncoder,
            pipelineState: pipelineConnector.pipelineState,
            depthStencilState: depthStencilState,
            vertexResources: vertexResources,
            fragmentResources: fragmentResources + [envMapHeap],
            meshes: meshes,
            vertexParams: vertexParams,
            envMapArgBuffer: envMapArgBuffer,
            fragmentParams: fragmentParams
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

    private func _loadAsset(asset: MDLAsset) async throws {
        let meshContainer = try await meshLoader.loadMeshes(from: asset)
        self.meshes = meshContainer.meshes
        self.vertexResources = meshContainer.vertexResources
        self.fragmentResources = meshContainer.fragmentResources
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
            throw NSError(domain: "MDLAssetMTKView", code: 0, userInfo: [NSLocalizedDescriptionKey: "Environment map not found"])
        }
        let (
            envMapHeap,
            prefilterEnvMap,
            irradianceMap,
            brdfLUT
        ) = try await envMapLoader.makeEnvMapHeapAndTexture(url: envMapUrl)
        self.envMapHeap = envMapHeap
        self._specularCubeMapTexture = prefilterEnvMap
        self._irradianceCubeMapTexture = irradianceMap
        self._brdfLUT = brdfLUT
        self.envMapArgBuffer = try pipelineConnector.makeEnvMapArgBuffer(
            prefilterEnvMap: prefilterEnvMap,
            irradianceMap: irradianceMap,
            brdfLUT: brdfLUT
        )
    }
}
