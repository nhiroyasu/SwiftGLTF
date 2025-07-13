import Foundation

public struct GLTFBufferLoader {
    public let gltf: GLTF
    public let baseURL: URL
    public let loadedBuffers: [Data]

    public init(gltf: GLTF, baseURL: URL, binaryChunk: Data? = nil) throws {
        self.gltf = gltf
        self.baseURL = baseURL
        self.loadedBuffers = try gltf.buffers?.enumerated().map { index, buffer in
            if let uri = buffer.uri {
                let bufferURL = baseURL.appendingPathComponent(uri)
                return try Data(contentsOf: bufferURL)
            } else if index == 0, let binaryChunk {
                return binaryChunk
            } else {
                throw NSError(domain: "GLTF", code: -1, userInfo: [NSLocalizedDescriptionKey: "Buffer URI is missing"])
            }
        } ?? []
    }

    public func extractData(accessorIndex: Int) throws -> Data {
        guard let accessor = gltf.accessors?[accessorIndex] else {
            throw NSError(domain: "GLTF", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid accessor index"])
        }

        guard let bufferViewIndex = accessor.bufferView,
              let bufferView = gltf.bufferViews?[bufferViewIndex] else {
            throw NSError(domain: "GLTF", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid bufferView reference"])
        }

        let buffer = loadedBuffers[bufferView.buffer]
        let baseOffset = (accessor.byteOffset ?? 0) + (bufferView.byteOffset ?? 0)
        let accessorStride = accessor.type.components * accessor.componentType.size
        let bufferStride = bufferView.byteStride ?? accessorStride
        let expectedLength = bufferStride * accessor.count

        let endOffset = baseOffset + expectedLength
        guard endOffset <= buffer.count else {
            throw NSError(domain: "GLTF", code: -1, userInfo: [NSLocalizedDescriptionKey: "Buffer overrun in accessor"])
        }

        var result = buffer.subdata(in: baseOffset..<endOffset)

        let isDifferedStride = bufferStride != accessorStride
        if isDifferedStride {
            result = arrangeDataForAccessorStride(result, accessorStride: accessorStride, bufferStride: bufferStride)
        }

        return result
    }

    private func arrangeDataForAccessorStride(
        _ data: Data,
        accessorStride: Int,
        bufferStride: Int
    ) -> Data {
        var strideData: Data = Data()
        var offset = 0
        while offset < data.count {
            let strideSlice = data.subdata(in: offset..<offset + accessorStride)
            strideData.append(strideSlice)
            offset += bufferStride
        }
        return strideData
    }
}
