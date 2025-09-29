#include <metal_stdlib>
#include "includes/pbr_clearcoat.h"
#include "includes/helper.h"
using namespace metal;

float clearcoatFresnel(float3 clearcoatNormal,
                       float3 worldPosition,
                       float3 viewPosition,
                       float3 lightPosition)
{
    float3 V = normalize(viewPosition - worldPosition);
    float3 L = normalize(lightPosition - worldPosition);
    float3 H = normalize(V + L);
    float3 Nc = normalize(clearcoatNormal);
    float NdotLc = max(dot(Nc, L), 0.0);
    float NdotVc = max(dot(Nc, V), 0.0);
    if (NdotLc > 0.0 && NdotVc > 0.0) {
        float Fc = fresnelSchlick(max(dot(H, V), 0.0), 0.04);
        return Fc;
    } else {
        return 0.0;
    }
}
