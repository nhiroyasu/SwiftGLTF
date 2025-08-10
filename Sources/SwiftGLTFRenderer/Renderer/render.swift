import MetalKit
import SwiftGLTFShaderTypes

func drawSkybox(
    renderEncoder: MTLRenderCommandEncoder,
    mesh: SkyboxMesh,
    vpMatrixBuffer: MTLBuffer,
    specularCubeMapTexture: MTLTexture
) {
    renderEncoder.setRenderPipelineState(mesh.pso)
    renderEncoder.setDepthStencilState(mesh.dso)
    renderEncoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: 0)
    renderEncoder.setVertexBuffer(vpMatrixBuffer, offset: 0, index: 1)
    renderEncoder.setFragmentTexture(specularCubeMapTexture, index: 0)

    renderEncoder.drawIndexedPrimitives(
        type: .triangle,
        indexCount: mesh.indexCount,
        indexType: mesh.indexType,
        indexBuffer: mesh.indexBuffer,
        indexBufferOffset: 0
    )
}

func drawPBR(
    renderEncoder: MTLRenderCommandEncoder,
    pipelineStateOpaque: MTLRenderPipelineState,
    pipelineStateTransparent: MTLRenderPipelineState,
    depthStencilStateWrite: MTLDepthStencilState,
    depthStencilStateNoWrite: MTLDepthStencilState,
    vertexResources: [MTLHeap],
    fragmentResources: [MTLHeap],
    meshes: [PBRMesh],
    vertexParams: MTLBuffer,
    envMapArgBuffer: MTLBuffer,
    fragmentParams: MTLBuffer
) {
    renderEncoder.useHeaps(vertexResources, stages: .vertex)
    renderEncoder.useHeaps(fragmentResources, stages: .fragment)
    renderEncoder.setVertexBuffer(vertexParams, offset: 0, index: 2)
    renderEncoder.setFragmentBuffer(envMapArgBuffer, offset: 0, index: 1)
    renderEncoder.setFragmentBuffer(fragmentParams, offset: 0, index: 2)
    // Read camera position for sorting
    let fragParamsPtr = fragmentParams.contents().bindMemory(to: PBRFragmentVariableParameters.self, capacity: 1)
    let cameraPos = fragParamsPtr.pointee.viewPosition

    // Opaque pass
    renderEncoder.setRenderPipelineState(pipelineStateOpaque)
    renderEncoder.setDepthStencilState(depthStencilStateWrite)
    for mesh in meshes {
        renderEncoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBuffer(mesh.modelBuffer, offset: 0, index: 1)
        for submesh in mesh.submeshes where submesh.alphaMode == .opaque {
            renderEncoder.setFragmentBuffer(submesh.fragmentArgumentBuffer, offset: 0, index: 0)
            renderEncoder.drawIndexedPrimitives(
                type: submesh.primitiveType,
                indexCount: submesh.indexCount,
                indexType: submesh.indexType,
                indexBuffer: submesh.indexBuffer.buffer,
                indexBufferOffset: submesh.indexBuffer.offset
            )
        }
    }

    // Masked (cutout) pass
    renderEncoder.setRenderPipelineState(pipelineStateOpaque)
    renderEncoder.setDepthStencilState(depthStencilStateWrite)
    for mesh in meshes {
        renderEncoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBuffer(mesh.modelBuffer, offset: 0, index: 1)
        for submesh in mesh.submeshes where submesh.alphaMode == .mask {
            renderEncoder.setFragmentBuffer(submesh.fragmentArgumentBuffer, offset: 0, index: 0)
            renderEncoder.drawIndexedPrimitives(
                type: submesh.primitiveType,
                indexCount: submesh.indexCount,
                indexType: submesh.indexType,
                indexBuffer: submesh.indexBuffer.buffer,
                indexBufferOffset: submesh.indexBuffer.offset
            )
        }
    }

    // Transparent pass (sort back-to-front per mesh)
    struct TransparentDrawItem { let distanceSq: Float; let meshIndex: Int; let submeshIndex: Int }
    var transparentItems: [TransparentDrawItem] = []
    for (mi, mesh) in meshes.enumerated() {
        // approximate mesh position by translation part of model matrix
        let model = mesh.modelMatrix
        // TODO: 多分ちゃんと距離計算できてない
        let meshPos = SIMD3<Float>(model.columns.3.x, model.columns.3.y, model.columns.3.z)
        let d = meshPos - cameraPos
        let distSq = simd_dot(d, d)
        for (si, submesh) in mesh.submeshes.enumerated() where submesh.alphaMode == .blend {
            transparentItems.append(TransparentDrawItem(distanceSq: distSq, meshIndex: mi, submeshIndex: si))
        }
    }
    transparentItems.sort { $0.distanceSq > $1.distanceSq } // back-to-front
    renderEncoder.setRenderPipelineState(pipelineStateTransparent)
    renderEncoder.setDepthStencilState(depthStencilStateNoWrite)
    for item in transparentItems {
        let mesh = meshes[item.meshIndex]
        let submesh = mesh.submeshes[item.submeshIndex]
        renderEncoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBuffer(mesh.modelBuffer, offset: 0, index: 1)
        renderEncoder.setFragmentBuffer(submesh.fragmentArgumentBuffer, offset: 0, index: 0)
        renderEncoder.drawIndexedPrimitives(
            type: submesh.primitiveType,
            indexCount: submesh.indexCount,
            indexType: submesh.indexType,
            indexBuffer: submesh.indexBuffer.buffer,
            indexBufferOffset: submesh.indexBuffer.offset
        )
    }

}

func drawWireframe(
    renderEncoder: MTLRenderCommandEncoder,
    pipelineState: MTLRenderPipelineState,
    depthStencilState: MTLDepthStencilState,
    meshes: [PBRMesh],
    vertexParams: MTLBuffer
) {
    renderEncoder.setTriangleFillMode(.lines)
    renderEncoder.setRenderPipelineState(pipelineState)
    renderEncoder.setDepthStencilState(depthStencilState)
    renderEncoder.setVertexBuffer(vertexParams, offset: 0, index: 2)
    for mesh in meshes {
        renderEncoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBuffer(mesh.modelBuffer, offset: 0, index: 1)
        for submesh in mesh.submeshes {
            renderEncoder.drawIndexedPrimitives(
                type: submesh.primitiveType,
                indexCount: submesh.indexCount,
                indexType: submesh.indexType,
                indexBuffer: submesh.indexBuffer.buffer,
                indexBufferOffset: submesh.indexBuffer.offset
            )
        }
    }
}
