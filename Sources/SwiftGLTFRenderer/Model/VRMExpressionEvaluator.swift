import Foundation
import SwiftGLTFCore
import SwiftGLTFShaderTypes

func resolveVRMExpressionMorphWeights(
    for morphWeights: [Float],
    input expressionWeights: [VRMExpressionKey: Float],
    definitions: [VRMExpression],
    morphDispatches: [MorphDispatch]
) -> [Float] {
    guard !definitions.isEmpty else { return morphWeights }

    let resolvedWeights = resolveExpressionWeights(
        for: expressionWeights,
        definitions: definitions
    )

    var morphWeights = morphWeights

    // Expression-bound morphs are rebuilt from resolved expressions without keeping base or animated weights.
    for definition in definitions {
        for morphBind in definition.morphTargetBinds {
            let dispatch = morphDispatches[morphBind.node]
            let morphIndex = Int(dispatch.offset) + morphBind.index
            morphWeights[morphIndex] = 0
        }
    }

    // Multiple expressions can target the same morph, so reset before accumulating expression weights.
    for definition in definitions {
        guard let expressionWeight = resolvedWeights[definition.key],
              expressionWeight > 0 else {
            continue
        }

        for morphBind in definition.morphTargetBinds {
            let dispatch = morphDispatches[morphBind.node]
            let morphIndex = Int(dispatch.offset) + morphBind.index
            morphWeights[morphIndex] += morphBind.weight * expressionWeight
        }
    }

    return morphWeights
}

func resolveExpressionWeights(
    for expressionWeights: [VRMExpressionKey: Float],
    definitions: [VRMExpression]
) -> [VRMExpressionKey: Float] {
    var output: [VRMExpressionKey: Float] = [:]

    for definition in definitions {
        var value = clamp01(expressionWeights[definition.key] ?? 0)
        if definition.isBinary {
            value = value > 0.5 ? 1 : 0
        }
        output[definition.key] = value
    }

    // TODO: わざわざ enum VRMExpressionOverrideCategory 作って、3回同じメソッド呼ぶの違和感。普通にメソッド分けるか、ベタガキでも良さそう
    output = applyOverride(
        for: output,
        category: .blink,
        definitions: definitions,
    )
    output = applyOverride(
        for: output,
        category: .lookAt,
        definitions: definitions,
    )
    output = applyOverride(
        for: output,
        category: .mouth,
        definitions: definitions,
    )

    return output
}

private func applyOverride(
    for expressionWeights: [VRMExpressionKey: Float],
    category: VRMExpressionOverrideCategory,
    definitions: [VRMExpression]
) -> [VRMExpressionKey: Float] {
    var hasBlock = false
    var blendValue: Float = 0
    for definition in definitions {
        guard definition.key.isPreset,
              !category.presetKeys.contains(definition.key),
              let value = expressionWeights[definition.key],
              value > 0 else {
            continue
        }

        let overrideType = switch category {
        case .blink:
            definition.overrideBlink
        case .lookAt:
            definition.overrideLookAt
        case .mouth:
            definition.overrideMouth
        }
        switch overrideType {
        case .none:
            break
        case .block:
            hasBlock = true
        case .blend:
            blendValue += value
        }
    }

    let factor = 1 - clamp01(blendValue)
    var output = expressionWeights
    for definition in definitions {
        guard definition.key.isPreset,
              category.presetKeys.contains(definition.key) else {
            continue
        }

        if hasBlock {
            output[definition.key] = 0
        } else if definition.isBinary && blendValue > 0 {
            output[definition.key] = 0
        } else {
            output[definition.key] = (output[definition.key] ?? 0) * factor
        }
    }

    return output
}

private enum VRMExpressionOverrideCategory {
    case blink
    case lookAt
    case mouth

    var presetKeys: Set<VRMExpressionKey> {
        switch self {
        case .blink:
            [.blink, .blinkLeft, .blinkRight]
        case .lookAt:
            [.lookUp, .lookDown, .lookLeft, .lookRight]
        case .mouth:
            [.aa, .ih, .ou, .ee, .oh]
        }
    }
}

private func clamp01(_ value: Float) -> Float {
    min(max(value, 0), 1)
}
