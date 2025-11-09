#ifndef helper_h
#define helper_h

#include "../../../SwiftGLTFShaderTypes/includes/pbr.h"
using namespace metal;

float3 importanceSampleGGX(float2 xi, float3 N, float roughness);
uint bitfieldReverse(uint x);
float2 hammersley(uint i, uint N);
float geometrySchlickGGX(float NdotV, float roughness);
float geometrySmith(float NdotV, float NdotL, float roughness);
float geometrySmith(float3 N, float3 V, float3 L, float roughness);
float distributionGGX(float3 N, float3 H, float roughness);
float3 ACESFilm(float3 x);
float3 ImportanceSampleCosineWeighted(float2 Xi, float3 N);
float3 linearToSrgb(float3 color_linear);
float3 srgbToLinear(float3 color_srgb);
float4 srgbToLinear(float4 srgb);
float4 linearToSrgb(float4 rgbaLinear);
float3x3 _float3x3(float4x4 m);
float3x3 inverse(float3x3 m);
float3x3 inverse3x3(float3x3 A);
float4x4 inverse_affine(float4x4 m);
float3x3 makeNormalMatrix(float4x4 mvp);
float toolMultiplier(float value);
float3x3 make_tbn(float3 normal);
float3x3 make_tbn(float3 N, float3 T, float Tw);
float fresnelSchlick(float cosTheta, float F0);
float3 fresnelSchlick(float cosTheta, float3 F0);
float3 getDirectionForFace(uint faceIndex, float2 uv);
float luminance709(float3 linearRGB);
float luminanceFromSRGB(float3 srgbRGB);
float D_Charlie(float NoH, float alpha);
float3 sampleHalfVectorCharlie(float2 xi, float3 N, float a, thread float* outPdfH);
float3 toWorld(float3 h, float3 N);
uint wangHash(uint x);
float2 hash2(uint x, uint y, uint z, uint w);
float remapSheenRoughness(float r);
float4x4 perspectiveMatrix(NodeCameraUniforms nodeCameraUniforms, float defaultAspectRatio);
float4x4 perspectiveMatrix(float fov, float aspect, float near, float far);

#endif /* helper_h */
