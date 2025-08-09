import MetalKit

public enum GLTFVertexAttributeIndex {
    public static let POSITION = 0
    public static let NORMAL = 1
    public static let TANGENT = 2
    public static let TEXCOORD_0 = 3
    public static let COLOR_0 = 4
    public static let TEXCOORD_1 = 5
}

public func makeGLTFVertexDescriptor() -> MTLVertexDescriptor {
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
    offset += 16

    // texcoord
    mtlVertexDescriptor.attributes[GLTFVertexAttributeIndex.TEXCOORD_0].format = .float2
    mtlVertexDescriptor.attributes[GLTFVertexAttributeIndex.TEXCOORD_0].offset = offset
    mtlVertexDescriptor.attributes[GLTFVertexAttributeIndex.TEXCOORD_0].bufferIndex = 0
    offset += 8

    // color
    mtlVertexDescriptor.attributes[GLTFVertexAttributeIndex.COLOR_0].format = .float4
    mtlVertexDescriptor.attributes[GLTFVertexAttributeIndex.COLOR_0].offset = offset
    mtlVertexDescriptor.attributes[GLTFVertexAttributeIndex.COLOR_0].bufferIndex = 0
    offset += 16

    // Texcoord1 (dummy)
    mtlVertexDescriptor.attributes[GLTFVertexAttributeIndex.TEXCOORD_1].format = .float2
    mtlVertexDescriptor.attributes[GLTFVertexAttributeIndex.TEXCOORD_1].offset = offset
    mtlVertexDescriptor.attributes[GLTFVertexAttributeIndex.TEXCOORD_1].bufferIndex = 0
    offset += 8
    // Set the layout stride
    mtlVertexDescriptor.layouts[0].stride = offset
    mtlVertexDescriptor.layouts[0].stepFunction = .perVertex
    mtlVertexDescriptor.layouts[0].stepRate = 1

    return mtlVertexDescriptor
}
