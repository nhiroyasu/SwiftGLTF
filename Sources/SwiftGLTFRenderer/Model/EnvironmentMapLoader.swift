import MetalKit
import Img2Cubemap

class EnvironmentMapLoader {
    private let device: MTLDevice
    private let library: MTLLibrary
    private let commandQueue: MTLCommandQueue
    private let shaderConnection: ShaderConnection

    private let IRRADIANCE_SIZE = 32

    init(
        device: MTLDevice,
        library: MTLLibrary,
        commandQueue: MTLCommandQueue,
        shaderConnection: ShaderConnection
    ) {
        self.device = device
        self.commandQueue = commandQueue
        self.library = library
        self.shaderConnection = shaderConnection
    }

    func makeEnvMapHeapAndTexture(url: URL) async throws -> (MTLHeap, MTLTexture, MTLTexture, MTLTexture) {
        let envMap = try await generateCubeTexture(device: device, exr: url)
        let prefilterEnvMapTexture = generatePrefilterEnvMapTexture(
            commandQueue: commandQueue,
            library: library,
            envMap: envMap
        )
        let irradianceCubeMapTexture = generateIrradianceTexture(
            commandQueue: commandQueue,
            library: library,
            envMap: envMap,
            size: IRRADIANCE_SIZE
        )
        let brdfLUT = generateBRDFLUT(
            commandQueue: commandQueue,
            library: library,
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
}
