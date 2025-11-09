import ModelIO
import SwiftGLTFCore

public class GLTFCameraNode: MDLObject {
    public let nodeIndex: Int
    public let cameraIndex: CameraIndex
    public let camera: MDLCamera

    public init(
        nodeIndex: Int,
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
