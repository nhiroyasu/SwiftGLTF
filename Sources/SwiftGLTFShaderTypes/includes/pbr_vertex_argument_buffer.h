#ifndef pbr_vertex_argument_buffer_h
#define pbr_vertex_argument_buffer_h

#include <simd/simd.h>
#include "metal_argument_buffer_bridge.h"
#include "pbr.h"

struct PBRVertexArguments {
    // Morph targets (optional)
    uint morphTargetCount;
    uint morphVertexCount;
    AB_BUFFER_PTR(float) morphDefaultWeights;
    AB_BUFFER_PTR(float) morphInterleaved;

    int64_t transformIndex;
    int64_t morphDispatchIndex; // equal to `transformIndex`
    SkinDispatch skinDispatch;
};


#endif /* pbr_vertex_argument_buffer_h */
