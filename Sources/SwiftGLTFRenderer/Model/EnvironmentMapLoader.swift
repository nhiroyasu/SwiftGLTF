import MetalKit
import Img2Cubemap
import SwiftGLTFCore

class EnvironmentMapLoader {
    private let device: MTLDevice
    private let library: MTLLibrary
    private let shaderConnection: ShaderConnection

    private let IRRADIANCE_SIZE = 32

    init(
        device: MTLDevice,
        library: MTLLibrary,
        shaderConnection: ShaderConnection
    ) {
        self.device = device
        self.library = library
        self.shaderConnection = shaderConnection
    }

    func makeEnvMapHeapAndTexture(url: URL) throws -> (MTLHeap, MTLTexture, MTLTexture, MTLTexture) {
        let envMap = try generateCubeTexture(device: device, exr: url)
        let prefilterEnvMapTexture = shaderConnection.generatePrefilterEnvMapTexture(envMap: envMap)
        let irradianceCubeMapTexture = shaderConnection.generateIrradianceTexture(
            envMap: envMap,
            size: IRRADIANCE_SIZE
        )
        let brdfLUT = shaderConnection.generateBRDFLUT(
            width: envMap.width,
            height: envMap.height
        )

        let descriptor = MTLHeapDescriptor()
        descriptor.storageMode = .private
        let prefilterEnvMapDescriptor = newDescriptorFromTexture(prefilterEnvMapTexture, storageMode: .private)
        let irradianceDescriptor = newDescriptorFromTexture(irradianceCubeMapTexture, storageMode: .private)
        let brdfLUTDescriptor = newDescriptorFromTexture(brdfLUT, storageMode: .private)
        let prefilterEnvMapSize = device.heapTextureSizeAndAlign(descriptor: prefilterEnvMapDescriptor)
        let irradianceSize = device.heapTextureSizeAndAlign(descriptor: irradianceDescriptor)
        let brdfLUTSize = device.heapTextureSizeAndAlign(descriptor: brdfLUTDescriptor)
        descriptor.size = prefilterEnvMapSize.alignedSize +
                            irradianceSize.alignedSize +
                            brdfLUTSize.alignedSize

        let heap = device.makeHeap(descriptor: descriptor)!

        let results = try shaderConnection.moveResourcesToHeap(
            from: [prefilterEnvMapTexture, irradianceCubeMapTexture, brdfLUT],
            use: heap
        )

        return (
            heap,
            results[0],
            results[1],
            results[2]
        )
    }

    /// Generate IBL from an already cubemap texture
    /// - Parameter cubeTexture: Assumes a `.typeCube` texture.
    /// - Returns: `(heap, prefilteredSpecular, irradiance, brdfLUT)`
    func makeEnvMapHeapAndTexture(fromCube cubeTexture: MTLTexture) throws -> (MTLHeap, MTLTexture, MTLTexture, MTLTexture) {
        guard cubeTexture.textureType == .typeCube else {
            throw SwiftGLTFError.makeRender(.cubeTextureExpected, context: .capture(stage: .render))
        }
        
        let prefilterEnvMapTexture = shaderConnection.generatePrefilterEnvMapTexture(envMap: cubeTexture)
        let irradianceCubeMapTexture = shaderConnection.generateIrradianceTexture(
            envMap: cubeTexture,
            size: IRRADIANCE_SIZE
        )
        let brdfLUT = shaderConnection.generateBRDFLUT(
            width: cubeTexture.width,
            height: cubeTexture.height
        )

        let descriptor = MTLHeapDescriptor()
        descriptor.storageMode = .private
        let prefilterEnvMapDescriptor = newDescriptorFromTexture(prefilterEnvMapTexture, storageMode: .private)
        let irradianceDescriptor = newDescriptorFromTexture(irradianceCubeMapTexture, storageMode: .private)
        let brdfLUTDescriptor = newDescriptorFromTexture(brdfLUT, storageMode: .private)
        let prefilterEnvMapSize = device.heapTextureSizeAndAlign(descriptor: prefilterEnvMapDescriptor)
        let irradianceSize = device.heapTextureSizeAndAlign(descriptor: irradianceDescriptor)
        let brdfLUTSize = device.heapTextureSizeAndAlign(descriptor: brdfLUTDescriptor)
        descriptor.size = prefilterEnvMapSize.alignedSize +
                            irradianceSize.alignedSize +
                            brdfLUTSize.alignedSize

        let heap = device.makeHeap(descriptor: descriptor)!

        let results = try shaderConnection.moveResourcesToHeap(
            from: [prefilterEnvMapTexture, irradianceCubeMapTexture, brdfLUT],
            use: heap
        )

        return (
            heap,
            results[0],
            results[1],
            results[2]
        )
    }

    func makeEnvMapHeapAndTexture(from color: CGColor) throws -> (MTLHeap, MTLTexture, MTLTexture, MTLTexture) {
        let size = 1
        let descriptor = MTLTextureDescriptor.textureCubeDescriptor(
            pixelFormat: .rgba8Unorm,
            size: size,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        guard let cubeTexture = device.makeTexture(descriptor: descriptor) else {
            throw SwiftGLTFError.makeRender(.cubeTextureCreateFailed, context: .capture(stage: .render))
        }

        let red: UInt8
        let green: UInt8
        let blue: UInt8
        if let components = color.components {
            if color.numberOfComponents >= 3 {
                red = UInt8(components[0] * 255)
                green = UInt8(components[1] * 255)
                blue = UInt8(components[2] * 255)
            } else if color.numberOfComponents >= 1 {
                red = UInt8(components[0] * 255)
                green = red
                blue = red
            } else {
                red = 255
                green = 255
                blue = 255
            }
        } else {
            red = 255
            green = 255
            blue = 255
        }
        let alpha: UInt8 = 255
        let color = [red, green, blue, alpha]
        let colorData: [UInt8] = Array(repeating: color, count: size * size).flatMap { $0 }
        let region = MTLRegionMake2D(0, 0, size, size)
        for face in 0..<6 {
            cubeTexture.replace(
                region: region,
                mipmapLevel: 0,
                slice: face,
                withBytes: colorData,
                bytesPerRow: size * 4,
                bytesPerImage: size * size * 4
            )
        }

        let heapDescriptor = MTLHeapDescriptor()
        heapDescriptor.storageMode = .private
        let texSize = device.heapTextureSizeAndAlign(descriptor: descriptor)
        heapDescriptor.size = texSize.alignedSize

        let heap = device.makeHeap(descriptor: heapDescriptor)!

        let results = try shaderConnection.moveResourcesToHeap(
            from: [cubeTexture],
            use: heap
        )

        return (
            heap,
            results[0],
            results[0],
            results[0]
        )
    }
}
