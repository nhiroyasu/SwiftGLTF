import ModelIO
import SwiftGLTFCore

public class GLTFCamera: MDLCamera {
    public var xmag: Float?
    public var ymag: Float?

    init(perspective: PerspectiveCamera) {
        super.init()
        projection = .perspective
        fieldOfView = perspective.yfov * 180.0 / .pi
        nearVisibilityDistance = max(perspective.znear, 0.0001)
        farVisibilityDistance = perspective.zfar ?? .infinity
        sensorAspect = perspective.aspectRatio ?? -1.0
    }

    init(orthographic: OrthographicCamera) {
        super.init()
        projection = .orthographic
        nearVisibilityDistance = max(orthographic.znear, 0.0001)
        farVisibilityDistance = orthographic.zfar
        xmag = orthographic.xmag
        ymag = orthographic.ymag
    }

    public override var projectionMatrix: matrix_float4x4 {
        switch projection {
        case .perspective:
            return perspectiveMatrix(
                fov: fieldOfView * .pi / 180.0,
                aspect: sensorAspect > 0 ? sensorAspect : 1.0,
                near: nearVisibilityDistance,
                far: farVisibilityDistance
            )

        case .orthographic:
            return orthographicMatrix(
                xmag: xmag ?? 1.0,
                ymag: ymag ?? 1.0,
                near: nearVisibilityDistance,
                far: farVisibilityDistance
            )

        default:
            return super.projectionMatrix
        }
    }
}
