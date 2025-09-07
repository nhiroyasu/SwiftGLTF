import MetalKit
import Accelerate
import SwiftGLTFParser

class WireframeMeshLoader {
    private let device: MTLDevice
    private let pipelineConnector: WireframePipelineConnector
    private let shaderConnection: ShaderConnection

    private let SCENE_INDEX = 0

    init(
        device: MTLDevice,
        pipelineConnector: WireframePipelineConnector,
        shaderConnection: ShaderConnection
    ) {
        self.device = device
        self.pipelineConnector = pipelineConnector
        self.shaderConnection = shaderConnection
    }

    func loadMeshes(from asset: MDLAsset) throws -> WireframeMeshBundle {
        let scene = asset.object(atPath: GLTFAssetPath.scene(SCENE_INDEX))
        let nodeLevelHierarchy = makeNodeLevelHierarchy(root: scene)
        let worldTransformsBuffer = try shaderConnection.computeWorldMatrices(nodeLevelHierarchy: nodeLevelHierarchy)

        let nodes = asset.object(atPath: GLTFAssetPath.nodes(atScene: SCENE_INDEX))
        let wireframeMeshes: [WireframeMesh] = try loadRecursiveMeshes(
            device: device,
            obj: nodes,
            nodeLevelHierarchy: nodeLevelHierarchy
        )

        return WireframeMeshBundle(
            meshes: wireframeMeshes,
            worldTransformBuffer: worldTransformsBuffer
        )
    }

    private func loadRecursiveMeshes(
        device: MTLDevice,
        obj: MDLObject,
        nodeLevelHierarchy: NodeLevelHierarchy
    ) throws -> [WireframeMesh] {
        var wireframeMeshes: [WireframeMesh] = []

        for mdlMesh in obj.component(ofType: GLTFMesh.self)?.primitives ?? [] {
            let mtkMesh = try MTKMesh(mesh: mdlMesh, device: device)

            var submeshes: [WireframeMesh.Submesh] = []
            for mtkSubmesh in mtkMesh.submeshes {
                let submeshData = WireframeMesh.Submesh(
                    primitiveType: mtkSubmesh.primitiveType,
                    indexCount: mtkSubmesh.indexCount,
                    indexType: mtkSubmesh.indexType,
                    indexBuffer: mtkSubmesh.indexBuffer
                )
                submeshes.append(submeshData)
            }

            let wireframeMesh = WireframeMesh(
                vertexBuffer: mtkMesh.vertexBuffers[0].buffer,
                transformIndex: nodeLevelHierarchy.objectToIndex[ObjectIdentifier(obj)]!,
                submeshes: submeshes,
            )
            wireframeMeshes.append(wireframeMesh)
        }

        for childObj in obj.children.objects {
            let childMeshes = try loadRecursiveMeshes(
                device: device,
                obj: childObj,
                nodeLevelHierarchy: nodeLevelHierarchy
            )
            wireframeMeshes.append(contentsOf: childMeshes)
        }

        return wireframeMeshes
    }
}
