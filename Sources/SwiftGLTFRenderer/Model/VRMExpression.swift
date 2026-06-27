import Foundation
import SwiftGLTFCore
import SwiftGLTFParser
import SwiftGLTFShaderTypes

struct VRMExpressionMorphTargetBind: Equatable {
    let node: NodeIndex
    /// Index of target morph
    let index: Int
    let weight: Float
}

struct VRMExpression: Equatable {
    let key: VRMExpressionKey
    let morphTargetBinds: [VRMExpressionMorphTargetBind]
    let isBinary: Bool
    let overrideBlink: VRMCVrmExpressionOverrideType
    let overrideLookAt: VRMCVrmExpressionOverrideType
    let overrideMouth: VRMCVrmExpressionOverrideType
}
