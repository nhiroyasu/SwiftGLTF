import ModelIO
import OSLog
import SwiftGLTFCore
import SwiftGLTFParser

/// Hierarchy representation of node tree for model matrix calculation in shaders.
///
/// Example of model matrix tree:
///
/// ```
///        A(0)
///       /   \
///    B(1)     C(2)
///    / \        \
///D(3) E(4)     F(5)
/// ```
///
/// ```
/// parentIndex = [-1, 0, 0, 1, 1, 2]
/// levelNodes = [0, 1, 2, 3, 4, 5]
/// levelStarts = [0, 1, 3]
/// levelCounts = [1, 2, 3]
/// ```
struct NodeLevelHierarchy {
    let parentIndex: [Int]
    let levelNodes:  [Int]
    let levelStarts: [Int]
    let levelCounts: [Int]
    let localTransforms: [float4x4]

    // options
    let cameraNodeIndices: [NodeIndex]
    let cameraIndices: [CameraIndex]

    var maxDepth: Int { levelCounts.count }

    func copy(localTransforms: [float4x4]) -> NodeLevelHierarchy {
        precondition(localTransforms.count == self.localTransforms.count)
        return NodeLevelHierarchy(
            parentIndex: parentIndex,
            levelNodes: levelNodes,
            levelStarts: levelStarts,
            levelCounts: levelCounts,
            localTransforms: localTransforms,
            cameraNodeIndices: cameraNodeIndices,
            cameraIndices: cameraIndices
        )
    }
}

func makeNodeLevelHierarchy(nodesRoot: MDLObject) -> NodeLevelHierarchy {
    let nodes = nodesRoot.children.objects
    var parentIndex = Array(repeating: -1, count: nodes.count)
    var childrenMap: [Int: [Int]] = [:]
    var localTransforms = Array(repeating: float4x4(1), count: nodes.count)
    var hasParent = Array(repeating: false, count: nodes.count)
    var levelNodes:  [Int] = []
    var levelStarts: [Int] = []
    var levelCounts: [Int] = []
    var cameraNodeIndices: [NodeIndex] = []
    var cameraIndices: [CameraIndex] = []

    for object in nodes {
        guard let nodeIndex = (object.component(ofType: GLTFNodeIndexProtocol.self) as? GLTFNodeIndex)?.index,
              nodes.indices.contains(nodeIndex.value) else {
            continue
        }
        localTransforms[nodeIndex.value] = object.transform?.matrix ?? float4x4(1)
        let children = (object.component(ofType: GLTFNodeMetadataProtocol.self) as? GLTFNodeMetadata)?.children ?? []
        childrenMap[nodeIndex.value] = children.map(\.value).filter { nodes.indices.contains($0) }
        for childIndex in childrenMap[nodeIndex.value] ?? [] {
            parentIndex[childIndex] = nodeIndex.value
            hasParent[childIndex] = true
        }
        if let cameraNode = object as? GLTFCameraNode {
            cameraNodeIndices.append(nodeIndex)
            cameraIndices.append(cameraNode.cameraIndex)
        }
    }

    var visited: Set<Int> = []
    var curr = nodes.indices.filter { !hasParent[$0] }
    while !curr.isEmpty {
        let start = levelNodes.count
        for nodeIndex in curr {
            guard visited.insert(nodeIndex).inserted else {
                logger.error("⚠️ Warning: Detected cyclic or duplicate node reference for \(nodeIndex, privacy: .public). Skipping.")
                continue
            }
            levelNodes.append(nodeIndex)
        }
        levelStarts.append(start)
        levelCounts.append(levelNodes.count - start)

        var next: [Int] = []
        next.reserveCapacity(curr.count * 2)
        for nodeIndex in curr {
            next.append(contentsOf: (childrenMap[nodeIndex] ?? []).filter { !visited.contains($0) })
        }
        curr = next
    }

    return NodeLevelHierarchy(
        parentIndex: parentIndex,
        levelNodes:  levelNodes,
        levelStarts: levelStarts,
        levelCounts: levelCounts,
        localTransforms: localTransforms,
        cameraNodeIndices: cameraNodeIndices,
        cameraIndices: cameraIndices
    )
}
