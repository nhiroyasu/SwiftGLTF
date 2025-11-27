import ModelIO
import SwiftGLTFCore

public final class GLTFVRMHumanoid: MDLObject {
    public let humanoid: VRMCHumanoid

    init(humanoid: VRMCHumanoid) {
        self.humanoid = humanoid
        super.init()
    }
}
