#ifndef metal_argument_buffer_bridge_h
#define metal_argument_buffer_bridge_h

#include <simd/simd.h>

#ifdef __METAL_VERSION__

using namespace metal;
    #define AB_TEXTURECUBE(type)    texturecube<type>
    #define AB_TEXTURE2D(type)      texture2d<type>
    #define AB_SAMPLER              sampler
    #define AB_BUFFER_PTR(T)        device T*
#else

#include <Metal/Metal.h>
    #define AB_TEXTURECUBE(type)    MTLResourceID   // texture.gpuResourceID
    #define AB_TEXTURE2D(type)      MTLResourceID   // texture.gpuResourceID
    #define AB_SAMPLER              MTLResourceID   // sampler.gpuResourceID
    #define AB_BUFFER_PTR(T)        uint64_t        // buffer.gpuAddress
#endif

#endif /* metal_argument_buffer_bridge_h */
