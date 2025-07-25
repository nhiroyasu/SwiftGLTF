#ifndef PBR_h
#define PBR_h

#include <simd/simd.h>

typedef struct {
    vector_float3 lightPosition; // Position of the light source
    vector_float3 viewPosition; // Position of the camera/viewer
    vector_float3 ambientLightColor; // Ambient light color
} PBRSceneUniforms;

typedef struct {
    bool hasUV;
    bool hasModulationColor;
} VertexAttributeFlags;

#endif /* PBR_h */
