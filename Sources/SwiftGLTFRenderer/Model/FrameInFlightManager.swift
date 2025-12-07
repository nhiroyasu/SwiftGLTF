import Metal
import SwiftGLTFShaderTypes

class FrameInFlightBuffer {
    private let maxFramesInFlight: Int
    private let buffers: [MTLBuffer]

    init(maxFramesInFlight: Int, initialBuffer: () -> MTLBuffer) {
        self.maxFramesInFlight = maxFramesInFlight
        self.buffers = (0..<maxFramesInFlight).map { _ in
            initialBuffer()
        }
    }

    func buffer(_ index: Int) -> MTLBuffer {
        return buffers[index % maxFramesInFlight]
    }

    func updateBuffer(_ index: Int, from data: UnsafeRawPointer, byteCount: Int) {
        let buffer = buffers[index % maxFramesInFlight]
        buffer.contents().copyMemory(from: data, byteCount: byteCount)
    }
}

struct PBRFrameInFlightResources {
    let sceneUniformsBuffer: MTLBuffer
    let modelMatrixBuffer: MTLBuffer
    let cameraIndexBuffer: MTLBuffer
    let freeCameraUniformsBuffer: MTLBuffer
}

class PBRFrameInFlightManager {
    private let sceneUniformsBuffer: FrameInFlightBuffer
    private let modelMatrixBuffer: FrameInFlightBuffer
    private let cameraIndexBuffer: FrameInFlightBuffer
    private let freeCameraUniformsBuffer: FrameInFlightBuffer
    private let maxFramesInFlight: Int
    private var currentFrameIndex: Int = 0

    init(device: MTLDevice, maxFramesInFlight: Int = 2) {
        self.maxFramesInFlight = maxFramesInFlight
        self.sceneUniformsBuffer = FrameInFlightBuffer(maxFramesInFlight: maxFramesInFlight) {
            device.makeBuffer(
                length: MemoryLayout<SceneUniforms>.size,
                options: .storageModeShared
            )!
        }
        self.modelMatrixBuffer = FrameInFlightBuffer(maxFramesInFlight: maxFramesInFlight) {
            device.makeBuffer(
                length: MemoryLayout<float4x4>.size,
                options: .storageModeShared
            )!
        }
        self.cameraIndexBuffer = FrameInFlightBuffer(maxFramesInFlight: maxFramesInFlight) {
            device.makeBuffer(
                length: MemoryLayout<Int>.size,
                options: .storageModeShared
            )!
        }
        self.freeCameraUniformsBuffer = FrameInFlightBuffer(maxFramesInFlight: maxFramesInFlight) {
            device.makeBuffer(
                length: MemoryLayout<FreeCameraUniforms>.size,
                options: .storageModeShared
            )!
        }
    }

    private func _updateFrame() {
        currentFrameIndex = (currentFrameIndex + 1) % maxFramesInFlight
    }

    func currentResources() -> PBRFrameInFlightResources {
        return .init(
            sceneUniformsBuffer: sceneUniformsBuffer.buffer(currentFrameIndex),
            modelMatrixBuffer: modelMatrixBuffer.buffer(currentFrameIndex),
            cameraIndexBuffer: cameraIndexBuffer.buffer(currentFrameIndex),
            freeCameraUniformsBuffer: freeCameraUniformsBuffer.buffer(currentFrameIndex)
        )
    }

    func currentResourcesWith(
        modelMatrix: float4x4,
        sceneUniforms: SceneUniforms,
        cameraIndex: Int?,
        freeCameraUniforms: FreeCameraUniforms
    ) -> PBRFrameInFlightResources {
        let currentResources = currentResources()

        var modelMatrix = modelMatrix
        currentResources.modelMatrixBuffer.contents().copyMemory(
            from: &modelMatrix,
            byteCount: MemoryLayout<float4x4>.size
        )

        var sceneUniforms = sceneUniforms
        currentResources.sceneUniformsBuffer.contents().copyMemory(
            from: &sceneUniforms,
            byteCount: MemoryLayout<SceneUniforms>.size
        )

        var bCameraIndex = cameraIndex ?? -1
        currentResources.cameraIndexBuffer.contents().copyMemory(
            from: &bCameraIndex,
            byteCount: MemoryLayout<Int>.size
        )

        var freeCameraUniforms = freeCameraUniforms
        currentResources.freeCameraUniformsBuffer.contents().copyMemory(
            from: &freeCameraUniforms,
            byteCount: MemoryLayout<FreeCameraUniforms>.size
        )

        _updateFrame()
        return currentResources
    }
}
