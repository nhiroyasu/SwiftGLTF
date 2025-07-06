#include <metal_stdlib>
using namespace metal;

kernel void occlusion_multiplier_shader(constant float &occlusionFactor [[buffer(0)]],
                                       texture2d<float, access::read> occlusionTexture [[texture(0)]],
                                       texture2d<float, access::write> outputTexture [[texture(1)]],
                                       uint2 gid [[thread_position_in_grid]])
{
    float occlusion = occlusionTexture.read(gid).r;

    float result = 1.0 + occlusionFactor * (occlusion - 1.0);

    outputTexture.write(float4(result, 0, 0, 0), gid);
}
