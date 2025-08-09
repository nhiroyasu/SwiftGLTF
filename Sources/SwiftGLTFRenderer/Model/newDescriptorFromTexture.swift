import MetalKit

func newDescriptorFromTexture(_ texture: MTLTexture, storageMode: MTLStorageMode) -> MTLTextureDescriptor {
    let descriptor = MTLTextureDescriptor()
    descriptor.textureType      = texture.textureType
    descriptor.pixelFormat      = texture.pixelFormat
    descriptor.width            = texture.width
    descriptor.height           = texture.height
    descriptor.depth            = texture.depth
    descriptor.mipmapLevelCount = texture.mipmapLevelCount
    descriptor.arrayLength      = texture.arrayLength
    descriptor.sampleCount      = texture.sampleCount
    descriptor.storageMode      = storageMode
    return descriptor
}
