import AppKit

final class CodeBlockView: NSView {

    private let headerView: NSView
    private let languageLabel: NSTextField
    private let copyButton: NSButton
    private let codeTextField: NSTextField
    private var currentCode = ""

    private static let backgroundColorDynamic = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor.white.withAlphaComponent(0.08)
            : NSColor.black.withAlphaComponent(0.04)
    }

    private static let headerColorDynamic = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor.white.withAlphaComponent(0.12)
            : NSColor.black.withAlphaComponent(0.06)
    }

    init(code: String, language: String) {
        self.currentCode = code
        headerView = NSView()
        languageLabel = NSTextField(labelWithString: language.isEmpty ? "code" : language)
        copyButton = NSButton(image: NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy code")!, target: nil, action: nil)
        codeTextField = NSTextField(wrappingLabelWithString: code)
        super.init(frame: .zero)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func update(code: String, language: String) {
        currentCode = code
        codeTextField.stringValue = code
        languageLabel.stringValue = language.isEmpty ? "code" : language
        invalidateIntrinsicContentSize()
    }

    private func setupViews() {
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true

        headerView.wantsLayer = true
        headerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerView)

        languageLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        languageLabel.textColor = .secondaryLabelColor
        languageLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(languageLabel)

        copyButton.bezelStyle = .inline
        copyButton.isBordered = false
        copyButton.contentTintColor = .secondaryLabelColor
        copyButton.target = self
        copyButton.action = #selector(copyCode)
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.toolTip = "Copy code"
        headerView.addSubview(copyButton)

        codeTextField.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        codeTextField.textColor = .labelColor
        codeTextField.isEditable = false
        codeTextField.isSelectable = true
        codeTextField.isBordered = false
        codeTextField.isBezeled = false
        codeTextField.drawsBackground = false
        codeTextField.lineBreakMode = .byCharWrapping
        codeTextField.maximumNumberOfLines = 0
        codeTextField.cell?.wraps = true
        codeTextField.cell?.isScrollable = false
        codeTextField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        codeTextField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        codeTextField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(codeTextField)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: topAnchor),
            headerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 32),

            languageLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 12),
            languageLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            copyButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -8),
            copyButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            codeTextField.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 8),
            codeTextField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            codeTextField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            codeTextField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
        ])

        updateColors()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppearanceChange),
            name: .appAppearanceDidChange,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func updateColors() {
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            self.layer?.backgroundColor = Self.backgroundColorDynamic.cgColor
            self.headerView.layer?.backgroundColor = Self.headerColorDynamic.cgColor
        }
    }

    @objc private func handleAppearanceChange() {
        updateColors()
    }

    @objc private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(currentCode, forType: .string)

        let original = copyButton.contentTintColor
        copyButton.contentTintColor = .controlAccentColor
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            self?.copyButton.contentTintColor = original
        }
    }
}
