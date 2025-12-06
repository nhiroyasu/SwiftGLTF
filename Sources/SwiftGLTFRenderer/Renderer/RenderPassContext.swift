import Metal

struct RenderPassContext {
    private(set) var passList: [RenderPass]

    init(sequenceList: [RenderPass] = []) {
        self.passList = sequenceList
    }

    enum RenderPass {
        case drawIndex(
            range: Range<Int>,
            cullMode: MTLCullMode,
            pso: MTLRenderPipelineState,
            dso: MTLDepthStencilState
        )
    }

    mutating func add(_ pass: RenderPass) {
        passList.append(pass)
    }
}
