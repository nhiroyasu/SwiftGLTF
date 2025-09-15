#ifndef screen_arguments_h
#define screen_arguments_h

struct PBRScreenColorArguments {
    texture2d<float> sceneColorTexture [[id(0)]];
    sampler sceneColorSampler [[id(1)]];
    bool useSceneColor [[id(2)]];
};

#endif /* screen_arguments_h */
