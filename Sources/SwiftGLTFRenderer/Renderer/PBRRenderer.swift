import Img2Cubemap
import MetalKit
import os.log
import simd
import ModelIO
import SwiftGLTFParser
import SwiftGLTFCore
import SwiftGLTFShaderTypes

public class PBRRenderer {
    private var bundle: PBRMeshBundle? = nil

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
        commandEncoder en: MTLComputeCommandEncoder,
        animationState state: RendererAnimationState
    ) {
        guard let bundle else { return }

        var localTransforms = bundle.nodeLevelHierarchy.localTransforms
        var morphWeights = bundle.originMorphWeights
        var morphDispatches = bundle.morphDispatches

        for animation in bundle.animations {
            let trs = evaluateTRS(
                type: animation.type,
                interpolation: animation.interpolation,
                keyFrameTimes: animation.keyframes,
                duration: animation.duration,
                time: state.time,
                looping: state.isLooping
            )
            let weights = evaluateWeights(
                type: animation.type,
                interpolation: animation.interpolation,
                keyFrameTimes: animation.keyframes,
                duration: animation.duration,
                time: state.time,
                looping: state.isLooping
            )

            let target = animation.targetNode

            localTransforms[target] = trs.apply(localTransforms[target])

            let dispatch = morphDispatches[target]
            if dispatch.length == 0 {
                morphWeights.insert(contentsOf: weights, at: Int(dispatch.offset))
                morphDispatches[target] = MorphDispatch(
                    offset: dispatch.offset,
                    length: Int64(weights.count)
                )
            } else {
                morphWeights.replaceSubrange(Int(dispatch.offset)..<Int(dispatch.offset + dispatch.length), with: weights)
            }
        }

        let nlh = bundle.nodeLevelHierarchy.copy(localTransforms: localTransforms)
        do {
            try shaderConnection.computeWorldMatrices(
                nodeLevelHierarchy: nlh,
                out: bundle.worldTransformBuffer,
                commandEncoder: en
            )
        } catch {
            os_log("Failed to compute world matrices: %@", type: .error, String(describing: error))
            return
        }

        bundle.morphWeightsBuffer.contents().copyMemory(
            from: &morphWeights,
            byteCount: MemoryLayout<Float>.size * morphWeights.count
        )
        bundle.morphDispatchesBuffer.contents().copyMemory(
            from: &morphDispatches,
            byteCount: MemoryLayout<MorphDispatch>.size * morphDispatches.count
        )
    }

    public func render(
        using renderEncoder: MTLRenderCommandEncoder,
        mvpUniformBuffer: MTLBuffer,
        fragmentParams: MTLBuffer,
        skyboxVP: MTLBuffer,
        viewPos: SIMD3<Float>
    ) {
        guard let bundle else {
            os_log("No mesh loaded", type: .error)
            return
        }

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
            vertexResources: bundle.vertexResources,
            fragmentResources: bundle.fragmentResources + [envMapHeap],
            meshes: bundle.meshes,
            worldTransformBuffer: bundle.worldTransformBuffer,
            jointsBuffer: bundle.jointsBuffer,
            inverseBindMatricesBuffer: bundle.inverseBindMatricesBuffer,
            morphWeightsBuffer: bundle.morphWeightsBuffer,
            morphDispatchesBuffer: bundle.morphDispatchesBuffer,
            envMapArgBuffer: envMapArgBuffer,
            fragmentParams: fragmentParams,
            mvpUniformBuffer: mvpUniformBuffer,
            viewPos: viewPos
        )
    }

    // MARK: - Update states

    /// Load a gltf asset
    public func load(from asset: MDLAsset) async throws {
        self.bundle = try await meshLoader.loadMeshes(from: asset)
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
