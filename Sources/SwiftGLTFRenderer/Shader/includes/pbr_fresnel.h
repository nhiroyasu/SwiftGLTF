#ifndef pbr_fresnel_h
#define pbr_fresnel_h

float3 compute_f0_dielectric_rgb(float ior,
                                 float specularFactor,
                                 float3 specularColor);

float3 compute_f0_rgb(float ior,
                      float specularFactor,
                      float3 specularColor,
                      float3 albedo,
                      float metallic);


#endif /* pbr_fresnel_h */
