import Foundation
import MikkTSpace

private class ContextData {
    let floatPositions: [Float]
    let floatNormals: [Float]
    let floatTexcoords: [Float]
    let indices: [Int]
    let vertexCount: Int
    let convertToLeftHanded: Bool
    var tangents: [Float]

    init(
        floatPositions: [Float],
        floatNormals: [Float],
        floatTexcoords: [Float],
        indices: [Int],
        vertexCount: Int,
        convertToLeftHanded: Bool,
        tangents: [Float]
    ) {
        self.floatPositions = floatPositions
        self.floatNormals = floatNormals
        self.floatTexcoords = floatTexcoords
        self.indices = indices
        self.vertexCount = vertexCount
        self.convertToLeftHanded = convertToLeftHanded
        self.tangents = tangents
    }
}

func generateTangents(
    _ positionVertex: VertexInfo,
    _ normalVertex: VertexInfo,
    _ texcoordVertex: VertexInfo,
    _ indexInfo: IndexInfo,
    vertexCount: Int,
    options: GLTFDecodeOptions
) throws -> VertexInfo {

    var interface = SMikkTSpaceInterface(
        m_getNumFaces: { context in
            guard let data = context?.pointee.m_pUserData.load(as: ContextData.self) else {
                fatalError("Invalid user data")
            }
            return Int32(data.indices.count / 3)
        },
        m_getNumVerticesOfFace: { _, _ in
            return 3
        },
        m_getPosition: { (context, pos, face, vert) in
            guard let data = context?.pointee.m_pUserData.load(as: ContextData.self) else {
                fatalError("Invalid user data")
            }
            let baseIndex = data.indices[Int(face * 3 + vert)] * 3
            var copyPosition = [
                data.floatPositions[baseIndex],
                data.floatPositions[baseIndex + 1],
                data.floatPositions[baseIndex + 2] * (data.convertToLeftHanded ? -1 : 1)
            ]
            memcpy(pos, &copyPosition, MemoryLayout<Float>.size * 3)
        },
        m_getNormal: { (context, normal, face, vert) in
            guard let data = context?.pointee.m_pUserData.load(as: ContextData.self) else {
                fatalError("Invalid user data")
            }
            let baseIndex = data.indices[Int(face * 3 + vert)] * 3
            var copyNormal = [
                data.floatNormals[baseIndex],
                data.floatNormals[baseIndex + 1],
                data.floatNormals[baseIndex + 2] * (data.convertToLeftHanded ? -1 : 1)
            ]
            memcpy(normal, &copyNormal, MemoryLayout<Float>.size * 3)
        },
        m_getTexCoord: { (context, uv, face, vert) in
            guard let data = context?.pointee.m_pUserData.load(as: ContextData.self) else {
                fatalError("Invalid user data")
            }
            let baseIndex = data.indices[Int(face * 3 + vert)] * 2
            var texcoord = [
                data.floatTexcoords[baseIndex],
                data.floatTexcoords[baseIndex + 1]
            ]
            memcpy(uv, &texcoord, MemoryLayout<Float>.size * 2)
        },
        m_setTSpaceBasic: { (context, tangent, sign, face, vert) in
            guard let data = context?.pointee.m_pUserData.load(as: ContextData.self),
                  let tangent else {
                fatalError("Invalid user data")
            }
            let index = data.indices[Int(face * 3 + vert)]
            let tangents = Array(UnsafeBufferPointer(start: tangent, count: 3))
            data.tangents[index * 4] = tangents[0]
            data.tangents[index * 4 + 1] = tangents[1]
            data.tangents[index * 4 + 2] = tangents[2]
            data.tangents[index * 4 + 3] = sign
        },
        m_setTSpace: nil
    )

    let floatPositions = positionVertex.data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    let floatNormals = normalVertex.data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    let floatTexcoords = texcoordVertex.data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }

    var userData = ContextData(
        floatPositions: floatPositions,
        floatNormals: floatNormals,
        floatTexcoords: floatTexcoords,
        indices: try indexInfo.getIndices(),
        vertexCount: vertexCount,
        convertToLeftHanded: options.convertToLeftHanded,
        tangents: Array(repeating: 0, count: vertexCount * 4)
    )

    var context = SMikkTSpaceContext(
        m_pInterface: withUnsafePointer(to: &interface) { UnsafeMutablePointer(mutating: $0) },
        m_pUserData: withUnsafePointer(to: &userData) { UnsafeMutablePointer(mutating: $0) }
    )

    if genTangSpaceDefault(&context) == 0 {
        throw NSError(domain: "MikkTSpace", code: 1, userInfo: nil)
    }

    return VertexInfo(
        data: Data(
            bytes: &userData.tangents,
            count: MemoryLayout<Float>.size * 4 * userData.tangents.count
        ),
        componentFormat: .float4,
        componentSize: MemoryLayout<Float>.size * 4
    )
}
