#include <metal_stdlib>
using namespace metal;


kernel void emissive_multiplier_shader(constant float3 &emissiveFactor [[buffer(0)]],
                                       texture2d<float, access::read> emissiveTexture [[texture(0)]],
                                       texture2d<float, access::write> outputTexture [[texture(1)]],
                                       uint2 gid [[thread_position_in_grid]])
{
    float3 emissive = emissiveTexture.read(gid).rgb;

    float3 result = emissiveFactor * emissive;

    outputTexture.write(float4(result, 1.0), gid);
}
