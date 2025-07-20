#ifndef helper_h
#define helper_h

using namespace metal;

float3 importanceSampleGGX(float2 xi, float3 N, float roughness);
uint bitfieldReverse(uint x);
float2 hammersley(uint i, uint N);
float geometrySchlickGGX(float NdotV, float roughness);
float geometrySmith(float NdotV, float NdotL, float roughness);
float3 ACESFilm(float3 x);
float3 ImportanceSampleCosineWeighted(float2 Xi, float3 N);
float3 linearToSrgb(float3 color_linear);
float3 srgbToLinear(float3 color_srgb);
float4 srgbToLinear(float4 srgb);
float4 linearToSrgb(float4 rgbaLinear);
float3x3 _float3x3(float4x4 m);
float3x3 inverse(float3x3 m);
float3x3 makeNormalMatrix(float4x4 mvp);
float toolMultiplier(float value);

#endif /* helper_h */
