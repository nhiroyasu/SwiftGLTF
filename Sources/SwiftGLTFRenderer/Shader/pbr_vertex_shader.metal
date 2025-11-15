#include <metal_stdlib>
#include "includes/helper.h"
#include "includes/pbr_vertex.h"
#include "includes/pbr_arguments.h"
#include "includes/pbr_morph.h"
#include "includes/pbr_skin.h"
#include "../../SwiftGLTFShaderTypes/includes/pbr.h"

using namespace metal;

vertex PBRVertexOut pbr_vertex_shader(VertexIn in [[stage_in]],
                                      constant PBRVertexArguments &args [[buffer(PBRVertexShaderArgsBuffer)]],
                                      constant float4x4* worldTransforms [[buffer(PBRVertexShaderWorldTransformsBuffer)]],
                                      constant int64_t* skinJoints [[buffer(PBRVertexShaderSkinJointsBuffer)]],
                                      constant float4x4* skinInverseBindMatrices [[buffer(PBRVertexShaderSkinInverseBindMatricesBuffer)]],
                                      constant float* morphWeights [[buffer(PBRVertexShaderMorphWeightsBuffer)]],
                                      constant MorphDispatch* morphDispatches [[buffer(PBRVertexShaderMorphDispatchesBuffer)]],
                                      constant int64_t &cameraIndex [[buffer(PBRVertexShaderCameraIndexBuffer)]],
                                      constant FreeCameraUniforms &freeCameraUniforms [[buffer(PBRVertexShaderFreeCameraUniformsBuffer)]],
                                      constant NodeCameraUniforms* nodeCameraUniforms [[buffer(PBRVertexShaderNodeCameraUniformsBuffer)]],
                                      constant float4x4 &rootModelMatrix [[buffer(PBRVertexShaderModelMatrixBuffer)]],
                                      uint vid [[vertex_id]])
{
    PBRVertexOut out;

    // Apply morph targets in model space before skinning
    float3 pos = in.position;
    float3 normal = in.normal;
    float4 tan = in.tangent;
    MorphApplyResult morphed = apply_morph(pos, normal, tan, args, morphWeights, morphDispatches, vid);
    pos = morphed.pos;
    normal = morphed.normal;
    tan = morphed.tangent;

    float4x4 worldTransform = worldTransforms[args.transformIndex];
    float4x4 inverseWorldTransform = inverse_affine(worldTransform);
    float4x4 skinMatrix = args.skinDispatch.offset != -1
    ? compute_skin_matrix(worldTransforms, skinJoints, skinInverseBindMatrices, inverseWorldTransform, args.skinDispatch, in.joints, in.weights)
    : float4x4(1.0);

    // TODO: cameraIndex may exceed the count of nodeCameraUniforms(fragment and skybox too)
    float4x4 view = cameraIndex >= 0
    ? inverse_affine(worldTransforms[nodeCameraUniforms[cameraIndex].nodeHierarchyOffset])
    : freeCameraUniforms.viewMatrix;
    float4x4 projection = cameraIndex >= 0
    ? projectionMatrix(nodeCameraUniforms[cameraIndex], freeCameraUniforms.aspectRatio)
    : freeCameraUniforms.projectionMatrix;
    float4x4 modelTransform = rootModelMatrix * worldTransform * skinMatrix;
    float4x4 mvpTransform = projection * view * modelTransform;

    float3x3 normalTransform = transpose(inverse(_float3x3(modelTransform)));

    out.position = mvpTransform * float4(pos, 1.0);
    out.positionVS = (view * modelTransform * float4(pos, 1.0)).xyz;
    out.worldPosition = (modelTransform * float4(pos, 1.0)).xyz;
    out.normal = normalize(normalTransform * normal);
    out.normalVS = normalize(_float3x3(view * modelTransform) * normal);
    out.tangent = normalize(float4(normalTransform * tan.xyz, tan.w));
    out.uv = in.uv;
    out.uv1 = in.uv1;
    out.modulationColor = in.modulationColor;
    return out;
}
