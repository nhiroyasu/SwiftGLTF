import ModelIO
import os.log

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

func makeNodeLevelHierarchy(root: MDLObject) -> NodeLevelHierarchy {
    var objectToIndex: [ObjectIdentifier: Int] = [:]
    var indexToObject: [MDLObject] = []

    // outputs
    var parentIndex: [Int] = []
    var levelNodes:  [Int] = []
    var levelStarts: [Int] = []
    var levelCounts: [Int] = []
    var localTransforms: [float4x4] = []

    // 訪問済み（防御：循環/重複参照を避ける）
    var visited: Set<ObjectIdentifier> = []

    // 現在レベルの (node, parentIndex) キュー
    var curr: [(MDLObject, Int)] = [(root, -1)]

    while !curr.isEmpty {
        let start = levelNodes.count
        // 先に今レベルのノードへ “連番の index” を割り当てる
        for (obj, p) in curr {
            let oid = ObjectIdentifier(obj)
            guard !visited.contains(oid) else {
                os_log("⚠️ Warning: Detected cyclic or duplicate node reference for %s. Skipping.", log: .default, type: .error, obj.name)
                continue
            }
            visited.insert(oid)

            let idx = indexToObject.count
            objectToIndex[oid] = idx
            indexToObject.append(obj)

            parentIndex.append(p)
            levelNodes.append(idx)
            localTransforms.append(obj.transform?.matrix ?? float4x4(1))
        }
        levelStarts.append(start)
        levelCounts.append(levelNodes.count - start)

        // 次レベルを作る（今レベルで確定した index を親として持たせる）
        var next: [(MDLObject, Int)] = []
        next.reserveCapacity(curr.count * 2)

        for (obj, _) in curr {
            let parentIdx = objectToIndex[ObjectIdentifier(obj)]
            for child in obj.children.objects {
                let coid = ObjectIdentifier(child)
                if !visited.contains(coid), let p = parentIdx {
                    next.append((child, p))
                }
            }
        }
        curr = next
    }

    return NodeLevelHierarchy(
        parentIndex: parentIndex,
        levelNodes:  levelNodes,
        levelStarts: levelStarts,
        levelCounts: levelCounts,
        localTransforms: localTransforms,
        indexToObject: indexToObject,
        objectToIndex: objectToIndex
    )
}
