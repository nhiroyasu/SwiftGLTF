import MetalKit

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
    pipelineState: MTLRenderPipelineState,
    depthStencilState: MTLDepthStencilState,
    vertexResources: [MTLHeap],
    fragmentResources: [MTLHeap],
    meshes: [PBRMesh],
    vertexParams: MTLBuffer,
    skyboxArgBuffer: MTLBuffer,
    fragmentParams: MTLBuffer
) {
    renderEncoder.setRenderPipelineState(pipelineState)
    renderEncoder.setDepthStencilState(depthStencilState)
    renderEncoder.useHeaps(vertexResources, stages: .vertex)
    renderEncoder.useHeaps(fragmentResources, stages: .fragment)
    renderEncoder.setVertexBuffer(vertexParams, offset: 0, index: 2)
    renderEncoder.setFragmentBuffer(skyboxArgBuffer, offset: 0, index: 1)
    renderEncoder.setFragmentBuffer(fragmentParams, offset: 0, index: 2)
    for mesh in meshes {
        renderEncoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBuffer(mesh.modelBuffer, offset: 0, index: 1)

        for submesh in mesh.submeshes {
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
