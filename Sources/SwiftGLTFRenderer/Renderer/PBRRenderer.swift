import Img2Cubemap
import MetalKit
import OSLog
import simd

public class PBRRenderer {
    private var meshes: [PBRMesh] = []
    private var vertexResources: [MTLHeap] = []
    private var fragmentResources: [MTLHeap] = []

    private var skyboxMesh: SkyboxMesh
    private var envMapArgBuffer: MTLBuffer
    private var envMapHeap: MTLHeap
    // Variables to prevent deallocation by ARC
    private var _prefilterEnvMap: MTLTexture
    private var _irradianceMap: MTLTexture
    private var _brdfLUT: MTLTexture

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

        (
            self.envMapHeap,
            self._prefilterEnvMap,
            self._irradianceMap,
            self._brdfLUT
        ) = try envMapLoader.makeEnvMapHeapAndTexture(from: CGColor(gray: 0.35, alpha: 1.0))
        self.envMapArgBuffer = try pipelineConnector.makeEnvMapArgBuffer(
            prefilterEnvMap: _prefilterEnvMap,
            irradianceMap: _irradianceMap,
            brdfLUT: _brdfLUT
        )
    }

    // MARK: - Rendering

    public func render(
        using renderEncoder: MTLRenderCommandEncoder,
        vertexParams: MTLBuffer,
        fragmentParams: MTLBuffer,
        skyboxVP: MTLBuffer
    ) {
        drawSkybox(
            renderEncoder: renderEncoder,
            mesh: skyboxMesh,
            vpMatrixBuffer: skyboxVP,
            specularCubeMapTexture: _prefilterEnvMap
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
        let meshContainer = try await meshLoader.loadMeshes(from: asset)
        self.meshes = meshContainer.meshes
        self.vertexResources = meshContainer.vertexResources
        self.fragmentResources = meshContainer.fragmentResources
    }

    /// Set environment from external URL (equirectangular .exr)
    public func setEnvironment(url: URL) async throws {
        (
            self.envMapHeap,
            self._prefilterEnvMap,
            self._irradianceMap,
            self._brdfLUT
        ) = try envMapLoader.makeEnvMapHeapAndTexture(url: url)
        self.envMapArgBuffer = try pipelineConnector.makeEnvMapArgBuffer(
            prefilterEnvMap: _prefilterEnvMap,
            irradianceMap: _irradianceMap,
            brdfLUT: _brdfLUT
        )
    }

    /// Set environment from existing cube texture
    public func setEnvironment(cubeTexture: MTLTexture) throws {
        (
            self.envMapHeap,
            self._prefilterEnvMap,
            self._irradianceMap,
            self._brdfLUT
        ) = try envMapLoader.makeEnvMapHeapAndTexture(fromCube: cubeTexture)
        self.envMapArgBuffer = try pipelineConnector.makeEnvMapArgBuffer(
            prefilterEnvMap: _prefilterEnvMap,
            irradianceMap: _irradianceMap,
            brdfLUT: _brdfLUT
        )
    }
}
