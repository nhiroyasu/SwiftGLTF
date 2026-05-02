#if os(macOS)
import AppKit

final class DebugHUDScrollAdjustingTextField: NSTextField {
    var scrollStep: Float = 1
    var fractionDigits: Int = 0

    override func scrollWheel(with event: NSEvent) {
        guard isEnabled,
              event.scrollingDeltaY != 0,
              let value = Float(stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return
        }

        let updatedValue = value - Float(event.scrollingDeltaY) * scrollStep
        stringValue = String(format: "%.\(fractionDigits)f", updatedValue)
        sendAction(action, to: target)
    }
}
#endif
