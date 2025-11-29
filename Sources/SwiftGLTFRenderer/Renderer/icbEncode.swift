import MetalKit
import SwiftGLTFShaderTypes

func encodeDrawingSkybox(
    cmd: MTLIndirectRenderCommand,
    mesh: SkyboxMesh,
    worldTransformBuffer: MTLBuffer,
    cameraIndexBuffer: MTLBuffer,
    freeCameraUniformsBuffer: MTLBuffer,
    nodeCameraUniformsBuffer: MTLBuffer,
    fragmentArgumentsBuffer: MTLBuffer
) {
    cmd.setVertexBuffer(mesh.vertexBuffer, offset: 0, at: 0)
    cmd.setVertexBuffer(worldTransformBuffer, offset: 0, at: 1)
    cmd.setVertexBuffer(cameraIndexBuffer, offset: 0, at: 2)
    cmd.setVertexBuffer(freeCameraUniformsBuffer, offset: 0, at: 3)
    cmd.setVertexBuffer(nodeCameraUniformsBuffer, offset: 0, at: 4)

    cmd.setFragmentBuffer(fragmentArgumentsBuffer, offset: 0, at: 0)

    cmd.drawIndexedPrimitives(
        .triangle,
        indexCount: mesh.indexCount,
        indexType: mesh.indexType,
        indexBuffer: mesh.indexBuffer,
        indexBufferOffset: 0,
        instanceCount: 1,
        baseVertex: 0,
        baseInstance: 0
    )
}
