#include <metal_stdlib>
using namespace metal;

float3 compute_f0_dielectric_rgb(float ior,
                                 float specularFactor,
                                 float3 specularColor) {
    float f0_dielectric = pow((ior - 1.0) / (ior + 1.0), 2.0);
    float3 F0_diel_rgb = float3(f0_dielectric) * specularFactor * specularColor;
    return clamp(F0_diel_rgb, float3(0.0), float3(0.99));
}

float3 compute_f0_rgb(float ior,
                      float specularFactor,
                      float3 specularColor,
                      float3 albedo,
                      float metallic) {
    float3 F0_diel_rgb = compute_f0_dielectric_rgb(ior, specularFactor, specularColor);
    return mix(F0_diel_rgb, albedo, metallic);
}
