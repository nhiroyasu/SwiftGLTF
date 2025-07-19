import Testing
import ModelIO
@testable import SwiftGLTF
@testable import SwiftGLTFCore

struct CubeBinaryWithTextureTests {
    @Test
    func testTexCoordBufferMatchesOriginalBinary() throws {
        let (gltfContainer, asset) = try loadGLBAndAsset()
        let gltf = gltfContainer.gltf
        let mesh = asset.object(at: 0).children.objects[0] as! MDLMesh
        let vertexData = Data(bytes: mesh.vertexBuffers[0].map().bytes.assumingMemoryBound(to: UInt8.self), count: mesh.vertexBuffers[0].length)

        let binURL = Bundle.module.url(forResource: "bricks_cube", withExtension: "bin")!
        let originalData = try Data(contentsOf: binURL)

        let posAccessorIndex = gltf.meshes![0].primitives[0].attributes["TEXCOORD_0"]!
        let accessor = gltf.accessors![posAccessorIndex]
        let bufferView = gltf.bufferViews![accessor.bufferView!.value]
        let start = bufferView.byteOffset ?? 0
        let length = bufferView.byteLength
        let expectedTexCoordData = originalData.subdata(in: start..<(start + length))

        var actualTexCoordData = Data(capacity: length)
        let stride = 32 // 4 * float3 + 4 * float3 + 4 * float2 = 32 bytes (pos + normal + texcoord)
        let readSize = 8 // TexCoord is float3 (3 * 4 bytes)
        var offset = 24
        while offset + readSize <= stride * accessor.count {
            let value = vertexData.subdata(in: offset..<offset + readSize)
            actualTexCoordData.append(value)
            offset += stride
        }

        #expect(expectedTexCoordData == actualTexCoordData)
    }

    @Test
    func testMaterialBaseColorAndNormalTexture() throws {
        let (gltfContainer, asset) = try loadGLBAndAsset()
        let mesh = asset.object(at: 0).children.objects[0] as! MDLMesh
        let submesh = mesh.submeshes?.firstObject as! MDLSubmesh
        let material = submesh.material!

        let baseColor = material.property(with: .baseColor)!
        #expect(baseColor.type == .texture)
        let baseColorTexture = baseColor.textureSamplerValue!.texture!

        let normal = material.property(with: .tangentSpaceNormal)!
        #expect(normal.type == .texture)
        let normalTexture = normal.textureSamplerValue!.texture!

        // glTFに定義されたURIから直接MDLTextureを作成
        // en: Create MDLTexture directly from the URI defined in glTF
        let expectedBaseColorTexture = gltfContainer.binaryTextures[1]
        let expectedNormalTexture = gltfContainer.binaryTextures[0]

        #expect(baseColorTexture.imageFromTexture()!.takeUnretainedValue().dataProvider!.data! == expectedBaseColorTexture.imageFromTexture()!.takeUnretainedValue().dataProvider!.data!)
        #expect(normalTexture.imageFromTexture()!.takeUnretainedValue().dataProvider!.data! == expectedNormalTexture.imageFromTexture()!.takeUnretainedValue().dataProvider!.data!)
    }

    @Test
    func testSamplerFilterAndWrapSettings() throws {
        let (gltfContainer, asset) = try loadGLBAndAsset()
        let gltf = gltfContainer.gltf
        let mesh = asset.object(at: 0).children.objects[0] as! MDLMesh
        let submesh = mesh.submeshes?.firstObject as! MDLSubmesh
        let material = submesh.material!

        let baseColor = material.property(with: .baseColor)!
        let sampler = baseColor.textureSamplerValue!

        let textureIndex = gltf.materials![0].pbrMetallicRoughness!.baseColorTexture!.index
        let samplerIndex = gltf.textures![textureIndex.value].sampler!
        let gltfSampler = gltf.samplers![samplerIndex]

        // compare filter modes
        if let gltfMin = gltfSampler.minFilter {
            let expected = convertFilterMode(gltfMin)
            #expect(sampler.hardwareFilter?.minFilter == expected)
        }
        if let gltfMag = gltfSampler.magFilter {
            let expected = convertFilterMode(gltfMag)
            #expect(sampler.hardwareFilter?.magFilter == expected)
        }

        // compare wrap modes
        if let gltfWrapS = gltfSampler.wrapS {
            let expected = convertWrapMode(gltfWrapS)
            #expect(sampler.hardwareFilter?.sWrapMode == expected)
        }
        if let gltfWrapT = gltfSampler.wrapT {
            let expected = convertWrapMode(gltfWrapT)
            #expect(sampler.hardwareFilter?.tWrapMode == expected)
        }
    }

    @Test
    func testMetallicRoughnessProperties() throws {
        // Please write a test for metallic and roughness properties
        let (_, asset) = try loadGLBAndAsset()
        let mesh = asset.object(at: 0).children.objects[0] as! MDLMesh
        let submesh = mesh.submeshes?.firstObject as! MDLSubmesh
        let material = submesh.material!
        let metallic = material.property(with: .metallic)!
        let roughness = material.property(with: .roughness)!

        #expect(metallic.floatValue == 0.0)
        #expect(roughness.floatValue == 1.0)
    }

    // MARK: - Helper Methods

    private func loadGLBAndAsset() throws -> (GLTFContainer, MDLAsset) {
        guard let gltfURL = Bundle.module.url(forResource: "bricks_cube", withExtension: "glb") else {
            throw NSError(domain: "CubeGLTFTests", code: -1, userInfo: [NSLocalizedDescriptionKey: "cube.glb not found"])
        }
        let data = try Data(contentsOf: gltfURL)
        let gltfContainer = try loadGLTF(from: data, baseURL: gltfURL.deletingLastPathComponent())
        let asset = try makeMDLAsset(
            from: gltfContainer,
            options: .init(
                generateNormalVertexIfNeeded: false,
                generateTangentVertexIfNeeded: false
            )
        )
        return (gltfContainer, asset)
    }

    private func convertFilterMode(_ mode: GLTFFilterMode) -> MDLMaterialTextureFilterMode {
        switch mode {
        case .nearest, .nearestMipmapNearest, .nearestMipmapLinear:
            return .nearest
        case .linear, .linearMipmapNearest, .linearMipmapLinear:
            return .linear
        }
    }

    private func convertWrapMode(_ mode: GLTFWrapMode) -> MDLMaterialTextureWrapMode {
        switch mode {
        case .clampToEdge:
            return .clamp
        case .mirroredRepeat:
            return .mirror
        case .repeatWrap:
            return .repeat
        }
    }
}
