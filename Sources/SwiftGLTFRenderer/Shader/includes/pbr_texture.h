#ifndef pbr_texture_h
#define pbr_texture_h

using namespace metal;

float2 apply_texture_transform(float2 uv, float4 offsetScale, float rotation);

#endif /* pbr_texture_h */
