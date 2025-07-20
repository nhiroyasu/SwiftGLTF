#include <metal_stdlib>
#include "../../SwiftGLTFShaderTypes/includes/metal_helper.h"

using namespace metal;

float3 importanceSampleGGX(float2 xi, float3 N, float roughness) {
    float a = roughness * roughness;
    float phi = 2.0 * M_PI_F * xi.x;
    float cosTheta = sqrt((1.0 - xi.y) / (1.0 + (a * a - 1.0) * xi.y));
    float sinTheta = sqrt(1.0 - cosTheta * cosTheta);

    float3 H = float3(sinTheta * cos(phi), sinTheta * sin(phi), cosTheta);
    return normalize(H);
}

uint bitfieldReverse(uint x) {
    x = (x >> 1) & 0x55555555 | (x & 0x55555555) << 1;
    x = (x >> 2) & 0x33333333 | (x & 0x33333333) << 2;
    x = (x >> 4) & 0x0F0F0F0F | (x & 0x0F0F0F0F) << 4;
    x = (x >> 8) & 0x00FF00FF | (x & 0x00FF00FF) << 8;
    x = (x >> 16) & 0x0000FFFF | (x & 0x0000FFFF) << 16;
    return x;
}

float2 hammersley(uint i, uint N) {
    float u = float(i) / float(N);
    float v = float(bitfieldReverse(i)) * 2.3283064365386963e-10;
    return float2(u, v);
}

float geometrySchlickGGX(float NdotV, float roughness)
{
    float k = (roughness + 1.0) * (roughness + 1.0) / 8.0;
    return NdotV / (NdotV * (1.0 - k) + k);
}

float geometrySmith(float NdotV, float NdotL, float roughness)
{
    return geometrySchlickGGX(NdotV, roughness) * geometrySchlickGGX(NdotL, roughness);
}

float3 ACESFilm(float3 x) {
    float a = 2.51;
    float b = 0.03;
    float c = 2.43;
    float d = 0.59;
    float e = 0.14;
    return saturate((x*(a*x + b))/(x*(c*x + d) + e));
}

float3 ImportanceSampleCosineWeighted(float2 Xi, float3 N)
{
    float phi = 2 * M_PI_F * Xi.x;
    float cosTheta = sqrt(1 - Xi.y);
    float sinTheta = sqrt(1 - cosTheta * cosTheta);

    float3 H = float3(sinTheta * cos(phi), cosTheta, sinTheta * sin(phi));

    float3 X = abs(N.x) < 0.999 ? float3(1, 0, 0) : float3(0, -1, 0);
    float3 zTangent = normalize( cross(X, N) );
    float3 xTangent = cross ( N, zTangent );
    // Tangent to world space
    return normalize(xTangent * H.x + N * H.y + zTangent * H.z);
}

float3 linearToSrgb(float3 rgbLinear)
{
    constexpr float  kGammaCutoff = 0.0031308;
    constexpr float  kGamma       = 1.0 / 2.4;
    constexpr float  kA           = 0.055;
    constexpr float  kScale       = 12.92;

    float3 lo = rgbLinear * kScale;
    float3 hi = (1.0 + kA) * pow(rgbLinear, float3(kGamma)) - kA;

    return select(hi, lo, rgbLinear <= kGammaCutoff);
}

float3 srgbToLinear(float3 srgb)
{
    constexpr float  kInvGammaCutoff = 0.04045;
    constexpr float  kLinearScale    = 1.0 / 12.92;
    constexpr float  kA              = 0.055;
    constexpr float  kInv1PlusA      = 1.0 / (1.0 + kA);
    constexpr float  kGamma          = 2.4;

    // ベクタ演算に合わせて両方計算し、条件で select
    float3 lo  = srgb * kLinearScale;
    float3 hi  = pow( (srgb + kA) * kInv1PlusA, float3(kGamma) );

    return select(hi, lo, srgb <= kInvGammaCutoff);
}

float4 srgbToLinear(float4 srgb)
{
    return float4(srgbToLinear(srgb.rgb), srgb.a);
}
float4 linearToSrgb(float4 rgbaLinear)
{
    return float4(linearToSrgb(rgbaLinear.rgb), rgbaLinear.a);
}

metal::float3x3 _float3x3(float4x4 m) {
    return metal::float3x3(
        m[0].xyz,
        m[1].xyz,
        m[2].xyz
    );
}

float3x3 inverse(float3x3 m) {
    float a00 = m[0][0], a01 = m[0][1], a02 = m[0][2];
    float a10 = m[1][0], a11 = m[1][1], a12 = m[1][2];
    float a20 = m[2][0], a21 = m[2][1], a22 = m[2][2];

    float det = determinant(m);
    if (abs(det) < 1e-6) return float3x3(1.0); // fallback identity

    float invDet = 1.0 / det;

    float3x3 inv;

    inv[0][0] =  (a11 * a22 - a12 * a21) * invDet;
    inv[0][1] = -(a01 * a22 - a02 * a21) * invDet;
    inv[0][2] =  (a01 * a12 - a02 * a11) * invDet;

    inv[1][0] = -(a10 * a22 - a12 * a20) * invDet;
    inv[1][1] =  (a00 * a22 - a02 * a20) * invDet;
    inv[1][2] = -(a00 * a12 - a02 * a10) * invDet;

    inv[2][0] =  (a10 * a21 - a11 * a20) * invDet;
    inv[2][1] = -(a00 * a21 - a01 * a20) * invDet;
    inv[2][2] =  (a00 * a11 - a01 * a10) * invDet;

    return inv;
}

float3x3 makeNormalMatrix(float4x4 mvp) {
    return inverse(transpose(_float3x3(mvp)));
}

float toolMultiplier(float value) {
    const float t1 = 0.6;
    const float t2 = 0.3;

    float shadeColor;
    if (value > t1) {
        shadeColor = 1;
    } else if (value > t2) {
        shadeColor = 0.6;
    } else {
        shadeColor = 0.3;
    }
    return shadeColor;
}
