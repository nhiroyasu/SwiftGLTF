#ifndef screen_arguments_h
#define screen_arguments_h

#include "metal_argument_buffer_bridge.h"

typedef struct {
    AB_TEXTURE2D(float) sceneColorTexture;
    AB_SAMPLER sceneColorSampler;
    bool useSceneColor;
} PBRScreenColorArguments;

#endif /* screen_arguments_h */
