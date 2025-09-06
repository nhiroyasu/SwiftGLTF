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
    worldTransformBuffer: MTLBuffer,
    jointsBuffer: MTLBuffer,
    inverseBindMatricesBuffer: MTLBuffer,
    morphWeightsBuffer: MTLBuffer,
    morphDispatchesBuffer: MTLBuffer,
    envMapArgBuffer: MTLBuffer,
    fragmentParams: MTLBuffer
) {
    renderEncoder.setFrontFacing(.counterClockwise)
    renderEncoder.useHeaps(vertexResources, stages: .vertex)
    renderEncoder.useHeaps(fragmentResources, stages: .fragment)
    renderEncoder.setVertexBuffer(vertexParams, offset: 0, index: 2)
    renderEncoder.setVertexBuffer(worldTransformBuffer, offset: 0, index: 3)
    renderEncoder.setVertexBuffer(jointsBuffer, offset: 0, index: 4)
    renderEncoder.setVertexBuffer(inverseBindMatricesBuffer, offset: 0, index: 5)
    renderEncoder.setVertexBuffer(morphWeightsBuffer, offset: 0, index: 6)
    renderEncoder.setVertexBuffer(morphDispatchesBuffer, offset: 0, index: 7)
    renderEncoder.setFragmentBuffer(envMapArgBuffer, offset: 0, index: 1)
    renderEncoder.setFragmentBuffer(fragmentParams, offset: 0, index: 2)

    // Opaque pass
    renderEncoder.setRenderPipelineState(pipelineStateOpaque)
    renderEncoder.setDepthStencilState(depthStencilStateWrite)
    for mesh in meshes {
        renderEncoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBuffer(mesh.vertexArgumentBuffer, offset: 0, index: 1)
        for submesh in mesh.submeshes where submesh.alphaMode == .opaque {
            renderEncoder.setFragmentBuffer(submesh.fragmentArgumentBuffer, offset: 0, index: 0)
            // Culling control per material
            renderEncoder.setCullMode(submesh.doubleSided ? .none : .back)
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
        renderEncoder.setVertexBuffer(mesh.vertexArgumentBuffer, offset: 0, index: 1)
        for submesh in mesh.submeshes where submesh.alphaMode == .mask {
            renderEncoder.setFragmentBuffer(submesh.fragmentArgumentBuffer, offset: 0, index: 0)
            renderEncoder.setCullMode(submesh.doubleSided ? .none : .back)
            renderEncoder.drawIndexedPrimitives(
                type: submesh.primitiveType,
                indexCount: submesh.indexCount,
                indexType: submesh.indexType,
                indexBuffer: submesh.indexBuffer.buffer,
                indexBufferOffset: submesh.indexBuffer.offset
            )
        }
    }

    // Read camera position for sorting
    let fragParamsPtr = fragmentParams.contents().bindMemory(to: PBRFragmentVariableParameters.self, capacity: 1)
    let cameraPos = fragParamsPtr.pointee.viewPosition

    // Transparent pass (sort back-to-front per submesh using mesh center)
    // TODO: Need to sort considering Morph
    struct TransparentDrawItem { let distanceSq: Float; let meshIndex: Int; let submeshIndex: Int }
    var transparentItems: [TransparentDrawItem] = []
    for (mi, mesh) in meshes.enumerated() {
        let model = mesh.modelMatrix
        for (si, submesh) in mesh.submeshes.enumerated() where submesh.alphaMode == .blend {
            let center = submesh.centerModelSpace
            let worldPos4 = model * SIMD4<Float>(center.x, center.y, center.z, 1.0)
            let worldPos = SIMD3<Float>(worldPos4.x, worldPos4.y, worldPos4.z)
            let d = worldPos - cameraPos
            let distSq = simd_dot(d, d)
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
        renderEncoder.setVertexBuffer(mesh.vertexArgumentBuffer, offset: 0, index: 1)
        renderEncoder.setFragmentBuffer(submesh.fragmentArgumentBuffer, offset: 0, index: 0)
        renderEncoder.setCullMode(submesh.doubleSided ? .none : .back)
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
        renderEncoder.setVertexBuffer(mesh.vertexArgumentBuffer, offset: 0, index: 1)
        for submesh in mesh.submeshes {
            renderEncoder.setCullMode(submesh.doubleSided ? .none : .back)
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
