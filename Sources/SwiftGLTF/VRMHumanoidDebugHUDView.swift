import Foundation
import SwiftGLTFCore
import simd

private func vrmQuaternion(fromDegrees degrees: SIMD3<Float>) -> simd_quatf {
    let radians = degrees * (.pi / 180)
    let qx = simd_quatf(angle: radians.x, axis: SIMD3<Float>(1, 0, 0))
    let qy = simd_quatf(angle: radians.y, axis: SIMD3<Float>(0, 1, 0))
    let qz = simd_quatf(angle: radians.z, axis: SIMD3<Float>(0, 0, 1))
    return simd_normalize(qz * qy * qx)
}

private func vrmEulerDegrees(from quaternion: simd_quatf) -> SIMD3<Float> {
    let q = simd_normalize(quaternion)
    let x = q.imag.x
    let y = q.imag.y
    let z = q.imag.z
    let w = q.real
    let roll = atan2(2 * (w * x + y * z), 1 - 2 * (x * x + y * y))
    let pitch = asin(max(-1, min(1, 2 * (w * y - z * x))))
    let yaw = atan2(2 * (w * z + x * y), 1 - 2 * (y * y + z * z))
    return SIMD3<Float>(roll, pitch, yaw) * (180 / .pi)
}

#if os(iOS)
import UIKit

final class VRMHumanoidDebugHUDView: UIView, UITextFieldDelegate {
    private let stackView = UIStackView()
    private var fieldsByBone: [VRMHumanoidBoneName: [UITextField]] = [:]
    private var fieldBoneMap: [ObjectIdentifier: VRMHumanoidBoneName] = [:]
    private var resetBoneMap: [ObjectIdentifier: VRMHumanoidBoneName] = [:]
    var onBoneRotationChange: ((VRMHumanoidBoneName, simd_quatf) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
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

        let titleLabel = UILabel()
        titleLabel.text = "VRM Humanoid"
        titleLabel.textColor = .white
        titleLabel.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        stackView.addArrangedSubview(titleLabel)

        for boneName in VRMHumanoidBoneName.supportedTransformBones {
            stackView.addArrangedSubview(makeRow(for: boneName))
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(availableBones: Set<VRMHumanoidBoneName>, rotations: [VRMHumanoidBoneName: simd_quatf]) {
        for boneName in VRMHumanoidBoneName.supportedTransformBones {
            let enabled = availableBones.contains(boneName)
            guard let fields = fieldsByBone[boneName] else { continue }
            let degrees = vrmEulerDegrees(from: rotations[boneName] ?? simd_quatf(angle: 0, axis: SIMD3<Float>(1, 0, 0)))
            for (index, field) in fields.enumerated() {
                field.isEnabled = enabled
                field.alpha = enabled ? 1.0 : 0.4
                field.text = String(format: "%.1f", degrees[index])
            }
        }
    }

    private func makeRow(for boneName: VRMHumanoidBoneName) -> UIStackView {
        let label = UILabel()
        label.text = boneName.rawValue
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 11, weight: .semibold)

        let row = UIStackView()
        row.axis = .vertical
        row.spacing = 4
        row.alignment = .leading
        row.addArrangedSubview(label)

        let controls = UIStackView()
        controls.axis = .horizontal
        controls.spacing = 6
        controls.alignment = .center

        let fields = (0..<3).map { _ in makeField(for: boneName) }
        fieldsByBone[boneName] = fields
        for field in fields {
            controls.addArrangedSubview(field)
        }

        let resetButton = UIButton(type: .system)
        resetButton.setTitle("Reset", for: .normal)
        resetButton.titleLabel?.font = UIFont.systemFont(ofSize: 11)
        resetButton.addTarget(self, action: #selector(handleReset(_:)), for: .touchUpInside)
        resetBoneMap[ObjectIdentifier(resetButton)] = boneName
        controls.addArrangedSubview(resetButton)
        row.addArrangedSubview(controls)

        return row
    }

    private func makeField(for boneName: VRMHumanoidBoneName) -> UITextField {
        let field = UITextField()
        field.keyboardType = .numbersAndPunctuation
        field.returnKeyType = .done
        field.borderStyle = .roundedRect
        field.font = UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        field.widthAnchor.constraint(equalToConstant: 44).isActive = true
        field.delegate = self
        field.addTarget(self, action: #selector(handleEditingEnd(_:)), for: .editingDidEnd)
        fieldBoneMap[ObjectIdentifier(field)] = boneName
        return field
    }

    @objc private func handleEditingEnd(_ sender: UITextField) {
        guard let boneName = fieldBoneMap[ObjectIdentifier(sender)],
              let fields = fieldsByBone[boneName],
              let vector = makeVector(from: fields) else {
            return
        }
        onBoneRotationChange?(boneName, vrmQuaternion(fromDegrees: vector))
    }

    @objc private func handleReset(_ sender: UIButton) {
        guard let boneName = resetBoneMap[ObjectIdentifier(sender)] else { return }
        onBoneRotationChange?(boneName, simd_quatf(angle: 0, axis: SIMD3<Float>(1, 0, 0)))
    }

    private func makeVector(from fields: [UITextField]) -> SIMD3<Float>? {
        let values = fields.compactMap { Float($0.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") }
        guard values.count == 3 else { return nil }
        return SIMD3<Float>(values[0], values[1], values[2])
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
#elseif os(macOS)
import AppKit

final class VRMHumanoidDebugHUDView: NSView {
    private let stackView = NSStackView()
    private var fieldsByBone: [VRMHumanoidBoneName: [NSTextField]] = [:]
    private var fieldBoneMap: [ObjectIdentifier: VRMHumanoidBoneName] = [:]
    private var resetBoneMap: [ObjectIdentifier: VRMHumanoidBoneName] = [:]
    var onBoneRotationChange: ((VRMHumanoidBoneName, simd_quatf) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.5).cgColor
        layer?.cornerRadius = 8

        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        ])

        let titleLabel = NSTextField(labelWithString: "VRM Humanoid")
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .white
        stackView.addArrangedSubview(titleLabel)

        for boneName in VRMHumanoidBoneName.supportedTransformBones {
            stackView.addArrangedSubview(makeRow(for: boneName))
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(availableBones: Set<VRMHumanoidBoneName>, rotations: [VRMHumanoidBoneName: simd_quatf]) {
        for boneName in VRMHumanoidBoneName.supportedTransformBones {
            let enabled = availableBones.contains(boneName)
            guard let fields = fieldsByBone[boneName] else { continue }
            let degrees = vrmEulerDegrees(from: rotations[boneName] ?? simd_quatf(angle: 0, axis: SIMD3<Float>(1, 0, 0)))
            for (index, field) in fields.enumerated() {
                field.isEnabled = enabled
                field.alphaValue = enabled ? 1.0 : 0.4
                field.stringValue = String(format: "%.1f", degrees[index])
            }
        }
    }

    private func makeRow(for boneName: VRMHumanoidBoneName) -> NSStackView {
        let label = NSTextField(labelWithString: boneName.rawValue)
        label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .white

        let row = NSStackView()
        row.orientation = .vertical
        row.alignment = .leading
        row.spacing = 4
        row.addArrangedSubview(label)

        let controls = NSStackView()
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 6

        let fields = (0..<3).map { _ in makeField(for: boneName) }
        fieldsByBone[boneName] = fields
        for field in fields {
            controls.addArrangedSubview(field)
        }

        let resetButton = NSButton(title: "Reset", target: self, action: #selector(handleReset(_:)))
        resetButton.bezelColor = .controlBackgroundColor
        resetButton.font = NSFont.systemFont(ofSize: 11)
        resetBoneMap[ObjectIdentifier(resetButton)] = boneName
        controls.addArrangedSubview(resetButton)
        row.addArrangedSubview(controls)

        return row
    }

    private func makeField(for boneName: VRMHumanoidBoneName) -> NSTextField {
        let field = NSTextField()
        field.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        field.alignment = .left
        field.maximumNumberOfLines = 1
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 44).isActive = true
        field.target = self
        field.action = #selector(handleEditingEnd(_:))
        fieldBoneMap[ObjectIdentifier(field)] = boneName
        return field
    }

    @objc private func handleEditingEnd(_ sender: NSTextField) {
        guard let boneName = fieldBoneMap[ObjectIdentifier(sender)],
              let fields = fieldsByBone[boneName],
              let vector = makeVector(from: fields) else {
            return
        }
        onBoneRotationChange?(boneName, vrmQuaternion(fromDegrees: vector))
    }

    @objc private func handleReset(_ sender: NSButton) {
        guard let boneName = resetBoneMap[ObjectIdentifier(sender)] else { return }
        onBoneRotationChange?(boneName, simd_quatf(angle: 0, axis: SIMD3<Float>(1, 0, 0)))
    }

    private func makeVector(from fields: [NSTextField]) -> SIMD3<Float>? {
        let values = fields.compactMap { Float($0.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard values.count == 3 else { return nil }
        return SIMD3<Float>(values[0], values[1], values[2])
    }
}
#endif
