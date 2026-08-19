import AppKit

@MainActor protocol CanvasToolbarViewDelegate: AnyObject {
    func toolbarDidSelectSchema(_ schema: String?)
    func toolbarDidTapResetLayout()
}

final class CanvasToolbarView: NSView {
    weak var delegate: CanvasToolbarViewDelegate?

    private let pill: NSView
    private let schemaPopup = NSPopUpButton()
    private let schemaLabel = NSTextField(labelWithString: "Schema")
    private let separator = NSBox()
    private let resetLayoutButton = NSButton()

    override init(frame frameRect: NSRect) {
        pill = Self.makePill(cornerRadius: 8)
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        pill = Self.makePill(cornerRadius: 8)
        super.init(coder: coder)
        setupViews()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let result = super.hitTest(point)
        return result === self ? nil : result
    }

    private func setupViews() {
        addSubview(pill)

        schemaLabel.textColor = .secondaryLabelColor
        schemaLabel.translatesAutoresizingMaskIntoConstraints = false

        schemaPopup.bezelStyle = .toolbar
        schemaPopup.controlSize = .regular
        schemaPopup.target = self
        schemaPopup.action = #selector(schemaChanged)
        schemaPopup.translatesAutoresizingMaskIntoConstraints = false

        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        configureIconButton(resetLayoutButton, symbol: "rectangle.3.group", tooltip: "Reset Layout", action: #selector(resetLayoutTapped))

        for item in [schemaLabel, schemaPopup, separator, resetLayoutButton] as [NSView] {
            pill.addSubview(item)
        }

        NSLayoutConstraint.activate([
            pill.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            pill.topAnchor.constraint(equalTo: topAnchor, constant: 10),

            schemaLabel.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 12),
            schemaLabel.centerYAnchor.constraint(equalTo: pill.centerYAnchor),

            schemaPopup.leadingAnchor.constraint(equalTo: schemaLabel.trailingAnchor, constant: 6),
            schemaPopup.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            schemaPopup.topAnchor.constraint(equalTo: pill.topAnchor, constant: 6),
            schemaPopup.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -6),
            schemaPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 130),

            separator.leadingAnchor.constraint(equalTo: schemaPopup.trailingAnchor, constant: 8),
            separator.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            separator.widthAnchor.constraint(equalToConstant: 1),
            separator.heightAnchor.constraint(equalToConstant: 20),

            resetLayoutButton.leadingAnchor.constraint(equalTo: separator.trailingAnchor, constant: 6),
            resetLayoutButton.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            resetLayoutButton.topAnchor.constraint(equalTo: pill.topAnchor, constant: 6),
            resetLayoutButton.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -6),
            resetLayoutButton.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -6),
        ])
    }

    private static func makePill(cornerRadius: CGFloat) -> NSView {
        ThemedPillView.makePill(cornerRadius: cornerRadius)
    }

    private func configureIconButton(_ button: NSButton, symbol: String, tooltip: String, action: Selector) {
        button.bezelStyle = .toolbar
        button.showsBorderOnlyWhileMouseInside = true
        let config = NSImage.SymbolConfiguration(paletteColors: [.labelColor])
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)?
            .withSymbolConfiguration(config)
        button.imagePosition = .imageOnly
        button.target = self
        button.action = action
        button.toolTip = tooltip
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    func setSchemas(_ schemas: [String], selected: String?) {
        schemaPopup.removeAllItems()

        if schemas.isEmpty {
            schemaPopup.addItem(withTitle: "All Tables")
            pill.isHidden = true
        } else {
            pill.isHidden = false
            for schema in schemas {
                schemaPopup.addItem(withTitle: schema)
            }
            if let selected, let index = schemas.firstIndex(of: selected) {
                schemaPopup.selectItem(at: index)
            } else {
                schemaPopup.selectItem(at: 0)
            }
        }
    }

    var selectedSchema: String? {
        pill.isHidden ? nil : schemaPopup.titleOfSelectedItem
    }

    @objc private func schemaChanged() {
        delegate?.toolbarDidSelectSchema(selectedSchema)
    }
    @objc private func resetLayoutTapped() { delegate?.toolbarDidTapResetLayout() }
}

final class ThemedPillView: NSVisualEffectView {
    static func makePill(cornerRadius: CGFloat) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.translatesAutoresizingMaskIntoConstraints = false
            glass.cornerRadius = cornerRadius
            return glass
        } else {
            let pill = ThemedPillView()
            pill.translatesAutoresizingMaskIntoConstraints = false
            pill.material = .popover
            pill.blendingMode = .withinWindow
            pill.state = .active
            pill.wantsLayer = true
            pill.layer?.cornerRadius = cornerRadius
            pill.layer?.masksToBounds = true
            pill.layer?.borderWidth = 0.5
            pill.layer?.shadowColor = NSColor.black.withAlphaComponent(0.05).cgColor
            pill.layer?.shadowRadius = 4
            pill.layer?.shadowOpacity = 1
            pill.layer?.shadowOffset = .zero
            pill.updateBorderColor()
            return pill
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBorderColor()
    }

    private func updateBorderColor() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.borderColor = isDark ? NSColor.separatorColor.cgColor : NSColor.white.cgColor
    }
}
