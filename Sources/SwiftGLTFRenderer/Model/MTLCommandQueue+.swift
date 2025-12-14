import Metal
import OSLog

extension MTLCommandQueue {
    func makeDebuggableCommandBuffer() -> MTLCommandBuffer? {
        #if DEBUG
        let desc = MTLCommandBufferDescriptor()
        desc.errorOptions = .encoderExecutionStatus
        let buffer = self.makeCommandBuffer(descriptor: desc)
        buffer?.label = "[SwiftGLTF] Common Command Buffer in SwiftGLTFRenderer"
        buffer?.addCompletedHandler { cb in
            switch cb.status {
            case .error:
                Log.common.error("[SwiftGLTF] Renderer: Command buffer completed with error: \(String(describing: cb.error), privacy: .public)")
                if let error = cb.error as? NSError {
                    Log.common.error("[SwiftGLTF] Renderer: Metal error domain: \(String(describing: error.userInfo[MTLCommandBufferEncoderInfoErrorKey]), privacy: .public)")
                }
            default:
                break
            }
        }
        return buffer
        #else
        return self.makeCommandBuffer()
        #endif
    }
}
