import Img2Cubemap
import MetalKit
import OSLog
import simd
import ModelIO
import SwiftGLTFParser
import SwiftGLTFCore

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

    private let depthStencilStateWrite: MTLDepthStencilState
    private let depthStencilStateNoWrite: MTLDepthStencilState

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

        self.depthStencilStateWrite = try makeLessEqualDepthStencilState(device: device)
        self.depthStencilStateNoWrite = try makeLessEqualNoWriteDepthStencilState(device: device)

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

    public func animation(
        using blitCommandEncoder: MTLBlitCommandEncoder,
        animationState state: RendererAnimationState
    ) {
        for mesh in meshes {
            guard let animation = mesh.animation else { continue }

            var modelMatrixTree = mesh.modelMatrixTree
            var animGlobalJointMatrixTrees: [[TRS]] = mesh.skeleton?.joints.map({ $0.globalJointTRSTree }) ?? []
            var morphWeights: [Float]? = nil
            for channel in animation.channels {
                let trs = evaluateTRS(
                    channel: channel,
                    duration: animation.duration,
                    time: state.time,
                    looping: state.isLooping
                )
                if let effectIndex = channel.modelMatrixTreeEffectIndex {
                    modelMatrixTree[effectIndex] = trs.apply(modelMatrixTree[effectIndex])
                }

                if let nodeIndex = channel.globalJointNodeTreeEffectIndex,
                   let matrixIndex = channel.globalJointMatrixTreeEffectIndex {
                    animGlobalJointMatrixTrees[nodeIndex][matrixIndex] = trs.apply(animGlobalJointMatrixTrees[nodeIndex][matrixIndex])
                }

                if let w = evaluateWeights(
                    channel: channel,
                    duration: animation.duration,
                    time: state.time,
                    looping: state.isLooping
                ) {
                    morphWeights = w
                }
            }

            var totalModelMatrix: float4x4 = modelMatrixTree.reduce(float4x4(1), *)
            var inverseModelMatrix = totalModelMatrix.inverse

            // Update model and inverse model matrix buffer
            let length = MemoryLayout<simd_float4x4>.size
            let modelBuffer = device.makeBuffer(
                bytes: &totalModelMatrix,
                length: length,
                options: .storageModeShared
            )!
            let inverseModelBuffer = device.makeBuffer(
                bytes: &inverseModelMatrix,
                length: length,
                options: .storageModeShared
            )!

            blitCommandEncoder.copy(
                from: modelBuffer,
                sourceOffset: 0,
                to: animation.animatableBuffers.modelBuffer,
                destinationOffset: 0,
                size: length
            )
            blitCommandEncoder.copy(
                from: inverseModelBuffer,
                sourceOffset: 0,
                to: animation.animatableBuffers.inverseModelBuffer,
                destinationOffset: 0,
                size: length
            )

            // Update global joint matrices buffer if exists
            if !animGlobalJointMatrixTrees.isEmpty,
               let jointBuffer = animation.animatableBuffers.globalJointMatricesBuffer,
               let skeleton = mesh.skeleton {
                var jointMatrices: [float4x4] = skeleton.jointMatrices
                for (jointNodeIndex, matrixTree) in animGlobalJointMatrixTrees.enumerated() {
                    let globalJointMatrix = matrixTree
                        .map { trs2matrix($0) }
                        .reduce(float4x4(1), *)
                    let inverseBindMatrix = skeleton.joints[jointNodeIndex].inverseBindMatrix
                    jointMatrices[jointNodeIndex] = globalJointMatrix * inverseBindMatrix
                }
                let buffer = device.makeBuffer(
                    bytes: jointMatrices,
                    length: MemoryLayout<float4x4>.size * jointMatrices.count,
                    options: .storageModeShared
                )!
                blitCommandEncoder.copy(
                    from: buffer,
                    sourceOffset: 0,
                    to: jointBuffer,
                    destinationOffset: 0,
                    size: jointBuffer.length
                )
            }


            if let morphWeights {
                guard let buffer = animation.animatableBuffers.morphWeightsBuffer else {
                    assertionFailure("Morph weights buffer is nil")
                    continue
                }
                let staging = device.makeBuffer(
                    bytes: morphWeights,
                    length: buffer.length,
                    options: .storageModeShared
                )!
                blitCommandEncoder.copy(
                    from: staging,
                    sourceOffset: 0,
                    to: buffer,
                    destinationOffset: 0,
                    size: buffer.length
                )
            }
        }
        blitCommandEncoder.endEncoding()
    }

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
            pipelineStateOpaque: pipelineConnector.pipelineStateOpaque,
            pipelineStateTransparent: pipelineConnector.pipelineStateTransparent,
            depthStencilStateWrite: depthStencilStateWrite,
            depthStencilStateNoWrite: depthStencilStateNoWrite,
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
