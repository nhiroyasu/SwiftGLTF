// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftGLTF",
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "SwiftGLTF",
            targets: ["SwiftGLTF"]),
        .library(
            name: "SwiftGLTFRenderer",
            targets: ["SwiftGLTFRenderer"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/nhiroyasu/Img2Cubemap.git", from: "0.1.1")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "SwiftGLTFRenderer",
            dependencies: ["SwiftGLTF", "Img2Cubemap"],
            resources: [
                .process("Shader/EmissiveMultiplierShader.metal"),
                .process("Shader/metal_helper.metal"),
                .process("Shader/MDLAssetBlinnPhongShader.metal"),
                .process("Shader/MDLAssetPBRShader.metal"),
                .process("Shader/MetallicRoughnessTextureShader.metal"),
                .process("Shader/PBRTextureComputeShader.metal"),
                .process("Shader/SkyboxShader.metal"),
                .process("Shader/Srgb2LinearShader.metal"),
                .process("Shader/OcclusionMultiplierShader.metal"),
                .process("Shader/BaseColorMultiplierShader.metal"),
            ]),
        .testTarget(
            name: "SwiftGLTFRendererTests",
            dependencies: ["SwiftGLTFRenderer"],
            resources: [
                .process("Resources/"),
                .process("Golden/"),
            ]),


        .target(
            name: "SwiftGLTF",
            dependencies: ["SwiftGLTFCore", "MikkTSpace"]),
        .testTarget(
            name: "SwiftGLTFTests",
            dependencies: ["SwiftGLTF"],
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
            ]),

        .target(name: "SwiftGLTFCore"),
        .testTarget(name: "SwiftGLTFCoreTests",
                    dependencies: ["SwiftGLTFCore"]),

        .target(
            name: "MikkTSpace",
            publicHeadersPath: "includes"
        )
    ]
)
