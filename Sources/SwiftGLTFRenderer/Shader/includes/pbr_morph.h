#ifndef pbr_morph_h
#define pbr_morph_h

#include "pbr_arguments.h"

struct MorphApplyResult {
    float3 pos;
    float3 normal;
    float4 tangent;
};

MorphApplyResult apply_morph(float3 pos,
                             float3 normal,
                             float4 tangent,
                             constant PBRVertexArguments &args,
                             constant float *weights,
                             constant MorphDispatch *dispatches,
                             uint vid);

#endif /* pbr_morph_h */
