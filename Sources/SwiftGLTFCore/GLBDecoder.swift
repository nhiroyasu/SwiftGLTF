import Foundation

public struct GLBDecoder {
    public static func decode(_ data: Data) throws -> (gltf: GLTF, binaryChunk: Data?) {
        struct GLBError: LocalizedError {
            var errorDescription: String?
        }

        func readUInt32LE(_ range: Range<Data.Index>) -> UInt32 {
            return data.subdata(in: range).withUnsafeBytes { $0.load(as: UInt32.self) }
        }

        guard data.count >= 12 else {
            throw GLBError(errorDescription: "Invalid GLB header")
        }
        let magic = readUInt32LE(0..<4)
        guard magic == 0x46546c67 else { // "glTF"
            throw GLBError(errorDescription: "Invalid magic")
        }
        let version = readUInt32LE(4..<8)
        guard version == 2 else {
            throw GLBError(errorDescription: "Unsupported GLB version")
        }
        let length = Int(readUInt32LE(8..<12))
        guard length <= data.count else {
            throw GLBError(errorDescription: "Length mismatch")
        }
        var offset = 12
        guard offset + 8 <= data.count else {
            throw GLBError(errorDescription: "Missing JSON chunk header")
        }
        let jsonLength = Int(readUInt32LE(offset..<(offset+4)))
        let jsonType = readUInt32LE((offset+4)..<(offset+8))
        guard jsonType == 0x4E4F534A else { // "JSON"
            throw GLBError(errorDescription: "First chunk is not JSON")
        }
        offset += 8
        guard offset + jsonLength <= data.count else {
            throw GLBError(errorDescription: "JSON chunk out of range")
        }
        let jsonData = data.subdata(in: offset..<(offset+jsonLength))
        let decoder = JSONDecoder()
        let gltf = try decoder.decode(GLTF.self, from: jsonData)
        offset += (jsonLength + 3) & ~3 // align 4

        var binaryChunk: Data? = nil
        if offset < data.count {
            guard offset + 8 <= data.count else {
                throw GLBError(errorDescription: "Missing BIN chunk header")
            }
            let binLength = Int(readUInt32LE(offset..<(offset+4)))
            let binType = readUInt32LE((offset+4)..<(offset+8))
            guard binType == 0x004E4942 else { // "BIN\0"
                throw GLBError(errorDescription: "Second chunk is not BIN")
            }
            offset += 8
            guard offset + binLength <= data.count else {
                throw GLBError(errorDescription: "BIN chunk out of range")
            }
            binaryChunk = data.subdata(in: offset..<(offset+binLength))
        }
        return (gltf, binaryChunk)
    }
}
