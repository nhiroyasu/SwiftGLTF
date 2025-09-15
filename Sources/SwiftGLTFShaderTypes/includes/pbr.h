#ifndef PBR_h
#define PBR_h

#include <simd/simd.h>

/// Material factors for PBR shading: base color factor, metallic/roughness/occlusion, emissive factor
typedef struct {
    vector_float4 baseColorFactor;
    vector_float4 metalRoughnessOcclusion; // x=metallic, y=roughness, z=occlusion, w=padding
    vector_float4 emissiveFactor;
    uint32_t doubleSided; // 0 or 1
    vector_float4 transmissionThicknessDistance; // x: transmissionFactor, y: thicknessFactor, z: attenuationDistance, w: padding
    vector_float4 attenuationColor; // xyz: attenuationColor, w: padding
} PBRMaterialUniforms;

typedef struct {
    matrix_float4x4 view;
    matrix_float4x4 projection;
    matrix_float4x4 externalTransform;
} MVPUniform;

typedef struct {
    vector_float3 lightPosition; // Position of the light source
    vector_float3 viewPosition; // Position of the camera/viewer
    vector_float3 ambientLightColor; // Ambient light color
    vector_float2 viewportSize; // render target size (width, height)
    vector_float2 fov; // x: fovx, y: fovy
    vector_float3 camRight; // right direction in view space (usually float3(1,0,0))
    vector_float3 camUp;    // up direction in view space (usually float3(0,1,0))
} SceneUniforms;

typedef struct {
    float roughness;
    uint32_t mipLevel;
    uint32_t cubeSize;
    uint32_t sampleCount;
} PreFilterEnvMapParams;

typedef struct {
    uint32_t cubeSize;
} IrradianceMapParams;

// Prefilter 2D texture params for scene color pyramid generation
typedef struct {
    uint32_t width;
    uint32_t height;
    uint32_t mipLevel; // output mip level (reads from mipLevel-1)
} Prefilter2DParams;

typedef struct {
    int64_t start;   // levelStarts[d]
    int64_t count;   // levelCounts[d]
} LevelDispatch;

/* ex:
# glTF.skins
 - joints: [0, 1, 2]
 - joints: [0, 2, 3, 5]

# GPU Memory Layout
 joints: [
 0, 1, 2, // first skin
 0, 2, 3, 5 // second skin
 ]

 ↑ SkinDispatch
    [offset: 0, length: 3], // first skin
    [offset: 3, length: 4]  // second skin
*/
typedef struct {
    // if -1, no skinning
    int64_t offset;
    int64_t length;
} SkinDispatch;

/** ex:
 # glTF
 ```
 nodes: [
   {
     mesh: 0,
     weights: [0.5, 1.0]
   },
   {
     mesh: 1,
     weights: [0.7, 0.7]
    },
 ],
 ]

 # GPU Memory Layout
 morphWeights: [
   0.5, 1.0, // first node
   0.7, 0.7, // second node
 ]

↑ MorphDispatch
[offset: 0, length: 2], // first node
[offset: 2, length: 2]  // second node
 ```
 */
typedef struct {
    // if -1, no morph
    int64_t offset;
    int64_t length;

} MorphDispatch;

enum PBRVertexArgId: int {
    PBRVertexArgIdModel = 0,
    PBRVertexArgIdInverseModel,
    PBRVertexArgIdMorphTargetCount,
    PBRVertexArgIdMorphDefaultWeights,
    PBRVertexArgIdMorphInterleaved0,
    PBRVertexArgIdMorphInterleaved1,
    PBRVertexArgIdMorphInterleaved2,
    PBRVertexArgIdMorphInterleaved3,
    PBRVertexArgIdMorphInterleaved4,
    PBRVertexArgIdMorphInterleaved5,
    PBRVertexArgIdMorphInterleaved6,
    PBRVertexArgIdMorphInterleaved7,
    PBRVertexArgIdTransformIndex,
    PBRVertexArgIdMorphDispatchIndex,
    PBRVertexArgIdSkinDispatch,
};

typedef enum: int {
    PBRFragmentShaderArgsBuffer = 0,
    PBRFragmentShaderEnvMapArgsBuffer,
    PBRFragmentShaderSceneUniformsBuffer,
    PBRFragmentShaderScreenColorBuffer,
} PBRFragmentShaderBufferIndex;

typedef enum: uint32_t {
    AlphaModeOpaque = 0,
    AlphaModeMask   = 1,
    AlphaModeBlend  = 2
} AlphaMode;

#endif /* PBR_h */
