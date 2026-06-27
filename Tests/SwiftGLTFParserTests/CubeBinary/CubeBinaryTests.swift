import Testing
import ModelIO
@testable import SwiftGLTFParser
@testable import SwiftGLTFCore

// Tests for loading .glb (binary glTF) files, mirrored from CubeTests
struct CubeBinaryTests {
    @Test
    func testGLBStructure() async throws {
        let (gltf, _) = try await loadGLBAndAsset()
        #expect(gltf.asset.version == "2.0")
        // Generator may differ for .glb export; just ensure non-nil
        #expect(gltf.asset.generator != nil)
    }

    @Test
    func testVertexAndIndexCounts() async throws {
        let (_, asset) = try await loadGLBAndAsset()
        let mesh = targetMesh(from: asset)
        // Cube has 24 vertices and 36 indices
        #expect(mesh.vertexCount == 24)
        let submesh = mesh.submeshes?.firstObject as! MDLSubmesh
        #expect(submesh.indexCount == 36)
    }

    @Test
    func testVertexData() async throws {
        let (_, asset) = try await loadGLBAndAsset()
        let mesh = targetMesh(from: asset)
        #expect(mesh.vertexCount == 24)
        #expect(mesh.vertexBuffers[0].length == 24 * VertexAttributeStride.stride)
    }

    @Test
    func testIndexData() async throws {
        let (_, asset) = try await loadGLBAndAsset()
        let mesh = targetMesh(from: asset)
        let submesh = mesh.submeshes?.firstObject as! MDLSubmesh
        #expect(submesh.indexCount == 36)
        #expect(submesh.indexType == .uInt16)
    }

    @Test
    func testGeometryType() async throws {
        let (_, asset) = try await loadGLBAndAsset()
        let mesh = targetMesh(from: asset)
        let submesh = mesh.submeshes?.firstObject as! MDLSubmesh
        #expect(submesh.geometryType == .triangles)
    }

    @Test
    func testSceneNodeHierarchy() async throws {
        let (gltf, asset) = try await loadGLBAndAsset()
        #expect(gltf.scenes!.count == 1)
        #expect(gltf.nodes!.count == 1)
        #expect(asset.object(atPath: GLTFAssetPath.nodes).children.count == 1)
        #expect(asset.object(atPath: GLTFAssetPath.scene(0)).children.count == 0)
        let rootNodes = asset.object(atPath: GLTFAssetPath.scene(0))
            .componentConforming(to: GLTFSceneRootNodesProtocol.self) as? GLTFSceneRootNodes
        #expect(rootNodes?.nodes == [0])
        #expect(gltf.scene == 0)
    }

    @Test
    func testVertexDescriptor() async throws {
        let (_, asset) = try await loadGLBAndAsset()
        let mesh = targetMesh(from: asset)
        let descriptor = mesh.vertexDescriptor

        let position = descriptor.attributes[0] as! MDLVertexAttribute
        #expect(position.name == MDLVertexAttributePosition)
        #expect(position.format == .float3)
        #expect(position.offset == VertexAttributeOffset.position)
        #expect(position.bufferIndex == 0)

        let normal = descriptor.attributes[1] as! MDLVertexAttribute
        #expect(normal.name == MDLVertexAttributeNormal)
        #expect(normal.format == .float3)
        #expect(normal.offset == VertexAttributeOffset.normal)
        #expect(normal.bufferIndex == 0)

        let texcoord = descriptor.attributes[3] as! MDLVertexAttribute
        #expect(texcoord.name == MDLVertexAttributeTextureCoordinate)
        #expect(texcoord.format == .float2)
        #expect(texcoord.offset == VertexAttributeOffset.texcoord0)
        #expect(texcoord.bufferIndex == 0)

        let layout = descriptor.layouts[0] as! MDLVertexBufferLayout
        #expect(layout.stride == VertexAttributeStride.stride)
    }

    @Test
    func testIndexBufferMatchesOriginalBinary() async throws {
        let (gltf, asset) = try await loadGLBAndAsset()
        let mesh = targetMesh(from: asset)
        let indicesData = (mesh.submeshes?.firstObject as! MDLSubmesh).indexBuffer.map().bytes.assumingMemoryBound(to: UInt8.self)

        let binURL = Bundle.module.url(forResource: "cube", withExtension: "bin")!
        let originalData = try Data(contentsOf: binURL)

        let posAccessorIndex = gltf.meshes![0].primitives[0].indices!
        let accessor = gltf.accessors![posAccessorIndex.value]
        let bufferView = gltf.bufferViews![accessor.bufferView!.value]
        let start = bufferView.byteOffset
        let length = bufferView.byteLength
        let expectedIndexData = originalData.subdata(in: start..<(start + length))

        let actualIndexData = Data(bytes: indicesData, count: length)

        #expect(expectedIndexData == actualIndexData)
    }

    @Test
    func testPositionBufferMatchesOriginalBinary() async throws {
        let (gltf, asset) = try await loadGLBAndAsset()
        let mesh = targetMesh(from: asset)
        let vertexData = Data(bytes: mesh.vertexBuffers[0].map().bytes.assumingMemoryBound(to: UInt8.self), count: mesh.vertexBuffers[0].length)

        let binURL = Bundle.module.url(forResource: "cube", withExtension: "bin")!
        let originalData = try Data(contentsOf: binURL)

        let posAccessorIndex = gltf.meshes![0].primitives[0].attributes["POSITION"]!
        let accessor = gltf.accessors![posAccessorIndex]
        let bufferView = gltf.bufferViews![accessor.bufferView!.value]
        let start = bufferView.byteOffset
        let length = bufferView.byteLength
        let expectedPositionData = originalData.subdata(in: start..<(start + length))

        var actualPositionData = Data(capacity: length)
        let stride = VertexAttributeStride.stride
        let readSize = VertexAttributeSize.position
        var offset = VertexAttributeOffset.position
        while offset + readSize <= stride * accessor.count {
            let value = vertexData.subdata(in: offset..<offset + readSize)
            actualPositionData.append(value)
            offset += stride
        }

        #expect(expectedPositionData == actualPositionData)
    }

    @Test
    func testNormalBufferMatchesOriginalBinary() async throws {
        let (gltf, asset) = try await loadGLBAndAsset()
        let mesh = targetMesh(from: asset)
        let vertexData = Data(bytes: mesh.vertexBuffers[0].map().bytes.assumingMemoryBound(to: UInt8.self), count: mesh.vertexBuffers[0].length)

        let binURL = Bundle.module.url(forResource: "cube", withExtension: "bin")!
        let originalData = try Data(contentsOf: binURL)

        let posAccessorIndex = gltf.meshes![0].primitives[0].attributes["NORMAL"]!
        let accessor = gltf.accessors![posAccessorIndex]
        let bufferView = gltf.bufferViews![accessor.bufferView!.value]
        let start = bufferView.byteOffset
        let length = bufferView.byteLength
        let expectedNormalData = originalData.subdata(in: start..<(start + length))

        var actualNormalData = Data(capacity: length)
        let stride = VertexAttributeStride.stride
        let readSize = VertexAttributeSize.normal
        var offset = VertexAttributeOffset.normal
        while offset + readSize <= stride * accessor.count {
            let value = vertexData.subdata(in: offset..<offset + readSize)
            actualNormalData.append(value)
            offset += stride
        }

        #expect(expectedNormalData == actualNormalData)
    }

    @Test
    func testTexCoordBufferMatchesOriginalBinary() async throws {
        let (gltf, asset) = try await loadGLBAndAsset()
        let mesh = targetMesh(from: asset)
        let vertexData = Data(bytes: mesh.vertexBuffers[0].map().bytes.assumingMemoryBound(to: UInt8.self), count: mesh.vertexBuffers[0].length)

        let binURL = Bundle.module.url(forResource: "cube", withExtension: "bin")!
        let originalData = try Data(contentsOf: binURL)

        let posAccessorIndex = gltf.meshes![0].primitives[0].attributes["TEXCOORD_0"]!
        let accessor = gltf.accessors![posAccessorIndex]
        let bufferView = gltf.bufferViews![accessor.bufferView!.value]
        let start = bufferView.byteOffset
        let length = bufferView.byteLength
        let expectedTexCoordData = originalData.subdata(in: start..<(start + length))

        var actualTexCoordData = Data(capacity: length)
        let stride = VertexAttributeStride.stride
        let readSize = VertexAttributeSize.texcoord0
        var offset = VertexAttributeOffset.texcoord0
        while offset + readSize <= stride * accessor.count {
            let value = vertexData.subdata(in: offset..<offset + readSize)
            actualTexCoordData.append(value)
            offset += stride
        }

        #expect(expectedTexCoordData == actualTexCoordData)
    }

    @Test
    func testMaterialProperties() async throws {
        let (_, asset) = try await loadGLBAndAsset()
        let mesh = targetMesh(from: asset)
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


    // Helper to load GLTF and MDLAsset from cube.glb
    private func loadGLBAndAsset() async throws -> (GLTF, MDLAsset) {
        guard let url = Bundle.module.url(forResource: "cube", withExtension: "glb") else {
            throw NSError(domain: "CubeBinaryTests", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "cube.glb not found"])
        }
        let data = try Data(contentsOf: url)
        let gltfContainer = try await loadGLTF(from: data, baseURL: url.deletingLastPathComponent())
        let asset = try await makeMDLAsset(
            from: gltfContainer,
            options: GLTFDecodeOptions(convertToLeftHanded: false, autoScale: false)
        )
        return (gltfContainer.gltf, asset)
    }

    private func targetMesh(from asset: MDLAsset) -> MDLMesh {
        let mesh = asset.object(atPath: GLTFAssetPath.primitiveMesh(0)).children[0] as! MDLMesh
        return mesh
    }
}

enum VertexAttributeStride {
    // 12 (position) + 12 (normal) + 16 (tangent) + 8 (texcoord0) + 8 (texcoord1) + 16 (color) + 8 (joints) + 16 (weights)
    static let stride = 96
}

enum VertexAttributeSize: CaseIterable {
    static let position = 12 // float3
    static let normal = 12 // float3
    static let tangent = 16 // float4
    static let texcoord0 = 8 // float2
    static let texcoord1 = 8 // float2
    static let color = 16 // float4
    static let joints = 8 // float4
    static let weights = 16 // float4
}

enum VertexAttributeOffset {
    static let position = 0
    static let normal = 12
    static let tangent = 24
    static let texcoord0 = 40
    static let texcoord1 = 48
    static let color = 56
    static let joints = 72
    static let weights = 80
}
