import MetalKit
import OSLog

public class PBRPipelineStateLoader {
    private let device: MTLDevice
    private let library: MTLLibrary
    private let config: PipelineStateLoaderConfig

    private let fragmentFunction: MTLFunction
    private var cachedPipelineStates: [MDLVertexDescriptor: MTLRenderPipelineState] = [:]

    public init(
        device: MTLDevice,
        library: MTLLibrary,
        config: PipelineStateLoaderConfig = PipelineStateLoaderConfig()
    ) {
        self.device = device
        self.library = library
        self.config = config
        self.fragmentFunction = library.makeFunction(name: "pbr_shader")!
    }

    func load(
        for vertexDescriptor: MDLVertexDescriptor,
        useCache: Bool = true
    ) throws -> MTLRenderPipelineState {
        if useCache, let cachedState = cachedPipelineStates[vertexDescriptor] {
            return cachedState
        }

        let psoDescriptor = MTLRenderPipelineDescriptor()
        psoDescriptor.vertexFunction = try decideVertexShader(from: vertexDescriptor)
        psoDescriptor.fragmentFunction = fragmentFunction
        psoDescriptor.colorAttachments[0].pixelFormat = config.colorPixelFormat
        psoDescriptor.depthAttachmentPixelFormat = config.depthPixelFormat
        psoDescriptor.rasterSampleCount = config.sampleCount
        psoDescriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(vertexDescriptor)

        let pso = try device.makeRenderPipelineState(descriptor: psoDescriptor)
        cachedPipelineStates[vertexDescriptor] = pso
        return pso
    }

    private func decideVertexShader(from vertexDescriptor: MDLVertexDescriptor) throws -> MTLFunction {
        var existingPosition: Bool = false
        var existingNormal: Bool = false
        var existingTangent: Bool = false
        var existingModulationColor: Bool = false
        var existingTextureCoordinate: Bool = false

        for attr in vertexDescriptor.attributes {
            if let attr = attr as? MDLVertexAttribute {
                if attr.name == MDLVertexAttributePosition {
                    existingPosition = true
                }
                if attr.name == MDLVertexAttributeNormal {
                    existingNormal = true
                }
                if attr.name == MDLVertexAttributeTangent {
                    existingTangent = true
                }
                if attr.name == MDLVertexAttributeColor {
                    existingModulationColor = true
                }
                if attr.name == MDLVertexAttributeTextureCoordinate {
                    existingTextureCoordinate = true
                }
            }
        }

        if existingPosition && existingNormal && existingTangent && existingModulationColor && existingTextureCoordinate {
            os_log("⬇️ Loading PNTUC shaders")
            return library.makeFunction(name: "pntuc_vertex_shader")!
        } else if existingPosition && existingNormal && existingTangent && existingTextureCoordinate {
            os_log("⬇️ Loading PNTU shaders")
            return library.makeFunction(name: "pntu_vertex_shader")!
        } else if existingPosition && existingNormal && existingTangent && existingModulationColor {
            os_log("⬇️ Loading PNTC shaders")
            return library.makeFunction(name: "pntc_vertex_shader")!
        } else if existingPosition && existingNormal && existingTangent {
            os_log("⬇️ Loading PNT shaders")
            return library.makeFunction(name: "pnt_vertex_shader")!
        } else if existingPosition && existingNormal && existingModulationColor {
            os_log("⬇️ Loading PNC shaders")
            return library.makeFunction(name: "pnc_vertex_shader")!
        } else if existingPosition && existingNormal {
            os_log("⬇️ Loading PN shaders")
            return library.makeFunction(name: "pn_vertex_shader")!
        } else {
            throw NSError(
                domain: "MDLAssetLoader",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: """
                Unsupported vertex descriptor.
                Make sure that the vertex descriptor contains at least the position, normal, and tangent coordinate attributes.
                ---
                existingPosition: \(existingPosition),
                existingNormal: \(existingNormal),
                existingTangent: \(existingTangent)
                """]
            )
        }
    }
}
