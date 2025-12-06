#ifndef pbr_vertex_argument_buffer_h
#define pbr_vertex_argument_buffer_h

#include <simd/simd.h>
#include "metal_argument_buffer_bridge.h"
#include "pbr.h"

struct PBRVertexArguments {
    AB_MATRIX4x4 model;
    AB_MATRIX4x4 inverseModel;

    // Morph targets (optional)
    uint morphTargetCount;
    AB_BUFFER_PTR(float) morphDefaultWeights;
    AB_BUFFER_PTR(float) morphInterleaved0;
    AB_BUFFER_PTR(float) morphInterleaved1;
    AB_BUFFER_PTR(float) morphInterleaved2;
    AB_BUFFER_PTR(float) morphInterleaved3;
    AB_BUFFER_PTR(float) morphInterleaved4;
    AB_BUFFER_PTR(float) morphInterleaved5;
    AB_BUFFER_PTR(float) morphInterleaved6;
    AB_BUFFER_PTR(float) morphInterleaved7;

    int64_t transformIndex;
    int64_t morphDispatchIndex; // equal to `transformIndex`
    SkinDispatch skinDispatch;
};


#endif /* pbr_vertex_argument_buffer_h */
