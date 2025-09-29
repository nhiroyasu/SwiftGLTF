#ifndef pbr_clearcoat_h
#define pbr_clearcoat_h

float clearcoatFresnel(float3 clearcoatNormal,
                       float3 worldPosition,
                       float3 viewPosition,
                       float3 lightPosition);

#endif /* pbr_clearcoat_h */
