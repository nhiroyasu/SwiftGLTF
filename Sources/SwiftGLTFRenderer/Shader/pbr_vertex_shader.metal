#include <metal_stdlib>
#include "includes/helper.h"
#include "includes/pbr_vertex.h"
#include "includes/pbr_arguments.h"
#include "includes/pbr_morph.h"
#include "includes/pbr_skin.h"
#include "../../SwiftGLTFShaderTypes/includes/pbr.h"

using namespace metal;

vertex PBRVertexOut pbr_vertex_shader(VertexIn in [[stage_in]],
                                      constant PBRVertexArguments &args [[buffer(1)]],
                                      constant MVPUniform &mvp [[buffer(2)]],
                                      constant float4x4* worldTransforms [[buffer(3)]],
                                      constant int64_t* skinJoints [[buffer(4)]],
                                      constant float4x4* skinInverseBindMatrices [[buffer(5)]],
                                      constant float* morphWeights [[buffer(6)]],
                                      constant MorphDispatch* morphDispatches [[buffer(7)]],
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
    float4x4 modelTransform = mvp.externalTransform * worldTransform * skinMatrix;
    float4x4 mvpTransform = mvp.projection * mvp.view * modelTransform;

    float3x3 normalTransform = transpose(inverse(_float3x3(modelTransform)));

    out.position = mvpTransform * float4(pos, 1.0);
    out.positionVS = (mvp.view * modelTransform * float4(pos, 1.0)).xyz;
    out.worldPosition = (modelTransform * float4(pos, 1.0)).xyz;
    out.normal = normalize(normalTransform * normal);
    out.normalVS = normalize(_float3x3(mvp.view * modelTransform) * normal);
    out.tangent = normalize(float4(normalTransform * tan.xyz, tan.w));
    out.uv = in.uv;
    out.uv1 = in.uv1;
    out.modulationColor = in.modulationColor;
    return out;
}
