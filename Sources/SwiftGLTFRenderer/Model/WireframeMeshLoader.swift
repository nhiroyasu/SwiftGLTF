import MetalKit
import Accelerate
import SwiftGLTFParser
import SwiftGLTFCore

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
        guard let nodesRoot = asset.objectSafe(atPath: GLTFAssetPath.nodes) else {
            throw SwiftGLTFRendererError(description: "Nodes not found")
        }
        let nodeLevelHierarchy = makeNodeLevelHierarchy(nodesRoot: nodesRoot)
        let worldTransformsBuffer = try shaderConnection.computeWorldMatrices(nodeLevelHierarchy: nodeLevelHierarchy)

        var wireframeMeshes: [WireframeMesh] = []
        for rootNodeIndex in asset.sceneRootNodes(at: SCENE_INDEX) {
            let meshes = try loadRecursiveMeshes(
                device: device,
                asset: asset,
                nodeIndex: rootNodeIndex,
                primitiveMeshes: asset.primitiveMeshes,
                nodeLevelHierarchy: nodeLevelHierarchy
            )
            wireframeMeshes.append(contentsOf: meshes)
        }

        return WireframeMeshBundle(
            meshes: wireframeMeshes,
            worldTransformBuffer: worldTransformsBuffer
        )
    }

    private func loadRecursiveMeshes(
        device: MTLDevice,
        asset: MDLAsset,
        nodeIndex: NodeIndex,
        primitiveMeshes: [GLTFPrimitiveMesh],
        nodeLevelHierarchy: NodeLevelHierarchy
    ) throws -> [WireframeMesh] {
        guard let obj = asset.node(at: nodeIndex) else {
            throw SwiftGLTFRendererError(description: "Node \(nodeIndex.value) not found")
        }
        var wireframeMeshes: [WireframeMesh] = []

        if let meshRef = obj.component(ofType: GLTFMeshRef.self) {
            for mdlMesh in primitiveMeshes[meshRef.index].meshes {
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
                    transformIndex: nodeIndex.value,
                    submeshes: submeshes,
                )
                wireframeMeshes.append(wireframeMesh)
            }
        }

        let children = (obj.component(ofType: GLTFNodeMetadataProtocol.self) as? GLTFNodeMetadata)?.children ?? []
        for childNodeIndex in children {
            let childMeshes = try loadRecursiveMeshes(
                device: device,
                asset: asset,
                nodeIndex: childNodeIndex,
                primitiveMeshes: primitiveMeshes,
                nodeLevelHierarchy: nodeLevelHierarchy
            )
            wireframeMeshes.append(contentsOf: childMeshes)
        }

        return wireframeMeshes
    }
}
