import simd

struct TextureTransformParameters {
    var offsetScale: SIMD4<Float>
    var rotation: Float
    var padding: SIMD3<Float>

    init(offsetScale: SIMD4<Float>, rotation: Float) {
        self.offsetScale = offsetScale
        self.rotation = rotation
        self.padding = SIMD3<Float>(repeating: 0)
    }

    init(offset: SIMD2<Float>, scale: SIMD2<Float>, rotation: Float) {
        self.init(offsetScale: SIMD4<Float>(offset.x, offset.y, scale.x, scale.y), rotation: rotation)
    }

    static let identity = TextureTransformParameters(
        offset: SIMD2<Float>(repeating: 0),
        scale: SIMD2<Float>(repeating: 1),
        rotation: 0
    )
}
