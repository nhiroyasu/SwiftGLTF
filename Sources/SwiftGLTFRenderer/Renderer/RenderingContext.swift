import Metal
import SwiftGLTFCore
import SwiftGLTFParser
import SwiftGLTFShaderTypes

public class RenderingContextBuilder {
    static public func new() -> RenderingContext {
        .init()
    }
}

public struct RenderingContext {
    // resources
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
    private var vrmHumanoidRotations: [VRMHumanoidBoneName: SIMD3<Float>] = [:]
    private var vrmExpressionWeights: [VRMExpressionKey: Float] = [:]

    // render
    private var renderingState: RenderingState? = nil
    private var viewportSize: simd_float2 = simd_float2(1, 1)
    private var showsSkybox: Bool = false

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

    public func vrmHumanoidRotations(_ rotations: [VRMHumanoidBoneName: SIMD3<Float>]) -> Self {
        var copy = self
        copy.vrmHumanoidRotations = rotations
        return copy
    }

    public func vrmExpressions(_ weights: [VRMExpressionKey: Float]) -> Self {
        var copy = self
        copy.vrmExpressionWeights = weights
        return copy
    }

    public func finalizeWithICB(
        state: PBRIndirectRenderState,
        renderPassDescriptor: MTLRenderPassDescriptor,
        drawableSize: CGSize,
        viewport: MTLViewport
    ) -> FinalizedRenderingContext {
        let renderingState = RenderingState(
            renderPassDescriptor: renderPassDescriptor,
            drawableSize: drawableSize,
            viewport: viewport
        )
        let viewportSize = simd_float2(Float(viewport.width), Float(viewport.height))

        return FinalizedRenderingContext.icb(
            indirectRenderState: state,
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
            vrmHumanoidRotations: vrmHumanoidRotations,
            vrmExpressionWeights: vrmExpressionWeights,
            renderingState: renderingState,
            showsSkybox: showsSkybox
        )
    }
}

public struct RenderingState {
    let renderPassDescriptor: MTLRenderPassDescriptor
    let drawableSize: CGSize
    let viewport: MTLViewport
}

public enum FinalizedRenderingContext {
    case icb(
        indirectRenderState: PBRIndirectRenderState,
        envMapBundle: EnvMapBundle?,
        modelMatrix: float4x4,
        sceneUniforms: SceneUniforms,
        cameraIndex: Int,
        freeCameraUniforms: FreeCameraUniforms,
        animationState: RendererAnimationState?,
        vrmHumanoidRotations: [VRMHumanoidBoneName: SIMD3<Float>],
        vrmExpressionWeights: [VRMExpressionKey: Float],
        renderingState: RenderingState,
        showsSkybox: Bool
    )
}
