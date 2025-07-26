import MetalKit
import OSLog
import SwiftGLTF

enum DepthStencilType: String {
    case lessThan
    case always
}

public class DepthStencilStateLoader {
    private let device: MTLDevice
    private var cachedDSOs: [DepthStencilType: MTLDepthStencilState] = [:]

    public init(device: MTLDevice) {
        self.device = device
    }

    func load(
        for type: DepthStencilType,
        useCache: Bool = true
    ) throws -> MTLDepthStencilState {
        if useCache, let cachedState = cachedDSOs[type] {
            return cachedState
        }

        let dso: MTLDepthStencilState
        switch type {
        case .lessThan:
            let descriptor = MTLDepthStencilDescriptor()
            descriptor.label = "Less Than Depth Stencil State"
            descriptor.depthCompareFunction = .less
            descriptor.isDepthWriteEnabled = true
            
            if let depthStencilState = device.makeDepthStencilState(descriptor: descriptor) {
                dso = depthStencilState
            } else {
                throw NSError(domain: "DepthStencilStateLoader", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create depth stencil state"])
            }
        case .always:
            let descriptor = MTLDepthStencilDescriptor()
            descriptor.label = "Always Depth Stencil State"
            descriptor.depthCompareFunction = .always
            descriptor.isDepthWriteEnabled = false
            
            if let depthStencilState = device.makeDepthStencilState(descriptor: descriptor) {
                dso = depthStencilState
            } else {
                throw NSError(domain: "DepthStencilStateLoader", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create depth stencil state"])
            }
        }

        cachedDSOs[type] = dso
        return dso
    }
}
