import Testing
import ModelIO
@testable import SwiftGLTF
@testable import SwiftGLTFCore

// Tests for loading .glb (binary glTF) files, mirrored from CubeTests
struct CubeBinaryTests {
    @Test
    func testGLBStructure() throws {
        let (gltf, _) = try loadGLBAndAsset()
        #expect(gltf.asset.version == "2.0")
        // Generator may differ for .glb export; just ensure non-nil
        #expect(gltf.asset.generator != nil)
    }

    @Test
    func testVertexAndIndexCounts() throws {
        let (_, asset) = try loadGLBAndAsset()
        // Root object should contain one mesh
        #expect(asset.count == 1)
        let scene = asset.object(at: 0)
        let mesh = scene.children.objects[0] as! MDLMesh
        // Cube has 24 vertices and 36 indices
        #expect(mesh.vertexCount == 24)
        let submesh = mesh.submeshes?.firstObject as! MDLSubmesh
        #expect(submesh.indexCount == 36)
    }

    @Test
    func testVertexData() throws {
        let (_, asset) = try loadGLBAndAsset()
        let mesh = asset.object(at: 0).children.objects[0] as! MDLMesh
        #expect(mesh.vertexCount == 24)
        #expect(mesh.vertexBuffers[0].length == 1152) // 24points × VertexAttributeStride.stride = 24 × 48
    }

    @Test
    func testIndexData() throws {
        let (_, asset) = try loadGLBAndAsset()
        let mesh = asset.object(at: 0).children.objects[0] as! MDLMesh
        let submesh = mesh.submeshes?.firstObject as! MDLSubmesh
        #expect(submesh.indexCount == 36)
        #expect(submesh.indexType == .uInt16)
    }

    @Test
    func testGeometryType() throws {
        let (_, asset) = try loadGLBAndAsset()
        let mesh = asset.object(at: 0).children.objects[0] as! MDLMesh
        let submesh = mesh.submeshes?.firstObject as! MDLSubmesh
        #expect(submesh.geometryType == .triangles)
    }

    @Test
    func testSceneNodeHierarchy() throws {
        let (gltf, asset) = try loadGLBAndAsset()
        #expect(gltf.scenes!.count == 1)
        #expect(gltf.nodes!.count == 1)
        #expect(asset.count == 1)
        #expect(gltf.scene == 0)
    }

    @Test
    func testVertexDescriptor() throws {
        let (_, asset) = try loadGLBAndAsset()
        let mesh = asset.object(at: 0).children.objects[0] as! MDLMesh
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
        #expect(texcoord.offset == VertexAttributeOffset.texcoord)
        #expect(texcoord.bufferIndex == 0)

        let layout = descriptor.layouts[0] as! MDLVertexBufferLayout
        #expect(layout.stride == VertexAttributeStride.stride)
    }

    @Test
    func testIndexBufferMatchesOriginalBinary() throws {
        let (gltf, asset) = try loadGLBAndAsset()
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
        let (gltf, asset) = try loadGLBAndAsset()
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
    func testNormalBufferMatchesOriginalBinary() throws {
        let (gltf, asset) = try loadGLBAndAsset()
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
    func testTexCoordBufferMatchesOriginalBinary() throws {
        let (gltf, asset) = try loadGLBAndAsset()
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
        let stride = VertexAttributeStride.stride
        let readSize = VertexAttributeSize.texcoord
        var offset = VertexAttributeOffset.texcoord
        while offset + readSize <= stride * accessor.count {
            let value = vertexData.subdata(in: offset..<offset + readSize)
            actualTexCoordData.append(value)
            offset += stride
        }

        #expect(expectedTexCoordData == actualTexCoordData)
    }

    @Test
    func testMaterialProperties() throws {
        let (_, asset) = try loadGLBAndAsset()
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


    // Helper to load GLTF and MDLAsset from cube.glb
    private func loadGLBAndAsset() throws -> (GLTF, MDLAsset) {
        guard let url = Bundle.module.url(forResource: "cube", withExtension: "glb") else {
            throw NSError(domain: "CubeBinaryTests", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "cube.glb not found"])
        }
        let data = try Data(contentsOf: url)
        let gltfContainer = try loadGLTF(from: data, baseURL: url.deletingLastPathComponent())
        let asset = try makeMDLAsset(
            from: gltfContainer,
            options: GLTFDecodeOptions(convertToLeftHanded: false, autoScale: false)
        )
        return (gltfContainer.gltf, asset)
    }

    enum VertexAttributeStride {
        static let stride = 48
    }

    enum VertexAttributeSize {
        static let position = 12 // float3
        static let normal = 12 // float3
        static let tangent = 16 // float4
        static let texcoord = 8 // float2
    }

    enum VertexAttributeOffset {
        static let position = 0
        static let normal = 12
        static let tangent = 24
        static let texcoord = 40
    }
}
