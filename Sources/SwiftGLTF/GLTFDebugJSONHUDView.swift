#if os(iOS)
import UIKit

final class GLTFDebugJSONHUDView: UIView, UITextFieldDelegate {
    private let stackView = UIStackView()
    private let headerLabel = UILabel()
    private let bodyStackView = UIStackView()
    private let searchStackView = UIStackView()
    private let searchField = UISearchTextField()
    private let searchCountLabel = UILabel()
    private let textView = UITextView()
    private var isCollapsed = false
    private var searchRanges: [NSRange] = []
    private var selectedSearchIndex: Int?
    private var currentSearchQuery = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = UIColor.black.withAlphaComponent(0.5)
        layer.cornerRadius = 8
        clipsToBounds = true

        stackView.axis = .vertical
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
        headerLabel.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        headerLabel.isUserInteractionEnabled = true
        headerLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(toggleBody)))
        stackView.addArrangedSubview(headerLabel)
        updateHeader()

        bodyStackView.axis = .vertical
        bodyStackView.spacing = 8
        stackView.addArrangedSubview(bodyStackView)

        searchStackView.axis = .horizontal
        searchStackView.spacing = 8
        searchStackView.alignment = .center
        bodyStackView.addArrangedSubview(searchStackView)

        searchField.delegate = self
        searchField.placeholder = "Search"
        searchField.returnKeyType = .search
        searchField.font = UIFont.systemFont(ofSize: 12, weight: .regular)
        searchField.autocapitalizationType = .none
        searchField.autocorrectionType = .no
        searchField.addTarget(self, action: #selector(searchTextDidChange), for: .editingChanged)
        searchStackView.addArrangedSubview(searchField)

        searchCountLabel.textColor = .white
        searchCountLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        searchCountLabel.textAlignment = .right
        searchCountLabel.setContentHuggingPriority(.required, for: .horizontal)
        searchCountLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        searchStackView.addArrangedSubview(searchCountLabel)

        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.textColor = .white
        textView.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.heightAnchor.constraint(equalToConstant: 240).isActive = true
        bodyStackView.addArrangedSubview(textView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(jsonString: String) {
        textView.text = jsonString
        resetSearch()
    }

    @objc private func toggleBody() {
        isCollapsed.toggle()
        bodyStackView.isHidden = isCollapsed
        updateHeader()
    }

    private func updateHeader() {
        headerLabel.text = "\(isCollapsed ? "▸" : "▾") glTF JSON"
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        searchNext()
        return true
    }

    @objc private func searchTextDidChange() {
        resetSearch()
    }

    private func searchNext() {
        guard let query = searchField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !query.isEmpty,
              let text = textView.text,
              !text.isEmpty else {
            resetSearch()
            return
        }

        if query != currentSearchQuery {
            updateSearchRanges(query: query, text: text)
        }

        guard !searchRanges.isEmpty else {
            selectedSearchIndex = nil
            updateSearchCountLabel()
            return
        }

        let nextIndex = selectedSearchIndex.map { ($0 + 1) % searchRanges.count } ?? 0
        selectedSearchIndex = nextIndex
        let nsRange = searchRanges[nextIndex]
        textView.selectedRange = nsRange
        textView.scrollRangeToVisible(nsRange)
        updateSearchCountLabel()
    }

    private func updateSearchRanges(query: String, text: String) {
        currentSearchQuery = query
        selectedSearchIndex = nil
        searchRanges = []

        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: query, options: [.caseInsensitive], range: searchRange) {
            searchRanges.append(NSRange(range, in: text))
            searchRange = range.upperBound..<text.endIndex
        }
        updateSearchCountLabel()
    }

    private func resetSearch() {
        currentSearchQuery = ""
        searchRanges = []
        selectedSearchIndex = nil
        searchCountLabel.text = ""
    }

    private func updateSearchCountLabel() {
        guard !currentSearchQuery.isEmpty else {
            searchCountLabel.text = ""
            return
        }
        let current = selectedSearchIndex.map { $0 + 1 } ?? 0
        searchCountLabel.text = "\(current)/\(searchRanges.count)"
    }
}
#elseif os(macOS)
import AppKit

final class GLTFDebugJSONHUDView: NSView, NSSearchFieldDelegate {
    private let stackView = NSStackView()
    private let headerLabel = NSTextField(labelWithString: "")
    private let bodyStackView = NSStackView()
    private let searchStackView = NSStackView()
    private let searchField = NSSearchField()
    private let searchCountLabel = NSTextField(labelWithString: "")
    private let scrollView = NSScrollView()
    private let textView = NSTextView()
    private var isCollapsed = false
    private var searchRanges: [NSRange] = []
    private var selectedSearchIndex: Int?
    private var currentSearchQuery = ""

    override init(frame frameRect: NSRect) {
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
        bodyStackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(bodyStackView)
        bodyStackView.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true

        searchStackView.orientation = .horizontal
        searchStackView.alignment = .centerY
        searchStackView.spacing = 8
        searchStackView.translatesAutoresizingMaskIntoConstraints = false
        bodyStackView.addArrangedSubview(searchStackView)
        searchStackView.widthAnchor.constraint(equalTo: bodyStackView.widthAnchor).isActive = true

        searchField.delegate = self
        searchField.placeholderString = "Search"
        searchField.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        searchField.target = self
        searchField.action = #selector(searchNext)
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchStackView.addArrangedSubview(searchField)

        searchCountLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        searchCountLabel.textColor = .white
        searchCountLabel.alignment = .right
        searchCountLabel.setContentHuggingPriority(.required, for: .horizontal)
        searchCountLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        searchStackView.addArrangedSubview(searchCountLabel)
        searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textColor = .white
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.frame = NSRect(x: 0, y: 0, width: 480, height: 240)
        textView.minSize = NSSize(width: 0, height: 240)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.heightAnchor.constraint(equalToConstant: 240).isActive = true
        bodyStackView.addArrangedSubview(scrollView)
        scrollView.widthAnchor.constraint(equalTo: bodyStackView.widthAnchor).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(jsonString: String) {
        textView.string = jsonString
        resetSearch()
    }

    @objc private func toggleBody() {
        isCollapsed.toggle()
        bodyStackView.isHidden = isCollapsed
        updateHeader()
    }

    private func updateHeader() {
        headerLabel.stringValue = "\(isCollapsed ? "▸" : "▾") glTF JSON"
    }

    func controlTextDidChange(_ obj: Notification) {
        resetSearch()
    }

    @objc private func searchNext() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = textView.string
        guard !query.isEmpty, !text.isEmpty else {
            resetSearch()
            return
        }

        if query != currentSearchQuery {
            updateSearchRanges(query: query, text: text)
        }

        guard !searchRanges.isEmpty else {
            selectedSearchIndex = nil
            updateSearchCountLabel()
            return
        }

        let nextIndex = selectedSearchIndex.map { ($0 + 1) % searchRanges.count } ?? 0
        selectedSearchIndex = nextIndex
        let range = searchRanges[nextIndex]
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
        updateSearchCountLabel()
    }

    private func updateSearchRanges(query: String, text: String) {
        currentSearchQuery = query
        selectedSearchIndex = nil
        searchRanges = []

        let nsText = text as NSString
        var location = 0
        while location < nsText.length {
            let range = nsText.range(of: query, options: [.caseInsensitive], range: NSRange(location: location, length: nsText.length - location))
            if range.location == NSNotFound {
                break
            }
            searchRanges.append(range)
            location = range.location + range.length
        }
        updateSearchCountLabel()
    }

    private func resetSearch() {
        currentSearchQuery = ""
        searchRanges = []
        selectedSearchIndex = nil
        searchCountLabel.stringValue = ""
    }

    private func updateSearchCountLabel() {
        guard !currentSearchQuery.isEmpty else {
            searchCountLabel.stringValue = ""
            return
        }
        let current = selectedSearchIndex.map { $0 + 1 } ?? 0
        searchCountLabel.stringValue = "\(current)/\(searchRanges.count)"
    }
}
#endif
