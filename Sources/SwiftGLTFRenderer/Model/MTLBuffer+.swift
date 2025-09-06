import MetalKit

extension MTLBuffer {
    func printMemory<T>(_ type: T.Type, capacity: Int) {
        let ptr = contents().bindMemory(to: type, capacity: capacity)
        for i in 0..<capacity {
            print("\(i): \(ptr[i])")
        }
    }
}
