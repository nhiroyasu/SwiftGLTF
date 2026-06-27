import ModelIO
import SwiftGLTFCore

public class GLTFCameraNode: MDLObject {
    public let nodeIndex: NodeIndex
    public let cameraIndex: CameraIndex
    public let camera: MDLCamera

    public init(
        nodeIndex: NodeIndex,
        cameraIndex: CameraIndex,
        camera: MDLCamera
    ) {
        self.nodeIndex = nodeIndex
        self.cameraIndex = cameraIndex
        self.camera = camera
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
