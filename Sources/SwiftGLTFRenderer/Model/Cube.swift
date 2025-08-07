struct Cube {
    let vertices: [Float]
    let indices: [UInt16]

    init(size: Float) {
        let halfSize = size / 2
        let vertices: [Float] = [
            // -Z
            -halfSize, -halfSize, -halfSize, 1.0,
             halfSize, -halfSize, -halfSize, 1.0,
            -halfSize,  halfSize, -halfSize, 1.0,
             halfSize,  halfSize, -halfSize, 1.0,

            // +Z
            -halfSize, -halfSize,  halfSize, 1.0,
             halfSize, -halfSize,  halfSize, 1.0,
            -halfSize,  halfSize,  halfSize, 1.0,
             halfSize,  halfSize,  halfSize, 1.0,

            // +Y
            -halfSize,  halfSize, -halfSize, 1.0,
             halfSize,  halfSize, -halfSize, 1.0,
            -halfSize,  halfSize,  halfSize, 1.0,
             halfSize,  halfSize,  halfSize, 1.0,

             // -Y
            -halfSize, -halfSize, -halfSize, 1.0,
             halfSize, -halfSize, -halfSize, 1.0,
            -halfSize, -halfSize,  halfSize, 1.0,
             halfSize, -halfSize,  halfSize, 1.0,

             // +X
            halfSize, -halfSize, -halfSize, 1.0,
            halfSize,  halfSize, -halfSize, 1.0,
            halfSize, -halfSize,  halfSize, 1.0,
            halfSize,  halfSize,  halfSize, 1.0,

             // -X
            -halfSize, -halfSize, -halfSize, 1.0,
            -halfSize,  halfSize, -halfSize, 1.0,
            -halfSize, -halfSize,  halfSize, 1.0,
            -halfSize,  halfSize,  halfSize, 1.0,
        ]

        let indices: [UInt16] = [
            // front
            0, 1, 2,  2, 3, 1,
            // back
            4, 5, 6,  6, 7, 5,
            // up
            8, 9, 10,  10, 11, 9,
            // down
            12, 13, 14,  14, 15, 13,
            // left
            16, 17, 18,  18, 19, 17,
            // right
            20, 21, 22,  22, 23, 21
        ]
        self.vertices = vertices
        self.indices = indices
    }
}
