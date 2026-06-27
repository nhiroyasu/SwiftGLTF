#if os(iOS)
import UIKit

final class CameraDebugHUDView: UIView, UITextFieldDelegate {
    private let stackView = UIStackView()
    private let headerLabel = UILabel()
    private let bodyStackView = UIStackView()
    private let cameraValueLabel = UILabel()
    private let lightFields: [UITextField]
    private let ambientFields: [UITextField]
    private let resetCameraButton = UIButton(type: .system)
    private let resetLightButton = UIButton(type: .system)
    private var isCollapsed = false
    var onReset: (() -> Void)?
    var onLightPositionChange: ((SIMD3<Float>) -> Void)?
    var onAmbientLightColorChange: ((SIMD3<Float>) -> Void)?
    var onLightReset: (() -> Void)?

    override init(frame: CGRect) {
        lightFields = CameraDebugHUDView.makeFields()
        ambientFields = CameraDebugHUDView.makeFields()
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

        headerLabel.textColor = .white
        headerLabel.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        headerLabel.isUserInteractionEnabled = true
        headerLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(toggleBody)))
        stackView.addArrangedSubview(headerLabel)
        updateHeader()

        bodyStackView.axis = .vertical
        bodyStackView.spacing = 8
        bodyStackView.alignment = .leading
        stackView.addArrangedSubview(bodyStackView)

        let cameraSection = UIStackView()
        cameraSection.axis = .vertical
        cameraSection.spacing = 4

        let cameraTitleLabel = UILabel()
        cameraTitleLabel.text = "Camera"
        cameraTitleLabel.textColor = .white
        cameraTitleLabel.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        cameraSection.addArrangedSubview(cameraTitleLabel)

        cameraValueLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        cameraValueLabel.textColor = .white
        cameraValueLabel.numberOfLines = 1
        cameraSection.addArrangedSubview(cameraValueLabel)

        resetCameraButton.setTitle("Reset Camera", for: .normal)
        resetCameraButton.addTarget(self, action: #selector(handleResetCamera), for: .touchUpInside)
        resetCameraButton.contentHorizontalAlignment = .leading
        cameraSection.addArrangedSubview(resetCameraButton)

        bodyStackView.addArrangedSubview(cameraSection)

        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(equalToConstant: 8).isActive = true
        bodyStackView.addArrangedSubview(spacer)

        let lightSection = UIStackView()
        lightSection.axis = .vertical
        lightSection.spacing = 8

        lightSection.addArrangedSubview(
            makeVectorSection(
                title: "Light",
                fields: lightFields,
                labels: ["X", "Y", "Z"],
                selector: #selector(handleLightEditingEnd)
            )
        )
        lightSection.addArrangedSubview(
            makeVectorSection(
                title: "Ambient",
                fields: ambientFields,
                labels: ["R", "G", "B"],
                selector: #selector(handleAmbientEditingEnd)
            )
        )

        resetLightButton.setTitle("Reset Light", for: .normal)
        resetLightButton.addTarget(self, action: #selector(handleResetLight), for: .touchUpInside)
        resetLightButton.contentHorizontalAlignment = .leading
        lightSection.addArrangedSubview(resetLightButton)

        bodyStackView.addArrangedSubview(lightSection)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(position: SIMD3<Float>, lightPosition: SIMD3<Float>, ambientLightColor: SIMD3<Float>) {
        cameraValueLabel.text = String(format: "(%.2f, %.2f, %.2f)", position.x, position.y, position.z)
        set(fields: lightFields, vector: lightPosition)
        set(fields: ambientFields, vector: ambientLightColor)
    }

    @objc private func handleResetCamera() {
        onReset?()
    }

    @objc private func handleResetLight() {
        onLightReset?()
    }

    @objc private func toggleBody() {
        isCollapsed.toggle()
        bodyStackView.isHidden = isCollapsed
        updateHeader()
    }

    private func updateHeader() {
        headerLabel.text = "\(isCollapsed ? "▸" : "▾") Camera Debug"
    }

    @objc private func handleLightEditingEnd() {
        guard let vector = makeVector(from: lightFields) else { return }
        onLightPositionChange?(vector)
    }

    @objc private func handleAmbientEditingEnd() {
        guard let vector = makeVector(from: ambientFields) else { return }
        onAmbientLightColorChange?(vector)
    }

    private static func makeFields() -> [UITextField] {
        (0..<3).map { _ in
            let field = UITextField()
            field.keyboardType = .numbersAndPunctuation
            field.returnKeyType = .done
            field.borderStyle = .roundedRect
            field.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            field.widthAnchor.constraint(equalToConstant: 64).isActive = true
            return field
        }
    }

    private func makeVectorSection(title: String, fields: [UITextField], labels: [String], selector: Selector) -> UIStackView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textColor = .white
        titleLabel.font = UIFont.systemFont(ofSize: 12, weight: .semibold)

        let fieldsStack = UIStackView()
        fieldsStack.axis = .horizontal
        fieldsStack.spacing = 8
        fieldsStack.alignment = .center

        for (index, field) in fields.enumerated() {
            field.delegate = self
            field.addTarget(self, action: selector, for: .editingDidEnd)

            let componentStack = UIStackView()
            componentStack.axis = .horizontal
            componentStack.spacing = 4
            componentStack.alignment = .center

            if labels.indices.contains(index) {
                let label = UILabel()
                label.text = labels[index]
                label.textColor = .white
                label.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
                componentStack.addArrangedSubview(label)
            }

            componentStack.addArrangedSubview(field)
            fieldsStack.addArrangedSubview(componentStack)
        }

        let container = UIStackView(arrangedSubviews: [titleLabel, fieldsStack])
        container.axis = .vertical
        container.spacing = 4
        return container
    }

    private func set(fields: [UITextField], vector: SIMD3<Float>) {
        fields[0].text = String(format: "%.2f", vector.x)
        fields[1].text = String(format: "%.2f", vector.y)
        fields[2].text = String(format: "%.2f", vector.z)
    }

    private func makeVector(from fields: [UITextField]) -> SIMD3<Float>? {
        var components: [Float] = []
        for field in fields {
            guard let text = field.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let value = Float(text) else { return nil }
            components.append(value)
        }
        guard components.count == 3 else { return nil }
        return SIMD3<Float>(components[0], components[1], components[2])
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
#elseif os(macOS)
import AppKit

final class CameraDebugHUDView: NSView {
    private let stackView = NSStackView()
    private let headerLabel: NSTextField
    private let bodyStackView = NSStackView()
    private let cameraValueLabel: NSTextField
    private let lightFields: [NSTextField]
    private let ambientFields: [NSTextField]
    private let resetCameraButton: NSButton
    private let resetLightButton: NSButton
    private var isCollapsed = false
    var onReset: (() -> Void)?
    var onLightPositionChange: ((SIMD3<Float>) -> Void)?
    var onAmbientLightColorChange: ((SIMD3<Float>) -> Void)?
    var onLightReset: (() -> Void)?

    override init(frame frameRect: NSRect) {
        headerLabel = NSTextField(labelWithString: "")
        cameraValueLabel = NSTextField(labelWithString: "")
        resetCameraButton = NSButton(title: "Reset Camera", target: nil, action: nil)
        resetLightButton = NSButton(title: "Reset Light", target: nil, action: nil)
        lightFields = CameraDebugHUDView.makeFields()
        ambientFields = CameraDebugHUDView.makeFields()
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

        headerLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        headerLabel.textColor = .white
        headerLabel.isSelectable = false
        headerLabel.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(toggleBody)))
        stackView.addArrangedSubview(headerLabel)
        updateHeader()

        bodyStackView.orientation = .vertical
        bodyStackView.alignment = .leading
        bodyStackView.spacing = 8
        stackView.addArrangedSubview(bodyStackView)

        let cameraSection = NSStackView()
        cameraSection.orientation = .vertical
        cameraSection.alignment = .leading
        cameraSection.spacing = 4

        let cameraTitleLabel = NSTextField(labelWithString: "Camera")
        cameraTitleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        cameraTitleLabel.textColor = .white
        cameraSection.addArrangedSubview(cameraTitleLabel)

        cameraValueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        cameraValueLabel.textColor = .white
        cameraSection.addArrangedSubview(cameraValueLabel)

        resetCameraButton.target = self
        resetCameraButton.action = #selector(handleResetCamera)
        resetCameraButton.bezelColor = .controlBackgroundColor
        resetCameraButton.alignment = .left
        cameraSection.addArrangedSubview(resetCameraButton)

        bodyStackView.addArrangedSubview(cameraSection)

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(equalToConstant: 8).isActive = true
        bodyStackView.addArrangedSubview(spacer)

        let lightSection = NSStackView()
        lightSection.orientation = .vertical
        lightSection.alignment = .leading
        lightSection.spacing = 8

        lightSection.addArrangedSubview(
            makeVectorSection(
                title: "Light",
                fields: lightFields,
                labels: ["X", "Y", "Z"],
                selector: #selector(handleLightEditingEnd)
            )
        )
        lightSection.addArrangedSubview(
            makeVectorSection(
                title: "Ambient",
                fields: ambientFields,
                labels: ["R", "G", "B"],
                selector: #selector(handleAmbientEditingEnd)
            )
        )

        resetLightButton.target = self
        resetLightButton.action = #selector(handleResetLight)
        resetLightButton.bezelColor = .controlBackgroundColor
        resetLightButton.alignment = .left
        lightSection.addArrangedSubview(resetLightButton)

        bodyStackView.addArrangedSubview(lightSection)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(position: SIMD3<Float>, lightPosition: SIMD3<Float>, ambientLightColor: SIMD3<Float>) {
        cameraValueLabel.stringValue = String(format: "(%.2f, %.2f, %.2f)", position.x, position.y, position.z)
        set(fields: lightFields, vector: lightPosition)
        set(fields: ambientFields, vector: ambientLightColor)
    }

    @objc private func handleResetCamera() {
        onReset?()
    }

    @objc private func handleResetLight() {
        onLightReset?()
    }

    @objc private func toggleBody() {
        isCollapsed.toggle()
        bodyStackView.isHidden = isCollapsed
        updateHeader()
    }

    private func updateHeader() {
        headerLabel.stringValue = "\(isCollapsed ? "▸" : "▾") Camera Debug"
    }

    @objc private func handleLightEditingEnd() {
        guard let vector = makeVector(from: lightFields) else { return }
        onLightPositionChange?(vector)
    }

    @objc private func handleAmbientEditingEnd() {
        guard let vector = makeVector(from: ambientFields) else { return }
        onAmbientLightColorChange?(vector)
    }

    private static func makeFields() -> [NSTextField] {
        (0..<3).map { _ in
            let field = DebugHUDScrollAdjustingTextField()
            field.scrollStep = 0.01
            field.fractionDigits = 2
            field.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            field.alignment = .left
            field.maximumNumberOfLines = 1
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(equalToConstant: 64).isActive = true
            return field
        }
    }

    private func makeVectorSection(title: String, fields: [NSTextField], labels: [String], selector: Selector) -> NSStackView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .white

        let fieldsStack = NSStackView()
        fieldsStack.orientation = .horizontal
        fieldsStack.alignment = .centerY
        fieldsStack.spacing = 8

        for (index, field) in fields.enumerated() {
            field.target = self
            field.action = selector

            let componentStack = NSStackView()
            componentStack.orientation = .horizontal
            componentStack.alignment = .centerY
            componentStack.spacing = 4

            if labels.indices.contains(index) {
                let label = NSTextField(labelWithString: labels[index])
                label.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
                label.textColor = .white
                componentStack.addArrangedSubview(label)
            }

            componentStack.addArrangedSubview(field)
            fieldsStack.addArrangedSubview(componentStack)
        }

        let container = NSStackView(views: [titleLabel, fieldsStack])
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 4
        return container
    }

    private func set(fields: [NSTextField], vector: SIMD3<Float>) {
        fields[0].stringValue = String(format: "%.2f", vector.x)
        fields[1].stringValue = String(format: "%.2f", vector.y)
        fields[2].stringValue = String(format: "%.2f", vector.z)
    }

    private func makeVector(from fields: [NSTextField]) -> SIMD3<Float>? {
        var components: [Float] = []
        for field in fields {
            let trimmed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value = Float(trimmed) else { return nil }
            components.append(value)
        }
        guard components.count == 3 else { return nil }
        return SIMD3<Float>(components[0], components[1], components[2])
    }
}
#endif
