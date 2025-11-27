import Foundation

public struct VRMCVRMExtension: Codable, Equatable {
    public let humanoid: VRMCHumanoid
}

public struct VRMCHumanoid: Codable, Equatable {
    public let humanBones: VRMCHumanBones
}

public struct VRMCHumanBone: Codable, Equatable {
    public let node: NodeIndex
    public let min: [Float]?
    public let max: [Float]?
}

public struct VRMCHumanBones: Codable, Equatable {
    public let hips: VRMCHumanBone
    public let spine: VRMCHumanBone
    public let head: VRMCHumanBone
    public let leftUpperLeg: VRMCHumanBone
    public let rightUpperLeg: VRMCHumanBone
    public let leftLowerLeg: VRMCHumanBone
    public let rightLowerLeg: VRMCHumanBone
    public let leftFoot: VRMCHumanBone
    public let rightFoot: VRMCHumanBone
    public let leftUpperArm: VRMCHumanBone
    public let rightUpperArm: VRMCHumanBone
    public let leftLowerArm: VRMCHumanBone
    public let rightLowerArm: VRMCHumanBone
    public let leftHand: VRMCHumanBone
    public let rightHand: VRMCHumanBone
    public let leftToes: VRMCHumanBone?
    public let rightToes: VRMCHumanBone?
    public let chest: VRMCHumanBone?
    public let upperChest: VRMCHumanBone?
    public let neck: VRMCHumanBone?
    public let leftShoulder: VRMCHumanBone?
    public let rightShoulder: VRMCHumanBone?
    public let leftThumbMetacarpal: VRMCHumanBone?
    public let leftThumbProximal: VRMCHumanBone?
    public let leftThumbDistal: VRMCHumanBone?
    public let leftIndexProximal: VRMCHumanBone?
    public let leftIndexIntermediate: VRMCHumanBone?
    public let leftIndexDistal: VRMCHumanBone?
    public let leftMiddleProximal: VRMCHumanBone?
    public let leftMiddleIntermediate: VRMCHumanBone?
    public let leftMiddleDistal: VRMCHumanBone?
    public let leftRingProximal: VRMCHumanBone?
    public let leftRingIntermediate: VRMCHumanBone?
    public let leftRingDistal: VRMCHumanBone?
    public let leftLittleProximal: VRMCHumanBone?
    public let leftLittleIntermediate: VRMCHumanBone?
    public let leftLittleDistal: VRMCHumanBone?
    public let rightThumbMetacarpal: VRMCHumanBone?
    public let rightThumbProximal: VRMCHumanBone?
    public let rightThumbDistal: VRMCHumanBone?
    public let rightIndexProximal: VRMCHumanBone?
    public let rightIndexIntermediate: VRMCHumanBone?
    public let rightIndexDistal: VRMCHumanBone?
    public let rightMiddleProximal: VRMCHumanBone?
    public let rightMiddleIntermediate: VRMCHumanBone?
    public let rightMiddleDistal: VRMCHumanBone?
    public let rightRingProximal: VRMCHumanBone?
    public let rightRingIntermediate: VRMCHumanBone?
    public let rightRingDistal: VRMCHumanBone?
    public let rightLittleProximal: VRMCHumanBone?
    public let rightLittleIntermediate: VRMCHumanBone?
    public let rightLittleDistal: VRMCHumanBone?
    public let leftEye: VRMCHumanBone?
    public let rightEye: VRMCHumanBone?
    public let jaw: VRMCHumanBone?
}
