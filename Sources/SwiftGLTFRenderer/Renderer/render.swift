import MetalKit
import SwiftGLTFShaderTypes

func drawSkybox(
    renderEncoder: MTLRenderCommandEncoder,
    mesh: SkyboxMesh,
    mvpUniformBuffer: MTLBuffer,
    specularCubeMapTexture: MTLTexture
) {
    renderEncoder.setRenderPipelineState(mesh.pso)
    renderEncoder.setDepthStencilState(mesh.dso)
    renderEncoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: 0)
    renderEncoder.setVertexBuffer(mvpUniformBuffer, offset: 0, index: 1)
    renderEncoder.setFragmentTexture(specularCubeMapTexture, index: 0)

    renderEncoder.drawIndexedPrimitives(
        type: .triangle,
        indexCount: mesh.indexCount,
        indexType: mesh.indexType,
        indexBuffer: mesh.indexBuffer,
        indexBufferOffset: 0
    )
}

func drawPBRScreen(
    renderEncoder: MTLRenderCommandEncoder,
    opaquePSO: MTLRenderPipelineState,
    alphaBlendPSO: MTLRenderPipelineState,
    defaultDSO: MTLDepthStencilState,
    noWriteDSO: MTLDepthStencilState,
    vertexResources: [MTLHeap],
    fragmentResources: [MTLHeap],
    opaqueMeshes: [PBRMesh],
    maskedMeshes: [PBRMesh],
    blendedMeshes: [PBRMesh],
    transmissionMeshes: [PBRMesh],
    worldTransformBuffer: MTLBuffer,
    boundingSpheresBuffer: MTLBuffer,
    jointsBuffer: MTLBuffer,
    inverseBindMatricesBuffer: MTLBuffer,
    morphWeightsBuffer: MTLBuffer,
    morphDispatchesBuffer: MTLBuffer,
    envMapArgBuffer: MTLBuffer,
    fragmentParams: MTLBuffer,
    mvpUniformBuffer: MTLBuffer,
    screenColorArgsBuffer: MTLBuffer,
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
    renderEncoder.setFragmentBuffer(
        envMapArgBuffer,
        offset: 0,
        index: PBRFragmentShaderEnvMapArgsBuffer.index
    )
    renderEncoder.setFragmentBuffer(
        fragmentParams,
        offset: 0,
        index: PBRFragmentShaderSceneUniformsBuffer.index
    )
    renderEncoder.setFragmentBuffer(
        screenColorArgsBuffer,
        offset: 0,
        index: PBRFragmentShaderScreenColorBuffer.index
    )

    renderEncoder.setRenderPipelineState(opaquePSO)
    renderEncoder.setDepthStencilState(defaultDSO)
    // Opaque pass (no sorting)
    _drawPrimitives(renderEncoder: renderEncoder, meshes: opaqueMeshes)
    // Masked pass (no sorting)
    _drawPrimitives(renderEncoder: renderEncoder, meshes: maskedMeshes)

    renderEncoder.setRenderPipelineState(alphaBlendPSO)
    renderEncoder.setDepthStencilState(noWriteDSO)
    // Blended pass (sort back-to-front per mesh using bounding sphere center)
    _drawPrimitivesWithSort(
        renderEncoder: renderEncoder,
        meshes: blendedMeshes,
        worldTransformBuffer: worldTransformBuffer,
        boundingSpheresBuffer: boundingSpheresBuffer,
        viewPos: viewPos
    )
}

func _drawPrimitives(renderEncoder: MTLRenderCommandEncoder, meshes: [PBRMesh]) {
    for mesh in meshes {
        renderEncoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBuffer(mesh.vertexArgumentBuffer, offset: 0, index: 1)
        for submesh in mesh.submeshes {
            renderEncoder.setFragmentBuffer(
                submesh.fragmentArgumentBuffer,
                offset: 0,
                index: PBRFragmentShaderArgsBuffer.index
            )
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
}

func _drawPrimitivesWithSort(
    renderEncoder: MTLRenderCommandEncoder,
    meshes: [PBRMesh],
    worldTransformBuffer: MTLBuffer,
    boundingSpheresBuffer: MTLBuffer,
    viewPos: SIMD3<Float>
) {
    let drawItems = _sortMeshes(
        meshes,
        worldTransformBuffer: worldTransformBuffer,
        boundingSpheresBuffer: boundingSpheresBuffer,
        viewPos: viewPos
    )

    for item in drawItems {
        let mesh = meshes[item.meshIndex]
        renderEncoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBuffer(mesh.vertexArgumentBuffer, offset: 0, index: 1)
        for submesh in mesh.submeshes {
            renderEncoder.setFragmentBuffer(
                submesh.fragmentArgumentBuffer,
                offset: 0,
                index: PBRFragmentShaderArgsBuffer.index
            )
            // Culling control per material
            if submesh.doubleSided {
                renderEncoder.setCullMode(.front)
                renderEncoder.drawIndexedPrimitives(
                    type: submesh.primitiveType,
                    indexCount: submesh.indexCount,
                    indexType: submesh.indexType,
                    indexBuffer: submesh.indexBuffer.buffer,
                    indexBufferOffset: submesh.indexBuffer.offset
                )
            }
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

struct DrawItem { let distanceSq: Float; let meshIndex: Int; let submeshIndex: Int }
func _sortMeshes(
    _ meshes: [PBRMesh],
    worldTransformBuffer: MTLBuffer,
    boundingSpheresBuffer: MTLBuffer,
    viewPos: SIMD3<Float>
) -> [DrawItem] {
    // sort back-to-front per submesh using bounding sphere center
    // NOTE: バウンディングスフィアはバインドポーズ（非スキン・非モーフ）基準で算出しているため、
    //       スキン／モーフによる形状変化は反映していない。描画順の判断としては保守的に許容する。
    // NOTE: en: Since the bounding sphere is calculated based on the bind pose (non-skin, non-morph),
    //       it does not reflect shape changes due to skin/morph. It is conservatively
    var items: [DrawItem] = []
    let spherePtr = boundingSpheresBuffer.contents().bindMemory(to: SIMD4<Float>.self, capacity: meshes.count)
    let worldPtr = worldTransformBuffer.contents().bindMemory(to: simd_float4x4.self, capacity: worldTransformBuffer.length / MemoryLayout<simd_float4x4>.stride)
    for (mi, mesh) in meshes.enumerated() {
        let s = spherePtr[mi]
        let cModel = SIMD4<Float>(s.x, s.y, s.z, 1.0)
        let world = worldPtr[max(mesh.transformIndex, 0)]
        let cWorld4 = world * cModel
        let cWorld = SIMD3<Float>(cWorld4.x, cWorld4.y, cWorld4.z) - normalize(viewPos) * s.w // Offset by radius in view direction.
        for si in 0..<mesh.submeshes.count {
            let d = cWorld - viewPos
            let distSq = simd_dot(d, d)
            items.append(DrawItem(distanceSq: distSq, meshIndex: mi, submeshIndex: si))
        }
    }
    items.sort { $0.distanceSq > $1.distanceSq } // back-to-front
    return items
}

func drawPBRTransmission(
    renderEncoder: MTLRenderCommandEncoder,
    alphaBlendPSO pso: MTLRenderPipelineState,
    defaultDSO dso: MTLDepthStencilState,
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
    screenColorArgsBuffer: MTLBuffer,
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
    renderEncoder.setFragmentBuffer(
        envMapArgBuffer,
        offset: 0,
        index: PBRFragmentShaderEnvMapArgsBuffer.index
    )
    renderEncoder.setFragmentBuffer(
        fragmentParams,
        offset: 0,
        index: PBRFragmentShaderSceneUniformsBuffer.index
    )
    renderEncoder.setFragmentBuffer(
        screenColorArgsBuffer,
        offset: 0,
        index: PBRFragmentShaderScreenColorBuffer.index
    )

    renderEncoder.setRenderPipelineState(pso)
    renderEncoder.setDepthStencilState(dso)

    _drawPrimitivesWithSort(
        renderEncoder: renderEncoder,
        meshes: meshes,
        worldTransformBuffer: worldTransformBuffer,
        boundingSpheresBuffer: boundingSpheresBuffer,
        viewPos: viewPos
    )
}

func drawWireframe(
    renderEncoder: MTLRenderCommandEncoder,
    pipelineState: MTLRenderPipelineState,
    depthStencilState: MTLDepthStencilState,
    meshes: [WireframeMesh],
    mvpUniformBuffer: MTLBuffer,
    worldTransformBuffer: MTLBuffer
) {
    renderEncoder.setTriangleFillMode(.lines)
    renderEncoder.setRenderPipelineState(pipelineState)
    renderEncoder.setDepthStencilState(depthStencilState)
    renderEncoder.setVertexBuffer(mvpUniformBuffer, offset: 0, index: 1)
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
