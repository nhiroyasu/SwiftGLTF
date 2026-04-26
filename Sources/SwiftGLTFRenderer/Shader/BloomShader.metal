#include <metal_stdlib>
#include "includes/helper.h"

using namespace metal;

struct BloomExtractParams {
    uint width;
    uint height;
    float threshold;
    float padding;
};

kernel void bloom_extract(texture2d<float, access::sample> source [[texture(0)]],
                          texture2d<float, access::write> output [[texture(1)]],
                          constant BloomExtractParams &params [[buffer(0)]],
                          uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= params.width || gid.y >= params.height) {
        return;
    }

    constexpr sampler s(mag_filter::linear, min_filter::linear, s_address::clamp_to_edge, t_address::clamp_to_edge);
    float2 uv = (float2(gid) + 0.5) / float2(params.width, params.height);
    float3 color = source.sample(s, uv).rgb;
    float brightness = luminance709(color);
    float3 bloom = brightness > params.threshold ? color : float3(0.0);
    output.write(float4(bloom, 1.0), gid);
}

kernel void bloom_blur_horizontal(texture2d<float, access::read> source [[texture(0)]],
                                  texture2d<float, access::write> output [[texture(1)]],
                                  uint2 gid [[thread_position_in_grid]]) {
    uint width = output.get_width();
    uint height = output.get_height();
    if (gid.x >= width || gid.y >= height) {
        return;
    }

    constexpr float weights[5] = {
        0.204164,
        0.180174,
        0.123832,
        0.066282,
        0.027631
    };

    float3 color = source.read(gid).rgb * weights[0];
    for (int i = 1; i < 5; i++) {
        uint left = uint(max(int(gid.x) - i, 0));
        uint right = uint(min(int(gid.x) + i, int(width) - 1));
        color += source.read(uint2(left, gid.y)).rgb * weights[i];
        color += source.read(uint2(right, gid.y)).rgb * weights[i];
    }

    output.write(float4(color, 1.0), gid);
}

kernel void bloom_blur_vertical(texture2d<float, access::read> source [[texture(0)]],
                                texture2d<float, access::write> output [[texture(1)]],
                                uint2 gid [[thread_position_in_grid]]) {
    uint width = output.get_width();
    uint height = output.get_height();
    if (gid.x >= width || gid.y >= height) {
        return;
    }

    constexpr float weights[5] = {
        0.204164,
        0.180174,
        0.123832,
        0.066282,
        0.027631
    };

    float3 color = source.read(gid).rgb * weights[0];
    for (int i = 1; i < 5; i++) {
        uint top = uint(max(int(gid.y) - i, 0));
        uint bottom = uint(min(int(gid.y) + i, int(height) - 1));
        color += source.read(uint2(gid.x, top)).rgb * weights[i];
        color += source.read(uint2(gid.x, bottom)).rgb * weights[i];
    }

    output.write(float4(color, 1.0), gid);
}
