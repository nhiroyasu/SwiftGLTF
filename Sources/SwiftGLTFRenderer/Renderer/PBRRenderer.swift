import Img2Cubemap
import MetalKit
import OSLog
import simd

public class PBRRenderer {
    public var isLoaded: Bool = false

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

    private let device: MTLDevice
    private let library: MTLLibrary
    private let commandQueue: MTLCommandQueue

    private let sampleCount: Int
    private let colorPixelFormat: MTLPixelFormat
    private let depthPixelFormat: MTLPixelFormat

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

        self.depthStencilState = try makeLessEqualDepthStencilState(
            device: device
        )

        // Load default environment map if requested
        Task {
            _ = try await [
                loadDefaultEnvMap(),
                loadSkybox()
            ]
            isLoaded = true
        }
    }

    // MARK: - Rendering

    public func render(
        using renderEncoder: MTLRenderCommandEncoder,
        vertexParams: MTLBuffer,
        fragmentParams: MTLBuffer,
        skyboxVP: MTLBuffer
    ) {
        guard let skyboxMesh else {
            os_log(
                "Skybox or textures not loaded yet.",
                log: .default,
                type: .info
            )
            return
        }
        guard let _specularCubeMapTexture, let envMapHeap, let envMapArgBuffer
        else {
            os_log(
                "Environment map textures or heap not loaded yet.",
                log: .default,
                type: .info
            )
            return
        }
        guard !meshes.isEmpty else {
            os_log("No meshes to render.", log: .default, type: .info)
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

    /// Load a gltf asset
    public func load(from asset: MDLAsset) async throws {
        try await loadAsset(asset: asset)
    }

    /// Set environment from external URL (equirectangular .exr)
    public func setEnvironment(url: URL) async throws {
        let (
            envMapHeap,
            prefilterEnvMap,
            irradianceMap,
            brdfLUT
        ) = try await envMapLoader.makeEnvMapHeapAndTexture(url: url)
        try applyEnvironment(
            heap: envMapHeap,
            prefiltered: prefilterEnvMap,
            irradiance: irradianceMap,
            brdfLUT: brdfLUT
        )
    }

    /// Set environment from existing cube texture
    public func setEnvironment(cubeTexture: MTLTexture) throws {
        let (
            envMapHeap,
            prefilterEnvMap,
            irradianceMap,
            brdfLUT
        ) = try envMapLoader.makeEnvMapHeapAndTexture(fromCube: cubeTexture)
        try applyEnvironment(
            heap: envMapHeap,
            prefiltered: prefilterEnvMap,
            irradiance: irradianceMap,
            brdfLUT: brdfLUT
        )
    }

    // MARK: - Helper

    private func loadAsset(asset: MDLAsset) async throws {
        let meshContainer = try await meshLoader.loadMeshes(from: asset)
        self.meshes = meshContainer.meshes
        self.vertexResources = meshContainer.vertexResources
        self.fragmentResources = meshContainer.fragmentResources
    }

    private func loadSkybox() async throws {
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

    private func loadDefaultEnvMap() async throws {
        guard envMapHeap == nil else {
            // Environment map already loaded
            return
        }
        guard
            let envMapUrl = Bundle.module.url(
                forResource: "env_map",
                withExtension: "exr"
            )
        else {
            throw NSError(
                domain: "MDLAssetMTKView",
                code: 0,
                userInfo: [
                    NSLocalizedDescriptionKey: "Environment map not found"
                ]
            )
        }
        let (
            envMapHeap,
            prefilterEnvMap,
            irradianceMap,
            brdfLUT
        ) = try await envMapLoader.makeEnvMapHeapAndTexture(url: envMapUrl)
        try applyEnvironment(
            heap: envMapHeap,
            prefiltered: prefilterEnvMap,
            irradiance: irradianceMap,
            brdfLUT: brdfLUT
        )
    }

    private func applyEnvironment(
        heap: MTLHeap,
        prefiltered: MTLTexture,
        irradiance: MTLTexture,
        brdfLUT: MTLTexture
    ) throws {
        self.envMapHeap = heap
        self._specularCubeMapTexture = prefiltered
        self._irradianceCubeMapTexture = irradiance
        self._brdfLUT = brdfLUT
        self.envMapArgBuffer = try pipelineConnector.makeEnvMapArgBuffer(
            prefilterEnvMap: prefiltered,
            irradianceMap: irradiance,
            brdfLUT: brdfLUT
        )
    }
}
