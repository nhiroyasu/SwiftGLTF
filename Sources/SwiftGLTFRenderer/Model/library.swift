import MetalKit

extension MTLDevice {
    func makeSwiftGLTFRendererLib() throws -> MTLLibrary {
        try makeDefaultLibrary(bundle: .module)
    }
}
