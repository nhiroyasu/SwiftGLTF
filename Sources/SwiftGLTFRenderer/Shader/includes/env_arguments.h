#ifndef env_arguments_h
#define env_arguments_h

struct PBREnvMapArguments {
    texturecube<float> prefilterEnvMap [[id(0)]];
    texturecube<float> irradianceMap [[id(1)]];
    texture2d<float> brdfLUT [[id(2)]];
    texturecube<float> prefilterSheenMap [[id(3)]];
};

#endif /* env_arguments_h */
