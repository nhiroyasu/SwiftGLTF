import Foundation
import ModelIO
import OSLog

public class GLTFTextureLoader {
    private let gltf: GLTF
    private let loadedTextures: [Int: MDLTexture?]

    public init(gltf: GLTF, baseURL: URL) {
        self.gltf = gltf
        os_log("Preloading textures", log: .default, type: .info)
        var textures: [Int: MDLTexture] = [:]
        for (index, image) in (gltf.images ?? []).enumerated() {
            if let uri = image.uri, let url = URL(string: uri, relativeTo: baseURL) {
                let tex = MDLURLTexture(url: url, name: image.name ?? "Texture_\(index)")
                textures[index] = tex
            } else {
                textures[index] = nil
            }
        }
        loadedTextures = textures
        os_log("Preloaded %{public}d textures", log: .default, type: .info, textures.count)
    }

    public func texture(for sourceIndex: Int) -> MDLTexture? {
        loadedTextures[sourceIndex] ?? nil
    }
}
