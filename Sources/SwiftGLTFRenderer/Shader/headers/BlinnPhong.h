#ifndef LambertBlinnPhongMaterial_h
#define LambertBlinnPhongMaterial_h

#include <simd/simd.h>

typedef struct {
    vector_float3 diffuseColor; // Diffuse color of the material
    vector_float3 specularColor; // Specular color of the material
    float shininess; // Shininess factor for specular highlights
} BlinnPhongMaterial;

typedef struct {
    vector_float3 lightPosition; // Position of the light source
    vector_float3 viewPosition; // Position of the camera/viewer
    vector_float3 ambientLight; // Ambient light color
} BlinnPhongSceneUniforms;

#endif /* LambertBlinnPhongMaterial_h */
