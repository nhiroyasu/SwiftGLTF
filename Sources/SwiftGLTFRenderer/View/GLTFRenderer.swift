import MetalKit
import Img2Cubemap
import simd
import OSLog

public class GLTFRenderer {
    private var asset: MDLAsset?
    private var meshes: [PBRMesh] = []
    private var vertexResources: [MTLHeap] = []
    private var fragmentResources: [MTLHeap] = []
    private var type: RenderingType = .pbr

    private var skyboxMesh: SkyboxMesh?
    private var specularCubeMapTexture: MTLTexture?
    private var irradianceCubeMapTexture: MTLTexture?
    private var brdfLUT: MTLTexture?
    private var skyboxArgBuffer: MTLBuffer?
    private var skyboxFragmentHeap: MTLHeap?

    private let pbrMeshLoader: PBRMeshLoader
    private let wireframeMeshLoader: WireframeMeshLoader
    private let shaderConnection: ShaderConnection

    let device: MTLDevice
    let library: MTLLibrary
    let commandQueue: MTLCommandQueue

    let sampleCount: Int
    let colorPixelFormat: MTLPixelFormat
    let depthPixelFormat: MTLPixelFormat

    private let IRRADIANCE_SIZE = 128

    public init(
        device: MTLDevice = MTLCreateSystemDefaultDevice()!,
        renderingType type: RenderingType = .pbr,
        sampleCount: Int = 4,
        colorPixelFormat: MTLPixelFormat = .rgba8Unorm_srgb,
        depthPixelFormat: MTLPixelFormat = .depth32Float
    ) throws {
        self.device = device
        self.type = type
        if let commandQueue = device.makeCommandQueue() {
            self.commandQueue = commandQueue
        } else {
            throw NSError(domain: "PBRRenderer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create command queue"])
        }
        library = try device.makePackageLibrary()

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
        self.pbrMeshLoader = try PBRMeshLoader(
            device: device,
            library: library,
            config: pipelineStateConfig,
            shaderConnection: shaderConnection,
        )
        self.wireframeMeshLoader = try WireframeMeshLoader(
            device: device,
            library: library,
            config: pipelineStateConfig
        )
    }

    // MARK: - Rendering

    func render(
        using renderEncoder: MTLRenderCommandEncoder,
        vertexParams: MTLBuffer,
        fragmentParams: MTLBuffer,
        skyboxVP: MTLBuffer
    ) {
        guard let skyboxMesh, let specularCubeMapTexture, let skyboxFragmentHeap, let skyboxArgBuffer else {
            os_log("Skybox or textures not loaded", log: .default, type: .error)
            return
        }
        // Draw Skybox
        drawSkybox(
            renderEncoder: renderEncoder,
            mesh: skyboxMesh,
            vpMatrixBuffer: skyboxVP,
            specularCubeMapTexture: specularCubeMapTexture
        )

        switch type {
        case .pbr:
            drawPBR(
                renderEncoder: renderEncoder,
                pipelineState: pbrMeshLoader.pipelineState,
                depthStencilState: pbrMeshLoader.depthStencilState,
                vertexResources: vertexResources,
                fragmentResources: fragmentResources + [skyboxFragmentHeap],
                meshes: meshes,
                vertexParams: vertexParams,
                skyboxArgBuffer: skyboxArgBuffer,
                fragmentParams: fragmentParams
            )
        case .wireframe:
            drawWireframe(
                renderEncoder: renderEncoder,
                pipelineState: wireframeMeshLoader.pipelineState,
                depthStencilState: wireframeMeshLoader.depthStencilState,
                meshes: meshes,
                vertexParams: vertexParams
            )
        }
    }

    // MARK: - Update states

    public func load(from asset: MDLAsset) async throws {
        _ = try await (
            _loadSkybox(),
            _loadEnvMap(),
            _loadAsset(asset: asset, type: type)
        )
    }

    public func reload(with type: RenderingType) async throws {
        guard let asset = self.asset else {
            throw NSError(domain: "GLTFRenderer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Asset not loaded"])
        }

        try await _loadAsset(asset: asset, type: type)
        self.type = type
    }

    // MARK: - Helper

    private func _loadAsset(asset: MDLAsset, type: RenderingType) async throws {
        self.asset = asset
        switch type {
        case .pbr:
            let meshContainer = try await pbrMeshLoader.loadMeshes(from: asset)
            self.meshes = meshContainer.meshes
            self.vertexResources = meshContainer.vertexResources
            self.fragmentResources = meshContainer.fragmentResources
        case .wireframe:
            self.meshes = try wireframeMeshLoader.loadMeshes(from: asset)
            self.vertexResources = []
            self.fragmentResources = []
        }
    }

    private func _loadSkybox() async throws {
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
        // Load environment textures
        guard let envMapUrl = Bundle.main.url(forResource: "env_map", withExtension: "exr") else {
            throw NSError(domain: "MDLAssetMTKView", code: 0, userInfo: [NSLocalizedDescriptionKey: "Environment map not found"])
        }
        let specularCubeMapTexture = try await generateCubeTexture(device: device, exr: envMapUrl)
        let irradianceCubeMapTexture = generateIrradianceTexture(
            commandQueue: commandQueue,
            library: library,
            envMap: specularCubeMapTexture,
            size: IRRADIANCE_SIZE
        )
        let brdfLUT = generateBRDFLUT(
            commandQueue: commandQueue,
            library: library,
            width: specularCubeMapTexture.width,
            height: specularCubeMapTexture.height
        )
        let skyboxFragmentHeap = pbrMeshLoader.createSkyboxFragmentHeap(
            specularCubeMap: specularCubeMapTexture,
            irradianceMap: irradianceCubeMapTexture,
            brdfLUT: brdfLUT
        )
        self.skyboxFragmentHeap = skyboxFragmentHeap
        (
            skyboxArgBuffer,
            self.specularCubeMapTexture,
            self.irradianceCubeMapTexture,
            self.brdfLUT
        ) = try pbrMeshLoader.makeSkyboxArgBuffer(
            heap: skyboxFragmentHeap,
            specularCubeMap: specularCubeMapTexture,
            irradianceMap: irradianceCubeMapTexture,
            brdfLUT: brdfLUT
        )
    }
}
