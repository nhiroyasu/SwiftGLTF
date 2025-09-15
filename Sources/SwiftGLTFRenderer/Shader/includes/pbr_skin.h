#ifndef pbr_skin_h
#define pbr_skin_h

#include "../../../SwiftGLTFShaderTypes/includes/pbr.h"

float4x4 compute_skin_matrix(constant float4x4 *worldTransforms,
                             constant int64_t *skins,
                             constant float4x4 *skinInverseBindMatrices,
                             float4x4 inverseGlobalTransform,
                             SkinDispatch sd,
                             ushort4 joints,
                             float4 weights);

#endif /* pbr_skin_h */
