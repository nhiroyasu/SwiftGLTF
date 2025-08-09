import Foundation
import MikkTSpace
import simd
import Accelerate

private class ContextData {
    let floatPositions: [Float]
    let floatNormals: [Float]
    let floatTexcoords: [Float]
    let indices: [Int]
    let vertexCount: Int
    var tangents: [Float]
    let posBase: UnsafePointer<Float>
    let normalBase: UnsafePointer<Float>
    let texcoordBase: UnsafePointer<Float>

    init(
        floatPositions: [Float],
        floatNormals: [Float],
        floatTexcoords: [Float],
        indices: [Int],
        vertexCount: Int,
        tangents: [Float]
    ) {
        self.floatPositions = floatPositions
        self.floatNormals = floatNormals
        self.floatTexcoords = floatTexcoords
        self.indices = indices
        self.vertexCount = vertexCount
        self.tangents = tangents
        self.posBase = floatPositions.withUnsafeBufferPointer { $0.baseAddress! }
        self.normalBase = floatNormals.withUnsafeBufferPointer { $0.baseAddress! }
        self.texcoordBase = floatTexcoords.withUnsafeBufferPointer { $0.baseAddress! }
    }
}

func generateTangents(
    _ positionVertex: VertexInfo,
    _ normalVertex: VertexInfo,
    _ texcoordVertex: VertexInfo,
    _ indexInfo: IndexInfo,
    vertexCount: Int
) throws -> VertexInfo {
    var interface = SMikkTSpaceInterface(
        m_getNumFaces: { context in
            guard let data = context?.pointee.m_pUserData.load(as: ContextData.self) else {
                fatalError("Invalid user data")
            }
            return Int32(data.indices.count / 3)
        },
        m_getNumVerticesOfFace: { _, _ in 3 },
        m_getPosition: { (context, pos, face, vert) in
            guard let data = context?.pointee.m_pUserData.load(as: ContextData.self) else {
                fatalError("Invalid user data")
            }
            let baseIndex = data.indices[Int(face * 3 + vert)] * 3
            let base = data.posBase + baseIndex
            pos!.update(from: base, count: 3)
        },
        m_getNormal: { (context, normal, face, vert) in
            guard let data = context?.pointee.m_pUserData.load(as: ContextData.self) else {
                fatalError("Invalid user data")
            }
            let baseIndex = data.indices[Int(face * 3 + vert)] * 3
            let base = data.normalBase + baseIndex
            normal!.update(from: base, count: 3)
        },
        m_getTexCoord: { (context, uv, face, vert) in
            guard let data = context?.pointee.m_pUserData.load(as: ContextData.self) else {
                fatalError("Invalid user data")
            }
            let baseIndex = data.indices[Int(face * 3 + vert)] * 2
            let base = data.texcoordBase + baseIndex
            uv!.update(from: base, count: 2)
        },
        m_setTSpaceBasic: { (context, tangent, sign, face, vert) in
            guard let data = context?.pointee.m_pUserData.load(as: ContextData.self),
                  let tangent else {
                fatalError("Invalid user data")
            }
            let index = data.indices[Int(face * 3 + vert)] * 4
            data.tangents[index] = tangent[0]
            data.tangents[index + 1] = tangent[1]
            data.tangents[index + 2] = tangent[2]
            data.tangents[index + 3] = sign
        },
        m_setTSpace: nil
    )

    let floatPositions = positionVertex.data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    let floatNormals = normalVertex.data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    let floatTexcoords = texcoordVertex.data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    let indices = try indexInfo.getIndices()
    let triangleCount = indices.count / 3
    let threadCount = ProcessInfo.processInfo.activeProcessorCount * 3
    let chunkSize = max(1, triangleCount / threadCount)

    let resultsQueue = DispatchQueue(label: "com.swiftgltf.tangentGeneration")
    var results = Array(repeating: [Float](repeating: 0, count: vertexCount * 4), count: threadCount)
    DispatchQueue.concurrentPerform(iterations: threadCount) { i in
        let start = i * chunkSize
        let end = (i == threadCount - 1) ? triangleCount : min(start + chunkSize, triangleCount)
        guard start < end else { return }

        let triIndices = Array(indices[(start * 3)..<(end * 3)])

        var userData = ContextData(
            floatPositions: floatPositions,
            floatNormals: floatNormals,
            floatTexcoords: floatTexcoords,
            indices: triIndices,
            vertexCount: vertexCount,
            tangents: Array(repeating: 0, count: vertexCount * 4)
        )

        var context = SMikkTSpaceContext(
            m_pInterface: withUnsafePointer(to: &interface) { UnsafeMutablePointer(mutating: $0) },
            m_pUserData: withUnsafePointer(to: &userData) { UnsafeMutablePointer(mutating: $0) }
        )

        if genTangSpaceDefault(&context) == 0 {
            fatalError("Tangent generation failed")
        }

        resultsQueue.sync { results[i] = userData.tangents }
    }

    var result = [Float](repeating: 0, count: vertexCount * 4)
    for partial in results {
        vDSP_vadd(result, 1, partial, 1, &result, 1, vDSP_Length(vertexCount * 4))
    }

    return VertexInfo(
        data: Data(
            bytes: result,
            count: MemoryLayout<Float>.size * result.count
        ),
        componentFormat: .float4,
        componentSize: MemoryLayout<Float>.size * 4
    )
}
