import MetalKit
import SwiftGLTFCore

public func checkSwiftGLTFMTKDeviceSupported(device: MTLDevice) throws {
    // Check for argument buffer support
    guard device.argumentBuffersSupport == .tier2 else {
        throw SwiftGLTFError.swiftgltf(description: "Unsupported feature: Metal Argument Buffers Tier 2")
    }
    guard device.supportsFamily(.apple6) || device.supportsFamily(.mac2) else {
        throw SwiftGLTFError.swiftgltf(description: "Unsupported feature: Metal Family Apple6 or Mac2")
    }
}
