#include <metal_stdlib>
#include "includes/helper.h"
#include "includes/pbr_skin.h"

using namespace metal;

float4x4 compute_skin_matrix(constant float4x4 *worldTransforms,
                             constant int64_t *skins,
                             constant float4x4 *skinInverseBindMatrices,
                             float4x4 inverseGlobalTransform,
                             SkinDispatch sd,
                             ushort4 joints,
                             float4 weights) {
    int64_t jointOffsetX = sd.offset + joints.x;
    int64_t jointOffsetY = sd.offset + joints.y;
    int64_t jointOffsetZ = sd.offset + joints.z;
    int64_t jointOffsetW = sd.offset + joints.w;
    int64_t nodeIndexX = skins[jointOffsetX];
    int64_t nodeIndexY = skins[jointOffsetY];
    int64_t nodeIndexZ = skins[jointOffsetZ];
    int64_t nodeIndexW = skins[jointOffsetW];
    float4x4 globalJointMatrixX = worldTransforms[nodeIndexX];
    float4x4 globalJointMatrixY = worldTransforms[nodeIndexY];
    float4x4 globalJointMatrixZ = worldTransforms[nodeIndexZ];
    float4x4 globalJointMatrixW = worldTransforms[nodeIndexW];
    float4x4 inverseBindMatrixX = skinInverseBindMatrices[jointOffsetX];
    float4x4 inverseBindMatrixY = skinInverseBindMatrices[jointOffsetY];
    float4x4 inverseBindMatrixZ = skinInverseBindMatrices[jointOffsetZ];
    float4x4 inverseBindMatrixW = skinInverseBindMatrices[jointOffsetW];

    float4x4 skinMatrix =
    weights.x * inverseGlobalTransform * globalJointMatrixX * inverseBindMatrixX +
    weights.y * inverseGlobalTransform * globalJointMatrixY * inverseBindMatrixY +
    weights.z * inverseGlobalTransform * globalJointMatrixZ * inverseBindMatrixZ +
    weights.w * inverseGlobalTransform * globalJointMatrixW * inverseBindMatrixW;
    return skinMatrix;
}
