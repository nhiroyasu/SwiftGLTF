#include <metal_stdlib>
#include "includes/helper.h"
#include "../../SwiftGLTFShaderTypes/includes/pbr.h"

using namespace metal;

kernel void computeWorldMatrices(
    constant LevelDispatch&              lvl                    [[ buffer(0) ]],
    const device int64_t*                levelNodes             [[ buffer(1) ]],
    const device int64_t*                parentIndex            [[ buffer(2) ]],
    const device float4x4*               localTransform         [[ buffer(3) ]],
    device float4x4*                     worldTransform         [[ buffer(4) ]],
    uint tid [[thread_position_in_grid]]
) {
    if (tid >= lvl.count) return;
    int64_t node = levelNodes[lvl.start + tid];
    int parent = parentIndex[node];

    float4x4 local = localTransform[node];
    if (parent < 0) {
        worldTransform[node] = local;
    } else {
        worldTransform[node] = worldTransform[parent] * local;
    }
}
