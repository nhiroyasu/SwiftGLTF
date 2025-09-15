import simd

/// Material factors buffer matching Metal PBRMaterialUniforms
struct PBRMaterialUniforms {
    let baseColorFactor: simd_float4
    let metalRoughnessOcclusion: simd_float4
    let emissiveFactor: simd_float4
    let doubleSided: UInt32
    let transmissionThicknessDistance: simd_float4
    let attenuationColor: simd_float4
    let ior: Float
    let specularFactor: Float
    let specularFactorColor: simd_float4
}
