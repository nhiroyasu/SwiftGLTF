import simd

/// Material factors buffer matching Metal PBRMaterialUniforms
struct PBRMaterialUniforms {
    let baseColorFactor: simd_float4
    let metalRoughnessOcclusion: simd_float4
    let emissiveFactor: simd_float4
    let doubleSided: UInt32
}
