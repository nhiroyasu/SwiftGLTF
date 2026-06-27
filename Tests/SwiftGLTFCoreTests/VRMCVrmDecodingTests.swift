import Testing
import Foundation
@testable import SwiftGLTFCore

final class VRMCVrmDecodingTests {
    @Test
    func testMinimalVRMCVrmDecoding() throws {
        let json = """
        {
          "asset": { "version": "2.0" },
          "extensions": {
            "VRMC_vrm": {
              "specVersion": "1.0",
              "meta": {
                "name": "Sample Avatar",
                "authors": ["Author"],
                "licenseUrl": "https://example.com/license"
              },
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
                  "rightHand": { "node": 14 }
                }
              }
            }
          }
        }
        """.data(using: .utf8)!

        let gltf = try JSONDecoder().decode(GLTF.self, from: json)
        let vrm = try #require(gltf.extensions?.vrmcVrm)

        #expect(vrm.specVersion == "1.0")
        #expect(vrm.meta.name == "Sample Avatar")
        #expect(vrm.meta.authors == ["Author"])
        #expect(vrm.meta.licenseUrl == "https://example.com/license")
        #expect(vrm.humanoid.humanBones.hips.node.value == 0)
        #expect(vrm.humanoid.humanBones.head.node.value == 2)
        #expect(vrm.humanoid.humanBones.rightHand.node.value == 14)
    }

    @Test
    func testVRMCVrmOptionalDataDecoding() throws {
        let json = """
        {
          "asset": { "version": "2.0" },
          "images": [
            { "uri": "thumbnail.png" }
          ],
          "extensions": {
            "VRMC_vrm": {
              "specVersion": "1.0",
              "meta": {
                "name": "Sample Avatar",
                "version": "1.2.3",
                "authors": ["Author", "Contributor"],
                "copyrightInformation": "Copyright",
                "contactInformation": "contact@example.com",
                "references": ["Reference"],
                "thirdPartyLicenses": "Third party license",
                "thumbnailImage": 0,
                "licenseUrl": "https://example.com/license",
                "avatarPermission": "everyone",
                "allowExcessivelyViolentUsage": true,
                "allowExcessivelySexualUsage": true,
                "commercialUsage": "corporation",
                "allowPoliticalOrReligiousUsage": true,
                "allowAntisocialOrHateUsage": true,
                "creditNotation": "unnecessary",
                "allowRedistribution": true,
                "modification": "allowModificationRedistribution",
                "otherLicenseUrl": "https://example.com/other-license"
              },
              "humanoid": {
                "humanBones": {
                  "hips": { "node": 0 },
                  "spine": { "node": 1 },
                  "chest": { "node": 2 },
                  "upperChest": { "node": 3 },
                  "neck": { "node": 4 },
                  "head": { "node": 5 },
                  "leftEye": { "node": 6 },
                  "rightEye": { "node": 7 },
                  "jaw": { "node": 8 },
                  "leftUpperLeg": { "node": 9 },
                  "leftLowerLeg": { "node": 10 },
                  "leftFoot": { "node": 11 },
                  "leftToes": { "node": 12 },
                  "rightUpperLeg": { "node": 13 },
                  "rightLowerLeg": { "node": 14 },
                  "rightFoot": { "node": 15 },
                  "rightToes": { "node": 16 },
                  "leftShoulder": { "node": 17 },
                  "leftUpperArm": { "node": 18 },
                  "leftLowerArm": { "node": 19 },
                  "leftHand": { "node": 20 },
                  "rightShoulder": { "node": 21 },
                  "rightUpperArm": { "node": 22 },
                  "rightLowerArm": { "node": 23 },
                  "rightHand": { "node": 24 },
                  "leftThumbMetacarpal": { "node": 25 },
                  "leftThumbProximal": { "node": 26 },
                  "leftThumbDistal": { "node": 27 },
                  "leftIndexProximal": { "node": 28 },
                  "leftIndexIntermediate": { "node": 29 },
                  "leftIndexDistal": { "node": 30 },
                  "leftMiddleProximal": { "node": 31 },
                  "leftMiddleIntermediate": { "node": 32 },
                  "leftMiddleDistal": { "node": 33 },
                  "leftRingProximal": { "node": 34 },
                  "leftRingIntermediate": { "node": 35 },
                  "leftRingDistal": { "node": 36 },
                  "leftLittleProximal": { "node": 37 },
                  "leftLittleIntermediate": { "node": 38 },
                  "leftLittleDistal": { "node": 39 },
                  "rightThumbMetacarpal": { "node": 40 },
                  "rightThumbProximal": { "node": 41 },
                  "rightThumbDistal": { "node": 42 },
                  "rightIndexProximal": { "node": 43 },
                  "rightIndexIntermediate": { "node": 44 },
                  "rightIndexDistal": { "node": 45 },
                  "rightMiddleProximal": { "node": 46 },
                  "rightMiddleIntermediate": { "node": 47 },
                  "rightMiddleDistal": { "node": 48 },
                  "rightRingProximal": { "node": 49 },
                  "rightRingIntermediate": { "node": 50 },
                  "rightRingDistal": { "node": 51 },
                  "rightLittleProximal": { "node": 52 },
                  "rightLittleIntermediate": { "node": 53 },
                  "rightLittleDistal": { "node": 54 }
                }
              },
              "firstPerson": {
                "meshAnnotations": [
                  { "node": 55, "type": "auto" },
                  { "node": 56, "type": "thirdPersonOnly" }
                ]
              },
              "lookAt": {
                "offsetFromHeadBone": [0.0, 0.1, 0.2],
                "type": "expression",
                "rangeMapHorizontalInner": { "inputMaxValue": 30.0, "outputScale": 10.0 },
                "rangeMapHorizontalOuter": { "inputMaxValue": 40.0, "outputScale": 1.0 },
                "rangeMapVerticalDown": { "inputMaxValue": 20.0, "outputScale": 0.5 },
                "rangeMapVerticalUp": { "inputMaxValue": 25.0, "outputScale": 0.75 }
              },
              "expressions": {
                "preset": {
                  "happy": {
                    "morphTargetBinds": [
                      { "node": 57, "index": 1, "weight": 0.8 }
                    ],
                    "materialColorBinds": [
                      {
                        "material": 2,
                        "type": "emissionColor",
                        "targetValue": [1.0, 0.5, 0.25, 1.0]
                      }
                    ],
                    "textureTransformBinds": [
                      {
                        "material": 3,
                        "scale": [0.5, 0.25],
                        "offset": [0.1, 0.2]
                      }
                    ],
                    "isBinary": true,
                    "overrideBlink": "block",
                    "overrideLookAt": "blend",
                    "overrideMouth": "none"
                  }
                },
                "custom": {
                  "customSmile": {
                    "morphTargetBinds": [
                      { "node": 58, "index": 2, "weight": 1.0 }
                    ]
                  }
                }
              }
            }
          }
        }
        """.data(using: .utf8)!

        let gltf = try JSONDecoder().decode(GLTF.self, from: json)
        let vrm = try #require(gltf.extensions?.vrmcVrm)

        #expect(vrm.meta.version == "1.2.3")
        #expect(vrm.meta.authors == ["Author", "Contributor"])
        #expect(vrm.meta.thumbnailImage?.value == 0)
        #expect(vrm.meta.avatarPermission == .everyone)
        #expect(vrm.meta.commercialUsage == .corporation)
        #expect(vrm.meta.creditNotation == .unnecessary)
        #expect(vrm.meta.modification == .allowModificationRedistribution)
        #expect(vrm.humanoid.humanBones.leftThumbMetacarpal?.node.value == 25)
        #expect(vrm.humanoid.humanBones.rightLittleDistal?.node.value == 54)
        #expect(vrm.firstPerson?.meshAnnotations?[0].node.value == 55)
        #expect(vrm.firstPerson?.meshAnnotations?[1].type == .thirdPersonOnly)
        #expect(vrm.lookAt?.offsetFromHeadBone == [0.0, 0.1, 0.2])
        #expect(vrm.lookAt?.type == .expression)
        #expect(vrm.lookAt?.rangeMapHorizontalInner?.inputMaxValue == 30.0)
        #expect(vrm.lookAt?.rangeMapVerticalUp?.outputScale == 0.75)

        let happy = try #require(vrm.expressions?.preset?.happy)
        #expect(happy.morphTargetBinds?[0].node.value == 57)
        #expect(happy.morphTargetBinds?[0].index == 1)
        #expect(happy.morphTargetBinds?[0].weight == 0.8)
        #expect(happy.materialColorBinds?[0].material == 2)
        #expect(happy.materialColorBinds?[0].type == .emissionColor)
        #expect(happy.materialColorBinds?[0].targetValue == [1.0, 0.5, 0.25, 1.0])
        #expect(happy.textureTransformBinds?[0].material == 3)
        #expect(happy.textureTransformBinds?[0].scale == [0.5, 0.25])
        #expect(happy.textureTransformBinds?[0].offset == [0.1, 0.2])
        #expect(happy.isBinary == true)
        #expect(happy.overrideBlink == .block)
        #expect(happy.overrideLookAt == .blend)
        #expect(happy.overrideMouth == .none)

        let customSmile = try #require(vrm.expressions?.custom?["customSmile"])
        #expect(customSmile.morphTargetBinds?[0].node.value == 58)
        #expect(customSmile.morphTargetBinds?[0].index == 2)
    }

    @Test
    func testVRMCVrmDefaultDecoding() throws {
        let json = """
        {
          "asset": { "version": "2.0" },
          "extensions": {
            "VRMC_vrm": {
              "specVersion": "1.0",
              "meta": {
                "name": "Sample Avatar",
                "authors": ["Author"],
                "licenseUrl": "https://example.com/license"
              },
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
                  "rightHand": { "node": 14 }
                }
              },
              "expressions": {
                "preset": {
                  "neutral": {
                    "textureTransformBinds": [
                      { "material": 0 }
                    ]
                  }
                }
              }
            }
          }
        }
        """.data(using: .utf8)!

        let gltf = try JSONDecoder().decode(GLTF.self, from: json)
        let vrm = try #require(gltf.extensions?.vrmcVrm)
        let neutral = try #require(vrm.expressions?.preset?.neutral)
        let textureTransformBind = try #require(neutral.textureTransformBinds?.first)

        #expect(vrm.meta.avatarPermission == .onlyAuthor)
        #expect(vrm.meta.allowExcessivelyViolentUsage == false)
        #expect(vrm.meta.allowExcessivelySexualUsage == false)
        #expect(vrm.meta.commercialUsage == .personalNonProfit)
        #expect(vrm.meta.allowPoliticalOrReligiousUsage == false)
        #expect(vrm.meta.allowAntisocialOrHateUsage == false)
        #expect(vrm.meta.creditNotation == .required)
        #expect(vrm.meta.allowRedistribution == false)
        #expect(vrm.meta.modification == .prohibited)
        #expect(neutral.isBinary == false)
        #expect(neutral.overrideBlink == .none)
        #expect(neutral.overrideLookAt == .none)
        #expect(neutral.overrideMouth == .none)
        #expect(textureTransformBind.scale == [1, 1])
        #expect(textureTransformBind.offset == [0, 0])
    }
}
