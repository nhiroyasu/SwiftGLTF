public extension Accessor {
    var vertexFormat: VertexFormatInfo? {
        return getMDLVertexFormat(accessor: self)
    }
}
