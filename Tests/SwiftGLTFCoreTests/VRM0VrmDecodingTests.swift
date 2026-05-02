import Testing
import Foundation
@testable import SwiftGLTFCore

final class VRM0VrmDecodingTests {
    @Test
    func testMinimalVRM0VrmDecoding() throws {
        let json = """
        {
          "asset": { "version": "2.0" },
          "extensions": {
            "VRM": {
              "specVersion": "0.0",
              "meta": {
                "title": "Sample Avatar",
                "author": "Author",
                "licenseName": "Redistribution_Prohibited"
              },
              "humanoid": {
                "humanBones": [
                  { "bone": "hips", "node": 0 },
                  { "bone": "head", "node": 1 },
                  { "bone": "leftUpperArm", "node": 2 },
                  { "bone": "rightUpperArm", "node": 3 }
                ]
              }
            }
          }
        }
        """.data(using: .utf8)!

        let gltf = try JSONDecoder().decode(GLTF.self, from: json)
        let vrm = try #require(gltf.extensions?.vrm0)
        let humanoid = try #require(vrm.humanoid)

        #expect(vrm.specVersion == "0.0")
        #expect(vrm.meta?.title == "Sample Avatar")
        #expect(vrm.meta?.author == "Author")
        #expect(vrm.meta?.licenseName == "Redistribution_Prohibited")
        #expect(humanoid.humanBones?.count == 4)
        #expect(humanoid.nodeMap[.hips]?.value == 0)
        #expect(humanoid.nodeMap[.head]?.value == 1)
        #expect(humanoid.nodeMap[.leftUpperArm]?.value == 2)
        #expect(humanoid.nodeMap[.rightUpperArm]?.value == 3)
    }

    @Test
    func testVRM0VrmOptionalDataDecoding() throws {
        let json = """
        {
          "asset": { "version": "2.0" },
          "extensions": {
            "VRM": {
              "exporterVersion": "UniVRM-0.99.0",
              "specVersion": "0.0",
              "meta": {
                "title": "Optional Avatar",
                "version": "1.2.3",
                "author": "Author",
                "contactInformation": "contact@example.com",
                "reference": "Reference",
                "texture": 4,
                "allowedUserName": "Everyone",
                "violentUssageName": "Disallow",
                "sexualUssageName": "Allow",
                "commercialUssageName": "Allow",
                "otherPermissionUrl": "https://example.com/permission",
                "licenseName": "Other",
                "otherLicenseUrl": "https://example.com/license"
              },
              "humanoid": {
                "humanBones": [
                  {
                    "bone": "hips",
                    "node": 0,
                    "useDefaultValues": true,
                    "min": { "x": -1.0, "y": -2.0, "z": -3.0 },
                    "max": { "x": 1.0, "y": 2.0, "z": 3.0 },
                    "center": { "x": 0.0, "y": 1.0, "z": 2.0 },
                    "axisLength": 0.5
                  },
                  { "bone": "leftThumbIntermediate", "node": 1 }
                ],
                "armStretch": 0.05,
                "legStretch": 0.06,
                "upperArmTwist": 0.5,
                "lowerArmTwist": 0.6,
                "upperLegTwist": 0.7,
                "lowerLegTwist": 0.8,
                "feetSpacing": 0.1,
                "hasTranslationDoF": true
              },
              "firstPerson": {
                "firstPersonBone": 2,
                "firstPersonBoneOffset": { "x": 0.0, "y": 0.1, "z": 0.2 },
                "meshAnnotations": [
                  { "mesh": 0, "firstPersonFlag": "Auto" },
                  { "mesh": 1, "firstPersonFlag": "ThirdPersonOnly" }
                ],
                "lookAtTypeName": "Bone",
                "lookAtHorizontalInner": {
                  "curve": [0.0, 0.1, 0.2, 0.3],
                  "xRange": 90.0,
                  "yRange": 10.0
                }
              },
              "blendShapeMaster": {
                "blendShapeGroups": [
                  {
                    "name": "Joy",
                    "presetName": "joy",
                    "binds": [
                      { "mesh": 0, "index": 1, "weight": 100.0 }
                    ],
                    "materialValues": [
                      {
                        "materialName": "Face",
                        "propertyName": "_Color",
                        "targetValue": [1.0, 0.5, 0.25, 1.0]
                      }
                    ],
                    "isBinary": true
                  }
                ]
              },
              "secondaryAnimation": {
                "boneGroups": [
                  {
                    "comment": "Hair",
                    "stiffiness": 0.2,
                    "gravityPower": 0.3,
                    "gravityDir": { "x": 0.0, "y": -1.0, "z": 0.0 },
                    "dragForce": 0.4,
                    "center": 3,
                    "hitRadius": 0.05,
                    "bones": [4, 5],
                    "colliderGroups": [0]
                  }
                ],
                "colliderGroups": [
                  {
                    "node": 6,
                    "colliders": [
                      {
                        "offset": { "x": 0.1, "y": 0.2, "z": 0.3 },
                        "radius": 0.4
                      }
                    ]
                  }
                ]
              },
              "materialProperties": [
                {
                  "name": "Material",
                  "shader": "VRM/MToon",
                  "renderQueue": 2000,
                  "floatProperties": {
                    "_Cutoff": 0.5
                  },
                  "vectorProperties": {
                    "_Color": [1.0, 0.5, 0.25, 1.0]
                  },
                  "textureProperties": {
                    "_MainTex": 0
                  },
                  "keywordMap": {
                    "_ALPHATEST_ON": true
                  },
                  "tagMap": {
                    "RenderType": "Opaque"
                  }
                }
              ]
            }
          }
        }
        """.data(using: .utf8)!

        let gltf = try JSONDecoder().decode(GLTF.self, from: json)
        let vrm = try #require(gltf.extensions?.vrm0)
        let humanoid = try #require(vrm.humanoid)
        let hips = try #require(humanoid.humanBones?.first)
        let firstPerson = try #require(vrm.firstPerson)
        let blendShapeGroup = try #require(vrm.blendShapeMaster?.blendShapeGroups?.first)
        let boneGroup = try #require(vrm.secondaryAnimation?.boneGroups?.first)
        let colliderGroup = try #require(vrm.secondaryAnimation?.colliderGroups?.first)
        let materialProperty = try #require(vrm.materialProperties?.first)

        #expect(vrm.exporterVersion == "UniVRM-0.99.0")
        #expect(vrm.meta?.texture?.value == 4)
        #expect(vrm.meta?.otherLicenseUrl == "https://example.com/license")
        #expect(hips.useDefaultValues == true)
        #expect(hips.min?.x == -1.0)
        #expect(hips.max?.z == 3.0)
        #expect(hips.center?.y == 1.0)
        #expect(hips.axisLength == 0.5)
        #expect(humanoid.armStretch == 0.05)
        #expect(humanoid.hasTranslationDoF == true)
        #expect(VRM0HumanoidBoneName.leftThumbProximal.vrmHumanoidBoneName == nil)
        #expect(VRM0HumanoidBoneName.leftThumbIntermediate.vrmHumanoidBoneName == nil)
        #expect(VRM0HumanoidBoneName.leftThumbDistal.vrmHumanoidBoneName == nil)

        #expect(firstPerson.firstPersonBone?.value == 2)
        #expect(firstPerson.meshAnnotations?[1].firstPersonFlag == "ThirdPersonOnly")
        #expect(firstPerson.lookAtTypeName == "Bone")
        #expect(firstPerson.lookAtHorizontalInner?.curve == [0.0, 0.1, 0.2, 0.3])
        #expect(firstPerson.lookAtHorizontalInner?.xRange == 90.0)
        #expect(firstPerson.lookAtHorizontalInner?.yRange == 10.0)

        #expect(blendShapeGroup.name == "Joy")
        #expect(blendShapeGroup.binds?.first?.index == 1)
        #expect(blendShapeGroup.materialValues?.first?.propertyName == "_Color")
        #expect(blendShapeGroup.materialValues?.first?.targetValue == [1.0, 0.5, 0.25, 1.0])
        #expect(blendShapeGroup.isBinary == true)

        #expect(boneGroup.comment == "Hair")
        #expect(boneGroup.stiffiness == 0.2)
        #expect(boneGroup.gravityDir?.y == -1.0)
        #expect(boneGroup.center?.value == 3)
        #expect(boneGroup.bones?.map(\.value) == [4, 5])
        #expect(boneGroup.colliderGroups == [0])
        #expect(colliderGroup.node?.value == 6)
        #expect(colliderGroup.colliders?.first?.offset?.z == 0.3)
        #expect(colliderGroup.colliders?.first?.radius == 0.4)

        #expect(materialProperty.name == "Material")
        #expect(materialProperty.shader == "VRM/MToon")
        #expect(materialProperty.floatProperties?["_Cutoff"] == 0.5)
        #expect(materialProperty.vectorProperties?["_Color"] == [1.0, 0.5, 0.25, 1.0])
        #expect(materialProperty.textureProperties?["_MainTex"]?.value == 0)
        #expect(materialProperty.keywordMap?["_ALPHATEST_ON"] == true)
        #expect(materialProperty.tagMap?["RenderType"] == "Opaque")
    }
}
