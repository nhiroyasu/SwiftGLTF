import ModelIO
import SwiftGLTFCore

public class GLTFVRMHumanoid: MDLObject {
    public let nodeMap: [VRMHumanoidBoneName: NodeIndex]

    init(nodeMap: [VRMHumanoidBoneName: NodeIndex]) {
        self.nodeMap = nodeMap
        super.init()
    }
}
