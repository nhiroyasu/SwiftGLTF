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
    mesh: PBRMesh,
    viewBuffer: MTLBuffer,
    projectionBuffer: MTLBuffer,
    pbrSceneUniformsBuffer: MTLBuffer,
    specularCubeMapTexture: MTLTexture,
    irradianceCubeMapTexture: MTLTexture,
    brdfLUT: MTLTexture
) {
    renderEncoder.setRenderPipelineState(mesh.pso)
    renderEncoder.setDepthStencilState(mesh.dso)

    renderEncoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: 0)
    renderEncoder.setVertexBuffer(mesh.modelBuffer, offset: 0, index: 1)
    renderEncoder.setVertexBuffer(viewBuffer, offset: 0, index: 2)
    renderEncoder.setVertexBuffer(projectionBuffer, offset: 0, index: 3)
    renderEncoder.setVertexBuffer(mesh.normalMatrixBuffer, offset: 0, index: 4)
    renderEncoder.setFragmentBuffer(mesh.vertexUniformsBuffer, offset: 0, index: 0)
    renderEncoder.setFragmentBuffer(pbrSceneUniformsBuffer, offset: 0, index: 1)
    renderEncoder.setFragmentTexture(specularCubeMapTexture, index: 0)
    renderEncoder.setFragmentTexture(irradianceCubeMapTexture, index: 1)
    renderEncoder.setFragmentTexture(brdfLUT, index: 2)

    for submesh in mesh.submeshes {
        // Set baseColor, normal, metallic and roughness textures/samplers
        renderEncoder.setFragmentTexture(submesh.baseColorTexture, index: 3)
        renderEncoder.setFragmentSamplerState(submesh.baseColorSampler, index: 0)
        renderEncoder.setFragmentTexture(submesh.normalTexture, index: 4)
        renderEncoder.setFragmentSamplerState(submesh.normalSampler, index: 1)
        renderEncoder.setFragmentTexture(submesh.metallicRoughnessTexture, index: 5)
        renderEncoder.setFragmentSamplerState(submesh.metallicRoughnessSampler, index: 2)
        renderEncoder.setFragmentTexture(submesh.emissiveTexture, index: 6)
        renderEncoder.setFragmentSamplerState(submesh.emissiveSampler, index: 3)
        renderEncoder.setFragmentTexture(submesh.occlusionTexture, index: 7)
        renderEncoder.setFragmentSamplerState(submesh.occlusionSampler, index: 4)

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
    mesh: PBRMesh,
    viewBuffer: MTLBuffer,
    projectionBuffer: MTLBuffer
) {
    renderEncoder.setRenderPipelineState(mesh.pso)
    renderEncoder.setDepthStencilState(mesh.dso)

    renderEncoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: 0)
    renderEncoder.setVertexBuffer(mesh.modelBuffer, offset: 0, index: 1)
    renderEncoder.setVertexBuffer(viewBuffer, offset: 0, index: 2)
    renderEncoder.setVertexBuffer(projectionBuffer, offset: 0, index: 3)
    renderEncoder.setTriangleFillMode(.lines)

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
