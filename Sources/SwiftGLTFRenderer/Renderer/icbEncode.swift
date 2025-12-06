import MetalKit
import SwiftGLTFShaderTypes

func encodeDrawingSkybox(
    icb: MTLIndirectCommandBuffer,
    mesh: SkyboxMesh,
    pso: MTLRenderPipelineState,
    dso: MTLDepthStencilState,
    worldTransformBuffer: MTLBuffer,
    cameraIndexBuffer: MTLBuffer,
    freeCameraUniformsBuffer: MTLBuffer,
    nodeCameraUniformsBuffer: MTLBuffer,
    fragmentArgumentsBuffer: MTLBuffer
) -> RenderPassContext {
    var context = RenderPassContext()
    context.add(.drawIndex(
        range: 0..<1,
        cullMode: .none,
        pso: pso,
        dso: dso
    ))

    let cmd = icb.indirectRenderCommandAt(0)
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

    return context
}

// MARK: - Screen Space PBR Rendering

func computePBRScreenDrawingCount(meshes: [PBRMesh]) -> Int {
    meshes
        .filter {
            switch $0.renderingType {
            case .opaque, .masked: return true
            case .blended, .transmission: return false
            }
        }
        .flatMap { $0.submeshes }
        .count
    +
    meshes
        .filter {
            switch $0.renderingType {
            case .blended: return true
            case .opaque, .masked, .transmission: return false
            }
        }
        .flatMap { $0.submeshes }
        .map {
            $0.doubleSided ? 2 : 1
        }
        .reduce(0, +)
}

func encodeDrawingPBRScreen(
    icb: MTLIndirectCommandBuffer,
    meshes: [PBRMesh],
    opaquePSO: MTLRenderPipelineState,
    alphaBlendPSO: MTLRenderPipelineState,
    writeDSO: MTLDepthStencilState,
    worldTransformBuffer: MTLBuffer,
    boundingSpheresBuffer: MTLBuffer,
    jointsBuffer: MTLBuffer,
    inverseBindMatricesBuffer: MTLBuffer,
    morphWeightsBuffer: MTLBuffer,
    morphDispatchesBuffer: MTLBuffer,
    cameraIndexBuffer: MTLBuffer,
    freeCameraUniformsBuffer: MTLBuffer,
    nodeCameraUniformsBuffer: MTLBuffer,
    materialBuffer: MTLBuffer,
    envMapArgBuffer: MTLBuffer,
    fragmentParams: MTLBuffer,
    modelMatrixBuffer: MTLBuffer,
    screenColorArgsBuffer: MTLBuffer
) -> RenderPassContext {
    let _setBuffers: (MTLIndirectRenderCommand, PBRMesh, PBRMesh.Submesh) -> Void = { cmd, mesh, submesh in
        cmd.setVertexBuffer(
            mesh.vertexBuffer,
            offset: 0,
            at: PBRVertexShaderMeshVertexBuffer.index
        )
        cmd.setVertexBuffer(
            mesh.vertexArgumentBuffer,
            offset: 0,
            at: PBRVertexShaderArgsBuffer.index
        )
        cmd.setVertexBuffer(
            worldTransformBuffer,
            offset: 0,
            at: PBRVertexShaderWorldTransformsBuffer.index
        )
        cmd.setVertexBuffer(
            jointsBuffer,
            offset: 0,
            at: PBRVertexShaderSkinJointsBuffer.index
        )
        cmd.setVertexBuffer(
            inverseBindMatricesBuffer,
            offset: 0,
            at: PBRVertexShaderSkinInverseBindMatricesBuffer.index
        )
        cmd.setVertexBuffer(
            morphWeightsBuffer,
            offset: 0,
            at: PBRVertexShaderMorphWeightsBuffer.index
        )
        cmd.setVertexBuffer(
            morphDispatchesBuffer,
            offset: 0,
            at: PBRVertexShaderMorphDispatchesBuffer.index
        )
        cmd.setVertexBuffer(
            cameraIndexBuffer,
            offset: 0,
            at: PBRVertexShaderCameraIndexBuffer.index
        )
        cmd.setVertexBuffer(
            freeCameraUniformsBuffer,
            offset: 0,
            at: PBRVertexShaderFreeCameraUniformsBuffer.index
        )
        cmd.setVertexBuffer(
            nodeCameraUniformsBuffer,
            offset: 0,
            at: PBRVertexShaderNodeCameraUniformsBuffer.index
        )
        cmd.setVertexBuffer(
            modelMatrixBuffer,
            offset: 0,
            at: PBRVertexShaderModelMatrixBuffer.index
        )

        cmd.setFragmentBuffer(
            submesh.materialIndexBuffer,
            offset: 0,
            at: PBRFragmentShaderArgsPtrIndexBuffer.index
        )
        cmd.setFragmentBuffer(
            envMapArgBuffer,
            offset: 0,
            at: PBRFragmentShaderEnvMapArgsBuffer.index
        )
        cmd.setFragmentBuffer(
            fragmentParams,
            offset: 0,
            at: PBRFragmentShaderSceneUniformsBuffer.index
        )
        cmd.setFragmentBuffer(
            screenColorArgsBuffer,
            offset: 0,
            at: PBRFragmentShaderScreenColorBuffer.index
        )
        cmd.setFragmentBuffer(
            materialBuffer,
            offset: 0,
            at: PBRFragmentShaderArgsPtrBuffer.index
        )
        cmd.setFragmentBuffer(
            worldTransformBuffer,
            offset: 0,
            at: PBRFragmentShaderWorldTransformsBuffer.index
        )
        cmd.setFragmentBuffer(
            cameraIndexBuffer,
            offset: 0,
            at: PBRFragmentShaderCameraIndexBuffer.index
        )
        cmd.setFragmentBuffer(
            freeCameraUniformsBuffer,
            offset: 0,
            at: PBRFragmentShaderFreeCameraUniformsBuffer.index
        )
        cmd.setFragmentBuffer(
            nodeCameraUniformsBuffer,
            offset: 0,
            at: PBRFragmentShaderNodeCameraUniformsBuffer.index
        )
    }
    let _drawPrimitiveIndex: (MTLIndirectRenderCommand, PBRMesh.Submesh) -> Void = { cmd, submesh in
        cmd.drawIndexedPrimitives(
            submesh.primitiveType,
            indexCount: submesh.indexCount,
            indexType: submesh.indexType,
            indexBuffer: submesh.indexBuffer,
            indexBufferOffset: submesh.indexBufferOffset,
            instanceCount: 1,
            baseVertex: 0,
            baseInstance: 0
        )
    }

    struct MeshData {
        let mesh: PBRMesh
        let submesh: PBRMesh.Submesh
    }
    var opaqueMeshDoubleSide: [MeshData] = []
    var opaqueMeshSingleSide: [MeshData] = []
    var maskedMeshDoubleSide: [MeshData] = []
    var maskedMeshSingleSide: [MeshData] = []
    var blendedMeshDoubleSide: [MeshData] = []
    var blendedMeshSingleSide: [MeshData] = []

    for mesh in meshes {
        switch mesh.renderingType {
        case .opaque:
            for submesh in mesh.submeshes {
                if submesh.doubleSided {
                    opaqueMeshDoubleSide.append(MeshData(mesh: mesh, submesh: submesh))
                } else {
                    opaqueMeshSingleSide.append(MeshData(mesh: mesh, submesh: submesh))
                }
            }
        case .masked:
            for submesh in mesh.submeshes {
                if submesh.doubleSided {
                    maskedMeshDoubleSide.append(MeshData(mesh: mesh, submesh: submesh))
                } else {
                    maskedMeshSingleSide.append(MeshData(mesh: mesh, submesh: submesh))
                }
            }
        case .blended:
            for submesh in mesh.submeshes {
                if submesh.doubleSided {
                    blendedMeshDoubleSide.append(MeshData(mesh: mesh, submesh: submesh))
                } else {
                    blendedMeshSingleSide.append(MeshData(mesh: mesh, submesh: submesh))
                }
            }
        case .transmission:
            // Skip transmission meshes in this function
            break
        }
    }

    var commandIndex = 0
    var context = RenderPassContext()

    // Opaque pass - double sided
    if !opaqueMeshDoubleSide.isEmpty {
        context.add(.drawIndex(
            range: commandIndex..<(commandIndex + opaqueMeshDoubleSide.count),
            cullMode: .none,
            pso: opaquePSO,
            dso: writeDSO
        ))
        for meshData in opaqueMeshDoubleSide {
            defer { commandIndex += 1 }
            let mesh = meshData.mesh
            let submesh = meshData.submesh

            let cmd = icb.indirectRenderCommandAt(commandIndex)
            _setBuffers(cmd, mesh, submesh)
            _drawPrimitiveIndex(cmd, submesh)
        }
    }

    // Opaque pass - single sided
    if !opaqueMeshSingleSide.isEmpty {
        context.add(.drawIndex(
            range: commandIndex..<(commandIndex + opaqueMeshSingleSide.count),
            cullMode: .back,
            pso: opaquePSO,
            dso: writeDSO
        ))
        for meshData in opaqueMeshSingleSide {
            defer { commandIndex += 1 }
            let mesh = meshData.mesh
            let submesh = meshData.submesh

            let cmd = icb.indirectRenderCommandAt(commandIndex)
            _setBuffers(cmd, mesh, submesh)
            _drawPrimitiveIndex(cmd, submesh)
        }
    }

    // Masked pass - double sided
    if !maskedMeshDoubleSide.isEmpty {
        context.add(.drawIndex(
            range: commandIndex..<(commandIndex + maskedMeshDoubleSide.count),
            cullMode: .none,
            pso: opaquePSO,
            dso: writeDSO
        ))
        for meshData in maskedMeshDoubleSide {
            defer { commandIndex += 1 }
            let mesh = meshData.mesh
            let submesh = meshData.submesh

            let cmd = icb.indirectRenderCommandAt(commandIndex)
            _setBuffers(cmd, mesh, submesh)
            _drawPrimitiveIndex(cmd, submesh)
        }
    }

    if !maskedMeshSingleSide.isEmpty {
        // Masked pass - single sided
        context.add(.drawIndex(
            range: commandIndex..<(commandIndex + maskedMeshSingleSide.count),
            cullMode: .back,
            pso: opaquePSO,
            dso: writeDSO
        ))
        for meshData in maskedMeshSingleSide {
            defer { commandIndex += 1 }
            let mesh = meshData.mesh
            let submesh = meshData.submesh

            let cmd = icb.indirectRenderCommandAt(commandIndex)
            _setBuffers(cmd, mesh, submesh)
            _drawPrimitiveIndex(cmd, submesh)
        }
    }

    // Blended pass - celling front for double sided (draw back faces first)
    if !blendedMeshDoubleSide.isEmpty {
        context.add(.drawIndex(
            range: commandIndex..<(commandIndex + blendedMeshDoubleSide.count),
            cullMode: .front,
            pso: alphaBlendPSO,
            dso: writeDSO
        ))
        for meshData in blendedMeshDoubleSide {
            defer { commandIndex += 1 }
            let mesh = meshData.mesh
            let submesh = meshData.submesh

            let cmd = icb.indirectRenderCommandAt(commandIndex)
            _setBuffers(cmd, mesh, submesh)
            _drawPrimitiveIndex(cmd, submesh)
        }
    }

    // Blended pass - double sided
    if !blendedMeshDoubleSide.isEmpty {
        context.add(.drawIndex(
            range: commandIndex..<(commandIndex + blendedMeshDoubleSide.count),
            cullMode: .none,
            pso: alphaBlendPSO,
            dso: writeDSO
        ))
        for meshData in blendedMeshDoubleSide {
            defer { commandIndex += 1 }
            let mesh = meshData.mesh
            let submesh = meshData.submesh

            let cmd = icb.indirectRenderCommandAt(commandIndex)
            _setBuffers(cmd, mesh, submesh)
            _drawPrimitiveIndex(cmd, submesh)
        }
    }

    // Blended pass - single sided
    if !blendedMeshSingleSide.isEmpty {
        // Blended pass - single sided
        context.add(.drawIndex(
            range: commandIndex..<(commandIndex + blendedMeshSingleSide.count),
            cullMode: .back,
            pso: alphaBlendPSO,
            dso: writeDSO
        ))
        for meshData in blendedMeshSingleSide {
            defer { commandIndex += 1 }
            let mesh = meshData.mesh
            let submesh = meshData.submesh
            
            let cmd = icb.indirectRenderCommandAt(commandIndex)
            _setBuffers(cmd, mesh, submesh)
            _drawPrimitiveIndex(cmd, submesh)
        }
    }

    return context
}

// MARK: - Transmission Rendering

func computeTransmissionDrawingCount(meshes: [PBRMesh]) -> Int {
    meshes
        .filter {
            switch $0.renderingType {
            case .transmission: return true
            case .opaque, .masked, .blended: return false
            }
        }
        .flatMap { $0.submeshes }
        .map {
            $0.doubleSided ? 2 : 1
        }
        .reduce(0, +)
}

func encodeDrawingTransmission(
    icb: MTLIndirectCommandBuffer,
    meshes: [PBRMesh],
    alphaBlendPSO: MTLRenderPipelineState,
    writeDSO: MTLDepthStencilState,
    worldTransformBuffer: MTLBuffer,
    boundingSpheresBuffer: MTLBuffer,
    jointsBuffer: MTLBuffer,
    inverseBindMatricesBuffer: MTLBuffer,
    morphWeightsBuffer: MTLBuffer,
    morphDispatchesBuffer: MTLBuffer,
    cameraIndexBuffer: MTLBuffer,
    freeCameraUniformsBuffer: MTLBuffer,
    nodeCameraUniformsBuffer: MTLBuffer,
    materialBuffer: MTLBuffer,
    envMapArgBuffer: MTLBuffer,
    fragmentParams: MTLBuffer,
    modelMatrixBuffer: MTLBuffer,
    screenColorArgsBuffer: MTLBuffer
) -> RenderPassContext {
    let _setBuffers: (MTLIndirectRenderCommand, PBRMesh, PBRMesh.Submesh) -> Void = { cmd, mesh, submesh in
        cmd.setVertexBuffer(
            mesh.vertexBuffer,
            offset: 0,
            at: PBRVertexShaderMeshVertexBuffer.index
        )
        cmd.setVertexBuffer(
            mesh.vertexArgumentBuffer,
            offset: 0,
            at: PBRVertexShaderArgsBuffer.index
        )
        cmd.setVertexBuffer(
            worldTransformBuffer,
            offset: 0,
            at: PBRVertexShaderWorldTransformsBuffer.index
        )
        cmd.setVertexBuffer(
            jointsBuffer,
            offset: 0,
            at: PBRVertexShaderSkinJointsBuffer.index
        )
        cmd.setVertexBuffer(
            inverseBindMatricesBuffer,
            offset: 0,
            at: PBRVertexShaderSkinInverseBindMatricesBuffer.index
        )
        cmd.setVertexBuffer(
            morphWeightsBuffer,
            offset: 0,
            at: PBRVertexShaderMorphWeightsBuffer.index
        )
        cmd.setVertexBuffer(
            morphDispatchesBuffer,
            offset: 0,
            at: PBRVertexShaderMorphDispatchesBuffer.index
        )
        cmd.setVertexBuffer(
            cameraIndexBuffer,
            offset: 0,
            at: PBRVertexShaderCameraIndexBuffer.index
        )
        cmd.setVertexBuffer(
            freeCameraUniformsBuffer,
            offset: 0,
            at: PBRVertexShaderFreeCameraUniformsBuffer.index
        )
        cmd.setVertexBuffer(
            nodeCameraUniformsBuffer,
            offset: 0,
            at: PBRVertexShaderNodeCameraUniformsBuffer.index
        )
        cmd.setVertexBuffer(
            modelMatrixBuffer,
            offset: 0,
            at: PBRVertexShaderModelMatrixBuffer.index
        )

        cmd.setFragmentBuffer(
            submesh.materialIndexBuffer,
            offset: 0,
            at: PBRFragmentShaderArgsPtrIndexBuffer.index
        )
        cmd.setFragmentBuffer(
            envMapArgBuffer,
            offset: 0,
            at: PBRFragmentShaderEnvMapArgsBuffer.index
        )
        cmd.setFragmentBuffer(
            fragmentParams,
            offset: 0,
            at: PBRFragmentShaderSceneUniformsBuffer.index
        )
        cmd.setFragmentBuffer(
            screenColorArgsBuffer,
            offset: 0,
            at: PBRFragmentShaderScreenColorBuffer.index
        )
        cmd.setFragmentBuffer(
            materialBuffer,
            offset: 0,
            at: PBRFragmentShaderArgsPtrBuffer.index
        )
        cmd.setFragmentBuffer(
            worldTransformBuffer,
            offset: 0,
            at: PBRFragmentShaderWorldTransformsBuffer.index
        )
        cmd.setFragmentBuffer(
            cameraIndexBuffer,
            offset: 0,
            at: PBRFragmentShaderCameraIndexBuffer.index
        )
        cmd.setFragmentBuffer(
            freeCameraUniformsBuffer,
            offset: 0,
            at: PBRFragmentShaderFreeCameraUniformsBuffer.index
        )
        cmd.setFragmentBuffer(
            nodeCameraUniformsBuffer,
            offset: 0,
            at: PBRFragmentShaderNodeCameraUniformsBuffer.index
        )
    }
    let _drawPrimitiveIndex: (MTLIndirectRenderCommand, PBRMesh.Submesh) -> Void = { cmd, submesh in
        cmd.drawIndexedPrimitives(
            submesh.primitiveType,
            indexCount: submesh.indexCount,
            indexType: submesh.indexType,
            indexBuffer: submesh.indexBuffer,
            indexBufferOffset: submesh.indexBufferOffset,
            instanceCount: 1,
            baseVertex: 0,
            baseInstance: 0
        )
    }

    struct MeshData {
        let mesh: PBRMesh
        let submesh: PBRMesh.Submesh
    }
    var transmissionMeshDoubleSide: [MeshData] = []
    var transmissionMeshSingleSide: [MeshData] = []

    for mesh in meshes {
        switch mesh.renderingType {
        case .opaque, .masked, .blended:
            // Skip non-transmission meshes in this function
            break
        case .transmission:
            for submesh in mesh.submeshes {
                if submesh.doubleSided {
                    transmissionMeshDoubleSide.append(MeshData(mesh: mesh, submesh: submesh))
                } else {
                    transmissionMeshSingleSide.append(MeshData(mesh: mesh, submesh: submesh))
                }
            }
        }
    }

    var commandIndex = 0
    var context = RenderPassContext()

    // Blended pass - celling front for double sided (draw back faces first)
    if !transmissionMeshDoubleSide.isEmpty {
        context.add(.drawIndex(
            range: commandIndex..<(commandIndex + transmissionMeshDoubleSide.count),
            cullMode: .front,
            pso: alphaBlendPSO,
            dso: writeDSO
        ))
        for meshData in transmissionMeshDoubleSide {
            defer { commandIndex += 1 }
            let mesh = meshData.mesh
            let submesh = meshData.submesh

            let cmd = icb.indirectRenderCommandAt(commandIndex)
            _setBuffers(cmd, mesh, submesh)
            _drawPrimitiveIndex(cmd, submesh)
        }
    }

    // Blended pass - double sided
    if !transmissionMeshDoubleSide.isEmpty {
        context.add(.drawIndex(
            range: commandIndex..<(commandIndex + transmissionMeshDoubleSide.count),
            cullMode: .none,
            pso: alphaBlendPSO,
            dso: writeDSO
        ))
        for meshData in transmissionMeshDoubleSide {
            defer { commandIndex += 1 }
            let mesh = meshData.mesh
            let submesh = meshData.submesh

            let cmd = icb.indirectRenderCommandAt(commandIndex)
            _setBuffers(cmd, mesh, submesh)
            _drawPrimitiveIndex(cmd, submesh)
        }
    }

    // Blended pass - single sided
    if !transmissionMeshSingleSide.isEmpty {
        // Blended pass - single sided
        context.add(.drawIndex(
            range: commandIndex..<(commandIndex + transmissionMeshSingleSide.count),
            cullMode: .back,
            pso: alphaBlendPSO,
            dso: writeDSO
        ))
        for meshData in transmissionMeshSingleSide {
            defer { commandIndex += 1 }
            let mesh = meshData.mesh
            let submesh = meshData.submesh

            let cmd = icb.indirectRenderCommandAt(commandIndex)
            _setBuffers(cmd, mesh, submesh)
            _drawPrimitiveIndex(cmd, submesh)
        }
    }

    return context
}
