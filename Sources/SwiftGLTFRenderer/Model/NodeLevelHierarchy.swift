import ModelIO

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
    let parentIndex: [NodeHierarchyOffset]
    let levelNodes:  [NodeHierarchyOffset]
    let levelStarts: [NodeHierarchyOffset]
    let levelCounts: [Int]
    let localTransforms: [float4x4]
    let indexToObject: [MDLObject]
    let objectToIndex: [ObjectIdentifier: NodeHierarchyOffset]

    var maxDepth: Int { levelCounts.count }

    func copy(localTransforms: [float4x4]) -> NodeLevelHierarchy {
        precondition(localTransforms.count == self.localTransforms.count)
        return NodeLevelHierarchy(
            parentIndex: parentIndex,
            levelNodes: levelNodes,
            levelStarts: levelStarts,
            levelCounts: levelCounts,
            localTransforms: localTransforms,
            indexToObject: indexToObject,
            objectToIndex: objectToIndex
        )
    }
}

typealias NodeHierarchyOffset = Int
