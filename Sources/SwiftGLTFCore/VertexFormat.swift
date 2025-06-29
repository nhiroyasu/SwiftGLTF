import ModelIO

public struct VertexFormatInfo {
    public let format: MDLVertexFormat
    public let byteSize: Int
}

public func getMDLVertexFormat(accessor: Accessor) -> VertexFormatInfo? {
    let componentSize = accessor.componentType.size
    let components = accessor.type.components
    let byteLength = componentSize * components

    let format: MDLVertexFormat
    switch (accessor.componentType, accessor.type) {
    case (.byte, .scalar): format = .char
    case (.byte, .vec2): format = .char2
    case (.byte, .vec3): format = .char3
    case (.byte, .vec4): format = .char4

    case (.unsignedByte, .scalar): format = .uChar
    case (.unsignedByte, .vec2): format = .uChar2
    case (.unsignedByte, .vec3): format = .uChar3
    case (.unsignedByte, .vec4): format = .uChar4

    case (.short, .scalar): format = .short
    case (.short, .vec2): format = .short2
    case (.short, .vec3): format = .short3
    case (.short, .vec4): format = .short4

    case (.unsignedShort, .scalar): format = .uShort
    case (.unsignedShort, .vec2): format = .uShort2
    case (.unsignedShort, .vec3): format = .uShort3
    case (.unsignedShort, .vec4): format = .uShort4

    case (.unsignedInt, .scalar): format = .uInt
    case (.unsignedInt, .vec2): format = .uInt2
    case (.unsignedInt, .vec3): format = .uInt3
    case (.unsignedInt, .vec4): format = .uInt4

    case (.float, .scalar): format = .float
    case (.float, .vec2): format = .float2
    case (.float, .vec3): format = .float3
    case (.float, .vec4): format = .float4

    default: return nil
    }

    return VertexFormatInfo(format: format, byteSize: byteLength)
}
