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
    worldTransformBuffer: MTLBuffer,
    boundingSpheresBuffer: MTLBuffer,
    jointsBuffer: MTLBuffer,
    inverseBindMatricesBuffer: MTLBuffer,
    morphWeightsBuffer: MTLBuffer,
    morphDispatchesBuffer: MTLBuffer,
    envMapArgBuffer: MTLBuffer,
    fragmentParams: MTLBuffer,
    mvpUniformBuffer: MTLBuffer,
    viewPos: SIMD3<Float>
) {
    renderEncoder.setFrontFacing(.counterClockwise)
    renderEncoder.useHeaps(vertexResources, stages: .vertex)
    renderEncoder.useHeaps(fragmentResources, stages: .fragment)
    renderEncoder.setVertexBuffer(mvpUniformBuffer, offset: 0, index: 2)
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

    // Transparent pass (sort back-to-front per submesh using bounding sphere center)
    // NOTE: バウンディングスフィアはバインドポーズ（非スキン・非モーフ）基準で算出しているため、
    //       スキン／モーフによる形状変化は反映していない。描画順の判断としては保守的に許容する。
    // NOTE: en: Since the bounding sphere is calculated based on the bind pose (non-skin, non-morph),
    //       it does not reflect shape changes due to skin/morph. It is conservatively
    struct TransparentDrawItem { let distanceSq: Float; let meshIndex: Int; let submeshIndex: Int }
    var transparentItems: [TransparentDrawItem] = []
    let spherePtr = boundingSpheresBuffer.contents().bindMemory(to: SIMD4<Float>.self, capacity: meshes.count)
    let worldPtr = worldTransformBuffer.contents().bindMemory(to: simd_float4x4.self, capacity: worldTransformBuffer.length / MemoryLayout<simd_float4x4>.stride)
    for (mi, mesh) in meshes.enumerated() {
        let s = spherePtr[mi]
        let cModel = SIMD4<Float>(s.x, s.y, s.z, 1.0)
        let world = worldPtr[max(mesh.transformIndex, 0)]
        let cWorld4 = world * cModel
        let cWorld = SIMD3<Float>(cWorld4.x, cWorld4.y, cWorld4.z)
        for (si, submesh) in mesh.submeshes.enumerated() where submesh.alphaMode == .blend {
            let d = cWorld - viewPos
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
    meshes: [WireframeMesh],
    vertexParams: MTLBuffer,
    worldTransformBuffer: MTLBuffer
) {
    renderEncoder.setTriangleFillMode(.lines)
    renderEncoder.setRenderPipelineState(pipelineState)
    renderEncoder.setDepthStencilState(depthStencilState)
    renderEncoder.setVertexBuffer(vertexParams, offset: 0, index: 1)
    renderEncoder.setVertexBuffer(worldTransformBuffer, offset: 0, index: 2)
    for mesh in meshes {
        renderEncoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: 0)
        var transformIndex: Int = mesh.transformIndex
        renderEncoder.setVertexBytes(
            &transformIndex,
            length: MemoryLayout<Int>.size,
            index: 3
        )
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
