#include <metal_stdlib>
using namespace metal;

struct VertexIn_Wireframe {
    float3 position [[attribute(0)]];
};

struct VertexOut_Wireframe {
    float4 position [[position]];
};

vertex VertexOut_Wireframe wireframe_vertex_shader(VertexIn_Wireframe in [[stage_in]],
                                                   constant float4x4 &model [[buffer(1)]],
                                                   constant float4x4 &view [[buffer(2)]],
                                                   constant float4x4 &projection [[buffer(3)]],
                                                   constant float4x4 &offsetMatrix [[buffer(4)]]) {
    VertexOut_Wireframe out;

    float4x4 mvpMatrix = projection * view * model;

    out.position = mvpMatrix * float4(in.position, 1.0);
    return out;
}

fragment float4 wireframe_shader(VertexOut_Wireframe in [[stage_in]]) {
    return float4(0.945, 0.552, 0.216, 1.0);
}
