import MetalKit

extension MTLSizeAndAlign {
    var alignedSize: Int {
        return (size + align - 1) & ~(align - 1)
    }
}
