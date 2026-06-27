import Foundation
import ModelIO
import Testing
import SwiftGLTFCore
@testable import SwiftGLTFParser

final class VRMExpressionNormalizationTests {
    @Test
    func testVRM1ExpressionsNormalizeToCommonExpressions() throws {
        let gltf = try decodeGLTF(
            """
            {
              "asset": { "version": "2.0" },
              "extensions": {
                "VRMC_vrm": {
                  "specVersion": "1.0",
                  "meta": {
                    "name": "avatar",
                    "authors": ["author"],
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
                      "happy": {
                        "isBinary": true,
                        "morphTargetBinds": [
                          { "node": 2, "index": 1, "weight": 0.8 }
                        ],
                        "overrideBlink": "blend"
                      }
                    },
                    "custom": {
                      "smile": {
                        "morphTargetBinds": [
                          { "node": 2, "index": 2, "weight": 0.4 }
                        ]
                      }
                    }
                  }
                }
              }
            }
            """
        )

        let expressions = try #require(makeGLTFVRMExpressions(from: gltf)?.expressions)
        let happy = try #require(expressions.first { $0.key == VRMExpressionKey.happy })
        let smile = try #require(expressions.first { $0.key == VRMExpressionKey.custom("smile") })

        #expect(happy.isBinary == true)
        #expect(happy.overrideBlink == .blend)
        #expect(happy.morphTargetBinds.first?.node?.value == 2)
        #expect(happy.morphTargetBinds.first?.index == 1)
        #expect(abs((happy.morphTargetBinds.first?.weight ?? 0) - 0.8) < 0.0001)
        #expect(smile.morphTargetBinds.first?.node?.value == 2)
        #expect(smile.morphTargetBinds.first?.index == 2)
    }

    @Test
    func testVRM0BlendShapeMasterNormalizesPresetNamesAndWeights() throws {
        let gltf = try decodeGLTF(
            """
            {
              "asset": { "version": "2.0" },
              "extensions": {
                "VRM": {
                  "blendShapeMaster": {
                    "blendShapeGroups": [
                      {
                        "name": "Joy",
                        "presetName": "joy",
                        "binds": [
                          { "mesh": 3, "index": 1, "weight": 80 }
                        ],
                        "isBinary": true
                      },
                      {
                        "name": "BlinkLeft",
                        "presetName": "blink_l",
                        "binds": [
                          { "mesh": 4, "index": 2, "weight": 100 }
                        ]
                      }
                    ]
                  }
                }
              }
            }
            """
        )

        let expressions = try #require(makeGLTFVRMExpressions(from: gltf)?.expressions)
        let happy = try #require(expressions.first { $0.key == VRMExpressionKey.happy })
        let blinkLeft = try #require(expressions.first { $0.key == VRMExpressionKey.blinkLeft })

        #expect(happy.isBinary == true)
        #expect(happy.morphTargetBinds.first?.mesh?.value == 3)
        #expect(abs((happy.morphTargetBinds.first?.weight ?? 0) - 0.8) < 0.0001)
        #expect(blinkLeft.morphTargetBinds.first?.mesh?.value == 4)
        #expect(abs((blinkLeft.morphTargetBinds.first?.weight ?? 0) - 1.0) < 0.0001)
    }

    @Test
    func testVRM0BlendShapeBindKeepsMeshReference() throws {
        let gltf = try decodeGLTF(
            """
            {
              "asset": { "version": "2.0" },
              "nodes": [
                { "mesh": 1, "children": [1, 2] },
                { "mesh": 2 },
                { "mesh": 1 }
              ],
              "scenes": [
                { "nodes": [0] }
              ],
              "extensions": {
                "VRM": {
                  "blendShapeMaster": {
                    "blendShapeGroups": [
                      {
                        "name": "Joy",
                        "presetName": "joy",
                        "binds": [
                          { "mesh": 1, "index": 1, "weight": 80 }
                        ]
                      }
                    ]
                  }
                }
              }
            }
            """
        )

        let expressions = try #require(makeGLTFVRMExpressions(from: gltf))
        let bind = try #require(expressions.expressions.first?.morphTargetBinds.first)
        #expect(bind.mesh?.value == 1)
        #expect(bind.node == nil)
    }

    private func decodeGLTF(_ json: String) throws -> GLTF {
        try JSONDecoder().decode(GLTF.self, from: Data(json.utf8))
    }
}
