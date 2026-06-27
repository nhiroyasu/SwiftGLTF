import ModelIO
import SwiftGLTFCore

public final class GLTFVRMExpressionMorphTargetBind: Equatable {
    public let node: NodeIndex?
    public let mesh: MeshIndex?
    public let index: Int
    public let weight: Float

    public init(
        node: NodeIndex?,
        mesh: MeshIndex?,
        index: Int,
        weight: Float
    ) {
        self.node = node
        self.mesh = mesh
        self.index = index
        self.weight = weight
    }

    public static func == (
        lhs: GLTFVRMExpressionMorphTargetBind,
        rhs: GLTFVRMExpressionMorphTargetBind
    ) -> Bool {
        lhs.node == rhs.node &&
        lhs.mesh == rhs.mesh &&
        lhs.index == rhs.index &&
        lhs.weight == rhs.weight
    }
}

public struct GLTFVRMExpression: Equatable {
    public let key: VRMExpressionKey
    public let morphTargetBinds: [GLTFVRMExpressionMorphTargetBind]
    public let isBinary: Bool
    public let overrideBlink: VRMCVrmExpressionOverrideType
    public let overrideLookAt: VRMCVrmExpressionOverrideType
    public let overrideMouth: VRMCVrmExpressionOverrideType

    public init(
        key: VRMExpressionKey,
        morphTargetBinds: [GLTFVRMExpressionMorphTargetBind],
        isBinary: Bool,
        overrideBlink: VRMCVrmExpressionOverrideType,
        overrideLookAt: VRMCVrmExpressionOverrideType,
        overrideMouth: VRMCVrmExpressionOverrideType
    ) {
        self.key = key
        self.morphTargetBinds = morphTargetBinds
        self.isBinary = isBinary
        self.overrideBlink = overrideBlink
        self.overrideLookAt = overrideLookAt
        self.overrideMouth = overrideMouth
    }
}

public class GLTFVRMHumanoid: MDLObject {
    public let nodeMap: [VRMHumanoidBoneName: NodeIndex]

    init(nodeMap: [VRMHumanoidBoneName: NodeIndex]) {
        self.nodeMap = nodeMap
        super.init()
    }
}

public class GLTFVRMExpressions: MDLObject {
    public let expressions: [GLTFVRMExpression]

    init(expressions: [GLTFVRMExpression]) {
        self.expressions = expressions
        super.init()
    }
}

func makeGLTFVRMExpressions(from gltf: GLTF) -> GLTFVRMExpressions? {
    if let expressions = gltf.extensions?.vrmcVrm?.expressions {
        let normalized = makeVRM1Expressions(from: expressions)
        return normalized.isEmpty ? nil : GLTFVRMExpressions(expressions: normalized)
    }

    if let blendShapeGroups = gltf.extensions?.vrm0?.blendShapeMaster?.blendShapeGroups {
        let normalized = makeVRM0Expressions(from: blendShapeGroups)
        return normalized.isEmpty ? nil : GLTFVRMExpressions(expressions: normalized)
    }

    return nil
}

private func makeVRM1Expressions(from expressions: VRMCVrmExpressions) -> [GLTFVRMExpression] {
    var output: [GLTFVRMExpression] = []

    if let preset = expressions.preset {
        output.append(contentsOf: makeVRM1PresetExpressions(from: preset))
    }

    if let custom = expressions.custom {
        for name in custom.keys.sorted() {
            guard let expression = custom[name] else { continue }
            output.append(makeVRM1Expression(
                key: .custom(name),
                expression: expression
            ))
        }
    }

    return output
}

private func makeVRM1PresetExpressions(from preset: VRMCVrmPresetExpressions) -> [GLTFVRMExpression] {
    [
        (VRMExpressionKey.happy, preset.happy),
        (.angry, preset.angry),
        (.sad, preset.sad),
        (.relaxed, preset.relaxed),
        (.surprised, preset.surprised),
        (.aa, preset.aa),
        (.ih, preset.ih),
        (.ou, preset.ou),
        (.ee, preset.ee),
        (.oh, preset.oh),
        (.blink, preset.blink),
        (.blinkLeft, preset.blinkLeft),
        (.blinkRight, preset.blinkRight),
        (.lookUp, preset.lookUp),
        (.lookDown, preset.lookDown),
        (.lookLeft, preset.lookLeft),
        (.lookRight, preset.lookRight),
        (.neutral, preset.neutral)
    ].compactMap { key, expression in
        guard let expression else { return nil }
        return makeVRM1Expression(
            key: key,
            expression: expression
        )
    }
}

private func makeVRM1Expression(
    key: VRMExpressionKey,
    expression: VRMCVrmExpression
) -> GLTFVRMExpression {
    GLTFVRMExpression(
        key: key,
        morphTargetBinds: expression.morphTargetBinds?.map {
            GLTFVRMExpressionMorphTargetBind(
                node: $0.node,
                mesh: nil,
                index: $0.index,
                weight: $0.weight
            )
        } ?? [],
        isBinary: expression.isBinary,
        overrideBlink: expression.overrideBlink,
        overrideLookAt: expression.overrideLookAt,
        overrideMouth: expression.overrideMouth
    )
}

private func makeVRM0Expressions(from groups: [VRM0BlendShapeGroup]) -> [GLTFVRMExpression] {
    groups.compactMap { group in
        guard let key = normalizeVRM0ExpressionKey(from: group) else { return nil }
        return GLTFVRMExpression(
            key: key,
            morphTargetBinds: group.binds?.compactMap { bind in
                guard let mesh = bind.mesh,
                      let index = bind.index else {
                    return nil
                }
                return GLTFVRMExpressionMorphTargetBind(
                    node: nil,
                    mesh: mesh,
                    index: index,
                    weight: (bind.weight ?? 0) / 100
                )
            } ?? [],
            isBinary: group.isBinary ?? false,
            overrideBlink: .none,
            overrideLookAt: .none,
            overrideMouth: .none
        )
    }
}
