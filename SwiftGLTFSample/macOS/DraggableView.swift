import Cocoa

class DraggableView: NSView {
    private let dragHandler: (URL) async -> Void

    init(frame: CGRect, dragHandler: @escaping (URL) async -> Void) {
        self.dragHandler = dragHandler
        super.init(frame: frame)
        
        registerForDraggedTypes([.fileURL])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let item = sender.draggingPasteboard.pasteboardItems?.first,
              let path = item.string(forType: .fileURL),
              let url = URL(string: path),
              (url.absoluteString.hasSuffix(".gltf") || url.absoluteString.hasSuffix(".glb")) else {
            return []
        }
        return .link
    }

    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let item = sender.draggingPasteboard.pasteboardItems?.first,
              let path = item.string(forType: .fileURL),
              let url = URL(string: path) else {
            return false
        }
        Task { await dragHandler(url) }
        return true
    }
}
