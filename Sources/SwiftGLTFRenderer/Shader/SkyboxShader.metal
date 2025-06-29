#include <metal_stdlib>
using namespace metal;


struct SkyboxOut {
    float4 position [[position]];
    float3 texcoord;
};

vertex SkyboxOut skybox_vertex_shader(uint vertexID [[vertex_id]],
                                      constant float4 *vertices [[buffer(0)]],
                                      constant float4x4 &vpMatrix [[buffer(1)]])
{
    SkyboxOut out;

    out.position = vpMatrix * vertices[vertexID];
    out.texcoord = vertices[vertexID].xyz;

    out.position.z = 0;

    return out;
}

fragment float4 skybox_fragment_shader(SkyboxOut in [[stage_in]],
                                       texturecube<float> cubeMap [[texture(0)]]) {
    return cubeMap.sample(sampler(filter::linear), in.texcoord);
}
