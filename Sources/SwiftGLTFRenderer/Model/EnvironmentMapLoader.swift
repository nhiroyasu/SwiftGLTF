import MetalKit
import Img2Cubemap
import SwiftGLTFCore
import SwiftGLTFShaderTypes

public struct EnvMapBundle: Identifiable {
    public let id: UUID = UUID()
    public let heap: MTLHeap
    public let argBuffer: MTLBuffer

    // prevent deallocation of resources
    let _resources: [MTLResource]
}

public class EnvironmentMapLoader {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let library: MTLLibrary
    private let shaderConnection: ShaderConnection

    private let IRRADIANCE_SIZE = 32

    public init(commandQueue: MTLCommandQueue) throws {
        self.device = commandQueue.device
        self.commandQueue = commandQueue
        self.library = try device.makePackageLibrary()
        self.shaderConnection = try ShaderConnection(commandQueue: commandQueue)
    }

    func makeEnvMapHeapAndTexture(url: URL) async throws -> (
        MTLHeap,
        MTLTexture, // prefiltered specular
        MTLTexture, // irradiance
        MTLTexture, // brdfLUT
        MTLTexture  // prefiltered sheen
    ) {
        guard let cubeMapTextureCB = commandQueue.makeDebuggableCommandBuffer(),
              let prefilterEnvMapCB = commandQueue.makeDebuggableCommandBuffer(),
              let irradianceTextureCB = commandQueue.makeDebuggableCommandBuffer(),
              let brdfLUTCB = commandQueue.makeDebuggableCommandBuffer(),
              let sheenEnvMapCB = commandQueue.makeDebuggableCommandBuffer(),
              let blitCB = commandQueue.makeDebuggableCommandBuffer() else {
            throw SwiftGLTFError.makeRender(.commandBufferCreateFailed, context: .capture(stage: .render))
        }

        let (envMap, _) = try encodeGeneratingCubeTexture(
            commandBuffer: cubeMapTextureCB,
            exr: url
        )
        cubeMapTextureCB.commit()

        let prefilterEnvMapTexture = try shaderConnection.encodePrefilterEnvMapTexture(
            prefilterEnvMapCB,
            envMap: envMap
        )
        prefilterEnvMapCB.commit()

        let irradianceCubeMapTexture = try shaderConnection.encodeIrradianceTexture(
            irradianceTextureCB,
            envMap: envMap,
            size: IRRADIANCE_SIZE
        )
        irradianceTextureCB.commit()

        let brdfLUT = try shaderConnection.encodeBRDFLUT(
            brdfLUTCB,
            width: envMap.width,
            height: envMap.height
        )
        brdfLUTCB.commit()

        let prefilterSheenTexture = try shaderConnection.encodePrefilterSheenTexture(
            sheenEnvMapCB,
            envMap: envMap
        )
        sheenEnvMapCB.commit()

        let descriptor = MTLHeapDescriptor()
        descriptor.storageMode = .private
        let prefilterEnvMapDescriptor = newDescriptorFromTexture(prefilterEnvMapTexture, storageMode: .private)
        let irradianceDescriptor = newDescriptorFromTexture(irradianceCubeMapTexture, storageMode: .private)
        let brdfLUTDescriptor = newDescriptorFromTexture(brdfLUT, storageMode: .private)
        let prefilterSheenDescriptor = newDescriptorFromTexture(prefilterSheenTexture, storageMode: .private)

        let prefilterEnvMapSize = device.heapTextureSizeAndAlign(descriptor: prefilterEnvMapDescriptor)
        let irradianceSize = device.heapTextureSizeAndAlign(descriptor: irradianceDescriptor)
        let brdfLUTSize = device.heapTextureSizeAndAlign(descriptor: brdfLUTDescriptor)
        let prefilterSheenSize = device.heapTextureSizeAndAlign(descriptor: prefilterSheenDescriptor)
        descriptor.size = prefilterEnvMapSize.alignedSize +
                            irradianceSize.alignedSize +
                            brdfLUTSize.alignedSize +
                            prefilterSheenSize.alignedSize

        let heap = device.makeHeap(descriptor: descriptor)!
        heap.label = "[SwiftGLTF] Environment Map Heap"

        let results = try shaderConnection.encodeMoveResourcesToHeap(
            blitCB,
            from: [prefilterEnvMapTexture, irradianceCubeMapTexture, brdfLUT, prefilterSheenTexture],
            use: heap
        )
        results[0].label = "[SwiftGLTF] Prefilter Environment Map"
        results[1].label = "[SwiftGLTF] Irradiance Map"
        results[2].label = "[SwiftGLTF] BRDF LUT"
        results[3].label = "[SwiftGLTF] Prefilter Sheen Map"
        blitCB.commit()

        await withTaskGroup { group in
            group.addTask(operation: prefilterEnvMapCB.completed)
            group.addTask(operation: irradianceTextureCB.completed)
            group.addTask(operation: brdfLUTCB.completed)
            group.addTask(operation: sheenEnvMapCB.completed)
            group.addTask(operation: blitCB.completed)
            await group.waitForAll()
        }

        return (
            heap,
            results[0],
            results[1],
            results[2],
            results[3]
        )
    }

    /// Generate IBL from an already cubemap texture
    /// - Parameter cubeTexture: Assumes a `.typeCube` texture.
    /// - Returns: `(heap, prefilteredSpecular, irradiance, brdfLUT)`
    func makeEnvMapHeapAndTexture(fromCube cubeTexture: MTLTexture) throws -> (
        MTLHeap,
        MTLTexture, // prefiltered specular
        MTLTexture, // irradiance
        MTLTexture, // brdfLUT
        MTLTexture  // prefiltered sheen
    ) {
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
        let prefilterSheenTexture = shaderConnection.generatePrefilterSheenTexture(envMap: cubeTexture)

        let descriptor = MTLHeapDescriptor()
        descriptor.storageMode = .private
        let prefilterEnvMapDescriptor = newDescriptorFromTexture(prefilterEnvMapTexture, storageMode: .private)
        let irradianceDescriptor = newDescriptorFromTexture(irradianceCubeMapTexture, storageMode: .private)
        let brdfLUTDescriptor = newDescriptorFromTexture(brdfLUT, storageMode: .private)
        let prefilterSheenDescriptor = newDescriptorFromTexture(prefilterSheenTexture, storageMode: .private)

        let prefilterEnvMapSize = device.heapTextureSizeAndAlign(descriptor: prefilterEnvMapDescriptor)
        let irradianceSize = device.heapTextureSizeAndAlign(descriptor: irradianceDescriptor)
        let brdfLUTSize = device.heapTextureSizeAndAlign(descriptor: brdfLUTDescriptor)
        let prefilterSheenSize = device.heapTextureSizeAndAlign(descriptor: prefilterSheenDescriptor)
        descriptor.size = prefilterEnvMapSize.alignedSize +
                            irradianceSize.alignedSize +
                            brdfLUTSize.alignedSize +
                            prefilterSheenSize.alignedSize

        let heap = device.makeHeap(descriptor: descriptor)!

        let results = try shaderConnection.moveResourcesToHeap(
            from: [prefilterEnvMapTexture, irradianceCubeMapTexture, brdfLUT, prefilterSheenTexture],
            use: heap
        )

        return (
            heap,
            results[0],
            results[1],
            results[2],
            results[3]
        )
    }

    func makeEnvMapHeapAndTexture(from color: CGColor) throws -> (
        MTLHeap,
        MTLTexture, // prefiltered specular
        MTLTexture, // irradiance
        MTLTexture, // brdfLUT
        MTLTexture  // prefiltered sheen
    ) {
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
            results[0],
            results[0]
        )
    }

    public func makeEnvMapBundle(from url: URL) async throws -> EnvMapBundle {
        let (
            envMapHeap,
            prefilterEnvMap,
            irradianceMap,
            brdfLUT,
            prefilterSheenMap
        ) = try await makeEnvMapHeapAndTexture(url: url)

        return makeEnvMapBundle(
            heap: envMapHeap,
            prefilterEnvMap: prefilterEnvMap,
            irradianceMap: irradianceMap,
            brdfLUT: brdfLUT,
            prefilterSheenMap: prefilterSheenMap
        )
    }

    func makeEnvMapBundle(from cgColor: CGColor) throws -> EnvMapBundle {
        let (
            envMapHeap,
            prefilterEnvMap,
            irradianceMap,
            brdfLUT,
            prefilterSheenMap
        ) = try makeEnvMapHeapAndTexture(from: cgColor)

        return makeEnvMapBundle(
            heap: envMapHeap,
            prefilterEnvMap: prefilterEnvMap,
            irradianceMap: irradianceMap,
            brdfLUT: brdfLUT,
            prefilterSheenMap: prefilterSheenMap
        )
    }

    // MARK: - Helper

    private func makeEnvMapBundle(
        heap: MTLHeap,
        prefilterEnvMap: MTLTexture,
        irradianceMap: MTLTexture,
        brdfLUT: MTLTexture,
        prefilterSheenMap: MTLTexture
    ) -> EnvMapBundle {
        let envMapArgBuffer = device.makeBuffer(
            length: MemoryLayout<PBREnvMapArguments>.size,
            options: [.storageModeShared]
        )!
        let envMapArg = envMapArgBuffer.contents().bindMemory(to: PBREnvMapArguments.self, capacity: 1)
        envMapArg.pointee.prefilterEnvMap = prefilterEnvMap.gpuResourceID
        envMapArg.pointee.irradianceMap = irradianceMap.gpuResourceID
        envMapArg.pointee.brdfLUT = brdfLUT.gpuResourceID
        envMapArg.pointee.prefilterSheenMap = prefilterSheenMap.gpuResourceID

        return EnvMapBundle(
            heap: heap,
            argBuffer: envMapArgBuffer,
            _resources: [prefilterEnvMap, irradianceMap, brdfLUT, prefilterSheenMap]
        )
    }
}
