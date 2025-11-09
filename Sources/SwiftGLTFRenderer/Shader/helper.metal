#include <metal_stdlib>
#include "includes/helper.h"
#include "../../SwiftGLTFShaderTypes/includes/pbr.h"

using namespace metal;

float3 importanceSampleGGX(float2 xi, float3 N, float roughness) {
    float a = roughness * roughness;
    float phi = 2.0 * M_PI_F * xi.x;
    float cosTheta = sqrt((1.0 - xi.y) / (1.0 + (a * a - 1.0) * xi.y));
    float sinTheta = sqrt(1.0 - cosTheta * cosTheta);

    float3 H = float3(sinTheta * cos(phi), sinTheta * sin(phi), cosTheta);

    float3 up = abs(N.z) < 0.999 ? float3(0, 0, 1) : float3(1, 0, 0);
    float3 T = normalize(cross(up, N));
    float3 B = cross(N, T);
    return normalize(T * H.x + B * H.y + N * H.z);
}

float3 ImportanceSampleCosineWeighted(float2 xi, float3 N)
{
    float phi = 2 * M_PI_F * xi.x;
    float cosTheta = sqrt(1 - xi.y);
    float sinTheta = sqrt(1 - cosTheta * cosTheta);

    float3 H = float3(sinTheta * cos(phi), sinTheta * sin(phi), cosTheta);

    float3 up = abs(N.z) < 0.999 ? float3(0, 0, 1) : float3(1, 0, 0);
    float3 T = normalize(cross(up, N));
    float3 B = cross(N, T);
    return normalize(T * H.x + B * H.y + N * H.z);
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

float geometrySmith(float3 N, float3 V, float3 L, float roughness)
{
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    return geometrySmith(NdotV, NdotL, roughness);
}

float distributionGGX(float3 N, float3 H, float roughness) {
    float NdotH = max(dot(N, H), 0.0);
    float alpha = roughness * roughness;
    float alpha2 = alpha * alpha;
    float denom = NdotH * NdotH * (alpha2 - 1.0) + 1.0;
    return alpha2 / (M_PI_F * denom * denom + 1e-4);
}

float3 ACESFilm(float3 x) {
    float a = 2.51;
    float b = 0.03;
    float c = 2.43;
    float d = 0.59;
    float e = 0.14;
    return saturate((x*(a*x + b))/(x*(c*x + d) + e));
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

float3x3 inverse3x3(float3x3 A)
{
    // 列ベクトルを a,b,c とする。adj(A) の列は cross(b,c), cross(c,a), cross(a,b)
    float3 a = A[0], b = A[1], c = A[2];
    float3 r0 = cross(b, c);
    float3 r1 = cross(c, a);
    float3 r2 = cross(a, b);

    float det = dot(a, r0);
    // ほぼ特異な場合のガード（用途に応じて閾値調整）
    float invDet = 1.0 / max(fabs(det), 1e-8);

    // 逆行列 = adj(A) / det
    return float3x3(r0, r1, r2) * invDet;
}

float4x4 inverse_affine(float4x4 m)
{
    float3x3 A  = float3x3(m[0].xyz, m[1].xyz, m[2].xyz);
    float3   t  = m[3].xyz;
    float3x3 Ai = inverse(A);
    float3   ti = -(Ai * t);

    return float4x4(
        float4(Ai[0], 0.0),
        float4(Ai[1], 0.0),
        float4(Ai[2], 0.0),
        float4(ti,    1.0)
    );
}

float3x3 makeNormalMatrix(float4x4 mvp) {
    return inverse(transpose(_float3x3(mvp)));
}

float swapToonShading(float value) {
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

float3x3 make_tbn(float3 normal) {
    // Construct a TBN matrix assuming the normal is Z and use a fixed tangent space
    float3 up = abs(normal.z) < 0.999 ? float3(0, 0, 1) : float3(1, 0, 0);
    float3 tangent = normalize(cross(up, normal));
    float3 bitangent = cross(normal, tangent);
    return float3x3(tangent, bitangent, normal);
}

float3x3 make_tbn(float3 N, float3 T, float Tw) {
    float3 B = cross(N, T) * Tw;
    return float3x3(T, B, N);
}

float fresnelSchlick(float cosTheta, float F0) {
    return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

float3 fresnelSchlick(float cosTheta, float3 F0) {
    return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

float3 getDirectionForFace(uint faceIndex, float2 uv) {
    switch (faceIndex) {
        case 0: return normalize(float3(1.0, -uv.y, -uv.x)); // +X
        case 1: return normalize(float3(-1.0, -uv.y, uv.x)); // -X
        case 2: return normalize(float3(uv.x, 1.0, uv.y));    // +Y
        case 3: return normalize(float3(uv.x, -1.0, -uv.y));  // -Y
        case 4: return normalize(float3(uv.x, -uv.y, 1.0));   // +Z
        case 5: return normalize(float3(-uv.x, -uv.y, -1.0)); // -Z
        default: return float3(0.0);
    }
}

// --- Luminance (Rec.709 / sRGB primaries, linear RGB 入力) ---
float luminance709(float3 linearRGB)
{
    // Rec.709 (=sRGB) の相対輝度係数
    return dot(linearRGB, float3(0.2126f, 0.7152f, 0.0722f));
}

// --- sRGBテクスチャから直接 輝度 ---
float luminanceFromSRGB(float3 srgbRGB)
{
    return luminance709(srgbToLinear(srgbRGB));
}

float D_Charlie(float NoH, float alpha)
{
    alpha = clamp(alpha, 1e-6, 1.0);
    float invA = 1.0 / alpha;
    float c    = max(NoH, 1e-5);
    // ((2 + 1/alpha) / (2π)) * (cosθ)^(1/alpha)
    return ((2.0 + invA) * pow(c, invA)) * (0.5f / M_PI_F);
}

float3 sampleHalfVectorCharlie(float2 xi, float3 N, float a, thread float* outPdfH)
{
    a = clamp(a, 1e-6, 1.0);
    float invA  = 1.0 / a;
    float phi   = 2.0f * M_PI_F * xi.x;
    // cosθ = (1 - u.y)^(1/(2 + 1/α))
    float cosT  = pow(1.0f - xi.y, 1.0f / (2.0f + invA));
    float sinT  = sqrt(1.0f - cosT * cosT);
    float3 Ht   = float3(cos(phi)*sinT, sin(phi)*sinT, cosT);
    float3 H    = toWorld(Ht, N);

    float NoH = max(dot(N, H), 1e-6f);
    if (outPdfH) *outPdfH = D_Charlie(NoH, a) * cosT;
    return H;
}

float3 toWorld(float3 h, float3 N)
{
    float3 up = (abs(N.z) < 0.999) ? float3(0,0,1) : float3(1,0,0);
    float3 T  = normalize(cross(up, N));
    float3 B  = cross(N, T);
    return normalize(T*h.x + B*h.y + N*h.z);
}

uint wangHash(uint x) {
    x = (x ^ 61u) ^ (x >> 16);
    x *= 9u;
    x = x ^ (x >> 4);
    x *= 0x27d4eb2du;
    x = x ^ (x >> 15);
    return x;
}

float2 hash2(uint x, uint y, uint z, uint w) {
    // 4つの入力を XOR でミックス
    uint seed1 = wangHash(x ^ (y * 374761393u) ^ (z * 668265263u) ^ (w * 982451653u));
    uint seed2 = wangHash(y ^ (z * 362437u)    ^ (w * 521288629u) ^ (x * 88675123u));

    // 0..1 に正規化 (0xFFFFFFFF = 4294967295)
    float2 jitter = float2(seed1, seed2) * (1.0f / 4294967295.0f);
    return jitter;
}

// Remap sheen roughness to avoid too sharp highlights
float remapSheenRoughness(float r) {
    // ensure at least 0.07
    return clamp(0.5*r + 0.5*r*r, 0.07, 1.0);
}

float4x4 perspectiveMatrix(NodeCameraUniforms nodeCameraUniforms, float defaultAspectRatio) {
    float aspectRatio = nodeCameraUniforms.aspectRatio > 0
        ? nodeCameraUniforms.aspectRatio
        : defaultAspectRatio;
    return perspectiveMatrix(nodeCameraUniforms.fov.y,
                             aspectRatio,
                             nodeCameraUniforms.znear,
                             nodeCameraUniforms.zfar);
}

float4x4 perspectiveMatrix(float fov, float aspect, float near, float far) {
    float f = 1.0 / tan(fov / 2.0);
    return float4x4(float4(f / aspect, 0,  0,  0),
                    float4(0, f,  0,  0),
                    float4(0, 0, far / (far - near), 1),
                    float4(0, 0, -far * near / (far - near), 0)
                    );
}
