#include <metal_stdlib>
#include "includes/helper.h"
#include "../../SwiftGLTFShaderTypes/includes/pbr.h"

using namespace metal;



struct SkyboxOut {
    float4 position [[position]];
    float3 texcoord;
};

vertex SkyboxOut skybox_vertex_shader(uint vertexID [[vertex_id]],
                                      constant float4 *vertices [[buffer(0)]],
                                      constant MVPUniform &mvp [[buffer(1)]])
{
    SkyboxOut out;

    float3x3 R = _float3x3(mvp.view);
    float4x4 V_noTrans = float4x4(float4(R[0], 0),
                                  float4(R[1], 0),
                                  float4(R[2], 0),
                                  float4(0,0,0,1)
                                  );

    out.position = mvp.projection * V_noTrans * vertices[vertexID];
    out.texcoord = vertices[vertexID].xyz;

    // skybox z coordinate is set to w for perspective correction
    // so that it is not affected by the camera's position
    out.position.z = out.position.w;

    return out;
}

fragment float4 skybox_fragment_shader(SkyboxOut in [[stage_in]],
                                       texturecube<float> cubeMap [[texture(0)]]) {
    return cubeMap.sample(sampler(filter::linear), normalize(in.texcoord));
}
