import MetalKit
import SwiftGLTFCore

func makeLessEqualDepthStencilState(device: MTLDevice) throws -> MTLDepthStencilState {
    let descriptor = MTLDepthStencilDescriptor()
    descriptor.label = "[SwiftGLTF] lessEqualDepthStencilState"
    descriptor.depthCompareFunction = .lessEqual
    descriptor.isDepthWriteEnabled = true

    guard let depthStencilState = device.makeDepthStencilState(descriptor: descriptor) else {
        throw SwiftGLTFError.makeRender(.depthStencilStateCreateFailed(writeEnabled: true), context: .capture(stage: .render))
    }
    return depthStencilState
}

func makeLessEqualNoWriteDepthStencilState(device: MTLDevice) throws -> MTLDepthStencilState {
    let descriptor = MTLDepthStencilDescriptor()
    descriptor.label = "[SwiftGLTF] lessEqualNoWriteDepthStencilState"
    descriptor.depthCompareFunction = .lessEqual
    descriptor.isDepthWriteEnabled = false

    guard let depthStencilState = device.makeDepthStencilState(descriptor: descriptor) else {
        throw SwiftGLTFError.makeRender(.depthStencilStateCreateFailed(writeEnabled: false), context: .capture(stage: .render))
    }
    return depthStencilState
}
