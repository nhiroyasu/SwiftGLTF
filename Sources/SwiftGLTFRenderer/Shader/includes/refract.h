#ifndef refract_h
#define refract_h

float2 refract_uv_offset_thin_slab(float3 V,
                                   float3 N,
                                   float t,
                                   float IOR,
                                   float3 P_view,
                                   float2 fov,
                                   float2 viewportSize,
                                   float3 camRight,
                                   float3 camUp);

#endif /* refract_h */
