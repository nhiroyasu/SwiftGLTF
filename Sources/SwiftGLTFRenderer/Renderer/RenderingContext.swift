import Metal
import SwiftGLTFCore
import SwiftGLTFShaderTypes

public class RenderingContextBuilder {
    static public func new() -> RenderingContext {
        .init()
    }
}

public struct RenderingContext {
    // resources
    private var meshBundle: PBRMeshBundle? = nil
    private var envMapBundle: EnvMapBundle? = nil

    // uniforms
    private var modelMatrix: float4x4 = matrix_identity_float4x4
    private var lightPosition: simd_float3 = simd_float3(0, 0, 0)
    private var ambientLightColor: simd_float3 = simd_float3(0, 0 ,0)
    private var cameraIndex: Int = -1
    private var freeCameraUniforms: FreeCameraUniforms = .build(
        eye: simd_float3(0, 0, -5),
        target: simd_float3(0, 0, 0),
        upSign: 1.0,
        aspect: 1.0,
        fovY: .pi / 3
    )

     // animation
    private var animationState: RendererAnimationState? = nil

    // render
    private var renderingState: RenderingState? = nil
    private var viewportSize: simd_float2 = simd_float2(1, 1)
    private var showsSkybox: Bool = false
    private var enableIndirectCommands = true

    public func modelMatrix(_ matrix: float4x4) -> Self {
        var copy = self
        copy.modelMatrix = matrix
        return copy
    }

    public func lightPosition(_ position: simd_float3) -> Self {
        var copy = self
        copy.lightPosition = position
        return copy
    }

    public func ambientLightColor(_ color: simd_float3) -> Self {
        var copy = self
        copy.ambientLightColor = color
        return copy
    }

    public func cameraIndex(_ index: Int) -> Self {
        var copy = self
        copy.cameraIndex = index
        return copy
    }

    public func freeCameraUniforms(_ uniforms: FreeCameraUniforms) -> Self {
        var copy = self
        copy.freeCameraUniforms = uniforms
        return copy
    }

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
        viewport: MTLViewport
    ) -> Self {
        var copy = self
        copy.renderingState = RenderingState(
            renderPassDescriptor: renderPassDescriptor,
            drawableSize: drawableSize,
            viewport: viewport
        )
        copy.viewportSize = simd_float2(Float(viewport.width), Float(viewport.height))
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
            modelMatrix: modelMatrix,
            sceneUniforms: SceneUniforms(
                lightPosition: lightPosition,
                ambientLightColor: ambientLightColor,
                viewportSize: viewportSize
            ),
            cameraIndex: cameraIndex,
            freeCameraUniforms: freeCameraUniforms,
            animationState: animationState,
            renderingState: renderingState,
            showsSkybox: showsSkybox,
            enableIndirectCommands: enableIndirectCommands
        )
    }
}

public struct RenderingState {
    let renderPassDescriptor: MTLRenderPassDescriptor
    let drawableSize: CGSize
    let viewport: MTLViewport
}

public struct FinalizedRenderingContext {
    let meshBundle: PBRMeshBundle?
    let envMapBundle: EnvMapBundle?
    let modelMatrix: float4x4
    let sceneUniforms: SceneUniforms
    let cameraIndex: Int
    let freeCameraUniforms: FreeCameraUniforms
    let animationState: RendererAnimationState?
    let renderingState: RenderingState?
    let showsSkybox: Bool
    let enableIndirectCommands: Bool
}
