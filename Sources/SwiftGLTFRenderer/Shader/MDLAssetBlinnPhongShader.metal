#include <metal_stdlib>
#include "headers/BlinnPhong.h"

using namespace metal;

struct VertexIn {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float2 uv [[attribute(2)]];
};

struct VertexOut {
    float4 position [[position]];
    float3 worldPosition;
    float3 normal;
    BlinnPhongMaterial material;
};

vertex VertexOut blinn_phong_vertex_shader(VertexIn in [[stage_in]],
                                         constant float4x4 &mvp [[buffer(1)]],
                                         constant float3x3 &normalMatrix [[buffer(2)]]) {
    VertexOut out;
    out.position = mvp * float4(in.position, 1.0);
    out.worldPosition = in.position;
    out.normal = normalize(normalMatrix * in.normal);

    BlinnPhongMaterial material;
    material.diffuseColor = float3(1.0, 1.0, 1.0); // Example diffuse color
    material.specularColor = float3(1.0, 1.0, 1.0); // Example specular color
    material.shininess = 32.0; // Example shininess value

    out.material = material;
    return out;
}

fragment float4 blinn_phong_fragment_shader(VertexOut in [[stage_in]],
                                          constant BlinnPhongSceneUniforms &uniforms [[buffer(0)]]) {
    float3 diffuse = max(dot(in.normal, uniforms.lightPosition), 0.0) * in.material.diffuseColor;

    float3 reflectDir = reflect(-uniforms.lightPosition, in.normal);
    float3 spec = pow(max(dot(uniforms.viewPosition, reflectDir), 0.0), in.material.shininess) * in.material.specularColor;

    float3 lighting = uniforms.ambientLight + diffuse + spec;

    return float4(lighting, 1.0);
};
