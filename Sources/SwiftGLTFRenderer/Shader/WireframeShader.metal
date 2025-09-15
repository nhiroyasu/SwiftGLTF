#include <metal_stdlib>
#include "../../SwiftGLTFShaderTypes/includes/pbr.h"
using namespace metal;

struct VertexIn_Wireframe {
    float3 position [[attribute(0)]];
};

struct VertexOut_Wireframe {
    float4 position [[position]];
};

struct WireframeVertexArguments {
    constant float4x4 &model [[id(0)]];
};

vertex VertexOut_Wireframe wireframe_vertex_shader(VertexIn_Wireframe in [[stage_in]],
                                                   constant MVPUniform &mvp [[buffer(1)]],
                                                   constant float4x4* worldTransforms [[buffer(2)]],
                                                   constant int64_t &transformIndex [[buffer(3)]])
{
    VertexOut_Wireframe out;

    float4x4 mvpMatrix = mvp.projection * mvp.view * worldTransforms[transformIndex];

    out.position = mvpMatrix * float4(in.position, 1.0);
    return out;
}

fragment float4 wireframe_fragment_shader(VertexOut_Wireframe in [[stage_in]]) {
    return float4(0.945, 0.552, 0.216, 1.0);
}
