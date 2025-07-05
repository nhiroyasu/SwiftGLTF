
public class GLTFTextureLoader {
    public let gltf: GLTF
    public let baseURL: URL
    public let loadedTextures: [MDLTexture]

    public init(gltf: GLTF, baseURL: URL, device: MTLDevice) throws {
        self.gltf = gltf
        self.baseURL = baseURL
        self.loadedTextures = try gltf.textures?.compactMap { texture in
            guard let sourceIndex = texture.source else { return nil }
            let image = try loadImage(from: sourceIndex, baseURL: baseURL)
            return try createTexture(from: image, device: device)
        } ?? []
    }

    private func loadImage(from index: Int, baseURL: URL) throws -> CGImage {
        guard let imageData = gltf.images?[index].data else {
            throw NSError(domain: "GLTF", code: -1, userInfo: [NSLocalizedDescriptionKey: "Image data is missing"])
        }
        let imageURL = baseURL.appendingPathComponent(imageData.uri)
        guard let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw NSError(domain: "GLTF", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGImage from source"])
        }
        return cgImage
    }

    private func createTexture(from cgImage: CGImage, device: MTLDevice) throws -> MTLTexture {
        let textureLoader = MTKTextureLoader(device: device)
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: cgImage.width,
            height: cgImage.height,
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead]

        return try textureLoader.newTexture(cgImage: cgImage, options: [
            MTKTextureLoader.Option.origin.rawValue: MTKTextureLoader.Origin.bottomLeft.rawValue,
            MTKTextureLoader.Option.textureUsage.rawValue: textureDescriptor.usage.rawValue
        ])
    }
}
