import SwiftGLTFCore
import ModelIO

struct IndexInfo {
    let data: Data
    let count: Int
    let type: MDLIndexBitDepth

    func getIndices() throws -> [Int] {
        try data.withUnsafeBytes {
            switch type {
            case .uInt8:
                let uint8Array = Array($0.bindMemory(to: UInt8.self))
                let intArray = Array<Int>(unsafeUninitializedCapacity: uint8Array.count) { buffer, initializedCount in
                    for (i, value) in uint8Array.enumerated() {
                        buffer[i] = Int(value)
                    }
                    initializedCount = uint8Array.count
                }
                return intArray
            case .uInt16:
                let uint16Array = Array($0.bindMemory(to: UInt16.self))
                let intArray = Array<Int>(unsafeUninitializedCapacity: uint16Array.count) { buffer, initializedCount in
                    for (i, value) in uint16Array.enumerated() {
                        buffer[i] = Int(value)
                    }
                    initializedCount = uint16Array.count
                }
                return intArray
            case .uInt32:
                let uint32Array = Array($0.bindMemory(to: UInt32.self))
                let intArray = Array<Int>(unsafeUninitializedCapacity: uint32Array.count) { buffer, initializedCount in
                    for (i, value) in uint32Array.enumerated() {
                        buffer[i] = Int(value)
                    }
                    initializedCount = uint32Array.count
                }
                return intArray
            default:
                throw SwiftGLTFError.parser(description: "Unsupported index type for normal generation")
            }
        }
    }
}
