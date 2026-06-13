#include <metal_stdlib>
#include "includes/helper.h"
#include "includes/pbr_arguments.h"
#include "includes/pbr_morph.h"
#include "../../SwiftGLTFShaderTypes/includes/pbr_vertex_argument_buffer.h"

using namespace metal;

MorphApplyResult apply_morph(float3 pos,
                             float3 normal,
                             float4 tangent,
                             constant PBRVertexArguments &args,
                             constant float *weights,
                             constant MorphDispatch *dispatches,
                             uint vid) {
    uint count = args.morphTargetCount;
    MorphDispatch dispatch = dispatches[args.morphDispatchIndex];

    if (count == 0 || args.morphVertexCount == 0 || args.morphInterleaved == nullptr) {
        return { pos, normal, tangent };
    }

    for (uint i = 0; i < count; ++i) {
        float w;
        if (dispatch.length == 0) {
            w = args.morphDefaultWeights[i];
        } else {
            w = weights[dispatch.offset + i];
        }
        if (w == 0.0) { continue; }
        constant float *buf = args.morphInterleaved;
        uint base = (i * args.morphVertexCount + vid) * 9; // 9 floats per vertex (pos3+normal3+tan3)
        float3 dpos = float3(buf[base + 0], buf[base + 1], buf[base + 2]);
        float3 dnormal = float3(buf[base + 3], buf[base + 4], buf[base + 5]);
        float3 dtan = float3(buf[base + 6], buf[base + 7], buf[base + 8]);
        pos += dpos * w;
        normal += dnormal * w;
        tangent.xyz += dtan * w;
    }
    normal = normalize(normal);
    tangent = float4(normalize(tangent.xyz), tangent.w); // keep sign in w
    return { pos, normal, tangent };
}
