import Testing
import SwiftGLTFCore
import SwiftGLTFParser
import SwiftGLTFShaderTypes
@testable import SwiftGLTFRenderer

final class VRMExpressionTests {
    @Test
    func testExpressionWeightsClampBinaryAndOverrideProceduralPresets() {
        let happyKey = VRMExpressionKey.happy
        let blinkKey = VRMExpressionKey.blink
        let aaKey = VRMExpressionKey.aa

        let definitions = [
            makeDefinition(key: happyKey, isBinary: true, overrideBlink: .blend, overrideMouth: .block),
            makeDefinition(key: blinkKey, isBinary: false),
            makeDefinition(key: aaKey, isBinary: false)
        ]

        let weights = resolveExpressionWeights(
            for: [
                happyKey: 0.6,
                blinkKey: 1.0,
                aaKey: 1.0
            ],
            definitions: definitions
        )

        #expect(weights[happyKey] == 1)
        #expect(weights[blinkKey] == 0)
        #expect(weights[aaKey] == 0)
    }

    @Test
    func testApplyExpressionWeightsAccumulatesMorphTargets() {
        let happyKey = VRMExpressionKey.happy
        let relaxedKey = VRMExpressionKey.relaxed
        let definitions = [
            makeDefinition(
                key: happyKey,
                binds: [
                    VRMExpressionMorphTargetBind(node: 0, index: 1, weight: 0.8)
                ]
            ),
            makeDefinition(
                key: relaxedKey,
                binds: [
                    VRMExpressionMorphTargetBind(node: 0, index: 1, weight: 0.2)
                ]
            )
        ]
        let morphWeights: [Float] = [0.5, 0.4, 0.25]
        let morphDispatches = [MorphDispatch(offset: 0, length: 3)]

        let output = resolveVRMExpressionMorphWeights(
            for: morphWeights,
            input: [
                happyKey: 0.5,
                relaxedKey: 1.0
            ],
            definitions: definitions,
            morphDispatches: morphDispatches
        )

        #expect(output[0] == 0.5)
        #expect(abs(output[1] - 0.6) < 0.0001)
        #expect(output[2] == 0.25)
    }

    private func makeDefinition(
        key: VRMExpressionKey,
        binds: [VRMExpressionMorphTargetBind] = [],
        isBinary: Bool = false,
        overrideBlink: VRMCVrmExpressionOverrideType = .none,
        overrideLookAt: VRMCVrmExpressionOverrideType = .none,
        overrideMouth: VRMCVrmExpressionOverrideType = .none
    ) -> VRMExpression {
        VRMExpression(
            key: key,
            morphTargetBinds: binds,
            isBinary: isBinary,
            overrideBlink: overrideBlink,
            overrideLookAt: overrideLookAt,
            overrideMouth: overrideMouth
        )
    }
}
