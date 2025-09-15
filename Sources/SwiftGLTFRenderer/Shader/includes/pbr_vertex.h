#ifndef pbr_vertex_in_h
#define pbr_vertex_in_h

struct VertexIn {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float4 tangent [[attribute(2)]];
    float2 uv [[attribute(3)]];
    float2 uv1 [[attribute(4)]];
    float4 modulationColor [[attribute(5)]];
    ushort4 joints [[attribute(6)]];
    float4 weights [[attribute(7)]];
};

struct PBRVertexOut {
    float4 position [[position]];
    float3 positionVS; // View space position for refraction calculations
    float3 worldPosition;
    float3 normal;
    float3 normalVS; // View space normal for refraction calculations
    float4 tangent;
    float2 uv;
    float2 uv1;
    float4 modulationColor;
};

#endif /* pbr_vertex_in_h */
