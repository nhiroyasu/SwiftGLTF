#include <metal_stdlib>
using namespace metal;

struct VSOut {
    float4 position [[position]];
    float2 uv;
};

vertex VSOut fullscreen_vertex(uint vid [[vertex_id]]) {
    float2 pos[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    VSOut out;
    out.position = float4(pos[vid], 0.0, 1.0);
    // Flip Y to account for render target vs texture coordinate origin
    float2 uv = 0.5 * (out.position.xy + 1.0);
    uv.y = 1.0 - uv.y;
    out.uv = uv;
    return out;
}

fragment float4 compose_fragment(VSOut in [[stage_in]],
                                 texture2d<float> baseTex [[texture(0)]],
                                 constant uint &useTransTex [[buffer(0)]],
                                 texture2d<float> transTex [[texture(1)]]) {
    constexpr sampler s(mag_filter::linear, min_filter::linear, s_address::clamp_to_edge, t_address::clamp_to_edge);
    float2 uv = clamp(in.uv, float2(0.0), float2(1.0));
    float4 base = baseTex.sample(s, uv);
    float4 trans = useTransTex ? transTex.sample(s, uv) : float4(0,0,0,0);
    float3 rgb = base.rgb * (1.0 - trans.a) + trans.rgb;
    return float4(rgb, 1);
}
