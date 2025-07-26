import MetalKit
import Img2Cubemap
import simd

public class GLTFRenderer {
    private var asset: MDLAsset?
    private var meshes: [PBRMesh] = []
    private var type: RenderingType = .pbr

    private let pbrMeshLoader: PBRMeshLoader
    private let wireframeMeshLoader: WireframeMeshLoader
    private let depthStencilStateLoader: DepthStencilStateLoader
    private let shaderConnection: ShaderConnection

    private let specularCubeMapTexture: MTLTexture
    private let irradianceCubeMapTexture: MTLTexture
    private let brdfLUT: MTLTexture

    private let skyboxMesh: SkyboxMesh

    let device: MTLDevice
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
    ) async throws {
        self.device = device
        self.type = type
        if let commandQueue = device.makeCommandQueue() {
            self.commandQueue = commandQueue
        } else {
            throw NSError(domain: "PBRRenderer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create command queue"])
        }
        let library = try device.makePackageLibrary()

        self.sampleCount = sampleCount
        self.colorPixelFormat = colorPixelFormat
        self.depthPixelFormat = depthPixelFormat
        self.shaderConnection = ShaderConnection(
            device: device,
            library: library,
            commandQueue: commandQueue
        )
        self.depthStencilStateLoader = DepthStencilStateLoader(device: device)

        let pipelineStateConfig = PipelineStateLoaderConfig(
            sampleCount: sampleCount,
            colorPixelFormat: colorPixelFormat,
            depthPixelFormat: depthPixelFormat
        )
        let pbrPipelineStateLoader = PBRPipelineStateLoader(
            device: device,
            library: library,
            config: pipelineStateConfig
        )
        self.pbrMeshLoader = PBRMeshLoader(
            shaderConnection: shaderConnection,
            pipelineStateLoader: pbrPipelineStateLoader,
            depthStencilStateLoader: depthStencilStateLoader,
        )
        let wireframePipelineStateLoader = WireframePipelineStateLoader(
            device: device,
            library: library,
            config: pipelineStateConfig
        )
        self.wireframeMeshLoader = WireframeMeshLoader(
            pipelineStateLoader: wireframePipelineStateLoader,
            depthStencilStateLoader: depthStencilStateLoader,
        )

        // Create skybox mesh via loader
        let skyboxConfig = SkyboxPipelineConfig(
            sampleCount: sampleCount,
            colorPixelFormat: colorPixelFormat,
            depthPixelFormat: depthPixelFormat
        )
        let skyboxLoader = try await SkyboxMeshLoader(
            device: device,
            library: library,
            config: skyboxConfig
        )
        self.skyboxMesh = skyboxLoader.loadMesh()

        // Load environment textures
        guard let envMapUrl = Bundle.main.url(forResource: "env_map", withExtension: "exr") else {
            throw NSError(domain: "MDLAssetMTKView", code: 0, userInfo: [NSLocalizedDescriptionKey: "Environment map not found"])
        }
        self.specularCubeMapTexture = try await generateCubeTexture(device: device, exr: envMapUrl)
        self.irradianceCubeMapTexture = generateIrradianceTexture(
            commandQueue: commandQueue,
            library: library,
            envMap: specularCubeMapTexture,
            size: IRRADIANCE_SIZE
        )
        self.brdfLUT = generateBRDFLUT(
            commandQueue: commandQueue,
            library: library,
            width: specularCubeMapTexture.width,
            height: specularCubeMapTexture.height
        )
    }

    // MARK: - Rendering

    func render(
        using renderEncoder: MTLRenderCommandEncoder,
        view: MTLBuffer,
        projection: MTLBuffer,
        pbrScene: MTLBuffer,
        skyboxVP: MTLBuffer,
        offset: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    ) {
        // Draw Skybox
        drawSkybox(
            renderEncoder: renderEncoder,
            mesh: skyboxMesh,
            vpMatrixBuffer: skyboxVP,
            specularCubeMapTexture: specularCubeMapTexture
        )

        for mesh in meshes {
            updateMeshBuffer(toMesh: mesh, targetOffset: offset)

            switch type {
            case .pbr:
                drawPBR(
                    renderEncoder: renderEncoder,
                    mesh: mesh,
                    viewBuffer: view,
                    projectionBuffer: projection,
                    pbrSceneUniformsBuffer: pbrScene,
                    specularCubeMapTexture: specularCubeMapTexture,
                    irradianceCubeMapTexture: irradianceCubeMapTexture,
                    brdfLUT: brdfLUT
                )
            case .wireframe:
                drawWireframe(
                    renderEncoder: renderEncoder,
                    mesh: mesh,
                    viewBuffer: view,
                    projectionBuffer: projection
                )
            }
        }
    }

    // MARK: - Update states

    public func load(from asset: MDLAsset) throws {
        self.asset = asset

        switch type {
        case .pbr:
            self.meshes = try pbrMeshLoader.loadMeshes(from: asset, using: commandQueue.device)
        case .wireframe:
            self.meshes = try wireframeMeshLoader.loadMeshes(from: asset, using: commandQueue.device)
        }
    }

    public func reload(with type: RenderingType) throws {
        guard let asset = self.asset else {
            throw NSError(domain: "GLTFRenderer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Asset not loaded"])
        }

        self.type = type
        try load(from: asset)
    }

    // MARK: - Helper

    private func updateMeshBuffer(
        toMesh mesh: PBRMesh,
        targetOffset: SIMD3<Float>
    ) {
        let modelTransform = mesh.transform
        let offsetTranslation = translationMatrix(targetOffset.x, targetOffset.y, targetOffset.z)
        var model = offsetTranslation * modelTransform
        mesh.modelBuffer.contents().copyMemory(from: &model, byteCount: MemoryLayout<float4x4>.size)

        var normalMatrix = float3x3(model).transpose.inverse
        mesh.normalMatrixBuffer.contents().copyMemory(from: &normalMatrix, byteCount: MemoryLayout<float3x3>.size)
    }
}
