#include <metal_stdlib>
using namespace metal;

#define THREADS 256

kernel void computeBoundingSphereForMesh(
    device const uchar*      vertexBytes       [[ buffer(0) ]],
    constant uint&           vertexCount       [[ buffer(1) ]],
    constant uint&           positionStride    [[ buffer(2) ]],
    constant uint&           positionOffset    [[ buffer(3) ]],
    device float4*           outSpheres        [[ buffer(4) ]],
    constant uint&           outIndex          [[ buffer(5) ]],
    uint                     tid               [[ thread_index_in_threadgroup ]]
) {
    if (vertexCount == 0) {
        if (tid == 0) {
            outSpheres[outIndex] = float4(0.0, 0.0, 0.0, 0.0);
        }
        return;
    }

    threadgroup float3 tmin[THREADS];
    threadgroup float3 tmax[THREADS];

    float3 localMin = float3(INFINITY, INFINITY, INFINITY);
    float3 localMax = float3(-INFINITY, -INFINITY, -INFINITY);

    for (uint i = tid; i < vertexCount; i += THREADS) {
        device const float3* posPtr = (device const float3*)(vertexBytes + i * positionStride + positionOffset);
        float3 p = *posPtr;
        localMin = min(localMin, p);
        localMax = max(localMax, p);
    }

    tmin[tid] = localMin;
    tmax[tid] = localMax;
    threadgroup_barrier(mem_flags::mem_threadgroup);

    // halving reduction to find overall min and max
    for (uint s = THREADS >> 1; s > 0; s >>= 1) {
        if (tid < s) {
            tmin[tid] = min(tmin[tid], tmin[tid + s]);
            tmax[tid] = max(tmax[tid], tmax[tid + s]);
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }

    if (tid == 0) {
        float3 minv = tmin[0];
        float3 maxv = tmax[0];
        float3 center = 0.5f * (minv + maxv);
        float radius = length(maxv - center);
        outSpheres[outIndex] = float4(center, radius);
    }
}
