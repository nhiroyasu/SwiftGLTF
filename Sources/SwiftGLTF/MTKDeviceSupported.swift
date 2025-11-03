import MetalKit
import SwiftGLTFCore

public func isMTKDeviceSupported(device: MTLDevice) throws {
    // Check for argument buffer support
    if device.argumentBuffersSupport == .tier2 {
        throw SwiftGLTFError.makeRender(
            .unsupportedFeature(description: "Metal Argument Buffers Tier 2"),
            context: .capture(stage: .initialization)
        )
    }
}
