import MetalKit
import SwiftGLTFCore

public func checkSwiftGLTFMTKDeviceSupported(device: MTLDevice) throws {
    // Check for argument buffer support
    guard device.argumentBuffersSupport == .tier2 else {
        throw SwiftGLTFError.makeRender(
            .unsupportedFeature(description: "Metal Argument Buffers Tier 2"),
            context: .capture(stage: .initialization)
        )
    }
    guard device.supportsFamily(.apple6) || device.supportsFamily(.mac2) else {
        throw SwiftGLTFError.makeRender(
            .unsupportedFeature(description: "Metal Family Apple6 or Mac2"),
            context: .capture(stage: .initialization)
        )
    }
}
