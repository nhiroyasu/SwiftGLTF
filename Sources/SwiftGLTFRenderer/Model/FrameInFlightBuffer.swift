import MetalKit

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
