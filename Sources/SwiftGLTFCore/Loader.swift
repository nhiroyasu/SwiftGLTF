import Foundation
import ModelIO
import MetalKit
import simd
import Accelerate

/// Extracts the raw Data from a Data URI string (base64 encoded)
func dataFromDataURI(_ uri: String) throws -> Data {
    // Extract base64 string after comma
    guard let comma = uri.firstIndex(of: ",") else {
        throw SwiftGLTFError.makeIO(.invalidDataURI, context: .capture(stage: .io))
    }
    let b64 = String(uri[uri.index(after: comma)...])
    guard let data = Data(base64Encoded: b64) else {
        throw SwiftGLTFError.makeIO(.base64DecodeFailed, context: .capture(stage: .io))
    }
    return data
}

func makeMDLTexture(from data: Data, name: String) throws -> MDLTexture {
    guard
        let src = CGImageSourceCreateWithData(data as CFData, nil),
        let cgImage = CGImageSourceCreateImageAtIndex(src, 0, nil)
    else { throw SwiftGLTFError.makeIO(.makeCGImageFailed, context: .capture(stage: .decode)) }

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
        throw SwiftGLTFError.makeIO(.invalidCGImageFormat, context: .capture(stage: .decode))
    }

    var buffer = vImage_Buffer()
    let kvFlags = vImage_Flags(kvImageNoFlags)
    let initErr = vImageBuffer_InitWithCGImage(&buffer, &format, nil, cgImage, kvFlags)
    guard initErr == kvImageNoError else { throw SwiftGLTFError.makeIO(.vImageBufferInitFailed, context: .capture(stage: .decode)) }

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

private func loadFromGLB(_ data: Data) throws -> GLTFBundle {
    guard data.count >= 12 else {
        throw SwiftGLTFError.makeIO(.glbTooShort, context: .capture(stage: .decode))
    }

    let magic = data.prefix(4)
    let expectedMagic = Data([0x67, 0x6C, 0x54, 0x46])
    guard magic == expectedMagic else {
        throw SwiftGLTFError.makeIO(.glbInvalidMagic, context: .capture(stage: .decode))
    }

    let version: UInt32 = data[4..<8].withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
    guard version == 2 else {
        throw SwiftGLTFError.makeIO(.glbUnsupportedVersion(Int(version)), context: .capture(stage: .decode))
    }

    let totalLength: UInt32 = data[8..<12].withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
    guard totalLength == data.count else {
        throw SwiftGLTFError.makeIO(.glbLengthMismatch, context: .capture(stage: .decode))
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
            throw SwiftGLTFError.makeIO(.glbChunkOutOfBounds, context: .capture(stage: .decode))
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
        throw SwiftGLTFError.makeIO(.glbJSONChunkMissing, context: .capture(stage: .decode))
    }
    let decoder = JSONDecoder()
    let gltf = try decoder.decode(GLTF.self, from: jsonChunk)

    guard let binChunk else {
        throw SwiftGLTFError.makeIO(.glbBINChunkMissing, context: .capture(stage: .decode))
    }

    // Extract embedded images from bufferViews
    var textures: [MDLTexture] = []
    if let images = gltf.images {
        guard let bufferViews = gltf.bufferViews else {
            throw SwiftGLTFError.makeIO(.imageBufferViewMissing(index: 0), context: .capture(stage: .decode))
        }
        for (idx, image) in images.enumerated() {
            if let bvIndex = image.bufferView?.value {
                let bv = bufferViews[bvIndex]

                let start = bv.byteOffset
                let length = bv.byteLength
                let imageData = binChunk.subdata(in: start..<(start + length))
                let texture = try makeMDLTexture(from: imageData, name: "Texture_\(idx)")
                textures.append(texture)
            } else {
                throw SwiftGLTFError.makeIO(.imageBufferViewMissing(index: idx), context: .capture(stage: .decode))
            }
        }
    }
    return GLTFBundle(gltf: gltf, binaryBuffers: [binChunk], binaryTextures: textures)
}

private func loadFromGLTF(_ data: Data, baseURL: URL) throws -> GLTFBundle {
    let decoder = JSONDecoder()
    let gltf = try decoder.decode(GLTF.self, from: data)

    var buffers: [Data] = []
    for buffer in (gltf.buffers ?? []) {
        // Load buffer data (data URI or external file)
        let data: Data
        if let uri = buffer.uri, let url = URL(string: uri, relativeTo: baseURL) {
            if uri.hasPrefix("data:") {
                // Data URI: data:<mime>;base64,<data>
                guard let comma = uri.firstIndex(of: ",") else {
                    throw SwiftGLTFError.makeIO(.invalidDataURI, context: .capture(stage: .io))
                }
                let b64 = String(uri[uri.index(after: comma)...])
                guard let decoded = Data(base64Encoded: b64) else {
                    throw SwiftGLTFError.makeIO(.base64DecodeFailed, context: .capture(stage: .io))
                }
                data = decoded
            } else {
                data = try Data(contentsOf: url)
            }
        } else {
            throw SwiftGLTFError.makeIO(.bufferURIMissing, context: .capture(stage: .io))
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
                throw SwiftGLTFError.makeIO(.imageURIMissingOrInvalid, context: .capture(stage: .io))
            }
        } else {
            throw SwiftGLTFError.makeIO(.imageURIMissingOrInvalid, context: .capture(stage: .io))
        }
    }
    return GLTFBundle(gltf: gltf, binaryBuffers: buffers, binaryTextures: textures)
}

public func loadGLTF(from data: Data, baseURL: URL) throws -> GLTFBundle {
    if isGLB(data) {
        // Load GLB: parse JSON and binary chunks
        return try loadFromGLB(data)
    } else {
        // Load glTF: parse JSON and load buffers
        return try loadFromGLTF(data, baseURL: baseURL)
    }
}

public class GLTFBinaryLoader {
    private let gltfBundle: GLTFBundle

    public init(gltfBundle: GLTFBundle) {
        self.gltfBundle = gltfBundle
    }

    /// Extracts raw data for the given accessor index.
    /// - Throws: error if accessor or buffer view is invalid, or data out-of-bounds.
    public func extractData(accessorIndex: AccessorIndex) throws -> Data {
        let gltf = gltfBundle.gltf
        let binaryBuffers = gltfBundle.binaryBuffers

        guard let accessors = gltf.accessors, accessorIndex.value < accessors.count else {
            throw SwiftGLTFError.makeIO(.bufferIndexOutOfRange, context: .capture(stage: .decode))
        }
        let accessor = accessors[accessorIndex.value]
        guard let bufferViews = gltf.bufferViews,
              let bvIndex = accessor.bufferView?.value,
              bvIndex < bufferViews.count else {
            throw SwiftGLTFError.makeIO(.bufferIndexOutOfRange, context: .capture(stage: .decode))
        }
        let bv = bufferViews[bvIndex]
        let bufIdx = bv.buffer.value
        guard bufIdx < binaryBuffers.count else {
            throw SwiftGLTFError.makeIO(.bufferIndexOutOfRange, context: .capture(stage: .decode))
        }
        let bufferData = binaryBuffers[bufIdx]
        let baseOffset = accessor.byteOffset + bv.byteOffset
        let accessorStride = accessor.type.components * accessor.componentType.size
        let bufferStride = bv.byteStride ?? accessorStride
        let totalLength = accessor.count * bufferStride
        let diffStride = bufferStride - accessorStride
        let endOffset = baseOffset + totalLength - diffStride
        guard endOffset <= bufferData.count else {
            throw SwiftGLTFError.makeIO(.bufferOverrun, context: .capture(stage: .decode))
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
        let binaryTextures = gltfBundle.binaryTextures

        guard textureIndex.value < binaryTextures.count else {
            throw SwiftGLTFError.makeIO(.textureIndexOutOfRange, context: .capture(stage: .decode))
        }
        return binaryTextures[textureIndex.value]
    }
}
