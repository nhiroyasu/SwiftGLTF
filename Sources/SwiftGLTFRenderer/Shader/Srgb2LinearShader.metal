#include <metal_stdlib>
#include "headers/metal_helper.h"
using namespace metal;

kernel void srgb_2_linear_shader(constant float *srgb [[buffer(0)]],
                             device float *linear [[buffer(1)]],
                             uint id [[thread_position_in_grid]])
{
    // sRGB to Linear conversion
    float s = srgb[id];
    if (s <= 0.04045) {
        linear[id] = s / 12.92;
    } else {
        linear[id] = pow((s + 0.055) / 1.055, 2.4);
    }
}

kernel void texture_srgb_2_linear_shader(texture2d<float, access::read> srgbTexture [[texture(0)]],
                                                 texture2d<float, access::write> linearTexture [[texture(1)]],
                                                 uint2 gid [[thread_position_in_grid]])
{
    float4 srgbColor = srgbTexture.read(gid);
    float3 linearColor = srgbToLinear(srgbColor.rgb);

    linearTexture.write(float4(linearColor, srgbColor.a), gid);
}
