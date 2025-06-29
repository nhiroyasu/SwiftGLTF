#include <metal_stdlib>
using namespace metal;

kernel void metallic_roughness_texture_shader(constant float &metallicFactor [[buffer(0)]],
                                              constant float &roughnessFactor [[buffer(1)]],
                                              texture2d<float, access::read> metallicRoughnessTexture [[texture(0)]],
                                              texture2d<float, access::write> outputTexture [[texture(1)]],
                                              uint2 gid [[thread_position_in_grid]])
{
    // Read the metallic and roughness values from the texture
    float4 metallicRoughness = metallicRoughnessTexture.read(gid);

    float metallic = metallicRoughness.b * metallicFactor;
    float roughness = metallicRoughness.g * roughnessFactor;

    outputTexture.write(float4(0, roughness, metallic, 0.0), gid);
}
