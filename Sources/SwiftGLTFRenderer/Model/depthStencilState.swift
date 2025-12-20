import MetalKit
import SwiftGLTFCore

func makeLessEqualDepthStencilState(device: MTLDevice) throws -> MTLDepthStencilState {
    let descriptor = MTLDepthStencilDescriptor()
    descriptor.label = "[SwiftGLTF] lessEqualDepthStencilState"
    descriptor.depthCompareFunction = .lessEqual
    descriptor.isDepthWriteEnabled = true

    guard let depthStencilState = device.makeDepthStencilState(descriptor: descriptor) else {
        throw SwiftGLTFRendererError(description: "Failed to create depth stencil state (writeEnabled=true)")
    }
    return depthStencilState
}

func makeLessEqualNoWriteDepthStencilState(device: MTLDevice) throws -> MTLDepthStencilState {
    let descriptor = MTLDepthStencilDescriptor()
    descriptor.label = "[SwiftGLTF] lessEqualNoWriteDepthStencilState"
    descriptor.depthCompareFunction = .lessEqual
    descriptor.isDepthWriteEnabled = false

    guard let depthStencilState = device.makeDepthStencilState(descriptor: descriptor) else {
        throw SwiftGLTFRendererError(description: "Failed to create depth stencil state (writeEnabled=false)")
    }
    return depthStencilState
}
