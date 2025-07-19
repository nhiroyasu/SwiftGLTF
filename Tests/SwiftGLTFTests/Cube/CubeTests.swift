import Testing
import ModelIO
@testable import SwiftGLTF
@testable import SwiftGLTFCore

struct CubeTests {
    @Test
    func testGLTFStructure() throws {
        let (gltf, _) = try loadGLTFAndAsset()
        #expect(gltf.asset.version == "2.0")
        #expect(gltf.asset.generator == "Khronos glTF Blender I/O v4.4.55")
    }

    @Test
    func testVertexData() throws {
        let (_, asset) = try loadGLTFAndAsset()
        let mesh = asset.object(at: 0).children.objects[0] as! MDLMesh
        #expect(mesh.vertexCount == 24)
        #expect(mesh.vertexBuffers[0].length == 768) // 24points × (float3 pos + float3 normal + float2 texcoord) = 24 × 32
    }

    @Test
    func testIndexData() throws {
        let (_, asset) = try loadGLTFAndAsset()
        let mesh = asset.object(at: 0).children.objects[0] as! MDLMesh
        let submesh = mesh.submeshes?.firstObject as! MDLSubmesh
        #expect(submesh.indexCount == 36)
        #expect(submesh.indexType == .uInt16)
    }

    @Test
    func testGeometryType() throws {
        let (_, asset) = try loadGLTFAndAsset()
        let mesh = asset.object(at: 0).children.objects[0] as! MDLMesh
        let submesh = mesh.submeshes?.firstObject as! MDLSubmesh
        #expect(submesh.geometryType == .triangles)
    }

    @Test
    func testSceneNodeHierarchy() throws {
        let (gltf, asset) = try loadGLTFAndAsset()
        #expect(gltf.scenes!.count == 1)
        #expect(gltf.nodes!.count == 1)
        #expect(asset.count == 1)
        #expect(gltf.scene == 0)
    }

    @Test
    func testVertexDescriptor() throws {
        let (_, asset) = try loadGLTFAndAsset()
        let mesh = asset.object(at: 0).children.objects[0] as! MDLMesh
        let descriptor = mesh.vertexDescriptor

        let position = descriptor.attributes[0] as! MDLVertexAttribute
        #expect(position.name == MDLVertexAttributePosition)
        #expect(position.format == .float3)
        #expect(position.offset == 0)
        #expect(position.bufferIndex == 0)

        let normal = descriptor.attributes[1] as! MDLVertexAttribute
        #expect(normal.name == MDLVertexAttributeNormal)
        #expect(normal.format == .float3)
        #expect(normal.offset == 12)
        #expect(normal.bufferIndex == 0)

        let texcoord = descriptor.attributes[3] as! MDLVertexAttribute
        #expect(texcoord.name == MDLVertexAttributeTextureCoordinate)
        #expect(texcoord.format == .float2)
        #expect(texcoord.offset == 24)
        #expect(texcoord.bufferIndex == 0)

        let layout = descriptor.layouts[0] as! MDLVertexBufferLayout
        #expect(layout.stride == 32)
    }

    @Test
    func testIndexBufferMatchesOriginalBinary() throws {
        let (gltf, asset) = try loadGLTFAndAsset()
        let mesh = asset.object(at: 0).children.objects[0] as! MDLMesh
        let indicesData = (mesh.submeshes?.firstObject as! MDLSubmesh).indexBuffer.map().bytes.assumingMemoryBound(to: UInt8.self)

        let binURL = Bundle.module.url(forResource: "cube", withExtension: "bin")!
        let originalData = try Data(contentsOf: binURL)

        let posAccessorIndex = gltf.meshes![0].primitives[0].indices!
        let accessor = gltf.accessors![posAccessorIndex.value]
        let bufferView = gltf.bufferViews![accessor.bufferView!.value]
        let start = bufferView.byteOffset ?? 0
        let length = bufferView.byteLength
        let expectedIndexData = originalData.subdata(in: start..<(start + length))

        let actualIndexData = Data(bytes: indicesData, count: length)

        #expect(expectedIndexData == actualIndexData)
    }

    @Test
    func testPositionBufferMatchesOriginalBinary() throws {
        let (gltf, asset) = try loadGLTFAndAsset()
        let mesh = asset.object(at: 0).children.objects[0] as! MDLMesh
        let vertexData = Data(bytes: mesh.vertexBuffers[0].map().bytes.assumingMemoryBound(to: UInt8.self), count: mesh.vertexBuffers[0].length)

        let binURL = Bundle.module.url(forResource: "cube", withExtension: "bin")!
        let originalData = try Data(contentsOf: binURL)

        let posAccessorIndex = gltf.meshes![0].primitives[0].attributes["POSITION"]!
        let accessor = gltf.accessors![posAccessorIndex]
        let bufferView = gltf.bufferViews![accessor.bufferView!.value]
        let start = bufferView.byteOffset ?? 0
        let length = bufferView.byteLength
        let expectedPositionData = originalData.subdata(in: start..<(start + length))

        var actualPositionData = Data(capacity: length)
        let stride = 32 // 4 * float3 + 4 * float3 + 4 * float2 = 32 bytes (pos + normal + texcoord)
        let readSize = 12 // position is float3 (3 * 4 bytes)
        var offset = 0
        while offset + readSize <= stride * accessor.count {
            let value = vertexData.subdata(in: offset..<offset + readSize)
            actualPositionData.append(value)
            offset += stride
        }

        #expect(expectedPositionData == actualPositionData)
    }

    @Test
    func testNormalBufferMatchesOriginalBinary() throws {
        let (gltf, asset) = try loadGLTFAndAsset()
        let mesh = asset.object(at: 0).children.objects[0] as! MDLMesh
        let vertexData = Data(bytes: mesh.vertexBuffers[0].map().bytes.assumingMemoryBound(to: UInt8.self), count: mesh.vertexBuffers[0].length)

        let binURL = Bundle.module.url(forResource: "cube", withExtension: "bin")!
        let originalData = try Data(contentsOf: binURL)

        let posAccessorIndex = gltf.meshes![0].primitives[0].attributes["NORMAL"]!
        let accessor = gltf.accessors![posAccessorIndex]
        let bufferView = gltf.bufferViews![accessor.bufferView!.value]
        let start = bufferView.byteOffset ?? 0
        let length = bufferView.byteLength
        let expectedNormalData = originalData.subdata(in: start..<(start + length))

        var actualNormalData = Data(capacity: length)
        let stride = 32 // 4 * float3 + 4 * float3 + 4 * float2 = 32 bytes (pos + normal + texcoord)
        let readSize = 12 // Normal is float3 (3 * 4 bytes)
        var offset = 12
        while offset + readSize <= stride * accessor.count {
            let value = vertexData.subdata(in: offset..<offset + readSize)
            actualNormalData.append(value)
            offset += stride
        }

        #expect(expectedNormalData == actualNormalData)
    }

    @Test
    func testTexCoordBufferMatchesOriginalBinary() throws {
        let (gltf, asset) = try loadGLTFAndAsset()
        let mesh = asset.object(at: 0).children.objects[0] as! MDLMesh
        let vertexData = Data(bytes: mesh.vertexBuffers[0].map().bytes.assumingMemoryBound(to: UInt8.self), count: mesh.vertexBuffers[0].length)

        let binURL = Bundle.module.url(forResource: "cube", withExtension: "bin")!
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
    func testMaterialProperties() throws {
        let (_, asset) = try loadGLTFAndAsset()
        let mesh = asset.object(at: 0).children.objects[0] as! MDLMesh
        let submesh = mesh.submeshes?.firstObject as! MDLSubmesh
        let material = submesh.material!

        let name = material.name
        #expect(name == "Material")

        let baseColor = material.property(with: .baseColor)
        let expectedBaseColor = SIMD4<Float>(repeating: 0.8)
        #expect(baseColor?.float4Value.x == expectedBaseColor.x)
        #expect(baseColor?.float4Value.y == expectedBaseColor.y)
        #expect(baseColor?.float4Value.z == expectedBaseColor.z)
        #expect(baseColor?.float4Value.w == 1.0)

        let metallic = material.property(with: .metallic)
        #expect(metallic?.floatValue == 0.0)

        let roughness = material.property(with: .roughness)
        #expect(roughness?.floatValue == 0.5)
    }

    // MARK: - Helper Methods

    private func loadGLTFAndAsset() throws -> (GLTF, MDLAsset) {
        guard let gltfURL = Bundle.module.url(forResource: "cube", withExtension: "gltf") else {
            throw NSError(domain: "CubeGLTFTests", code: -1, userInfo: [NSLocalizedDescriptionKey: "cube.gltf not found"])
        }
        let data = try Data(contentsOf: gltfURL)
        let gltfContainer = try loadGLTF(from: data, baseURL: gltfURL.deletingLastPathComponent())
        let asset = try makeMDLAsset(
            from: gltfContainer,
            options: GLTFDecodeOptions(
                convertToLeftHanded: false,
                autoScale: false,
                generateNormalVertexIfNeeded: false,
                generateTangentVertexIfNeeded: false
            )
        )
        return (gltfContainer.gltf, asset)
    }
}
