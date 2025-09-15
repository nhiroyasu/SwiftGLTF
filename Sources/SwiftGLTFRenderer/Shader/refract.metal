#include <metal_stdlib>

using namespace metal;

// 薄板（平行面）近似でのUVオフセット計算
// V, N は正規化済みを想定。t は厚み（ビュー空間と同スケール）
// en: UV offset for refraction in thin slab approximation
float2 refract_uv_offset_thin_slab(float3 V,
                                   float3 N,
                                   float thickness,
                                   float IOR,
                                   float3 P_view,
                                   float2 fov,
                                   float2 viewportSize,
                                   float3 camRight,
                                   float3 camUp) {
    V = normalize(V);
    N = normalize(N);

    // 入射角/屈折角
    // en: Incident and transmitted angles
    float cosTi = saturate(dot(-V, N));
    float sinTi = sqrt(max(1.0 - cosTi * cosTi, 0.0));
    float sinTt = sinTi / max(IOR, 1e-6);
    float cosTt = sqrt(max(1.0 - sinTt * sinTt, 0.0));

    float tanTi = sinTi / max(cosTi, 1e-6);
    float tanTt = sinTt / max(cosTt, 1e-6);

    // 横ずれ量 δ = t * (tanθi - tanθt)
    // en: Lateral shift δ = t * (tanθi - tanθt)
    float delta = thickness * (tanTi - tanTt);

    // 面内方向（法線に直交する視線の成分）
    // en: Tangential direction (component of view vector perpendicular to normal)
    float3 T = -normalize(V - dot(V, N) * N);

    // 画素シフト（投影の一次近似）：Δx_pixels ≈ (δ * dot(T, Xc)) * fx / |z|
    // en: Pixel shift (first-order approximation of projection): Δx_pixels ≈ (δ * dot(T, Xc)) * fx / |z|
    float z = max(abs(P_view.z), 1e-3);
    float fx = (viewportSize.x / 2) / tan(fov.x / 2); // focal length in x pixels
    float fy = (viewportSize.y / 2) / tan(fov.y / 2); // focal length in y pixels
    float dx_pixels = (delta * dot(T, camRight)) * (fx / z);
    float dy_pixels = (delta * dot(T, camUp   )) * (fy / z);

    // UVへ正規化（Y上向き↔UV下向きなら符号反転）
    // en: Normalize to UV (invert sign if Y is up and UV is down)
    float du =  dx_pixels / max(viewportSize.x,  1.0);
    float dv = -dy_pixels / max(viewportSize.y, 1.0);
    return float2(du, dv);
}

