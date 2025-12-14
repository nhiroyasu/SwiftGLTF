import Metal
import os.log

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
                os_log("[SwiftGLTF] Renderer: Command buffer completed with error: %@", type: .error, String(describing: cb.error))
                if let error = cb.error as? NSError {
                    os_log("[SwiftGLTF] Renderer: Metal error domain: %@", type: .error, String(describing: error.userInfo[MTLCommandBufferEncoderInfoErrorKey]))
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
