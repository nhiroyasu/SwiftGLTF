#include <metal_stdlib>
using namespace metal;

kernel void base_color_multiplier_shader(constant float4 &baseColorFactor [[buffer(0)]],
                                         texture2d<float, access::read> baseColorTexture [[texture(0)]],
                                         texture2d<float, access::write> outputTexture [[texture(1)]],
                                         uint2 gid [[thread_position_in_grid]])
{
    float4 baseColor = baseColorTexture.read(gid);
    
    float4 result = baseColor * baseColorFactor;
    
    outputTexture.write(result, gid);
}
