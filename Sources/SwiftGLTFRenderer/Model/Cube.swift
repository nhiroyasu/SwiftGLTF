//
//  Cube.swift
//  SwiftGLTFPreview
//
//  Created by NH on 2025/06/28.
//



struct Cube {
    let vertices: [Float]
    let indices: [UInt16]

    init(size: Float) {
        let halfSize = size / 2
        let vertices: [Float] = [
            // 前面 (-Z)
            -halfSize, -halfSize, -halfSize, 1.0,
             halfSize, -halfSize, -halfSize, 1.0,
            -halfSize,  halfSize, -halfSize, 1.0,
             halfSize,  halfSize, -halfSize, 1.0,

            // 背面 (+Z)
            -halfSize, -halfSize,  halfSize, 1.0,
             halfSize, -halfSize,  halfSize, 1.0,
            -halfSize,  halfSize,  halfSize, 1.0,
             halfSize,  halfSize,  halfSize, 1.0,

            // 上面 (+Y)
            -halfSize,  halfSize, -halfSize, 1.0,
             halfSize,  halfSize, -halfSize, 1.0,
            -halfSize,  halfSize,  halfSize, 1.0,
             halfSize,  halfSize,  halfSize, 1.0,

             // 上面 (-Y)
            -halfSize, -halfSize, -halfSize, 1.0,
             halfSize, -halfSize, -halfSize, 1.0,
            -halfSize, -halfSize,  halfSize, 1.0,
             halfSize, -halfSize,  halfSize, 1.0,

             // 右面 (+X)
            halfSize, -halfSize, -halfSize, 1.0,
            halfSize,  halfSize, -halfSize, 1.0,
            halfSize, -halfSize,  halfSize, 1.0,
            halfSize,  halfSize,  halfSize, 1.0,

             // 左面 (-X)
            -halfSize, -halfSize, -halfSize, 1.0,
            -halfSize,  halfSize, -halfSize, 1.0,
            -halfSize, -halfSize,  halfSize, 1.0,
            -halfSize,  halfSize,  halfSize, 1.0,
        ]

        let indices: [UInt16] = [
            // 前面
            0, 1, 2,  2, 3, 1,
            // 背面
            4, 5, 6,  6, 7, 5,
            // 上面
            8, 9, 10,  10, 11, 9,
            // 下面
            12, 13, 14,  14, 15, 13,
            // 左面
            16, 17, 18,  18, 19, 17,
            // 右面
            20, 21, 22,  22, 23, 21
        ]
        self.vertices = vertices
        self.indices = indices
    }
}