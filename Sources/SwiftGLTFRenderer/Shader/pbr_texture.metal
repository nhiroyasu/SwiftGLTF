#include <metal_stdlib>
#include "includes/pbr_texture.h"

using namespace metal;

float2 apply_texture_transform(float2 uv, float4 offsetScale, float rotation) {
    float2 scale = offsetScale.zw;
    float2 offset = offsetScale.xy;

    float3x3 scaleMatrix = float3x3(float3(scale.x, 0.0f, 0.0f),
                                    float3(0.0f, scale.y, 0.0f),
                                    float3(0.0f, 0.0f, 1.0f));

    float s = sin(rotation);
    float c = cos(rotation);

    float3x3 rotationMatrix = float3x3(float3(c, -s, 0.0f),
                                       float3(s,  c, 0.0f),
                                       float3(0.0f, 0.0f, 1.0f));

    float3x3 translationMatrix = float3x3(float3(1.0f, 0.0f, 0.0f),
                                          float3(0.0f, 1.0f, 0.0f),
                                          float3(offset, 1.0f));

    float3x3 transform = translationMatrix * rotationMatrix * scaleMatrix;

    return (transform * float3(uv, 1.0f)).xy;
}
