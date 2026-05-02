import Foundation
import SwiftGLTFCore
import simd

private struct VRMHumanoidDebugHUDSection {
    let title: String
    let bones: [VRMHumanoidBoneName]
}

private let vrmHumanoidDebugHUDSections: [VRMHumanoidDebugHUDSection] = {
    let torso: [VRMHumanoidBoneName] = [.hips, .spine, .chest, .upperChest]
    let head: [VRMHumanoidBoneName] = [.neck, .head, .leftEye, .rightEye, .jaw]
    let legs: [VRMHumanoidBoneName] = [
        .leftUpperLeg, .leftLowerLeg, .leftFoot, .leftToes,
        .rightUpperLeg, .rightLowerLeg, .rightFoot, .rightToes
    ]
    let arms: [VRMHumanoidBoneName] = [
        .leftShoulder, .leftUpperArm, .leftLowerArm, .leftHand,
        .rightShoulder, .rightUpperArm, .rightLowerArm, .rightHand
    ]
    let fingers: [VRMHumanoidBoneName] = [
        .leftThumbMetacarpal, .leftThumbProximal, .leftThumbDistal,
        .leftIndexProximal, .leftIndexIntermediate, .leftIndexDistal,
        .leftMiddleProximal, .leftMiddleIntermediate, .leftMiddleDistal,
        .leftRingProximal, .leftRingIntermediate, .leftRingDistal,
        .leftLittleProximal, .leftLittleIntermediate, .leftLittleDistal,
        .rightThumbMetacarpal, .rightThumbProximal, .rightThumbDistal,
        .rightIndexProximal, .rightIndexIntermediate, .rightIndexDistal,
        .rightMiddleProximal, .rightMiddleIntermediate, .rightMiddleDistal,
        .rightRingProximal, .rightRingIntermediate, .rightRingDistal,
        .rightLittleProximal, .rightLittleIntermediate, .rightLittleDistal
    ]
    let groupedBones = Set(torso + head + legs + arms + fingers)
    let others = VRMHumanoidBoneName.allCases.filter { !groupedBones.contains($0) }
    return [
        VRMHumanoidDebugHUDSection(title: "Torso", bones: torso),
        VRMHumanoidDebugHUDSection(title: "Head", bones: head),
        VRMHumanoidDebugHUDSection(title: "Legs", bones: legs),
        VRMHumanoidDebugHUDSection(title: "Arms", bones: arms),
        VRMHumanoidDebugHUDSection(title: "Fingers", bones: fingers),
        VRMHumanoidDebugHUDSection(title: "Other", bones: others)
    ]
}()

#if os(iOS)
import UIKit

final class VRMHumanoidDebugHUDView: UIView, UITextFieldDelegate {
    private let stackView = UIStackView()
    private let headerLabel = UILabel()
    private let bodyStackView = UIStackView()
    private var sectionViewsByTitle: [String: UIStackView] = [:]
    private var sectionBodyViewsByTitle: [String: UIStackView] = [:]
    private var sectionTitleLabelsByTitle: [String: UILabel] = [:]
    private var sectionTitleMap: [ObjectIdentifier: String] = [:]
    private var rowsByBone: [VRMHumanoidBoneName: UIStackView] = [:]
    private var fieldsByBone: [VRMHumanoidBoneName: [UITextField]] = [:]
    private var fieldBoneMap: [ObjectIdentifier: VRMHumanoidBoneName] = [:]
    private var resetBoneMap: [ObjectIdentifier: VRMHumanoidBoneName] = [:]
    private var isCollapsed = false
    private var collapsedSectionTitles = Set(vrmHumanoidDebugHUDSections.map(\.title))
    var onBoneRotationChange: ((VRMHumanoidBoneName, SIMD3<Float>) -> Void)?

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

        for section in vrmHumanoidDebugHUDSections {
            let sectionView = makeSection(for: section)
            sectionViewsByTitle[section.title] = sectionView
            bodyStackView.addArrangedSubview(sectionView)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(availableBones: Set<VRMHumanoidBoneName>, rotations: [VRMHumanoidBoneName: SIMD3<Float>]) {
        for section in vrmHumanoidDebugHUDSections {
            sectionViewsByTitle[section.title]?.isHidden = !section.bones.contains { availableBones.contains($0) }
            sectionBodyViewsByTitle[section.title]?.isHidden = collapsedSectionTitles.contains(section.title)
        }

        for boneName in VRMHumanoidBoneName.allCases {
            let isAvailable = availableBones.contains(boneName)
            rowsByBone[boneName]?.isHidden = !isAvailable
            guard let fields = fieldsByBone[boneName] else { continue }
            let degrees = rotations[boneName] ?? .zero
            for (index, field) in fields.enumerated() {
                field.isEnabled = isAvailable
                field.alpha = isAvailable ? 1.0 : 0.4
                field.text = String(format: "%.1f", degrees[index])
            }
        }
    }

    private func makeSection(for section: VRMHumanoidDebugHUDSection) -> UIStackView {
        let titleLabel = UILabel()
        titleLabel.textColor = .lightGray
        titleLabel.font = UIFont.systemFont(ofSize: 12, weight: .bold)
        titleLabel.isUserInteractionEnabled = true
        titleLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(toggleSection(_:))))
        sectionTitleLabelsByTitle[section.title] = titleLabel
        sectionTitleMap[ObjectIdentifier(titleLabel)] = section.title

        let sectionView = UIStackView()
        sectionView.axis = .vertical
        sectionView.spacing = 6
        sectionView.alignment = .leading
        sectionView.addArrangedSubview(titleLabel)

        let sectionBodyView = UIStackView()
        sectionBodyView.axis = .vertical
        sectionBodyView.spacing = 6
        sectionBodyView.alignment = .leading
        sectionBodyView.isHidden = collapsedSectionTitles.contains(section.title)
        sectionBodyViewsByTitle[section.title] = sectionBodyView
        sectionView.addArrangedSubview(sectionBodyView)

        for boneName in section.bones {
            let row = makeRow(for: boneName)
            rowsByBone[boneName] = row
            sectionBodyView.addArrangedSubview(row)
        }

        updateSectionHeader(title: section.title)
        return sectionView
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
        onBoneRotationChange?(boneName, vector)
    }

    @objc private func handleReset(_ sender: UIButton) {
        guard let boneName = resetBoneMap[ObjectIdentifier(sender)] else { return }
        onBoneRotationChange?(boneName, .zero)
    }

    @objc private func toggleBody() {
        isCollapsed.toggle()
        bodyStackView.isHidden = isCollapsed
        updateHeader()
    }

    @objc private func toggleSection(_ sender: UITapGestureRecognizer) {
        guard let view = sender.view,
              let title = sectionTitleMap[ObjectIdentifier(view)] else {
            return
        }

        if collapsedSectionTitles.contains(title) {
            collapsedSectionTitles.remove(title)
        } else {
            collapsedSectionTitles.insert(title)
        }
        sectionBodyViewsByTitle[title]?.isHidden = collapsedSectionTitles.contains(title)
        updateSectionHeader(title: title)
    }

    private func updateHeader() {
        headerLabel.text = "\(isCollapsed ? "▸" : "▾") VRM Humanoid"
    }

    private func updateSectionHeader(title: String) {
        sectionTitleLabelsByTitle[title]?.text = "\(collapsedSectionTitles.contains(title) ? "▸" : "▾") \(title)"
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
    private let headerLabel = NSTextField(labelWithString: "")
    private let bodyStackView = NSStackView()
    private var sectionViewsByTitle: [String: NSStackView] = [:]
    private var sectionBodyViewsByTitle: [String: NSStackView] = [:]
    private var sectionTitleLabelsByTitle: [String: NSTextField] = [:]
    private var sectionTitleMap: [ObjectIdentifier: String] = [:]
    private var rowsByBone: [VRMHumanoidBoneName: NSStackView] = [:]
    private var fieldsByBone: [VRMHumanoidBoneName: [NSTextField]] = [:]
    private var fieldBoneMap: [ObjectIdentifier: VRMHumanoidBoneName] = [:]
    private var resetBoneMap: [ObjectIdentifier: VRMHumanoidBoneName] = [:]
    private var isCollapsed = false
    private var collapsedSectionTitles = Set(vrmHumanoidDebugHUDSections.map(\.title))
    var onBoneRotationChange: ((VRMHumanoidBoneName, SIMD3<Float>) -> Void)?

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

        for section in vrmHumanoidDebugHUDSections {
            let sectionView = makeSection(for: section)
            sectionViewsByTitle[section.title] = sectionView
            bodyStackView.addArrangedSubview(sectionView)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(availableBones: Set<VRMHumanoidBoneName>, rotations: [VRMHumanoidBoneName: SIMD3<Float>]) {
        for section in vrmHumanoidDebugHUDSections {
            sectionViewsByTitle[section.title]?.isHidden = !section.bones.contains { availableBones.contains($0) }
            sectionBodyViewsByTitle[section.title]?.isHidden = collapsedSectionTitles.contains(section.title)
        }

        for boneName in VRMHumanoidBoneName.allCases {
            let isAvailable = availableBones.contains(boneName)
            rowsByBone[boneName]?.isHidden = !isAvailable
            guard let fields = fieldsByBone[boneName] else { continue }
            let degrees = rotations[boneName] ?? .zero
            for (index, field) in fields.enumerated() {
                field.isEnabled = isAvailable
                field.alphaValue = isAvailable ? 1.0 : 0.4
                field.stringValue = String(format: "%.1f", degrees[index])
            }
        }
    }

    private func makeSection(for section: VRMHumanoidDebugHUDSection) -> NSStackView {
        let titleLabel = NSTextField(labelWithString: "")
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        titleLabel.textColor = .lightGray
        titleLabel.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(toggleSection(_:))))
        sectionTitleLabelsByTitle[section.title] = titleLabel
        sectionTitleMap[ObjectIdentifier(titleLabel)] = section.title

        let sectionView = NSStackView()
        sectionView.orientation = .vertical
        sectionView.alignment = .leading
        sectionView.spacing = 6
        sectionView.addArrangedSubview(titleLabel)

        let sectionBodyView = NSStackView()
        sectionBodyView.orientation = .vertical
        sectionBodyView.alignment = .leading
        sectionBodyView.spacing = 6
        sectionBodyView.isHidden = collapsedSectionTitles.contains(section.title)
        sectionBodyViewsByTitle[section.title] = sectionBodyView
        sectionView.addArrangedSubview(sectionBodyView)

        for boneName in section.bones {
            let row = makeRow(for: boneName)
            rowsByBone[boneName] = row
            sectionBodyView.addArrangedSubview(row)
        }

        updateSectionHeader(title: section.title)
        return sectionView
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
        let field = DebugHUDScrollAdjustingTextField()
        field.scrollStep = 0.1
        field.fractionDigits = 1
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
        onBoneRotationChange?(boneName, vector)
    }

    @objc private func handleReset(_ sender: NSButton) {
        guard let boneName = resetBoneMap[ObjectIdentifier(sender)] else { return }
        onBoneRotationChange?(boneName, .zero)
    }

    @objc private func toggleBody() {
        isCollapsed.toggle()
        bodyStackView.isHidden = isCollapsed
        updateHeader()
    }

    @objc private func toggleSection(_ sender: NSClickGestureRecognizer) {
        guard let view = sender.view,
              let title = sectionTitleMap[ObjectIdentifier(view)] else {
            return
        }

        if collapsedSectionTitles.contains(title) {
            collapsedSectionTitles.remove(title)
        } else {
            collapsedSectionTitles.insert(title)
        }
        sectionBodyViewsByTitle[title]?.isHidden = collapsedSectionTitles.contains(title)
        updateSectionHeader(title: title)
    }

    private func updateHeader() {
        headerLabel.stringValue = "\(isCollapsed ? "▸" : "▾") VRM Humanoid"
    }

    private func updateSectionHeader(title: String) {
        sectionTitleLabelsByTitle[title]?.stringValue = "\(collapsedSectionTitles.contains(title) ? "▸" : "▾") \(title)"
    }

    private func makeVector(from fields: [NSTextField]) -> SIMD3<Float>? {
        let values = fields.compactMap { Float($0.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard values.count == 3 else { return nil }
        return SIMD3<Float>(values[0], values[1], values[2])
    }
}
#endif
