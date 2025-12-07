import Metal
import SwiftGLTFCore

public class RenderingContextBuilder {
    static public func new() -> RenderingContext {
        .init()
    }
}

public struct RenderingState {
    let renderPassDescriptor: MTLRenderPassDescriptor
    let drawableSize: CGSize
    let viewport: MTLViewport
    let fragmentParams: MTLBuffer
    let viewPos: SIMD3<Float>
    let cameraIndexBuffer: MTLBuffer
    let freeCameraUniformsBuffer: MTLBuffer
    let modelMatrixBuffer: MTLBuffer

    public init(renderPassDescriptor: MTLRenderPassDescriptor, drawableSize: CGSize, viewport: MTLViewport, fragmentParams: MTLBuffer, viewPos: SIMD3<Float>, cameraIndexBuffer: MTLBuffer, freeCameraUniformsBuffer: MTLBuffer, modelMatrixBuffer: MTLBuffer) {
        self.renderPassDescriptor = renderPassDescriptor
        self.drawableSize = drawableSize
        self.viewport = viewport
        self.fragmentParams = fragmentParams
        self.viewPos = viewPos
        self.cameraIndexBuffer = cameraIndexBuffer
        self.freeCameraUniformsBuffer = freeCameraUniformsBuffer
        self.modelMatrixBuffer = modelMatrixBuffer
    }
}

public struct RenderingContext {
    private var meshBundle: PBRMeshBundle? = nil
    private var envMapBundle: EnvMapBundle? = nil
    private var showsSkybox: Bool = false
    // animation
    private var animationState: RendererAnimationState? = nil
    // render
    private var renderingState: RenderingState? = nil
    // icb
    private var enableIndirectCommands = true

    public func mesh(bundle: PBRMeshBundle?) -> Self {
        var copy = self
        copy.meshBundle = bundle
        return copy
    }

    public func envMap(bundle: EnvMapBundle?) -> Self {
        var copy = self
        copy.envMapBundle = bundle
        return copy
    }

    public func skybox(_ shows: Bool) -> Self {
        var copy = self
        copy.showsSkybox = shows
        return copy
    }

    public func animation(_ state: RendererAnimationState) -> Self {
        var copy = self
        copy.animationState = state
        return copy
    }

    public func render(
        renderPassDescriptor: MTLRenderPassDescriptor,
        drawableSize: CGSize,
        viewport: MTLViewport,
        fragmentParams: MTLBuffer,
        viewPos: SIMD3<Float>,
        cameraIndexBuffer: MTLBuffer,
        freeCameraUniformsBuffer: MTLBuffer,
        modelMatrixBuffer: MTLBuffer
    ) -> Self {
        var copy = self
        copy.renderingState = RenderingState(
            renderPassDescriptor: renderPassDescriptor,
            drawableSize: drawableSize,
            viewport: viewport,
            fragmentParams: fragmentParams,
            viewPos: viewPos,
            cameraIndexBuffer: cameraIndexBuffer,
            freeCameraUniformsBuffer: freeCameraUniformsBuffer,
            modelMatrixBuffer: modelMatrixBuffer
        )
        return copy
    }

    public func indirectCommands(_ enabled: Bool) -> Self {
        var copy = self
        copy.enableIndirectCommands = enabled
        return copy
    }

    public func finalize() -> FinalizedRenderingContext {
        return FinalizedRenderingContext(
            meshBundle: meshBundle,
            envMapBundle: envMapBundle,
            showsSkybox: showsSkybox,
            animationState: animationState,
            renderingState: renderingState,
            enableIndirectCommands: enableIndirectCommands
        )
    }
}

public struct FinalizedRenderingContext {
    let meshBundle: PBRMeshBundle?
    let envMapBundle: EnvMapBundle?
    let showsSkybox: Bool
    let animationState: RendererAnimationState?
    let renderingState: RenderingState?
    let enableIndirectCommands: Bool
}
