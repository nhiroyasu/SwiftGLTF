#include <metal_stdlib>
#include "includes/helper.h"
#include "includes/pbr_arguments.h"
#include "includes/pbr_morph.h"

using namespace metal;

MorphApplyResult apply_morph(float3 pos,
                             float3 normal,
                             float4 tangent,
                             constant PBRVertexArguments &args,
                             constant float *weights,
                             constant MorphDispatch *dispatches,
                             uint vid) {
    uint count = min(args.morphTargetCount, (uint)8);
    MorphDispatch dispatch = dispatches[args.morphDispatchIndex];

    if (count == 0 ) {
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
        constant float *buf = nullptr;
        switch (i) {
            case 0: buf = args.morphInterleaved0; break;
            case 1: buf = args.morphInterleaved1; break;
            case 2: buf = args.morphInterleaved2; break;
            case 3: buf = args.morphInterleaved3; break;
            case 4: buf = args.morphInterleaved4; break;
            case 5: buf = args.morphInterleaved5; break;
            case 6: buf = args.morphInterleaved6; break;
            case 7: buf = args.morphInterleaved7; break;
            default: break;
        }
        if (buf == nullptr) { continue; }
        uint base = vid * 9; // 9 floats per vertex (pos3+normal3+tan3)
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
