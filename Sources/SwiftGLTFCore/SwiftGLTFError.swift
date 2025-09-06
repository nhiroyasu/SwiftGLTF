import Foundation

public struct SourceLocation: Sendable, Equatable {
    public let fileID: String
    public let function: String
    public let line: Int

    public init(fileID: String, function: String, line: Int) {
        self.fileID = fileID
        self.function = function
        self.line = line
    }

    public static func capture(
        fileID: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) -> SourceLocation {
        SourceLocation(fileID: fileID, function: function, line: line)
    }
}

public enum SwiftGLTFStage: String, Sendable {
    case io, decode, parse, validate, build, render
}

public struct SwiftGLTFErrorContext: Sendable, Equatable {
    public let stage: SwiftGLTFStage
    public let location: SourceLocation
    public var url: URL?
    public var jsonPointer: String?
    public var nodeIndex: Int?
    public var meshIndex: Int?
    public var materialIndex: Int?
    public var textureIndex: Int?
    public var bufferIndex: Int?

    public init(
        stage: SwiftGLTFStage,
        location: SourceLocation = .capture(),
        url: URL? = nil,
        jsonPointer: String? = nil,
        nodeIndex: Int? = nil,
        meshIndex: Int? = nil,
        materialIndex: Int? = nil,
        textureIndex: Int? = nil,
        bufferIndex: Int? = nil
    ) {
        self.stage = stage
        self.location = location
        self.url = url
        self.jsonPointer = jsonPointer
        self.nodeIndex = nodeIndex
        self.meshIndex = meshIndex
        self.materialIndex = materialIndex
        self.textureIndex = textureIndex
        self.bufferIndex = bufferIndex
    }

    public static func capture(
        stage: SwiftGLTFStage,
        url: URL? = nil,
        jsonPointer: String? = nil,
        nodeIndex: Int? = nil,
        meshIndex: Int? = nil,
        materialIndex: Int? = nil,
        textureIndex: Int? = nil,
        bufferIndex: Int? = nil,
        fileID: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) -> SwiftGLTFErrorContext {
        SwiftGLTFErrorContext(
            stage: stage,
            location: .capture(fileID: fileID, function: function, line: line),
            url: url,
            jsonPointer: jsonPointer,
            nodeIndex: nodeIndex,
            meshIndex: meshIndex,
            materialIndex: materialIndex,
            textureIndex: textureIndex,
            bufferIndex: bufferIndex
        )
    }

    public func with(
        url: URL? = nil,
        jsonPointer: String? = nil,
        nodeIndex: Int? = nil,
        meshIndex: Int? = nil,
        materialIndex: Int? = nil,
        textureIndex: Int? = nil,
        bufferIndex: Int? = nil
    ) -> SwiftGLTFErrorContext {
        SwiftGLTFErrorContext(
            stage: stage,
            location: location,
            url: url ?? self.url,
            jsonPointer: jsonPointer ?? self.jsonPointer,
            nodeIndex: nodeIndex ?? self.nodeIndex,
            meshIndex: meshIndex ?? self.meshIndex,
            materialIndex: materialIndex ?? self.materialIndex,
            textureIndex: textureIndex ?? self.textureIndex,
            bufferIndex: bufferIndex ?? self.bufferIndex
        )
    }
}

// MARK: - Error Codes

public enum ParseErrorCode: Sendable, Equatable {
    case noValidScene
    case missingAttribute(name: String)
    case invalidAccessor(name: String)
    case invalidAccessorIndex(name: String, index: Int)
    case invalidIndicesReference
    case unsupportedIndexType
    case unsupportedIndexTypeForNormalGeneration
    case invalidVertexFormat(attribute: String, expected: String)
    case noValidMaterial
    case skinJointsCountMismatch
    case missingSkin(index: Int)
    case invalidSkinReference(node: Int)
    case invalidAnimationChannelTarget
}

public enum IOErrorCode: Sendable, Equatable {
    case invalidDataURI
    case base64DecodeFailed
    case glbTooShort
    case glbInvalidMagic
    case glbUnsupportedVersion(Int)
    case glbLengthMismatch
    case glbChunkOutOfBounds
    case glbJSONChunkMissing
    case glbBINChunkMissing
    case imageBufferViewMissing(index: Int)
    case bufferURIMissing
    case imageURIMissingOrInvalid
    case bufferIndexOutOfRange
    case bufferOverrun
    case textureIndexOutOfRange
    case makeCGImageFailed
    case invalidCGImageFormat
    case vImageBufferInitFailed
}

public enum RenderErrorCode: Sendable, Equatable {
    case commandQueueCreateFailed
    case environmentMapNotFound
    case depthStencilStateCreateFailed(writeEnabled: Bool)
    case convertShaderCreationFailed
    case outputTextureCreateFailed
    case moveTextureToHeapFailed
    case commandBufferCreateFailed
    case blitCommandEncoderCreateFailed
    case cubeTextureExpected
    case cubeTextureCreateFailed
    case texturesHeapCreateFailed
    case fragmentArgumentHeapCreateFailed
    case vertexModelHeapCreateFailed
    case argumentBufferCreateFailed
    case skeletonHeapCreateFailed
    case heapBufferCreateFailed
    case meshCreationFailed
}

public enum ValidateErrorCode: Sendable, Equatable {
    // 予備（必要に応じて拡張）
    case invalidValue(reason: String)
}

// MARK: - SwiftGLTFError

@frozen
public enum SwiftGLTFError: Error, Sendable {
    case io(_ code: IOErrorCode, context: SwiftGLTFErrorContext, underlying: Error? = nil)
    case parse(_ code: ParseErrorCode, context: SwiftGLTFErrorContext, underlying: Error? = nil)
    case validate(_ code: ValidateErrorCode, context: SwiftGLTFErrorContext, underlying: Error? = nil)
    case render(_ code: RenderErrorCode, context: SwiftGLTFErrorContext, underlying: Error? = nil)
    case internalError(message: String, context: SwiftGLTFErrorContext, underlying: Error? = nil)
}

extension SwiftGLTFError {
    @inlinable
    public static func makeParse(
        _ code: ParseErrorCode,
        context: SwiftGLTFErrorContext = .capture(stage: .parse),
        underlying: Error? = nil
    ) -> SwiftGLTFError {
        .parse(code, context: context, underlying: underlying)
    }

    @inlinable
    public static func makeIO(
        _ code: IOErrorCode,
        context: SwiftGLTFErrorContext = .capture(stage: .io),
        underlying: Error? = nil
    ) -> SwiftGLTFError {
        .io(code, context: context, underlying: underlying)
    }

    @inlinable
    public static func makeRender(
        _ code: RenderErrorCode,
        context: SwiftGLTFErrorContext = .capture(stage: .render),
        underlying: Error? = nil
    ) -> SwiftGLTFError {
        .render(code, context: context, underlying: underlying)
    }

    @inlinable
    public static func makeValidate(
        _ code: ValidateErrorCode,
        context: SwiftGLTFErrorContext = .capture(stage: .validate),
        underlying: Error? = nil
    ) -> SwiftGLTFError {
        .validate(code, context: context, underlying: underlying)
    }

    @inlinable
    public static func makeInternal(
        message: String,
        context: SwiftGLTFErrorContext = .capture(stage: .build),
        underlying: Error? = nil
    ) -> SwiftGLTFError {
        .internalError(message: message, context: context, underlying: underlying)
    }
}

// MARK: - LocalizedError

extension SwiftGLTFError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .io(code, context, underlying):
            return "[SwiftGLTF][IO] \(string(of: code)) @\(fmt(context))\(fmtUnderlying(underlying))"
        case let .parse(code, context, underlying):
            return "[SwiftGLTF][Parse] \(string(of: code)) @\(fmt(context))\(fmtUnderlying(underlying))"
        case let .validate(code, context, underlying):
            return "[SwiftGLTF][Validate] \(string(of: code)) @\(fmt(context))\(fmtUnderlying(underlying))"
        case let .render(code, context, underlying):
            return "[SwiftGLTF][Render] \(string(of: code)) @\(fmt(context))\(fmtUnderlying(underlying))"
        case let .internalError(message, context, underlying):
            return "[SwiftGLTF][Internal] \(message) @\(fmt(context))\(fmtUnderlying(underlying))"
        }
    }

    private func fmt(_ ctx: SwiftGLTFErrorContext) -> String {
        var parts: [String] = []
        parts.append("\(ctx.location.fileID)#\(ctx.location.function):\(ctx.location.line)")
        if let stage = Optional(ctx.stage) { parts.append("stage=\(stage.rawValue)") }
        if let jp = ctx.jsonPointer { parts.append("json=\(jp)") }
        if let url = ctx.url { parts.append("url=\(url.absoluteString)") }
        if let n = ctx.nodeIndex { parts.append("node=\(n)") }
        if let m = ctx.meshIndex { parts.append("mesh=\(m)") }
        if let mat = ctx.materialIndex { parts.append("material=\(mat)") }
        if let t = ctx.textureIndex { parts.append("tex=\(t)") }
        if let b = ctx.bufferIndex { parts.append("buf=\(b)") }
        return parts.joined(separator: " ")
    }

    private func fmtUnderlying(_ err: Error?) -> String {
        guard let err else { return "" }
        return " | underlying=\(err.localizedDescription)"
    }

    private func string(of code: ParseErrorCode) -> String {
        switch code {
        case .noValidScene: return "No valid scene found"
        case let .missingAttribute(name): return "Missing attribute: \(name)"
        case let .invalidAccessor(name): return "Invalid accessor: \(name)"
        case let .invalidAccessorIndex(name, index): return "Invalid accessor index for \(name): \(index)"
        case .invalidIndicesReference: return "Invalid indices reference"
        case .unsupportedIndexTypeForNormalGeneration: return "Unsupported index type for normal generation"
        case .unsupportedIndexType: return "Unsupported index type"
        case let .invalidVertexFormat(attribute, expected): return "\(attribute) vertex must be \(expected)"
        case .noValidMaterial: return "No valid material found"
        case .skinJointsCountMismatch: return "skin.joints count and inverseBindMatrices length mismatch"
        case let .missingSkin(index): return "Skin not found at index \(index)"
        case let .invalidSkinReference(node): return "Invalid skin reference on node \(node)"
        case .invalidAnimationChannelTarget: return "Invalid animation channel target"
        }
    }

    private func string(of code: IOErrorCode) -> String {
        switch code {
        case .invalidDataURI: return "Invalid data URI"
        case .base64DecodeFailed: return "Failed to decode base64 data"
        case .glbTooShort: return "GLB data too short for header"
        case .glbInvalidMagic: return "Invalid GLB magic header"
        case let .glbUnsupportedVersion(v): return "Unsupported GLB version: \(v)"
        case .glbLengthMismatch: return "GLB length mismatch"
        case .glbChunkOutOfBounds: return "GLB chunk exceeds data bounds"
        case .glbJSONChunkMissing: return "JSON chunk not found in GLB"
        case .glbBINChunkMissing: return "BIN chunk not found in GLB"
        case let .imageBufferViewMissing(i): return "Image bufferView is missing for image \(i)"
        case .bufferURIMissing: return "Buffer URI is missing or empty"
        case .imageURIMissingOrInvalid: return "Image URI is missing or invalid"
        case .bufferIndexOutOfRange: return "Buffer index out of range"
        case .bufferOverrun: return "Buffer overrun in accessor data"
        case .textureIndexOutOfRange: return "Texture index out of range"
        case .makeCGImageFailed: return "Failed to create CGImage from data"
        case .invalidCGImageFormat: return "Invalid CGImage format"
        case .vImageBufferInitFailed: return "Failed to initialize vImage buffer"
        }
    }

    private func string(of code: RenderErrorCode) -> String {
        switch code {
        case .commandQueueCreateFailed: return "Failed to create command queue"
        case .environmentMapNotFound: return "Environment map not found"
        case let .depthStencilStateCreateFailed(writeEnabled): return "Failed to create depth stencil state (writeEnabled=\(writeEnabled))"
        case .convertShaderCreationFailed: return "Failed to create convert shader"
        case .outputTextureCreateFailed: return "Failed to create output texture"
        case .moveTextureToHeapFailed: return "Failed to move texture to heap"
        case .commandBufferCreateFailed: return "Failed to create command buffer"
        case .blitCommandEncoderCreateFailed: return "Failed to create blit command encoder"
        case .cubeTextureExpected: return "Provided texture is not a cube texture."
        case .cubeTextureCreateFailed: return "Failed to create cube texture"
        case .texturesHeapCreateFailed: return "Failed to create textures heap"
        case .fragmentArgumentHeapCreateFailed: return "Failed to create fragment argument heap"
        case .vertexModelHeapCreateFailed: return "Failed to create vertex model heap"
        case .argumentBufferCreateFailed: return "Failed to create argument buffer"
        case .skeletonHeapCreateFailed: return "Failed to create skeleton heap"
        case .heapBufferCreateFailed: return "Failed to create heap buffer"
        case .meshCreationFailed: return "Failed to create mesh"
        }
    }

    private func string(of code: ValidateErrorCode) -> String {
        switch code {
        case let .invalidValue(reason): return "Invalid value: \(reason)"
        }
    }
}

// MARK: - CustomNSError Bridge

extension SwiftGLTFError: CustomNSError {
    public static var errorDomain: String { "com.swiftgltf.error" }

    public var errorCode: Int {
        switch self {
        case let .io(code, _, _): return 1000 + self._ioCode(code)
        case let .parse(code, _, _): return 2000 + self._parseCode(code)
        case let .validate(code, _, _): return 3000 + self._validateCode(code)
        case let .render(code, _, _): return 4000 + self._renderCode(code)
        case .internalError: return 9000
        }
    }

    public var errorUserInfo: [String : Any] {
        var info: [String: Any] = [:]
        info[NSLocalizedDescriptionKey] = self.errorDescription ?? "SwiftGLTFError"
        let ctx = self.context
        info["SwiftGLTF.Stage"] = ctx.stage.rawValue
        info["SwiftGLTF.FileID"] = ctx.location.fileID
        info["SwiftGLTF.Function"] = ctx.location.function
        info["SwiftGLTF.Line"] = ctx.location.line
        if let url = ctx.url { info["SwiftGLTF.URL"] = url.absoluteString }
        if let jp = ctx.jsonPointer { info["SwiftGLTF.JSONPointer"] = jp }
        if let v = ctx.nodeIndex { info["SwiftGLTF.NodeIndex"] = v }
        if let v = ctx.meshIndex { info["SwiftGLTF.MeshIndex"] = v }
        if let v = ctx.materialIndex { info["SwiftGLTF.MaterialIndex"] = v }
        if let v = ctx.textureIndex { info["SwiftGLTF.TextureIndex"] = v }
        if let v = ctx.bufferIndex { info["SwiftGLTF.BufferIndex"] = v }
        if let underlying = self.underlying { info[NSUnderlyingErrorKey] = underlying as NSError }
        return info
    }

    private func _parseCode(_ code: ParseErrorCode) -> Int {
        switch code {
        case .noValidScene: return 1
        case .missingAttribute: return 2
        case .invalidAccessor: return 3
        case .invalidAccessorIndex: return 4
        case .invalidIndicesReference: return 5
        case .unsupportedIndexTypeForNormalGeneration: return 6
        case .unsupportedIndexType: return 7
        case .invalidVertexFormat: return 8
        case .noValidMaterial: return 9
        case .skinJointsCountMismatch: return 10
        case .missingSkin: return 11
        case .invalidSkinReference: return 12
        case .invalidAnimationChannelTarget: return 13
        }
    }

    private func _ioCode(_ code: IOErrorCode) -> Int {
        switch code {
        case .invalidDataURI: return 1
        case .base64DecodeFailed: return 2
        case .glbTooShort: return 3
        case .glbInvalidMagic: return 4
        case .glbUnsupportedVersion: return 5
        case .glbLengthMismatch: return 6
        case .glbChunkOutOfBounds: return 7
        case .glbJSONChunkMissing: return 8
        case .glbBINChunkMissing: return 9
        case .imageBufferViewMissing: return 10
        case .bufferURIMissing: return 11
        case .imageURIMissingOrInvalid: return 12
        case .bufferIndexOutOfRange: return 13
        case .bufferOverrun: return 14
        case .textureIndexOutOfRange: return 15
        case .makeCGImageFailed: return 16
        case .invalidCGImageFormat: return 17
        case .vImageBufferInitFailed: return 18
        }
    }

    private func _renderCode(_ code: RenderErrorCode) -> Int {
        switch code {
        case .commandQueueCreateFailed: return 1
        case .environmentMapNotFound: return 2
        case .depthStencilStateCreateFailed: return 3
        case .convertShaderCreationFailed: return 4
        case .outputTextureCreateFailed: return 5
        case .moveTextureToHeapFailed: return 6
        case .commandBufferCreateFailed: return 7
        case .blitCommandEncoderCreateFailed: return 8
        case .cubeTextureExpected: return 9
        case .cubeTextureCreateFailed: return 10
        case .texturesHeapCreateFailed: return 11
        case .fragmentArgumentHeapCreateFailed: return 12
        case .vertexModelHeapCreateFailed: return 13
        case .argumentBufferCreateFailed: return 14
        case .skeletonHeapCreateFailed: return 15
        case .heapBufferCreateFailed: return 16
        case .meshCreationFailed: return 17
        }
    }

    private func _validateCode(_ code: ValidateErrorCode) -> Int {
        switch code {
        case .invalidValue: return 1
        }
    }
}

public extension SwiftGLTFError {
    var context: SwiftGLTFErrorContext {
        switch self {
        case let .io(_, context, _): return context
        case let .parse(_, context, _): return context
        case let .validate(_, context, _): return context
        case let .render(_, context, _): return context
        case let .internalError(_, context, _): return context
        }
    }

    var underlying: Error? {
        switch self {
        case let .io(_, _, u): return u
        case let .parse(_, _, u): return u
        case let .validate(_, _, u): return u
        case let .render(_, _, u): return u
        case let .internalError(_, _, u): return u
        }
    }
}
