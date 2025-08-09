import MetalKit
import Img2Cubemap

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

    func makeEnvMapHeapAndTexture(url: URL) async throws -> (MTLHeap, MTLTexture, MTLTexture, MTLTexture) {
        let envMap = try await generateCubeTexture(device: device, exr: url)
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
            throw NSError(
                domain: "EnvironmentMapLoader",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Provided texture is not a cube texture."]
            )
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
}
