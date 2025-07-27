#ifndef PBR_h
#define PBR_h

#include <simd/simd.h>

typedef struct {
    vector_float3 lightPosition; // Position of the light source
    vector_float3 viewPosition; // Position of the camera/viewer
    vector_float3 ambientLightColor; // Ambient light color
} PBRSceneUniforms;

typedef struct {
    bool hasTangent;
    bool hasUV;
    bool hasModulationColor;
} PBRVertexUniforms;

/// Material factors for PBR shading: base color factor, metallic/roughness/occlusion, emissive factor
typedef struct {
    vector_float4 baseColorFactor;
    vector_float4 metalRoughnessOcclusion; // x=metallic, y=roughness, z=occlusion, w=padding
    vector_float4 emissiveFactor;
} PBRMaterialUniforms;

#endif /* PBR_h */
