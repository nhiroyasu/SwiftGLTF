import Testing
import Foundation
@testable import SwiftGLTFCore

struct VRMCHumanoidDecodeTests {
    @Test
    func testHumanBones() throws {
        let json = """
        {
          "asset": { "version": "2.0" },
          "nodes": [
          ],
          "extensions": {
            "VRMC_vrm": {
              "humanoid": {
                "humanBones": {
                  "hips": { "node": 0 },
                  "spine": { "node": 1 },
                  "head": { "node": 2 },
                  "leftUpperLeg": { "node": 3 },
                  "leftLowerLeg": { "node": 4 },
                  "leftFoot": { "node": 5 },
                  "rightUpperLeg": { "node": 6 },
                  "rightLowerLeg": { "node": 7 },
                  "rightFoot": { "node": 8 },
                  "leftUpperArm": { "node": 9 },
                  "leftLowerArm": { "node": 10 },
                  "leftHand": { "node": 11 },
                  "rightUpperArm": { "node": 12 },
                  "rightLowerArm": { "node": 13 },
                  "rightHand": { "node": 14 },
                  "leftToes": { "node": 15 },
                  "rightToes": { "node": 16 },
                  "chest": { "node": 17 },
                  "upperChest": { "node": 18 },
                  "neck": { "node": 19 },
                  "leftShoulder": { "node": 20 },
                  "rightShoulder": { "node": 21 },
                  "leftThumbMetacarpal": { "node": 22 },
                  "leftThumbProximal": { "node": 23 },
                  "leftThumbDistal": { "node": 24 },
                  "leftIndexProximal": { "node": 25 },
                  "leftIndexIntermediate": { "node": 26 },
                  "leftIndexDistal": { "node": 27 },
                  "leftMiddleProximal": { "node": 28 },
                  "leftMiddleIntermediate": { "node": 29 },
                  "leftMiddleDistal": { "node": 30 },
                  "leftRingProximal": { "node": 31 },
                  "leftRingIntermediate": { "node": 32 },
                  "leftRingDistal": { "node": 33 },
                  "leftLittleProximal": { "node": 34 },
                  "leftLittleIntermediate": { "node": 35 },
                  "leftLittleDistal": { "node": 36 },
                  "rightThumbMetacarpal": { "node": 37 },
                  "rightThumbProximal": { "node": 38 },
                  "rightThumbDistal": { "node": 39 },
                  "rightIndexProximal": { "node": 40 },
                  "rightIndexIntermediate": { "node": 41 },
                  "rightIndexDistal": { "node": 42 },
                  "rightMiddleProximal": { "node": 43 },
                  "rightMiddleIntermediate": { "node": 44 },
                  "rightMiddleDistal": { "node": 45 },
                  "rightRingProximal": { "node": 46 },
                  "rightRingIntermediate": { "node": 47 },
                  "rightRingDistal": { "node": 48 },
                  "rightLittleProximal": { "node": 49 },
                  "rightLittleIntermediate": { "node": 50 },
                  "rightLittleDistal": { "node": 51 },
                  "leftEye": { "node": 52 },
                  "rightEye": { "node": 53 },
                  "jaw": { "node": 54 }
                }
              }
            }
          }
        }
        """.data(using: .utf8)!

        let gltf = try JSONDecoder().decode(GLTF.self, from: json)
        let humanoid = try #require(gltf.extensions?.vrmcVrm?.humanoid)
        let bones = humanoid.humanBones

        // Verify node indices are correct
        #expect(bones.hips.node.value == 0)
        #expect(bones.spine.node.value == 1)
        #expect(bones.head.node.value == 2)
        #expect(bones.leftUpperLeg.node.value == 3)
        #expect(bones.leftLowerLeg.node.value == 4)
        #expect(bones.leftFoot.node.value == 5)
        #expect(bones.rightUpperLeg.node.value == 6)
        #expect(bones.rightLowerLeg.node.value == 7)
        #expect(bones.rightFoot.node.value == 8)
        #expect(bones.leftUpperArm.node.value == 9)
        #expect(bones.leftLowerArm.node.value == 10)
        #expect(bones.leftHand.node.value == 11)
        #expect(bones.rightUpperArm.node.value == 12)
        #expect(bones.rightLowerArm.node.value == 13)
        #expect(bones.rightHand.node.value == 14)
        #expect(bones.leftToes?.node.value == 15)
        #expect(bones.rightToes?.node.value == 16)
        #expect(bones.chest?.node.value == 17)
        #expect(bones.upperChest?.node.value == 18)
        #expect(bones.neck?.node.value == 19)
        #expect(bones.leftShoulder?.node.value == 20)
        #expect(bones.rightShoulder?.node.value == 21)
        #expect(bones.leftThumbMetacarpal?.node.value == 22)
        #expect(bones.leftThumbProximal?.node.value == 23)
        #expect(bones.leftThumbDistal?.node.value == 24)
        #expect(bones.leftIndexProximal?.node.value == 25)
        #expect(bones.leftIndexIntermediate?.node.value == 26)
        #expect(bones.leftIndexDistal?.node.value == 27)
        #expect(bones.leftMiddleProximal?.node.value == 28)
        #expect(bones.leftMiddleIntermediate?.node.value == 29)
        #expect(bones.leftMiddleDistal?.node.value == 30)
        #expect(bones.leftRingProximal?.node.value == 31)
        #expect(bones.leftRingIntermediate?.node.value == 32)
        #expect(bones.leftRingDistal?.node.value == 33)
        #expect(bones.leftLittleProximal?.node.value == 34)
        #expect(bones.leftLittleIntermediate?.node.value == 35)
        #expect(bones.leftLittleDistal?.node.value == 36)
        #expect(bones.rightThumbMetacarpal?.node.value == 37)
        #expect(bones.rightThumbProximal?.node.value == 38)
        #expect(bones.rightThumbDistal?.node.value == 39)
        #expect(bones.rightIndexProximal?.node.value == 40)
        #expect(bones.rightIndexIntermediate?.node.value == 41)
        #expect(bones.rightIndexDistal?.node.value == 42)
        #expect(bones.rightMiddleProximal?.node.value == 43)
        #expect(bones.rightMiddleIntermediate?.node.value == 44)
        #expect(bones.rightMiddleDistal?.node.value == 45)
        #expect(bones.rightRingProximal?.node.value == 46)
        #expect(bones.rightRingIntermediate?.node.value == 47)
        #expect(bones.rightRingDistal?.node.value == 48)
        #expect(bones.rightLittleProximal?.node.value == 49)
        #expect(bones.rightLittleIntermediate?.node.value == 50)
        #expect(bones.rightLittleDistal?.node.value == 51)
        #expect(bones.leftEye?.node.value == 52)
        #expect(bones.rightEye?.node.value == 53)
        #expect(bones.jaw?.node.value == 54)
    }
}
