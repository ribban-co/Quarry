import AppKit

final class BlockquoteView: NSView {

    private let accentBar: NSView
    private let textField: NSTextField

    init(text: String) {
        accentBar = NSView()
        textField = NSTextField(labelWithAttributedString: Self.renderText(text))
        super.init(frame: .zero)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func update(text: String) {
        textField.attributedStringValue = Self.renderText(text)
        invalidateIntrinsicContentSize()
    }

    private func setupViews() {
        accentBar.wantsLayer = true
        accentBar.layer?.cornerRadius = 1.5
        accentBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(accentBar)

        textField.configureForMarkdownDisplay()
        textField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textField)

        NSLayoutConstraint.activate([
            accentBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            accentBar.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            accentBar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            accentBar.widthAnchor.constraint(equalToConstant: 3),

            textField.leadingAnchor.constraint(equalTo: accentBar.trailingAnchor, constant: 10),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor),
            textField.topAnchor.constraint(equalTo: topAnchor),
            textField.bottomAnchor.constraint(equalTo: bottomAnchor),
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
            self.accentBar.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.5).cgColor
        }
    }

    @objc private func handleAppearanceChange() {
        updateColors()
    }

    private static func renderText(_ text: String) -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let italicDescriptor = font.fontDescriptor.withSymbolicTraits(.italic)
        let italicFont = NSFont(descriptor: italicDescriptor, size: font.pointSize) ?? font
        return MarkdownInlineRenderer.render(text, font: italicFont, color: .secondaryLabelColor)
    }
}
