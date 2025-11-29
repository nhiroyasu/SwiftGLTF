#ifndef env_map_arguments_h
#define env_map_arguments_h

#include <simd/simd.h>
#include "metal_argument_buffer_bridge.h"

typedef struct {
    AB_TEXTURECUBE(float) prefilterEnvMap;
    AB_TEXTURECUBE(float) irradianceMap;
    AB_TEXTURE2D(float) brdfLUT;
    AB_TEXTURECUBE(float) prefilterSheenMap;
} PBREnvMapArguments;

#endif /* env_map_arguments_h */
