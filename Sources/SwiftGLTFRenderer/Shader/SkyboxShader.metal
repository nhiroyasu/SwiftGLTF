#include <metal_stdlib>
#include "includes/helper.h"
#include "../../SwiftGLTFShaderTypes/includes/pbr.h"
#include "../../SwiftGLTFShaderTypes/includes/env_map_arguments.h"

using namespace metal;



struct SkyboxOut {
    float4 position [[position]];
    float3 texcoord;
};

vertex SkyboxOut skybox_vertex_shader(uint vertexID [[vertex_id]],
                                      constant float4 *vertices [[buffer(0)]],
                                      constant float4x4* worldTransforms [[buffer(1)]],
                                      constant int64_t &cameraIndex [[buffer(2)]],
                                      constant FreeCameraUniforms &freeCameraUniforms [[buffer(3)]],
                                      constant NodeCameraUniforms* nodeCameraUniforms [[buffer(4)]])
{
    SkyboxOut out;

    float4x4 view = cameraIndex >= 0
    ? inverse_affine(worldTransforms[nodeCameraUniforms[cameraIndex].nodeHierarchyOffset])
    : freeCameraUniforms.viewMatrix;
    float4x4 projection = cameraIndex >= 0
    ? projectionMatrix(nodeCameraUniforms[cameraIndex], freeCameraUniforms.aspectRatio)
    : freeCameraUniforms.projectionMatrix;

    float3x3 R = _float3x3(view);
    float4x4 V_noTrans = float4x4(float4(R[0], 0),
                                  float4(R[1], 0),
                                  float4(R[2], 0),
                                  float4(0,0,0,1)
                                  );

    out.position = projection * V_noTrans * vertices[vertexID];
    out.texcoord = vertices[vertexID].xyz;

    // skybox z coordinate is set to w for perspective correction
    // so that it is not affected by the camera's position
    out.position.z = out.position.w;

    return out;
}

fragment float4 skybox_fragment_shader(SkyboxOut in [[stage_in]],
                                       constant PBREnvMapArguments &args [[buffer(0)]]) {
    return args.prefilterEnvMap.sample(sampler(filter::linear), normalize(in.texcoord));
}
