import Testing
import ModelIO
@testable import SwiftGLTF
@testable import SwiftGLTFCore

struct TangentCubeTests {
    @Test
    func testTangentBufferMatchesOriginalBinary() throws {
        let (gltf, asset) = try loadGLTFAndAsset()
        let mesh = asset.object(at: 0).children.objects[0] as! MDLMesh
        let vertexData = Data(bytes: mesh.vertexBuffers[0].map().bytes.assumingMemoryBound(to: UInt8.self), count: mesh.vertexBuffers[0].length)

        let binURL = Bundle.module.url(forResource: "tangent_cube", withExtension: "bin")!
        let originalData = try Data(contentsOf: binURL)

        let posAccessorIndex = gltf.meshes![0].primitives[0].attributes["TANGENT"]!
        let accessor = gltf.accessors![posAccessorIndex]
        let bufferView = gltf.bufferViews![accessor.bufferView!.value]
        let start = bufferView.byteOffset ?? 0
        let length = bufferView.byteLength
        let expectedPositionData = originalData.subdata(in: start..<(start + length))

        var actualPositionData = Data(capacity: length)
        let stride = VertexAttributeStride.stride
        let readSize = 16 // tangent is float4 (4 * 4 bytes)
        var offset = VertexAttributeOffset.tangent
        while offset + readSize <= stride * accessor.count {
            let value = vertexData.subdata(in: offset..<offset + readSize)
            actualPositionData.append(value)
            offset += stride
        }

        #expect(expectedPositionData == actualPositionData)
    }

    // MARK: - Helper Methods

    private func loadGLTFAndAsset() throws -> (GLTF, MDLAsset) {
        guard let gltfURL = Bundle.module.url(forResource: "tangent_cube", withExtension: "gltf") else {
            throw NSError(domain: "CubeGLTFTests", code: -1, userInfo: [NSLocalizedDescriptionKey: "tangent_cube.gltf not found"])
        }
        let data = try Data(contentsOf: gltfURL)
        let gltfContainer = try loadGLTF(from: data, baseURL: gltfURL.deletingLastPathComponent())
        let asset = try makeMDLAsset(
            from: gltfContainer,
            options: .init(convertToLeftHanded: false)
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
