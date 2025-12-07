// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftGLTF",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "SwiftGLTF",
            targets: ["SwiftGLTF"])
    ],
    dependencies: [
        .package(url: "https://github.com/nhiroyasu/Img2Cubemap.git", from: "0.1.13")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.

        .target(
            name: "SwiftGLTF",
            dependencies: ["SwiftGLTFRenderer", "SwiftGLTFParser", "SwiftGLTFCore", "SwiftGLTFShaderTypes"],
            resources: [
                .process("Resources/"),
            ]),

        .target(
            name: "SwiftGLTFRenderer",
            dependencies: ["SwiftGLTFParser", "SwiftGLTFShaderTypes", "Img2Cubemap", "SwiftGLTFCore"],
            resources: [
                .process("Shader/")
            ]),
        .testTarget(
            name: "SwiftGLTFRendererTests",
            dependencies: ["SwiftGLTFRenderer"],
            resources: [
                .process("Resources/"),
                .process("Golden/"),
            ]),

        .target(
            name: "SwiftGLTFParser",
            dependencies: ["SwiftGLTFCore", "MikkTSpace"]),
        .testTarget(
            name: "SwiftGLTFParserTests",
            dependencies: ["SwiftGLTFParser"],
            resources: [
                .process("Cube/Resources/cube.gltf"),
                .process("Cube/Resources/cube.bin"),
                .process("CubeBinary/Resources/cube.glb"),
                .process("CubeWithTexture/Resources/bricks_cube.gltf"),
                .process("CubeWithTexture/Resources/bricks_cube_empty_sampler.gltf"),
                .process("CubeWithTexture/Resources/bricks_cube.bin"),
                .process("CubeWithTexture/Resources/Bricks101_2K-JPG_Color.jpg"),
                .process("CubeWithTexture/Resources/Bricks101_2K-JPG_NormalGL.jpg"),
                .process("CubeBinaryWithTexture/Resources/bricks_cube.glb"),
                .process("MaterialCube/Resources/material_cube.gltf"),
                .process("MaterialCube/Resources/material_cube.bin"),
                .process("PlainCube/Resources/plain_cube.gltf"),
                .process("PlainCube/Resources/plain_cube.bin"),
                .process("TangentCube/Resources/tangent_cube.gltf"),
                .process("TangentCube/Resources/tangent_cube.bin"),
                .process("EmissiveCube/Resources/emissive_cube.gltf"),
                .process("EmissiveCube/Resources/emissive_cube.bin"),
                .process("BoxTextured/Resources/EmbeddedBoxTextured.gltf"),
                .process("BoxTextured/Resources/CesiumLogoFlat.png"),
                .process("SimpleSkin/Resources"),
                .process("AnimatedMorphCube/Resources"),
            ]),

        .target(name: "SwiftGLTFCore"),
        .testTarget(name: "SwiftGLTFCoreTests",
                    dependencies: ["SwiftGLTFCore"]),

        .target(
            name: "SwiftGLTFShaderTypes",
            publicHeadersPath: "includes"),

        .target(
            name: "MikkTSpace",
            publicHeadersPath: "includes"),
    ]
)
