import MetalKit
import Img2Cubemap
import simd

public class GLTFRenderer {
    private var asset: MDLAsset?
    private var meshes: [PBRMesh] = []
    private var type: RenderingType = .pbr

    private let pbrMeshLoader: PBRMeshLoader
    private let pbrPipelineStateLoader: PBRPipelineStateLoader
    private let wireframeMeshLoader: WireframeMeshLoader
    private let wireframePipelineStateLoader: WireframePipelineStateLoader

    private let shaderConnection: ShaderConnection

    private let dso: MTLDepthStencilState

    private let specularCubeMapTexture: MTLTexture
    private let irradianceCubeMapTexture: MTLTexture
    private let brdfLUT: MTLTexture

    private let skyboxCubeVertexBuffer: MTLBuffer
    private let skyboxCubeIndexBuffer: MTLBuffer
    private let skyboxPSO: MTLRenderPipelineState
    private let skyboxDSO: MTLDepthStencilState

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
        colorPixelFormat: MTLPixelFormat = .rgba16Float,
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

        let pipelineStateConfig = PipelineStateLoaderConfig(
            sampleCount: sampleCount,
            colorPixelFormat: colorPixelFormat,
            depthPixelFormat: depthPixelFormat
        )
        self.pbrPipelineStateLoader = PBRPipelineStateLoader(
            device: device,
            library: library,
            config: pipelineStateConfig
        )
        self.pbrMeshLoader = PBRMeshLoader(
            shaderConnection: shaderConnection,
            pipelineStateLoader: pbrPipelineStateLoader
        )
        self.wireframePipelineStateLoader = WireframePipelineStateLoader(
            device: device,
            library: library,
            config: pipelineStateConfig
        )
        self.wireframeMeshLoader = WireframeMeshLoader(
            pipelineStateLoader: wireframePipelineStateLoader
        )

        // Create a depth stencil descriptor
        let depthStencilDescriptor = MTLDepthStencilDescriptor()
        depthStencilDescriptor.depthCompareFunction = .less
        depthStencilDescriptor.isDepthWriteEnabled = true
        guard let depthStencilState = device.makeDepthStencilState(descriptor: depthStencilDescriptor) else {
            throw NSError(domain: "MDLAssetMTKView", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create depth stencil state"])
        }
        self.dso = depthStencilState

        // Create skybox buffers and pipeline state
        let skyboxPsoDescriptor = MTLRenderPipelineDescriptor()
        skyboxPsoDescriptor.label = "Skybox Pipeline"
        skyboxPsoDescriptor.vertexFunction = library.makeFunction(name: "skybox_vertex_shader")
        skyboxPsoDescriptor.fragmentFunction = library.makeFunction(name: "skybox_fragment_shader")
        skyboxPsoDescriptor.colorAttachments[0].pixelFormat = colorPixelFormat
        skyboxPsoDescriptor.depthAttachmentPixelFormat = depthPixelFormat
        skyboxPsoDescriptor.rasterSampleCount = sampleCount
        self.skyboxPSO = try await device.makeRenderPipelineState(descriptor: skyboxPsoDescriptor)

        let skyboxDSODescriptor = MTLDepthStencilDescriptor()
        skyboxDSODescriptor.depthCompareFunction = .always
        skyboxDSODescriptor.isDepthWriteEnabled = false
        skyboxDSODescriptor.label = "Skybox depth stencil"
        self.skyboxDSO = device.makeDepthStencilState(descriptor: skyboxDSODescriptor)!

        let skyboxCube = Cube(size: 1)
        self.skyboxCubeVertexBuffer = device.makeBuffer(
            bytes: skyboxCube.vertices,
            length: MemoryLayout<Float>.size * skyboxCube.vertices.count,
            options: .storageModeShared
        )!
        self.skyboxCubeIndexBuffer = device.makeBuffer(
            bytes: skyboxCube.indices,
            length: MemoryLayout<UInt16>.size * skyboxCube.indices.count,
            options: .storageModeShared
        )!

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
            pso: skyboxPSO,
            dso: skyboxDSO,
            vertexBuffer: skyboxCubeVertexBuffer,
            indexBuffer: skyboxCubeIndexBuffer,
            indexCount: skyboxCubeIndexBuffer.length / MemoryLayout<UInt16>.size,
            indexType: .uint16,
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
                    dso: dso,
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
                    dso: dso,
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
