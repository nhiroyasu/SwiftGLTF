import Foundation
import ModelIO
import ImageIO
import CoreGraphics
import simd

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

/// Creates an MDLTexture directly from a Data URI string containing image data
func mdlTextureFromDataURI(_ uri: String, name: String) throws -> MDLTexture {
    let imageData = try dataFromDataURI(uri)
    guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
        throw NSError(domain: "GLTF", code: -1,
                      userInfo: [NSLocalizedDescriptionKey: "Failed to create image from data URI"])
    }
    // Render CGImage into raw RGBA8 buffer
    let width = cgImage.width
    let height = cgImage.height
    let bytesPerPixel = 4
    let bytesPerRow = bytesPerPixel * width
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    guard let context = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                  space: colorSpace, bitmapInfo: bitmapInfo) else {
        throw NSError(domain: "GLTF", code: -1,
                      userInfo: [NSLocalizedDescriptionKey: "Failed to create CGContext for image"])
    }
    let rect = CGRect(x: 0, y: 0, width: width, height: height)
    context.draw(cgImage, in: rect)
    guard let dataPtr = context.data else {
        throw NSError(domain: "GLTF", code: -1,
                      userInfo: [NSLocalizedDescriptionKey: "Failed to access image pixel data"])
    }
    let pixelData = Data(bytes: dataPtr, count: bytesPerRow * height)
    // Create MDLTexture from raw data, flip origin
    let dims = vector_int2(Int32(width), Int32(height))
    let texture = MDLTexture(data: pixelData,
                             topLeftOrigin: false,
                             name: name,
                             dimensions: dims,
                             rowStride: bytesPerRow,
                             channelCount: bytesPerPixel,
                             channelEncoding: .uInt8,
                             isCube: false)
    return texture
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

                if let cgSource = CGImageSourceCreateWithData(imageData as CFData, nil),
                   let cgImage = CGImageSourceCreateImageAtIndex(cgSource, 0, nil) {
                    let properties = CGImageSourceCopyPropertiesAtIndex(cgSource, 0, nil) as? [CFString: Any]
                    let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 1
                    let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 1
                    let bitsPerComponent = properties?[kCGImagePropertyDepth] as? Int ?? 8
                    let channelCount = 4 // TODO: handle different formats
                    let bytesPerRow = Int(width) * channelCount

                    let colorSpace: CGColorSpace = switch properties?[kCGImagePropertyProfileName] as? String {
                    case "sRGB IEC61966-2.1": CGColorSpace(name: CGColorSpace.sRGB)!
                    case "Display P3": CGColorSpace(name: CGColorSpace.displayP3)!
                    case "Adobe RGB (1998)": CGColorSpace(name: CGColorSpace.adobeRGB1998)!
                    default: CGColorSpaceCreateDeviceRGB()
                    }

                    var rawData = Data(count: Int(height) * bytesPerRow)
                    rawData.withUnsafeMutableBytes { ptr in
                        if let context = CGContext(
                            data: ptr.baseAddress,
                            width: width,
                            height: height,
                            bitsPerComponent: bitsPerComponent,
                            bytesPerRow: bytesPerRow,
                            space: colorSpace,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                        ) {
                            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
                        }
                    }

                    let channelEncoding: MDLTextureChannelEncoding = switch image.mimeType {
                    case "image/png", "image/jpeg", "image/tiff":
                       switch bitsPerComponent {
                       case 8: .uInt8
                       case 16: .uint16
                       default: throw NSError(domain: "SwiftGLTF", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unsupported bits per component: \(bitsPerComponent)"])
                       }
                    default:
                        throw NSError(domain: "SwiftGLTF", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unsupported image MIME type: \(image.mimeType ?? "unknown")"])
                    }

                    let texture = MDLTexture(
                        data: rawData,
                        topLeftOrigin: false,
                        name: "Texture_\(idx)",
                        dimensions: vector_int2(Int32(width), Int32(height)),
                        rowStride: bytesPerRow, // Assuming RGBA format,
                        channelCount: channelCount, // TODO: handle different formats
                        channelEncoding: channelEncoding, // TODO: handle different encodings
                        isCube: false
                    )
                    textures.append(texture)
                } else {
                    throw NSError(domain: "SwiftGLTF", code: -1,
                                  userInfo: [NSLocalizedDescriptionKey: "Failed to create CGImageSource for image \(idx)"])
                }
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
                // Data URI texture
                let texture = try mdlTextureFromDataURI(uri, name: "Texture_\(idx)")
                textures.append(texture)
            } else if let url = URL(string: uri, relativeTo: baseURL) {
                let texture = MDLURLTexture(url: url, name: "Texture_\(idx)")
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
        let endOffset = baseOffset + totalLength
        guard endOffset <= bufferData.count else {
            throw NSError(domain: "GLTFContainer", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Buffer overrun in accessor data"])
        }
        var slice = bufferData.subdata(in: baseOffset..<endOffset)
        if bufferStride != accessorStride {
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
