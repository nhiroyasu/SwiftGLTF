#if os(iOS)
import UIKit

final class CameraDebugHUDView: UIView {
    private let stackView = UIStackView()
    private let label = UILabel()
    private let button = UIButton(type: .system)
    var onReset: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = UIColor.black.withAlphaComponent(0.5)
        layer.cornerRadius = 8
        clipsToBounds = true

        stackView.axis = .vertical
        stackView.spacing = 8
        stackView.alignment = .leading
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        ])

        label.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        label.textColor = .white
        label.numberOfLines = 1
        stackView.addArrangedSubview(label)

        button.setTitle("Reset Camera", for: .normal)
        button.addTarget(self, action: #selector(handleReset), for: .touchUpInside)
        stackView.addArrangedSubview(button)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(position: SIMD3<Float>) {
        label.text = String(format: "Camera: (%.2f, %.2f, %.2f)", position.x, position.y, position.z)
    }

    @objc private func handleReset() {
        onReset?()
    }
}
#elseif os(macOS)
import AppKit

final class CameraDebugHUDView: NSView {
    private let stackView = NSStackView()
    private let label: NSTextField
    private let button: NSButton
    var onReset: (() -> Void)?

    override init(frame frameRect: NSRect) {
        label = NSTextField(labelWithString: "")
        button = NSButton(title: "Reset Camera", target: nil, action: nil)
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.5).cgColor
        layer?.cornerRadius = 8

        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.distribution = .gravityAreas
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        ])

        label.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        label.textColor = .labelColor
        stackView.addArrangedSubview(label)

        button.target = self
        button.action = #selector(handleReset)
        button.bezelStyle = .rounded
        stackView.addArrangedSubview(button)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(position: SIMD3<Float>) {
        label.stringValue = String(format: "Camera: (%.2f, %.2f, %.2f)", position.x, position.y, position.z)
    }

    @objc private func handleReset() {
        onReset?()
    }
}
#endif
