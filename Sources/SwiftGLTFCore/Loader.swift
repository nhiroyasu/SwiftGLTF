import Foundation
import ModelIO
import MetalKit
import simd
import Accelerate

/// Extracts the raw Data from a Data URI string (base64 encoded)
func dataFromDataURI(_ uri: String) throws -> Data {
    // Extract base64 string after comma
    guard let comma = uri.firstIndex(of: ",") else {
        throw NSError(domain: "GLTF", code: -1,
                      userInfo: [NSLocalizedDescriptionKey: "Invalid data URI"])
    }
    let b64 = String(uri[uri.index(after: comma)...])
    guard let data = Data(base64Encoded: b64) else {
        throw NSError(domain: "GLTF", code: -1,
                      userInfo: [NSLocalizedDescriptionKey: "Failed to decode base64 data"])
    }
    return data
}

func makeMDLTexture(from data: Data, name: String) throws -> MDLTexture {
    guard
        let src = CGImageSourceCreateWithData(data as CFData, nil),
        let cgImage = CGImageSourceCreateImageAtIndex(src, 0, nil)
    else { throw NSError(domain: "SwiftGLTF", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGImage from data"]) }

    let properties = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
    let bitsPerComponent = properties?[kCGImagePropertyDepth] as? Int ?? 8
    let channelCount = 4 // TODO: handle different formats
    let bitsPerPixel = bitsPerComponent * channelCount

    guard var format = vImage_CGImageFormat(
        bitsPerComponent: bitsPerComponent,
        bitsPerPixel: bitsPerPixel,
        colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
        renderingIntent: .defaultIntent
    ) else {
        throw NSError(domain: "SwiftGLTF", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid CGImage format"])
    }

    var buffer = vImage_Buffer()
    let kvFlags = vImage_Flags(kvImageNoFlags)
    let initErr = vImageBuffer_InitWithCGImage(&buffer, &format, nil, cgImage, kvFlags)
    guard initErr == kvImageNoError else { throw NSError(domain: "SwiftGLTF", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize vImage buffer"]) }

    let bufferRowBytes = Int(buffer.rowBytes)
    let imageRowBytes = Int(buffer.width * 4)
    var raw = Data(count: Int(imageRowBytes * Int(buffer.height)))
    raw.withUnsafeMutableBytes { dstPtr in
        guard let dstBase = dstPtr.baseAddress else { return }
        // vImageのデータをDataにコピー
        for y in 0..<Int(buffer.height) {
            let srcRow = buffer.data!.advanced(by: y * bufferRowBytes)
            let dstRow = dstBase.advanced(by: y * imageRowBytes)
            memcpy(dstRow, srcRow, imageRowBytes)
        }
    }
    free(buffer.data)

    let mdl = MDLTexture(
        data: raw,
        topLeftOrigin: true,
        name: name,
        dimensions: vector_int2(Int32(buffer.width), Int32(buffer.height)),
        rowStride: imageRowBytes,
        channelCount: channelCount,
        channelEncoding: .uint8,
        isCube: false
    )
    return mdl
}

// Returns true if the data begins with the glb magic "glTF" header
func isGLB(_ data: Data) -> Bool {
    guard data.count >= 4 else { return false }
    // ASCII "glTF" == [0x67, 0x6C, 0x54, 0x46]
    let magic = data.prefix(4)
    return magic == Data([0x67, 0x6C, 0x54, 0x46])
}

private func loadFromGLB(_ data: Data) throws -> GLTFContainer {
    guard data.count >= 12 else {
        throw NSError(domain: "SwiftGLTF", code: -1,
                      userInfo: [NSLocalizedDescriptionKey: "GLB data too short for header"])
    }

    let magic = data.prefix(4)
    let expectedMagic = Data([0x67, 0x6C, 0x54, 0x46])
    guard magic == expectedMagic else {
        throw NSError(domain: "SwiftGLTF", code: -1,
                      userInfo: [NSLocalizedDescriptionKey: "Invalid GLB magic header"])
    }

    let version: UInt32 = data[4..<8].withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
    guard version == 2 else {
        throw NSError(domain: "SwiftGLTF", code: -1,
                      userInfo: [NSLocalizedDescriptionKey: "Unsupported GLB version: \(version)"])
    }

    let totalLength: UInt32 = data[8..<12].withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
    guard totalLength == data.count else {
        throw NSError(domain: "SwiftGLTF", code: -1,
                      userInfo: [NSLocalizedDescriptionKey: "GLB length mismatch"])
    }

    var offset = 12
    var jsonChunk: Data?
    var binChunk: Data?

    while offset + 8 <= data.count {
        let chunkLength = data[offset..<(offset+4)].withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let chunkType = data[(offset+4)..<(offset+8)].withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let chunkStart = offset + 8
        let chunkEnd = chunkStart + Int(chunkLength)
        guard chunkEnd <= data.count else {
            throw NSError(domain: "SwiftGLTF", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "GLB chunk exceeds data bounds"])
        }

        let chunk = data.subdata(in: chunkStart..<chunkEnd)
        switch chunkType {
        case 0x4E4F534A: // "JSON"
            jsonChunk = chunk
        case 0x004E4942: // "BIN"
            binChunk = chunk
        default:
            break
        }
        offset = chunkEnd
    }

    guard let jsonChunk else {
        throw NSError(domain: "SwiftGLTF", code: -1,
                      userInfo: [NSLocalizedDescriptionKey: "JSON chunk not found in GLB"])
    }
    let decoder = JSONDecoder()
    let gltf = try decoder.decode(GLTF.self, from: jsonChunk)

    guard let binChunk else {
        throw NSError(domain: "SwiftGLTF", code: -1,
                      userInfo: [NSLocalizedDescriptionKey: "BIN chunk not found in GLB"])
    }

    // Extract embedded images from bufferViews
    var textures: [MDLTexture] = []
    if let bufferViews = gltf.bufferViews, let images = gltf.images {
        for (idx, image) in images.enumerated() {
            if let bvIndex = image.bufferView?.value {
                let bv = bufferViews[bvIndex]

                let start = bv.byteOffset ?? 0
                let length = bv.byteLength
                let imageData = binChunk.subdata(in: start..<(start + length))
                let texture = try makeMDLTexture(from: imageData, name: "Texture_\(idx)")
                textures.append(texture)
            } else {
                throw NSError(domain: "SwiftGLTF", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "Image bufferView is missing for image \(idx)"])
            }
        }
    }
    return GLTFContainer(gltf: gltf, binaryBuffers: [binChunk], binaryTextures: textures)
}

private func loadFromGLTF(_ data: Data, baseURL: URL) throws -> GLTFContainer {
    let decoder = JSONDecoder()
    let gltf = try decoder.decode(GLTF.self, from: data)

    var buffers: [Data] = []
    for buffer in gltf.buffers ?? [] {
        // Load buffer data (data URI or external file)
        let data: Data
        if let uri = buffer.uri, let url = URL(string: uri, relativeTo: baseURL) {
            if uri.hasPrefix("data:") {
                // Data URI: data:<mime>;base64,<data>
                guard let comma = uri.firstIndex(of: ",") else {
                    throw NSError(domain: "GLTF", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid data URI for buffer"])
                }
                let b64 = String(uri[uri.index(after: comma)...])
                guard let decoded = Data(base64Encoded: b64) else {
                    throw NSError(domain: "GLTF", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to decode base64 buffer data"])
                }
                data = decoded
            } else {
                data = try Data(contentsOf: url)
            }
        } else {
            throw NSError(domain: "GLTF", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Buffer URI is missing or empty"])
        }
        buffers.append(data)
    }

    // Extract external images or data URIs
    var textures: [MDLTexture] = []
    for (idx, image) in (gltf.images ?? []).enumerated() {
        if let uri = image.uri {
            if uri.hasPrefix("data:") {
                // Make MDLTexture from data URI
                let imageData = try dataFromDataURI(uri)
                let texture = try makeMDLTexture(from: imageData, name: "Texture_\(idx)")
                textures.append(texture)
            } else if let url = URL(string: uri, relativeTo: baseURL) {
                // Make MDLTexture from external file
                let imageData = try Data(contentsOf: url)
                let texture = try makeMDLTexture(from: imageData, name: "Texture_\(idx)")
                textures.append(texture)
            } else {
                throw NSError(domain: "GLTF", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "Image URI is missing or invalid"])
            }
        } else {
            throw NSError(domain: "GLTF", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Image URI is missing or invalid"])
        }
    }
    return GLTFContainer(gltf: gltf, binaryBuffers: buffers, binaryTextures: textures)
}

public func loadGLTF(from data: Data, baseURL: URL) throws -> GLTFContainer {
    if isGLB(data) {
        // Load GLB: parse JSON and binary chunks
        return try loadFromGLB(data)
    } else {
        // Load glTF: parse JSON and load buffers
        return try loadFromGLTF(data, baseURL: baseURL)
    }
}

public class GLTFBinaryLoader {
    private let gltfContainer: GLTFContainer

    public init(gltfContainer: GLTFContainer) {
        self.gltfContainer = gltfContainer
    }

    /// Extracts raw data for the given accessor index.
    /// - Throws: error if accessor or buffer view is invalid, or data out-of-bounds.
    public func extractData(accessorIndex: AccessorIndex) throws -> Data {
        let gltf = gltfContainer.gltf
        let binaryBuffers = gltfContainer.binaryBuffers

        guard let accessor = gltf.accessors?[accessorIndex.value] else {
            throw NSError(domain: "GLTFContainer", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid accessor index"])
        }
        guard let bvIndex = accessor.bufferView?.value,
              let bufferViews = gltf.bufferViews,
              bvIndex < bufferViews.count else {
            throw NSError(domain: "GLTFContainer", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid bufferView reference"])
        }
        let bv = bufferViews[bvIndex]
        let bufIdx = bv.buffer.value
        guard bufIdx < binaryBuffers.count else {
            throw NSError(domain: "GLTFContainer", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Buffer index out of range"])
        }
        let bufferData = binaryBuffers[bufIdx]
        let baseOffset = (accessor.byteOffset ?? 0) + (bv.byteOffset ?? 0)
        let accessorStride = accessor.type.components * accessor.componentType.size
        let bufferStride = bv.byteStride ?? accessorStride
        let totalLength = accessor.count * bufferStride
        let diffStride = bufferStride - accessorStride
        let endOffset = baseOffset + totalLength - diffStride
        guard endOffset <= bufferData.count else {
            throw NSError(domain: "GLTFContainer", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Buffer overrun in accessor data"])
        }
        var slice = bufferData.subdata(in: baseOffset..<endOffset)
        if diffStride != 0 {
            slice = arrangeDataForStride(slice, accessorStride: accessorStride, bufferStride: bufferStride)
        }
        return slice
    }

    /// Reorders interleaved data into contiguous accessor blocks.
    private func arrangeDataForStride(_ data: Data, accessorStride: Int, bufferStride: Int) -> Data {
        var out = Data(capacity: data.count)
        var offset = 0
        while offset + accessorStride <= data.count {
            out.append(data.subdata(in: offset..<(offset + accessorStride)))
            offset += bufferStride
        }
        return out
    }

    public func extractTexture(textureIndex: ImageIndex) throws -> MDLTexture {
        let binaryTextures = gltfContainer.binaryTextures

        guard textureIndex.value < binaryTextures.count else {
            throw NSError(domain: "GLTFContainer", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Texture index out of range"])
        }
        return binaryTextures[textureIndex.value]
    }
}
