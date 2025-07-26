import MetalKit
import OSLog
import SwiftGLTF

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
        self.fragmentFunction = library.makeFunction(name: "pbr_fragment_shader")!
    }

    func load(
        for vertexDescriptor: MDLVertexDescriptor,
        useCache: Bool = true
    ) throws -> MTLRenderPipelineState {
        if useCache, let cachedState = cachedPipelineStates[vertexDescriptor] {
            return cachedState
        }

        // Validate the vertex descriptor
        try validate(for: vertexDescriptor)

        let psoDescriptor = MTLRenderPipelineDescriptor()
        psoDescriptor.vertexFunction = library.makeFunction(name: "pbr_vertex_shader")!
        psoDescriptor.fragmentFunction = fragmentFunction
        psoDescriptor.colorAttachments[0].pixelFormat = config.colorPixelFormat
        psoDescriptor.depthAttachmentPixelFormat = config.depthPixelFormat
        psoDescriptor.rasterSampleCount = config.sampleCount
        psoDescriptor.vertexDescriptor = makeMTLVertexDescriptor(from: vertexDescriptor)

        let pso = try device.makeRenderPipelineState(descriptor: psoDescriptor)
        cachedPipelineStates[vertexDescriptor] = pso
        return pso
    }

    private func validate(for vertexDescriptor: MDLVertexDescriptor) throws {
        // Validate that required attributes exist

        let existFloat3Position = (vertexDescriptor.attributes[GLTFVertexAttributeIndex.POSITION] as? MDLVertexAttribute)?.format == .float3
        let existFloat3Normal = (vertexDescriptor.attributes[GLTFVertexAttributeIndex.NORMAL] as? MDLVertexAttribute)?.format == .float3
        let typeFloat4Tangent = switch (vertexDescriptor.attributes[GLTFVertexAttributeIndex.TANGENT] as? MDLVertexAttribute)?.format {
        case .float4, .invalid:
            // invalid format is also acceptable for tangent because it can be optional
            true
        default:
            false
        }
        let typeFloat2Texcoord0 = switch (vertexDescriptor.attributes[GLTFVertexAttributeIndex.TEXCOORD_0] as? MDLVertexAttribute)?.format {
        case .float2, .invalid:
            true
        default:
            false
        }
        let typeFloat2Texcoord1 = switch (vertexDescriptor.attributes[GLTFVertexAttributeIndex.TEXCOORD_1] as? MDLVertexAttribute)?.format {
        case .float2, .invalid:
            true
        default:
            false
        }
        let typeFloat4Color = switch (vertexDescriptor.attributes[GLTFVertexAttributeIndex.COLOR_0] as? MDLVertexAttribute)?.format {
        case .float4, .invalid:
            // invalid format is also acceptable for color because it can be optional
            true
        default:
            false
        }

        if existFloat3Position && existFloat3Normal && typeFloat4Tangent && typeFloat2Texcoord0 && typeFloat4Color {
            return
        } else {
            throw NSError(
                domain: "MDLAssetLoader",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: """
                Required vertex attributes are missing
                - Position (float3)
                - Normal (float3)
                - Tangent (float4, optional)
                - Texcoord0 (float2, optional)
                - Texcoord1 (float2, optional)
                - Color (float4, optional)
                
                ---
                
                Actual attributes:
                Position: \(existFloat3Position ? "✓" : "✗")
                Normal: \(existFloat3Normal ? "✓" : "✗")
                Tangent: \(typeFloat4Tangent ? "✓" : "✗")
                Texcoord0: \(typeFloat2Texcoord0 ? "✓" : "✗")
                Texcoord1: \(typeFloat2Texcoord1 ? "✓" : "✗")
                Color: \(typeFloat4Color ? "✓" : "✗")
                Please check your MDLVertexDescriptor configuration.
                """]
            )
        }
    }

    private func makeMTLVertexDescriptor(from mdlVertexDescriptor: MDLVertexDescriptor) -> MTLVertexDescriptor {
        let mtlVertexDescriptor = MTLVertexDescriptor()

        var offset = 0
        // position
        mtlVertexDescriptor.attributes[GLTFVertexAttributeIndex.POSITION].format = .float3
        mtlVertexDescriptor.attributes[GLTFVertexAttributeIndex.POSITION].offset = offset
        mtlVertexDescriptor.attributes[GLTFVertexAttributeIndex.POSITION].bufferIndex = 0
        offset += 12

        // normal
        mtlVertexDescriptor.attributes[GLTFVertexAttributeIndex.NORMAL].format = .float3
        mtlVertexDescriptor.attributes[GLTFVertexAttributeIndex.NORMAL].offset = offset
        mtlVertexDescriptor.attributes[GLTFVertexAttributeIndex.NORMAL].bufferIndex = 0
        offset += 12

        // tangent
        mtlVertexDescriptor.attributes[GLTFVertexAttributeIndex.TANGENT].format = .float4
        mtlVertexDescriptor.attributes[GLTFVertexAttributeIndex.TANGENT].offset = offset
        mtlVertexDescriptor.attributes[GLTFVertexAttributeIndex.TANGENT].bufferIndex = 0
        offset += mdlVertexDescriptor.validTangentVertex ? 16 : 0

        // texcoord0
        mtlVertexDescriptor.attributes[GLTFVertexAttributeIndex.TEXCOORD_0].format = .float2
        mtlVertexDescriptor.attributes[GLTFVertexAttributeIndex.TEXCOORD_0].offset = offset
        mtlVertexDescriptor.attributes[GLTFVertexAttributeIndex.TEXCOORD_0].bufferIndex = 0
        offset += mdlVertexDescriptor.validTexcoord0Vertex ? 8 : 0

        // texcoord1
        mtlVertexDescriptor.attributes[GLTFVertexAttributeIndex.TEXCOORD_1].format = .float2
        mtlVertexDescriptor.attributes[GLTFVertexAttributeIndex.TEXCOORD_1].offset = offset
        mtlVertexDescriptor.attributes[GLTFVertexAttributeIndex.TEXCOORD_1].bufferIndex = 0
        offset += mdlVertexDescriptor.validTexcoord1Vertex ? 8 : 0

        // color
        mtlVertexDescriptor.attributes[GLTFVertexAttributeIndex.COLOR_0].format = .float4
        mtlVertexDescriptor.attributes[GLTFVertexAttributeIndex.COLOR_0].offset = offset
        mtlVertexDescriptor.attributes[GLTFVertexAttributeIndex.COLOR_0].bufferIndex = 0
        offset += mdlVertexDescriptor.validColorVertex ? 16 : 0

        // Set the layout stride
        mtlVertexDescriptor.layouts[0].stride = offset
        mtlVertexDescriptor.layouts[0].stepFunction = .perVertex
        mtlVertexDescriptor.layouts[0].stepRate = 1

        os_log("⬇️ Created MTLVertexDescriptor with stride: %{public}d for PBR shader", offset)
        return mtlVertexDescriptor
    }
}

extension MDLVertexDescriptor {
    var validTangentVertex: Bool {
        let tangentAttribute = attributes[GLTFVertexAttributeIndex.TANGENT] as? MDLVertexAttribute
        return tangentAttribute?.format == .float4
    }

    var validTexcoord0Vertex: Bool {
        let texcoordAttribute = attributes[GLTFVertexAttributeIndex.TEXCOORD_0] as? MDLVertexAttribute
        return texcoordAttribute?.format == .float2
    }

    var validTexcoord1Vertex: Bool {
        let texcoordAttribute = attributes[GLTFVertexAttributeIndex.TEXCOORD_1] as? MDLVertexAttribute
        return texcoordAttribute?.format == .float2
    }

    var validColorVertex: Bool {
        let colorAttribute = attributes[GLTFVertexAttributeIndex.COLOR_0] as? MDLVertexAttribute
        return colorAttribute?.format == .float4
    }
}
