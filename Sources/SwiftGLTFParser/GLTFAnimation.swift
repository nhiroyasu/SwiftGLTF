import ModelIO
import simd
import OSLog
import SwiftGLTFCore

public class GLTFAnimationContainer: MDLObjectContainer {
}

@objc public protocol GLTFAnimation: MDLComponent {
    var name: String? { get }
    var duration: Float { get }         // max of all sampler input times
    var channels: [GLTFAnimationChannel] { get }
}

public class GLTFAnimationImpl: NSObject, GLTFAnimation {
    public let name: String?
    public let duration: Float          // max of all sampler input times
    public let channels: [GLTFAnimationChannel]

    init(
        name: String?,
        duration: Float,
        channels: [GLTFAnimationChannel]
    ) {
        self.name = name
        self.duration = duration
        self.channels = channels
    }
}

public class GLTFAnimationChannel: NSObject {
    public let type: GLTFAnimationType
    public let targetNodeIndex: NodeIndex
    public let interpolation: GLTFInterpolation
    public let input: [Float]  // keyframe times in seconds

    private var _targetNode: MDLObject? = nil
    public var targetNodePath: String { _targetNode?.path ?? "" }
    public var targetNode: MDLObject {
        if let _targetNode {
            return _targetNode
        } else {
            fatalError("Target node not set for animation targeting node index \(targetNodeIndex)")
        }
    }
    public func bind(_ object: MDLObject) {
        _targetNode = object
    }

    init(
        type: GLTFAnimationType,
        targetNodeIndex: NodeIndex,
        interpolation: GLTFInterpolation,
        input: [Float]
    ) {
        self.type = type
        self.targetNodeIndex = targetNodeIndex
        self.interpolation = interpolation
        self.input = input
    }
}

enum GLTFAnimationChannelBuilder {
    static func build(
        from channel: AnimationChannel,
        samplers: [AnimationSampler],
        gltf: GLTF,
        binaryLoader: GLTFBinaryLoader,
        options: GLTFDecodeOptions
    ) throws -> GLTFAnimationChannel? {
        guard let nodeIndex = channel.target.node else {
            Log.common.debug("Animation channel missing target node index")
            return nil
        }
        let sampler = samplers[channel.sampler]
        let interpolation = sampler.interpolation
        let inputData = try binaryLoader.extractData(accessorIndex: sampler.input)
        let outputData = try binaryLoader.extractData(accessorIndex: sampler.output)

        let inputArray: [Float] = inputData.withUnsafeBytes { ptr in
            let floatPtr = ptr.bindMemory(to: Float.self)
            return Array(floatPtr)
        }

        let animationType: GLTFAnimationType
        switch channel.target.path {
        case .translation:
            if let accessor = gltf.accessors?[sampler.output.value],
               accessor.type == .vec3,
               accessor.componentType == .float {
                let outputArray: [Float] = outputData.withUnsafeBytes { ptr in
                    let floatPtr = ptr.bindMemory(to: Float.self)
                    return Array(floatPtr)
                }
                var float3Array = stride(from: 0, to: outputArray.count, by: 3).map {
                    SIMD3<Float>(outputArray[$0], outputArray[$0 + 1], outputArray[$0 + 2])
                }
                if options.convertToLeftHanded {
                    float3Array = float3Array.map { SIMD3<Float>($0.x, $0.y, -$0.z) }
                }
                animationType = .translation(float3Array)
            } else {
                Log.common.error("Unexpected accessor type for translation animation output")
                animationType = .unknown
            }
        case .scale:
            if let accessor = gltf.accessors?[sampler.output.value],
               accessor.type == .vec3,
               accessor.componentType == .float {
                let outputArray: [Float] = outputData.withUnsafeBytes { ptr in
                    let floatPtr = ptr.bindMemory(to: Float.self)
                    return Array(floatPtr)
                }
                let float3Array = stride(from: 0, to: outputArray.count, by: 3).map {
                    SIMD3<Float>(outputArray[$0], outputArray[$0 + 1], outputArray[$0 + 2])
                }
                animationType = .scale(float3Array)
            } else {
                Log.common.error("Unexpected accessor type for scale animation output")
                animationType = .unknown
            }
        case .rotation:
            if let accessor = gltf.accessors?[sampler.output.value],
                accessor.type == .vec4,
                accessor.componentType == .float {
                let outputArray: [Float] = outputData.withUnsafeBytes { ptr in
                    let floatPtr = ptr.bindMemory(to: Float.self)
                    return Array(floatPtr)
                }
                var quatArray = stride(from: 0, to: outputArray.count, by: 4).map {
                    simd_quatf(ix: outputArray[$0], iy: outputArray[$0 + 1], iz: outputArray[$0 + 2], r: outputArray[$0 + 3])
                }
                if options.convertToLeftHanded {
                    quatArray = quatArray.map { simd_quatf(ix: -$0.imag.x, iy: -$0.imag.y, iz: $0.imag.z, r: $0.real) }
                }
                animationType = .rotation(quatArray)
            } else {
                Log.common.error("Unexpected accessor type for rotation animation output")
                animationType = .unknown
            }
        case .weights:
            if let accessor = gltf.accessors?[sampler.output.value],
               accessor.type == .scalar,
               accessor.componentType == .float {
                let outputArray: [Float] = outputData.withUnsafeBytes { ptr in
                    let floatPtr = ptr.bindMemory(to: Float.self)
                    return Array(floatPtr)
                }
                animationType = .weights(outputArray)
            } else {
                Log.common.error("Unexpected accessor type for weights animation output")
                animationType = .unknown
            }
        case .unknown:
            Log.common.error("Unknown animation path")
            animationType = .unknown
        }

        return GLTFAnimationChannel(
            type: animationType,
            targetNodeIndex: nodeIndex,
            interpolation: interpolation,
            input: inputArray
        )
    }
}

public enum GLTFAnimationType {
    case translation([SIMD3<Float>])
    case rotation([simd_quatf])
    case scale([SIMD3<Float>])
    case weights([Float])
    case unknown
}
