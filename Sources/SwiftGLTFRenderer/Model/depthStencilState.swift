import MetalKit

func makeLessEqualDepthStencilState(device: MTLDevice) throws -> MTLDepthStencilState {
    let descriptor = MTLDepthStencilDescriptor()
    descriptor.label = "[SwiftGLTF] lessEqualDepthStencilState"
    descriptor.depthCompareFunction = .lessEqual
    descriptor.isDepthWriteEnabled = true

    guard let depthStencilState = device.makeDepthStencilState(descriptor: descriptor) else {
        throw NSError(domain: "SwiftGLTFRenderer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create depth stencil state"])
    }
    return depthStencilState
}
