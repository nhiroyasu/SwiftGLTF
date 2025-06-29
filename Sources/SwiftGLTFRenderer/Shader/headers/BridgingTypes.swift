import simd

struct BlinnPhongMaterial {
    let diffuseColor: SIMD3<Float> // Diffuse color of the material
    let specularColor: SIMD3<Float> // Specular color of the material
    let shininess: Float // Shininess factor for specular highlights
}

struct BlinnPhongSceneUniforms {
    let lightPosition: SIMD3<Float> // Position of the light source
    let viewPosition: SIMD3<Float> // Position of the camera/viewer
    let ambientLight: SIMD3<Float> // Ambient light color
}

struct PBRSceneUniforms {
    let lightPosition: SIMD3<Float> // Position of the light source
    let viewPosition: SIMD3<Float> // Position of the camera/viewer
    let ambientLightColor: SIMD3<Float> // Ambient light color
}
