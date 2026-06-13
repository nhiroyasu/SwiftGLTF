import SwiftGLTFCore

#if os(iOS)
import UIKit

final class VRMExpressionDebugHUDView: UIView {
    private let stackView = UIStackView()
    private let headerLabel = UILabel()
    private let bodyStackView = UIStackView()
    private var slidersByKey: [VRMExpressionKey: UISlider] = [:]
    private var valueLabelsByKey: [VRMExpressionKey: UILabel] = [:]
    private var sliderKeyMap: [ObjectIdentifier: VRMExpressionKey] = [:]
    private var expressionKeys: [VRMExpressionKey] = []
    private var isCollapsed = false
    var onExpressionWeightChange: ((VRMExpressionKey, Float) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.black.withAlphaComponent(0.5)
        layer.cornerRadius = 8
        clipsToBounds = true

        stackView.axis = .vertical
        stackView.spacing = 8
        stackView.alignment = .fill
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
        bodyStackView.alignment = .fill
        stackView.addArrangedSubview(bodyStackView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(expressions: [VRMExpressionKey], weights: [VRMExpressionKey: Float]) {
        guard expressions != expressionKeys else {
            updateValues(weights: weights)
            updateHeader()
            return
        }
        expressionKeys = expressions
        bodyStackView.arrangedSubviews.forEach {
            bodyStackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        slidersByKey.removeAll()
        valueLabelsByKey.removeAll()
        sliderKeyMap.removeAll()

        for expression in expressions {
            let row = makeRow(for: expression, value: weights[expression] ?? 0)
            bodyStackView.addArrangedSubview(row)
        }
        updateHeader()
    }

    private func updateValues(weights: [VRMExpressionKey: Float]) {
        for key in expressionKeys {
            let value = clamped(weights[key] ?? 0)
            if let slider = slidersByKey[key], !slider.isTracking {
                slider.value = value
            }
            valueLabelsByKey[key]?.text = String(format: "%.2f", value)
        }
    }

    private func makeRow(for key: VRMExpressionKey, value: Float) -> UIStackView {
        let titleLabel = UILabel()
        titleLabel.text = key.name
        titleLabel.textColor = .white
        titleLabel.font = UIFont.systemFont(ofSize: 11, weight: .semibold)

        let slider = UISlider()
        slider.minimumValue = 0
        slider.maximumValue = 1
        slider.value = clamped(value)
        slider.addTarget(self, action: #selector(handleSlider(_:)), for: .valueChanged)
        slidersByKey[key] = slider
        sliderKeyMap[ObjectIdentifier(slider)] = key

        let valueLabel = UILabel()
        valueLabel.text = String(format: "%.2f", slider.value)
        valueLabel.textColor = .white
        valueLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        valueLabel.widthAnchor.constraint(equalToConstant: 36).isActive = true
        valueLabelsByKey[key] = valueLabel

        let controlStack = UIStackView(arrangedSubviews: [slider, valueLabel])
        controlStack.axis = .horizontal
        controlStack.spacing = 8
        controlStack.alignment = .center

        let row = UIStackView(arrangedSubviews: [titleLabel, controlStack])
        row.axis = .vertical
        row.spacing = 4
        return row
    }

    @objc private func handleSlider(_ sender: UISlider) {
        guard let key = sliderKeyMap[ObjectIdentifier(sender)] else { return }
        let value = clamped(sender.value)
        valueLabelsByKey[key]?.text = String(format: "%.2f", value)
        onExpressionWeightChange?(key, value)
    }

    @objc private func toggleBody() {
        isCollapsed.toggle()
        bodyStackView.isHidden = isCollapsed
        updateHeader()
    }

    private func updateHeader() {
        headerLabel.text = "\(isCollapsed ? "▸" : "▾") VRM Expressions"
    }

    private func clamped(_ value: Float) -> Float {
        min(max(value, 0), 1)
    }
}
#elseif os(macOS)
import AppKit

final class VRMExpressionDebugHUDView: NSView {
    private let stackView = NSStackView()
    private let headerLabel = NSTextField(labelWithString: "")
    private let bodyStackView = NSStackView()
    private var slidersByKey: [VRMExpressionKey: NSSlider] = [:]
    private var valueLabelsByKey: [VRMExpressionKey: NSTextField] = [:]
    private var sliderKeyMap: [ObjectIdentifier: VRMExpressionKey] = [:]
    private var expressionKeys: [VRMExpressionKey] = []
    private var isCollapsed = false
    var onExpressionWeightChange: ((VRMExpressionKey, Float) -> Void)?

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

        headerLabel.textColor = .white
        headerLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        headerLabel.isEditable = false
        headerLabel.isBezeled = false
        headerLabel.drawsBackground = false
        let click = NSClickGestureRecognizer(target: self, action: #selector(toggleBody))
        headerLabel.addGestureRecognizer(click)
        stackView.addArrangedSubview(headerLabel)
        updateHeader()

        bodyStackView.orientation = .vertical
        bodyStackView.alignment = .leading
        bodyStackView.spacing = 8
        stackView.addArrangedSubview(bodyStackView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(expressions: [VRMExpressionKey], weights: [VRMExpressionKey: Float]) {
        guard expressions != expressionKeys else {
            updateValues(weights: weights)
            updateHeader()
            return
        }
        expressionKeys = expressions
        bodyStackView.arrangedSubviews.forEach {
            bodyStackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        slidersByKey.removeAll()
        valueLabelsByKey.removeAll()
        sliderKeyMap.removeAll()

        for expression in expressions {
            let row = makeRow(for: expression, value: weights[expression] ?? 0)
            bodyStackView.addArrangedSubview(row)
        }
        updateHeader()
    }

    private func updateValues(weights: [VRMExpressionKey: Float]) {
        for key in expressionKeys {
            let value = clamped(weights[key] ?? 0)
            slidersByKey[key]?.floatValue = value
            valueLabelsByKey[key]?.stringValue = String(format: "%.2f", value)
        }
    }

    private func makeRow(for key: VRMExpressionKey, value: Float) -> NSStackView {
        let titleLabel = NSTextField(labelWithString: key.name)
        titleLabel.textColor = .white
        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)

        let slider = NSSlider(value: Double(clamped(value)), minValue: 0, maxValue: 1, target: self, action: #selector(handleSlider(_:)))
        slider.isContinuous = true
        slider.widthAnchor.constraint(equalToConstant: 180).isActive = true
        slidersByKey[key] = slider
        sliderKeyMap[ObjectIdentifier(slider)] = key

        let valueLabel = NSTextField(labelWithString: String(format: "%.2f", slider.floatValue))
        valueLabel.textColor = .white
        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        valueLabel.widthAnchor.constraint(equalToConstant: 36).isActive = true
        valueLabelsByKey[key] = valueLabel

        let controlStack = NSStackView(views: [slider, valueLabel])
        controlStack.orientation = .horizontal
        controlStack.spacing = 8
        controlStack.alignment = .centerY

        let row = NSStackView(views: [titleLabel, controlStack])
        row.orientation = .vertical
        row.spacing = 4
        row.alignment = .leading
        return row
    }

    @objc private func handleSlider(_ sender: NSSlider) {
        guard let key = sliderKeyMap[ObjectIdentifier(sender)] else { return }
        let value = clamped(sender.floatValue)
        valueLabelsByKey[key]?.stringValue = String(format: "%.2f", value)
        onExpressionWeightChange?(key, value)
    }

    @objc private func toggleBody() {
        isCollapsed.toggle()
        bodyStackView.isHidden = isCollapsed
        updateHeader()
    }

    private func updateHeader() {
        headerLabel.stringValue = "\(isCollapsed ? "▸" : "▾") VRM Expressions"
    }

    private func clamped(_ value: Float) -> Float {
        min(max(value, 0), 1)
    }
}
#endif
