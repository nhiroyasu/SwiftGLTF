#ifndef pbr_lighting_h
#define pbr_lighting_h

float3 compute_direct_lighting(float3 normal,
                               float3 worldPosition,
                               float3 albedo,
                               float metallic,
                               float roughness,
                               float transmission,
                               float3 viewPosition,
                               float3 lightPosition,
                               float3 ambientLightColor,
                               float ior);

float3 compute_indirect_lighting(float3 normal,
                                 float3 worldPosition,
                                 float3 viewPosition,
                                 float3 albedo,
                                 float metallic,
                                 float roughness,
                                 float ambientOcclusion,
                                 float transmission,
                                 texturecube<float, access::sample> prefilterEnvMap,
                                 texturecube<float, access::sample> irradianceCubeMap,
                                 texture2d<float, access::sample> brdfLUT,
                                 float ior);

float3 compute_transmission_lighting(float3 Lbg,
                                     float3 normal,
                                     float3 albedo,
                                     float metallic,
                                     float transmission,
                                     float3 attenuation,
                                     float3 worldPosition,
                                     float3 viewPosition,
                                     float ior);

#endif /* pbr_lighting_h */
